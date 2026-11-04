[CmdletBinding()]
param(
    [switch]$ActorStorageOnly,
    [switch]$CleanupOnly,
    [switch]$EntryTemplatesOnly,
    [switch]$AdoptionPackageOnly,
    [switch]$CoreOnly,
    [switch]$TargetPreflightOnly,
    [switch]$ClosureContextOnly,
    [switch]$SourceMaterialOnly,
    [switch]$OriginalTaskArchiveFinalizeOnly,
    [string]$OriginalSourceFinalizeFixturePath,
    [string]$OriginalArchiveRuntimeRoot,
    [string]$LegacyRuntimeRoot
)

$ErrorActionPreference = 'Stop'
if($CleanupOnly){$ActorStorageOnly=$true}
Set-StrictMode -Version Latest

$scriptsRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionState.psm1') -Force
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionProjection.psm1') -Force
Import-Module (Join-Path $scriptsRoot 'ProjectAdoptionTransaction.psm1') -Force

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('aiw-adoption-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)

    if (-not $Condition) {
        throw ('ASSERT_FAIL|' + $Name)
    }
    $script:passed++
}

function Write-TestText {
    param([string]$Path, [string]$Text)

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent
    }
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function Write-TestJson {
    param([string]$RelativePath, $Value)

    Write-TestText (Join-Path $script:fixtureRoot $RelativePath) (($Value | ConvertTo-Json -Depth 20 -Compress) + "`n")
}

function Test-AdoptionClosureContext {
    # Exercise the real original reader, including its final recheck. Supply
    # an older fixed runtime to catch per-rule context retention regressions.
    $sourceRoot=Split-Path -Parent $script:scriptsRoot
    $readerRoot=if($LegacyRuntimeRoot){[IO.Path]::GetFullPath($LegacyRuntimeRoot)}else{$sourceRoot}
    $composer=@(Import-Module (Join-Path $readerRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
    $content=& $composer {(Get-Command New-AiwContentContext).Module}
    $transaction=@(Get-Module|Where-Object{$_.Path-ceq(Join-Path $script:scriptsRoot 'ProjectAdoptionTransaction.psm1')})[0]
    $project=Join-Path $script:fixtureRoot 'closure-context';$norm=Join-Path $project 'rules/shared.md'
    Write-TestText $norm 'A complete shared source.'
    $binding=[pscustomobject]@{id='closure-rules';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@(@{kind='FILE';locator='rules/shared.md'});decisionLocator='fixture:closure-context'}
    $config=[pscustomobject]@{schemaVersion=7;id='closure-fixture';displayName='Closure fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[pscustomobject]@{};sourceBindings=@($binding);processPolicy=@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
    Write-TestText (Join-Path $project '.ai-workspace/project.json') ($config|ConvertTo-Json -Depth 100)
    $identity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes($norm))
    $rules=@(foreach($id in @('FIRST','SECOND','THIRD')){
        $document=[pscustomobject]@{sourceId='ROOT';bindingId=$binding.id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=$identity};locator='rules/shared.md';identity=$identity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
        $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$binding.id;itemId=$id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='ROOT';documents=@($document)}
        $document.revision=& $content.ExportedCommands['Get-AiwContentRevision'] ([pscustomobject]@{documents=@($document)}) @($binding)
        $descriptor.revision=& $content.ExportedCommands['Get-AiwContentRevision'] $descriptor @($binding)
        $descriptor.itemIdentity=& $content.ExportedCommands['Get-AiwContentItemIdentity'] $descriptor
        [pscustomobject]@{ruleId=$id;requirementReason='Shared source regression';decisionLocator='fixture:closure-context';source=$descriptor;selectors=@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
    })
    Write-TestText (Join-Path $project '.ai-workspace/process-policy.json') (@{schemaVersion=3;contractVersion='2.0.0';projectId=$config.id;rules=$rules}|ConvertTo-Json -Depth 100)
    $configIdentity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $project '.ai-workspace/project.json')))
    $original=& $composer.ExportedCommands['Get-AiwProjectPolicySourceClosure'] -ProjectRoot $project -Rules $rules
    $null=& $composer.ExportedCommands['Assert-AiwProjectPolicySourceClosure'] $original
    $invoke={param($reader,$root,$rules,$identity,$forbidden) Get-AiwAdoptionPolicySourceClosure -Composer $reader -ProjectRoot $root -Rules $rules -ExpectedProjectConfigIdentity $identity -ForbiddenPaths $forbidden}
    $closure=& $transaction $invoke $composer $project $rules $configIdentity @()
    Assert-AiwAdoptionPolicySourceClosure $closure $composer
    Assert-True ($closure.Identity-ceq$original.Identity-and$closure.Documents.Count-eq1-and[Convert]::ToBase64String($closure.Documents[0].bytes)-ceq[Convert]::ToBase64String($original.Documents[0].bytes)) 'adoption-shared-context-full-closure-and-original-assert-preserve-content'
    if($closure.SnapshotChecks.Count){
        Assert-True ($closure.SnapshotChecks.Count-eq3-and@($closure.SnapshotChecks|Where-Object{-not[object]::ReferenceEquals($_.Context,$closure.SnapshotChecks[0].Context)}).Count-eq0) 'adoption-original-reader-retains-one-context-for-all-rules'
    }else{Assert-True ($null-ne$closure.LocalReadContext) 'adoption-current-reader-keeps-owned-context'}
    # Missing either public capability must keep the original complete reader.
    $contextless=New-Module -ArgumentList $composer.ExportedCommands['Get-AiwProjectPolicySourceClosure'] -ScriptBlock {
        param($original);$script:OriginalClosure=$original
        function Get-ContextlessClosure {[CmdletBinding()]param([string]$ProjectRoot,[object[]]$Rules,[string[]]$ForbiddenPaths) & $script:OriginalClosure -ProjectRoot $ProjectRoot -Rules $Rules -ForbiddenPaths $ForbiddenPaths}
        Export-ModuleMember -Function Get-ContextlessClosure
    }
    $fallbacks=@(@{ExportedCommands=@{'Get-AiwProjectPolicySourceClosure'=$composer.ExportedCommands['Get-AiwProjectPolicySourceClosure']}},@{ExportedCommands=@{'Get-AiwProjectPolicySourceClosure'=$contextless.ExportedCommands['Get-ContextlessClosure'];'New-AiwAdoptionContentContext'=$composer.ExportedCommands['New-AiwAdoptionContentContext']}})
    foreach($reader in $fallbacks){$fallback=& $transaction $invoke $reader $project $rules $configIdentity @();Assert-AiwAdoptionPolicySourceClosure $fallback $composer;Assert-True ($fallback.Identity-ceq$original.Identity-and$fallback.Documents.Count-eq1) 'adoption-missing-public-capability-preserves-complete-reader'}
    $reason='';try{$null=& $transaction $invoke $composer $project $rules $configIdentity @($norm)}catch{$reason=$_.Exception.Message}
    Assert-True ($reason.Contains('SOURCE_DENIED|FORBIDDEN_PATH')) 'adoption-shared-context-preserves-explicit-forbidden-source'
    Write-TestText $norm 'Changed after closure.'
    $reason='';try{Assert-AiwAdoptionPolicySourceClosure $closure $composer}catch{$reason=$_.Exception.Message}
    Assert-True ($reason.Contains('DRIFT')) 'adoption-shared-context-original-assert-rejects-source-drift'
}

function Test-AdoptionSourceMaterial {
    $sourceRoot=Split-Path -Parent $script:scriptsRoot
    $readerRoot=if($LegacyRuntimeRoot){[IO.Path]::GetFullPath($LegacyRuntimeRoot)}else{$sourceRoot}
    $composer=@(Import-Module (Join-Path $readerRoot 'framework/versions/2.0.0/scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
    $content=& $composer {(Get-Command New-AiwContentContext).Module}
    $transaction=@(Get-Module|Where-Object{$_.Path-ceq(Join-Path $script:scriptsRoot 'ProjectAdoptionTransaction.psm1')})[0]
    $project=Join-Path $script:fixtureRoot 'source-material';$shared=Join-Path $project 'rules/shared.md'
    $dependency=Join-Path $project 'rules/dependency.md';$external=Join-Path $script:fixtureRoot 'external/rule.md'
    Write-TestText $shared "<!-- FIRST:BEGIN -->`r`nFirst 完整 body.`r`n<!-- FIRST:END -->`r`n<!-- SECOND:BEGIN -->`r`nSecond complete body.`r`n<!-- SECOND:END -->`r`n"
    Write-TestText $dependency 'Independent ordered dependency.';Write-TestText $external 'External complete dependency.'
    $bindings=@([pscustomobject]@{id='local';provider='LOCAL_DIRECTORY';locator=@{root='.'};allowedPaths=@(@{kind='FILE';locator='rules/shared.md'},@{kind='FILE';locator='rules/dependency.md'});decisionLocator='fixture:material'},[pscustomobject]@{id='external';provider='LOCAL_DIRECTORY';locator=@{root=(Split-Path -Parent $external)};allowedPaths=@(@{kind='FILE';locator='rule.md'});decisionLocator='fixture:external'})
    $config=[pscustomobject]@{schemaVersion=7;id='material-fixture';displayName='Material fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[pscustomobject]@{};sourceBindings=$bindings;processPolicy=@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
    $configPath=Join-Path $project '.ai-workspace/project.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json'
    Write-TestText $configPath ($config|ConvertTo-Json -Depth 100)
    Write-TestText (Join-Path $project '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-TestText (Join-Path $project 'AGENTS.md') 'Isolated prospective component.'
    Write-TestText (Join-Path $project '.ai-workspace/corrections.json') (@{schemaVersion=3;contractVersion='2.0.0';projectId=$config.id;corrections=@()}|ConvertTo-Json -Depth 100)
    $rules=@(foreach($id in @('FIRST','SECOND')){
        $depPath=if($id-ceq'FIRST'){$dependency}else{$external};$depBinding=if($id-ceq'FIRST'){'local'}else{'external'};$depLocator=if($id-ceq'FIRST'){'rules/dependency.md'}else{'rule.md'}
        $documents=@([pscustomobject]@{sourceId='ROOT';bindingId='local';revision=@{kind='CONTENT_IDENTITY';value=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($shared)))};locator='rules/shared.md';identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($shared)));mode='MARKED_SECTION';sectionStart=('<!-- '+$id+':BEGIN -->');sectionEnd=('<!-- '+$id+':END -->');dependencies=@('DEP')},[pscustomobject]@{sourceId='DEP';bindingId=$depBinding;revision=@{kind='CONTENT_IDENTITY';value=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($depPath)))};locator=$depLocator;identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($depPath)));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})
        $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='local';itemId=$id;revision=@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='ROOT';documents=$documents}
        foreach($document in $documents){$document.revision=& $content.ExportedCommands['Get-AiwContentRevision'] ([pscustomobject]@{documents=@($document)}) $bindings}
        $descriptor.revision=& $content.ExportedCommands['Get-AiwContentRevision'] $descriptor $bindings;$descriptor.itemIdentity=& $content.ExportedCommands['Get-AiwContentItemIdentity'] $descriptor
        [pscustomobject]@{ruleId=$id;requirementReason='Full material regression';decisionLocator='fixture:material';source=$descriptor;selectors=@{profiles=@();roles=@();phases=@();actionKinds=@($(if($id-ceq'FIRST'){'CONTROL_WRITE'}else{'SOURCE_WRITE'}));resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
    })
    $policy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$config.id;rules=$rules}
    Write-TestText $policyPath ($policy|ConvertTo-Json -Depth 100)
    function Invoke-MaterialComposition([switch]$Complete,[string[]]$Forbidden=@()){
        & $composer.ExportedCommands['Invoke-ProcessRequirementComposition'] -ProjectRoot $project -FrameworkRoot $readerRoot -TargetVersion '2.0.0' -ExpectedProjectConfigIdentity (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($configPath))) -ExpectedCorrectionsIdentity (Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $project '.ai-workspace/corrections.json')))) -Profile CRITICAL -Role CONTROLLER -Phase IMPLEMENT -Actor fixture-owner -TaskIdentity MISSING -Capabilities @() -Objective 'software implementation' -ActionKind CONTROL_WRITE -ResultKind IMPLEMENTATION_RESULT -ExactPaths @('.ai-workspace/upgrade-recovery/2.0.0/state.json') -ForbiddenPaths $Forbidden -EvaluationOnly -ValidateCompleteAdoptedSet:$Complete
    }
    $externalBytes=[IO.File]::ReadAllBytes($external)
    [IO.File]::Delete($external)
    try{
        $selected=Invoke-MaterialComposition
        $reason='';try{$null=Invoke-MaterialComposition -Complete}catch{$reason=$_.Exception.Message}
        Assert-True ($selected.status-ceq'EVALUATION_ONLY'-and$reason-match'EFFECTIVE_SET_UNPROVEN|SOURCE_UNAVAILABLE') 'material-full-original-reader-rejects-unselected-unavailable-dependency'
    }finally{[IO.File]::WriteAllBytes($external,$externalBytes)}
    $complete=Invoke-MaterialComposition -Complete
    $body=@($complete.readTrace|Where-Object event -CEQ 'SOURCE_BODY_READ')
    Assert-True ($body.Count-eq4-and@($body|Where-Object ruleId -CEQ 'SECOND').Count-eq2-and@($complete.selectedRequirements|Where-Object requirementId -EQ 'project:material-fixture:SECOND').Count-eq0) 'material-real-full-trace-covers-explicitly-unselected-rule'
    $guards=@(foreach($path in @($configPath,$policyPath,$composer.Path,(Join-Path (Split-Path -Parent $composer.Path) 'ContentSources.psm1'))){[pscustomobject]@{path=$path;identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($path)))}})
    $convert={param($result,$root,$policy,$config,$guards,$forbidden) ConvertTo-AiwAdoptionLocalSourceMaterial $result $root $policy $config $guards $forbidden}
    $material=& $transaction $convert $complete $project $policy $config $guards @()
    $original=& $composer.ExportedCommands['Get-AiwProjectPolicySourceClosure'] -ProjectRoot $project -Rules $rules
    & $composer.ExportedCommands['Assert-AiwProjectPolicySourceClosure'] $original
    $same=$material.Mode-ceq'PUBLIC_COMPLETE_LOCAL'-and$material.Identity-ceq$original.Identity-and$material.Documents.Count-eq3
    foreach($doc in $original.Documents){$actual=@($material.Documents|Where-Object{$_.locatorKind-ceq$doc.locatorKind-and$_.sourcePath-ceq$doc.sourcePath});$same=$same-and$actual.Count-eq1-and[Convert]::ToBase64String($actual[0].bytes)-ceq[Convert]::ToBase64String($doc.bytes)}
    Assert-True $same 'material-retains-original-complete-closure-identity-and-raw-bytes'
    $stage=Join-Path $script:fixtureRoot 'material-stage'
    foreach($doc in $material.Documents){if($doc.locatorKind-ceq'PROJECT_RELATIVE'-and$doc.relativePath-cne'NOT_APPLICABLE'){Write-TestText (Join-Path $stage $doc.relativePath) '';[IO.File]::WriteAllBytes((Join-Path $stage $doc.relativePath),$doc.bytes)}}
    Assert-True ((Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $stage 'rules/shared.md'))))-ceq(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($shared)))-and(Test-Path -LiteralPath (Join-Path $stage 'rules/dependency.md'))-and@($material.Documents|Where-Object{$_.sourcePath-ceq$external-and$_.relativePath-ceq'NOT_APPLICABLE'}).Count-eq1) 'material-copies-full-original-local-bytes-and-keeps-external-outside-stage'
    $policyBytes=[IO.File]::ReadAllBytes($policyPath)
    $rules[1].source.documents[0].dependencies=@('NOT_ADOPTED');$rules[1].source.itemIdentity=& $content.ExportedCommands['Get-AiwContentItemIdentity'] $rules[1].source
    Write-TestText $policyPath ($policy|ConvertTo-Json -Depth 100)
    try{$reason='';try{$null=Invoke-MaterialComposition -Complete}catch{$reason=$_.Exception.Message};Assert-True ($reason.Contains('DEPENDENCY_NOT_ADOPTED')) 'material-full-original-reader-reaches-unselected-invalid-dependency'}finally{[IO.File]::WriteAllBytes($policyPath,$policyBytes);$policy=$script:utf8.GetString($policyBytes)|ConvertFrom-Json -Depth 100}
    $reason='';try{$null=Invoke-MaterialComposition -Complete -Forbidden @($external)}catch{$reason=$_.Exception.Message}
    Assert-True ($reason.Contains('SOURCE_DENIED|FORBIDDEN_PATH')) 'material-full-original-reader-protects-unselected-dependency'
    foreach($fault in @('missing','duplicate','path','identity','marker')){
        $bad=$complete|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
        $indices=@(for($i=0;$i-lt$bad.readTrace.Count;$i++){if($bad.readTrace[$i].event-ceq'SOURCE_BODY_READ'-and$bad.readTrace[$i].ruleId-ceq'SECOND'){$i}})
        switch($fault){
            missing {$bad.readTrace=@(for($i=0;$i-lt$bad.readTrace.Count;$i++){if($i-ne$indices[0]){$bad.readTrace[$i]}})}
            duplicate {$bad.readTrace[$indices[0]]=$bad.readTrace[$indices[1]]|ConvertTo-Json -Compress|ConvertFrom-Json}
            path {$bad.readTrace[$indices[0]].path=Join-Path $project 'wrong.md'}
            identity {$bad.readTrace[$indices[0]].identity='0|'+('0'*64)}
            marker {$bad.readTrace=@($bad.readTrace|Where-Object event -CNE 'COMPLETE_ADOPTED_SET_VERIFIED')}
        }
        for($i=0;$i-lt$bad.readTrace.Count;$i++){$bad.readTrace[$i].sequence=$i}
        $reason='';try{$null=& $transaction $convert $bad $project $policy $config $guards @()}catch{$reason=$_.Exception.Message}
        Assert-True ($reason.Contains('PUBLIC_COMPLETE_OBSERVATION_UNPROVEN')) ('material-adapter-rejects-real-result-corruption-'+$fault)
    }
    $assert={param($material,$reader) Assert-AiwAdoptionSourceMaterial $material $reader}
    foreach($drift in @($shared,$configPath,$policyPath)){
        $bytes=[IO.File]::ReadAllBytes($drift);[IO.File]::AppendAllText($drift,' ', $script:utf8)
        try{$reason='';try{& $transaction $assert $material $composer}catch{$reason=$_.Exception.Message};Assert-True ($reason.Contains('MATERIAL_DRIFT')) ('material-consumption-rejects-late-drift-'+[IO.Path]::GetFileName($drift))}finally{[IO.File]::WriteAllBytes($drift,$bytes)}
    }
    $reason='';try{$null=& $transaction $convert $complete $project $policy $config $guards @($external)}catch{$reason=$_.Exception.Message}
    Assert-True ($reason.Contains('FORBIDDEN_PATH')) 'material-protects-before-raw-materialization'
    # A missing public complete capability must still run the real original
    # closure and its own assertion. This unit receipt grants no real action.
    $binding=[pscustomobject]@{frameworkVersion='2.0.0';forbiddenScope=@();exactScope=@('.ai-workspace/upgrade-recovery/2.0.0/state.json');authorizedActions=@('CONTROL_WRITE')}
    $intent=[pscustomobject]@{schemaVersion=2;requestedActionKind='CONTROL_WRITE';ambiguityState='CLEAR'}
    $receipt=[pscustomobject]@{schemaVersion=3;inputContractVersion=4;binding=$binding;intentEnvelope=$intent;status='PASS';mode='DISCOVER';receiptType='PROCESS_REQUIREMENTS_DISCOVER';authorityGranted=$false;semanticCorrectnessProven=$false;contextIdentity=((Get-AiwByteIdentity ($script:utf8.GetBytes(($binding|ConvertTo-Json -Depth 30 -Compress)+[char]10+($intent|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1])}
    $reader=[pscustomobject]@{ExportedCommands=@{'Get-AiwProjectPolicySourceClosure'=$composer.ExportedCommands['Get-AiwProjectPolicySourceClosure'];'New-AiwAdoptionContentContext'=$composer.ExportedCommands['New-AiwAdoptionContentContext']}}
    $configDoc=Read-AiwProjectJson $configPath 'PROJECT';$policyDoc=Read-AiwProjectJson $policyPath 'POLICY'
    $fallback=& $transaction {param($reader,$root,$receipt,$policy,$config) Get-AiwAdoptionSourceMaterial $reader $root $receipt $null $policy $config} $reader $project $receipt $policyDoc $configDoc
    & $transaction $assert $fallback $composer
    Assert-True ($fallback.Mode-ceq'ORIGINAL_CLOSURE'-and$fallback.Identity-ceq$original.Identity) 'material-missing-public-complete-capability-preserves-original-full-reader'
    $legacyRule=[pscustomobject]@{ruleId='LEGACY';source=[pscustomobject]@{rootSourceId='ROOT';documents=@([pscustomobject]@{sourceId='ROOT';locator='rules/dependency.md';identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($dependency)));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()})}}
    $legacyPolicy=[pscustomobject]@{Value=[pscustomobject]@{rules=@($legacyRule)}}
    $legacy=& $transaction {param($reader,$root,$receipt,$policy,$config) Get-AiwAdoptionSourceMaterial $reader $root $receipt $null $policy $config} $composer $project $receipt $legacyPolicy $configDoc
    & $transaction $assert $legacy $composer
    Assert-True ($legacy.Mode-ceq'ORIGINAL_CLOSURE'-and$legacy.Documents.Count-eq1-and$legacy.Documents[0].identity-ceq$legacyRule.source.documents[0].identity) 'material-legacy-source-without-kind-uses-real-original-closure'
    $dependencyBytes=[IO.File]::ReadAllBytes($dependency);Write-TestText $dependency 'Legacy dependency changed after closure.'
    try{$reason='';try{& $transaction $assert $legacy $composer}catch{$reason=$_.Exception.Message};Assert-True ($reason.Contains('DRIFT')) 'material-legacy-fallback-keeps-real-original-assert'}finally{[IO.File]::WriteAllBytes($dependency,$dependencyBytes)}
    Write-TestText $shared 'Changed after original fallback.'
    $reason='';try{& $transaction $assert $fallback $composer}catch{$reason=$_.Exception.Message}
    Assert-True ($reason.Contains('DRIFT')) 'material-fallback-preserves-original-assertion'
}

function Test-TargetPreflightPermanentSources {
    # Use the real registrar and root preview, with the existing synthetic
    # mechanism fixture. This is not distribution qualification or live adoption.
    $sourceRoot=Split-Path -Parent $script:scriptsRoot
    Import-Module (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/TestHarness.psm1')
    Import-Module (Join-Path $sourceRoot 'framework/versions/2.0.0/scripts/ContentSources.psm1')
    $caseRoot=Join-Path $script:fixtureRoot 'target-preflight'
    $origin=Join-Path $caseRoot 'origin';$target=Join-Path $caseRoot 'target';$project=Join-Path $caseRoot 'project'
    function Fixture-Identity([string]$Path){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($Path))}
    function Fixture-Json([string]$Path,$Value){Write-TestText $Path (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
    function Fixture-Package([string]$Root,[string]$Distribution){
        [string[]]$paths=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'})
        [Array]::Sort($paths,[StringComparer]::Ordinal);$files=@();$rows=@()
        foreach($path in $paths){$id=Fixture-Identity (Join-Path $Root $path);$files+=@{path=$path;identity=$id};$rows+=($path+'='+$id)}
        $canonical=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($script:utf8.GetBytes(($rows-join"`n")+"`n")))
        Fixture-Json (Join-Path $Root 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;canonical=$canonical;files=$files;distributionId=$Distribution}
    }
    function Fixture-RootCall([string]$Entry,[Collections.IDictionary]$Parameters){
        $cli=@('-NoProfile','-NonInteractive','-File',$Entry)
        foreach($key in $Parameters.Keys){$cli+=('-'+$key);if($Parameters[$key]-isnot[bool]){$cli+=[string]$Parameters[$key]}elseif(-not$Parameters[$key]){throw 'PREFLIGHT_FIXTURE_FALSE_SWITCH'}}
        Write-Output ('ROOT_PREFLIGHT_COMMAND|'+($cli|ConvertTo-Json -Compress))
        $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
        try{$output=@(& ([Environment]::ProcessPath) @cli 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
        Write-Output ('ROOT_PREFLIGHT_RESULT|exit='+$code+'|'+($output-join"`n"))
        [pscustomobject]@{ExitCode=$code;Output=($output-join"`n")}
    }
    $version=New-AiwTestMechanismFixture -SourceRoot $sourceRoot -DestinationRoot $origin -DefinitionPath (Join-Path $sourceRoot 'framework/versions/2.0.0/tests/test-groups.json')
    Set-AiwTestFixtureQualification $version -Candidate
    foreach($name in @('README.md','AGENTS.md')){Write-TestText (Join-Path $origin $name) ([IO.File]::ReadAllText((Join-Path $sourceRoot ('framework/user-package/'+$name))))}
    Fixture-Package $origin '2.0.0-snapshot.17'
    Copy-Item -LiteralPath $origin -Destination $target -Recurse
    $targetVersion=Join-Path $target 'framework/versions/2.0.0'
    $template=Join-Path $targetVersion 'project-starter/BOOTSTRAP.md'
    Write-TestText $template ([IO.File]::ReadAllText($template).Replace('<!-- FRAMEWORK-MANAGED:END -->',"<!-- isolated target preflight fixture -->`n<!-- FRAMEWORK-MANAGED:END -->"))
    Set-AiwTestFixtureQualification $targetVersion -Candidate
    Fixture-Package $target '2.0.0-snapshot.18'
    $taskRelative='.ai-workspace/tasks/active/PREFLIGHT-001.md';$initial=Join-Path $caseRoot 'PREFLIGHT-001.md'
    Write-TestText $initial ([string]::Join("`n",@('# PREFLIGHT-001 — Isolated root preview','- Task schema: 2.0.0','- Status: ACTIVE','- Profile: CRITICAL; reason=Actual target-before-pin source boundaries.','- Owner: preflight-owner','- Work route: actor=preflight-owner; role=CONTROLLER; phase=IMPLEMENT','- Phase gate: FALSE','- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=TARGET_PREFLIGHT; expected_paths=[.ai-workspace/upgrade-recovery/2.0.0/state.json]; actual_paths=[.ai-workspace/upgrade-recovery/2.0.0/state.json]','- Writer / reviewer / authorization: isolated fixture only','- Stable candidate: NONE','- Git / push / external: DEFERRED','## Current','- Goal: Preview the next isolated runtime without applying it.','- Acceptance: Permanent sources resolve while actual protection remains.')))
    $null=[IO.Directory]::CreateDirectory($project)
    $registered=@(Fixture-RootCall (Join-Path $origin 'scripts/register-project.ps1') ([ordered]@{ProjectId='preflight-fixture';DisplayName='Preflight fixture';RepositoryPath=$project;FrameworkVersion='2.0.0';ControllerId='preflight-owner';WorkspaceRoot=$origin;LocalCandidatePilot=$true;InitialTaskPath=$initial;ExpectedInitialTaskIdentity=(Fixture-Identity $initial);InitialTaskRelativePath=$taskRelative;Apply=$true}))
    $registration=$registered[-1];$registered[0..($registered.Count-2)]|Write-Output
    Assert-True ($registration.ExitCode-eq0) ('preflight-fixture-register-origin|'+$registration.Output)
    $configPath=Join-Path $project '.ai-workspace/project.json';$policyPath=Join-Path $project '.ai-workspace/process-policy.json'
    $config=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json -Depth 100
    Assert-True ($config.schemaVersion-eq7) 'preflight-real-origin-is-schema-seven'
    Write-TestText (Join-Path $project 'docs/permanent.md') "A declared permanent rule and its explicit dependency.`n"
    Write-TestText (Join-Path $project 'docs/private/dependency.md') "The complete adopted dependency remains required.`n"
    $permissions=@(@{kind='FILE';locator='docs/permanent.md'},@{kind='FILE';locator='docs/private/dependency.md'})
    $binding=[pscustomobject]@{id='preflight-docs';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=$permissions;decisionLocator='fixture:adopted-permanent-docs'}
    $config.sourceBindings=@($binding);$config.routineExcludedPaths=@();Fixture-Json $configPath $config
    $documents=@(foreach($entry in @(@('ROOT','docs/permanent.md',@('DEPENDENCY')),@('DEPENDENCY','docs/private/dependency.md',@()))){[pscustomobject]@{sourceId=$entry[0];bindingId=$binding.id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=(Fixture-Identity (Join-Path $project $entry[1]))};locator=$entry[1];identity=(Fixture-Identity (Join-Path $project $entry[1]));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@($entry[2])}})
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$binding.id;itemId='PREFLIGHT_PERMANENT';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId='ROOT';documents=$documents}
    foreach($doc in $documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) @($binding)}
    $descriptor.revision=Get-AiwContentRevision $descriptor @($binding);$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    # The target check must validate the complete adopted set even though this
    # permanent rule is not selected by its read-only NONE intent.
    $rule=@{ruleId='PREFLIGHT_PERMANENT';requirementReason='Isolated permanent source regression';decisionLocator='fixture:adopted-permanent-docs';source=$descriptor;selectors=@{profiles=@();roles=@();phases=@();actionKinds=@('SOURCE_WRITE');resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
    Fixture-Json $policyPath @{schemaVersion=3;contractVersion='2.0.0';projectId='preflight-fixture';rules=@($rule)}
    $task=Join-Path $project $taskRelative
    $arguments=[ordered]@{ProjectId='preflight-fixture';ToVersion='2.0.0';RepositoryPath=$project;ControllerId='preflight-owner';WorkspaceRoot=$target;LocalCandidatePilot=$true;ActorRouteTaskPath=$taskRelative;ExpectedActorRouteTaskIdentity=(Fixture-Identity $task);ActorRouteActor='preflight-owner'}
    $managed=@('AGENTS.md','.ai-workspace/project.json','.ai-workspace/BOOTSTRAP.md','.ai-workspace/process-policy.json','.ai-workspace/corrections.json','.ai-workspace/controller.json',$taskRelative,'.ai-workspace/upgrade-recovery/2.0.0/state.json','.ai-workspace/runtime/project-adoption/register/state.json','.ai-workspace/runtime/project-adoption/refresh/state.json')
    function Fixture-ManagedSnapshot {(@(foreach($relative in $managed){$path=Join-Path $project $relative;$id=if(Test-Path -LiteralPath $path -PathType Leaf){Fixture-Identity $path}else{'MISSING'};$relative+'|'+$id})-join"`n")}
    $unrelated=Join-Path $project 'src/unrelated.md';Write-TestText $unrelated 'Not an adopted input.'
    $held=[IO.File]::Open($unrelated,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $before=Fixture-ManagedSnapshot;$observed=@(Fixture-RootCall (Join-Path $target 'scripts/upgrade-project.ps1') $arguments);$preview=$observed[-1];$observed[0..($observed.Count-2)]|Write-Output
        Assert-True ($preview.ExitCode-eq0-and$preview.Output.Contains('transaction=local-candidate-managed-projection-refresh')) ('root-preview-reaches-target-before-pin-with-local-docs|'+$preview.Output)
        Assert-True ((Fixture-ManagedSnapshot)-ceq$before) 'root-preview-no-adoption-writes-or-unrelated-business-read'
    }finally{$held.Dispose()}
    foreach($denial in @('excluded-dependency','outside-allowlist')){
        $config.routineExcludedPaths=@();$binding.allowedPaths=$permissions
        if($denial-ceq'excluded-dependency'){$config.routineExcludedPaths=@('docs/private/')}else{$binding.allowedPaths=@($permissions[0])}
        $config.sourceBindings=@($binding);Fixture-Json $configPath $config
        $before=Fixture-ManagedSnapshot;$observed=@(Fixture-RootCall (Join-Path $target 'scripts/upgrade-project.ps1') $arguments);$rejected=$observed[-1];$observed[0..($observed.Count-2)]|Write-Output
        $signal=if($denial-ceq'excluded-dependency'){'SOURCE_DENIED|FORBIDDEN_PATH'}else{'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS'}
        Assert-True ($rejected.ExitCode-ne0-and$rejected.Output.Contains($signal)-and$rejected.Output.Contains('Get-TargetProjectedProcessPreflight')) ('root-preview-preserves-'+$denial+'|'+$rejected.Output)
        Assert-True ((Fixture-ManagedSnapshot)-ceq$before) ('root-preview-denial-zero-adoption-writes-'+$denial)
    }
}

function Reset-TestProject {
    if (Test-Path -LiteralPath $script:fixtureRoot) {
        [IO.Directory]::Delete($script:fixtureRoot, $true)
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $script:fixtureRoot '.ai-workspace')
    Write-TestJson '.ai-workspace/project.json' ([ordered]@{
        schemaVersion = 4
        id = 'fixture'
        frameworkVersion = '1.16.0'
        frameworkToolBackend = 'powershell7'
        processPolicy = [ordered]@{ schemaVersion = 1; locator = '.ai-workspace/process-policy.json' }
    })
    Write-TestJson '.ai-workspace/controller.json' ([ordered]@{
        schemaVersion = 1
        projectId = 'fixture'
        controllerId = 'fixture-controller'
        controllerEpoch = 1
        state = 'CURRENT'
    })
    Write-TestJson '.ai-workspace/corrections.json' ([ordered]@{
        schemaVersion = 2
        projectId = 'fixture'
        corrections = @()
    })
    Write-TestJson '.ai-workspace/process-policy.json' ([ordered]@{
        schemaVersion = 1
        selectedRulePackBytes = 65536
        rules = @()
    })
    Write-TestText (Join-Path $script:fixtureRoot '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`nfixture`n<!-- PROJECT-CUSTOM:END -->`n"
    Write-TestText (Join-Path $script:fixtureRoot 'AGENTS.md') "fixture`n"
}

try {
    if($SourceMaterialOnly){Test-AdoptionSourceMaterial;Test-AdoptionClosureContext;Write-Output ('PASS|adoption-source-material|'+$passed+'/'+$passed+'|evidence=PROSPECTIVE_COMPONENT_ONLY');return}
    if($ClosureContextOnly){Test-AdoptionClosureContext;Write-Output ('PASS|adoption-closure-context|'+$passed+'/'+$passed);return}
    if($TargetPreflightOnly){Test-TargetPreflightPermanentSources;Write-Output ('PASS|root-target-preflight|'+$passed+'/'+$passed+'|qualification=SIMULATED_TEST_FIXTURE_ONLY');return}
    # JSON structural equality ignores object member order, never value/type,
    # array order, missing members or the strict reader's duplicate-key rule.
    $left='{"outer":{"a":1,"b":true},"items":[1,"2",null]}'|ConvertFrom-Json
    $right='{"items":[1,"2",null],"outer":{"b":true,"a":1}}'|ConvertFrom-Json
    Assert-AiwAdoptionSame $left $right 'STRUCTURAL_EQUALITY'
    Assert-True $true 'adoption-object-member-order-is-not-drift'
    foreach($json in @('{"outer":{"a":"1","b":true},"items":[1,"2",null]}','{"outer":{"a":1,"b":"true"},"items":[1,"2",null]}','{"outer":{"a":1,"b":true},"items":["2",1,null]}','{"outer":{"a":1},"items":[1,"2",null]}','{"outer":{"a":1,"b":true,"extra":null},"items":[1,"2",null]}')){
        $refused=$false;try{Assert-AiwAdoptionSame $left ($json|ConvertFrom-Json) 'STRUCTURAL_EQUALITY'}catch{$refused=$_.Exception.Message-ceq'ADOPTION_PROCESS_STRUCTURAL_EQUALITY'}
        Assert-True $refused 'adoption-real-structural-drift-rejected'
    }
    $duplicate=Join-Path $fixtureRoot 'duplicate.json';Write-TestText $duplicate '{"a":1,"a":1}'
    $refused=$false;try{$null=Read-AiwProjectJson $duplicate 'DUPLICATE'}catch{$refused=$_.Exception.Message-cmatch'DUPLICATE'}
    Assert-True $refused 'adoption-duplicate-json-members-still-rejected'
    if($OriginalSourceFinalizeFixturePath){
        # The integration owner supplies actual isolated O admission, candidate,
        # completed O -> T adoption and qualified X artifacts. No success mocks
        # or copied PASS templates can substitute for those existing consumers.
        $case=Read-AiwProjectJson $OriginalSourceFinalizeFixturePath 'SOURCE_FINALIZE_TEST_CASE'
        $arguments=@{};foreach($property in $case.Value.arguments.PSObject.Properties){$arguments[$property.Name]=$property.Value}
        $testRoot=[IO.Path]::GetFullPath($arguments.RepositoryRoot)
        $tempPrefix=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
        if(-not$testRoot.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($testRoot).StartsWith('aiw-')){throw 'SOURCE_FINALIZE_TEST_TEMP_ROOT_REQUIRED'}
        $original=(Read-AiwProjectJson $arguments.InputPath 'SOURCE_FINALIZE_TEST_INPUT').Value
        $receipt=(Read-AiwProjectJson $original.discoverReceiptPath 'SOURCE_FINALIZE_TEST_RECEIPT').Value
        $refs=@($arguments.InputPath,$original.discoverReceiptPath,$arguments.AdmitInputPath,$arguments.AdmitResultPath,$receipt.sourceLocators.authorizationPackagePath,$arguments.AdoptionAuthorizationPackagePath,$arguments.AdoptionFinalizeResultPath)
        $before=@($refs|ForEach-Object{(Read-AiwProjectJson $_ 'SOURCE_FINALIZE_TEST_ORIGINAL').Identity})
        $module=Get-AiwDistributionBinding $case.Value.executionRuntimeRoot '2.0.0' -Required
        $tx=@(Import-Module (Join-Path $module.runtimeRoot 'scripts/ProjectAdoptionTransaction.psm1') -PassThru)[0]
        $complete=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @arguments
        Assert-True ($complete.status-ceq'PASS'-and$complete.reason-ceq'ORIGINAL_SOURCE_FINALIZED_AFTER_COMPLETED_ADOPTION'-and$complete.successorState-ceq'NONE') 'real-original-source-finalized-through-O-and-completed-T'
        $again=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @arguments
        Assert-True ($again.decisionIdentity-ceq$complete.decisionIdentity) 'original-source-repeat-completion-stable'
        Assert-True (($before-join',')-ceq(@($refs|ForEach-Object{(Read-AiwProjectJson $_ 'SOURCE_FINALIZE_TEST_ORIGINAL').Identity})-join',')) 'original-source-evidence-remains-byte-identical'
        $bad=@{};foreach($key in $arguments.Keys){$bad[$key]=$arguments[$key]};$bad.ExpectedAdmitResultIdentity='1|'+('A'*64)
        $reason='';try{$null=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @bad}catch{$reason=$_.Exception.Message}
        Assert-True ($reason-cmatch'ADOPTION_PROCESS_EVIDENCE_DRIFT\|SOURCE_ADMIT_RESULT') ('original-source-forged-admission-rejected|'+$reason)
        $bad.ExpectedAdmitResultIdentity=$arguments.ExpectedAdmitResultIdentity;$bad.ExpectedAdoptionTransactionIdentity='1|'+('A'*64)
        $reason='';try{$null=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @bad}catch{$reason=$_.Exception.Message}
        Assert-True ($reason-ceq'ORIGINAL_SOURCE_ADOPTION_TRANSACTION_DRIFT') ('original-source-unrelated-adoption-rejected|'+$reason)
        $candidateRelative=[string]$case.Value.candidateRelativePath
        if($candidateRelative-cnotin@($receipt.binding.exactScope)){throw 'SOURCE_FINALIZE_TEST_CANDIDATE_SCOPE'}
        $candidate=Get-AiwContainedPath $testRoot $candidateRelative
        $saved=[IO.File]::ReadAllBytes($candidate)
        try{
            [IO.File]::WriteAllBytes($candidate,$script:utf8.GetBytes('actual candidate drift'))
            $reason='';try{$null=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @arguments}catch{$reason=$_.Exception.Message}
            Assert-True ($reason-cmatch'RESULT_POSTIMAGE_RECEIPT_REQUIRED|EVIDENCE_.*(DRIFT|IDENTITY)') ('original-source-real-candidate-drift-reaches-original-postimage-consumer|'+$reason)
        }finally{[IO.File]::WriteAllBytes($candidate,$saved)}
        function Assert-SourceProtectionBeforeRead($Call,[string]$File,[string]$Denied,[string]$Name){
            $bad=@{};foreach($key in $Call.Keys){$bad[$key]=$Call[$key]};$bad.ForbiddenPaths=@($Call.ForbiddenPaths)+@($Denied)
            $hold=[IO.File]::Open($File,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            try{
                $readBlocked=$false
                try{$null=[IO.File]::ReadAllBytes($File)}catch{$readBlocked=$_.Exception-is[IO.IOException]-or$_.Exception.InnerException-is[IO.IOException]}
                Assert-True $readBlocked ($Name+'-read-would-fail-with-io')
                $reason='';try{$null=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @bad}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-cmatch'PROTECTED|FORBIDDEN|DENIED|EXCLUDED') ($Name+'-protection-before-io|'+$reason)
            }finally{$hold.Dispose()}
        }
        Assert-SourceProtectionBeforeRead $arguments $candidate $candidateRelative 'original-source-relative-candidate-protection'
        Assert-SourceProtectionBeforeRead $arguments $candidate $candidate 'original-source-absolute-candidate-protection'
        # Add genuine file-backed typed evidence to a new FINALIZE input for
        # the same original action. Original compact, admission and final input
        # remain unchanged; O must consume this self-check before negative cases.
        $proofRoot=Split-Path -Parent $arguments.InputPath
        $notePath=Join-Path $proofRoot 'protection-observation.txt'
        Write-TestText $notePath 'Isolated test observation: verify recursive evidence protection; not release qualification.'
        $noteRef=[ordered]@{path=$notePath;identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($notePath)))}
        $selfPath=Join-Path $proofRoot 'protection-self-check.json'
        $self=[ordered]@{schemaVersion=1;taskId=$receipt.binding.taskId;actor=$arguments.ObservedActor;candidateObjects=@([ordered]@{path=$candidateRelative;identity=(Get-AiwByteIdentity $saved)});requirementsRef=[ordered]@{path=$original.discoverReceiptPath;identity=$original.expectedDiscoverReceiptIdentity};outcome='PASS';checks=@([ordered]@{id='ISOLATED_PROTECTION_FIXTURE';method='MODEL_JUDGMENT';outcome='PASS';reason='Test-only author observation for the unchanged isolated candidate; does not claim qualification.';evidenceLocators=@($noteRef)});evidenceLocators=@($noteRef)}
        Write-TestText $selfPath ($self|ConvertTo-Json -Depth 50)
        $typedInput=$original|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
        $typedInput.evidenceRefs=@([ordered]@{kind='SELF_CHECK';path=$selfPath;identity=(Get-AiwByteIdentity ([IO.File]::ReadAllBytes($selfPath)))})
        $typedPath=Join-Path $proofRoot 'protection-finalize-input.json';Write-TestText $typedPath ($typedInput|ConvertTo-Json -Depth 50)
        $typedCall=@{};foreach($key in $arguments.Keys){$typedCall[$key]=$arguments[$key]}
        $typedCall.InputPath=$typedPath;$typedCall.ExpectedInputIdentity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes($typedPath))
        $typedResult=& $tx.ExportedCommands['Invoke-AiwOriginalSourceFinalize'] @typedCall
        Assert-True ($typedResult.status-ceq'PASS') 'original-source-real-O-typed-evidence-consumed'
        Assert-SourceProtectionBeforeRead $typedCall $selfPath $selfPath 'original-source-absolute-typed-reference-protection'
        Assert-SourceProtectionBeforeRead $typedCall $notePath $notePath 'original-source-absolute-nested-evidence-protection'
        Assert-True (($before-join',')-ceq(@($refs|ForEach-Object{(Read-AiwProjectJson $_ 'SOURCE_FINALIZE_TEST_ORIGINAL').Identity})-join',')) 'original-source-all-originals-unchanged-after-protection-cases'
        Write-Output ('PASS|original-source-finalize|'+$passed+'/'+$passed+'|qualified-fixture-origin='+$case.Identity);return
    }
    if($OriginalTaskArchiveFinalizeOnly){
        if(-not$OriginalArchiveRuntimeRoot){throw 'ORIGINAL_ARCHIVE_REAL_OLD_RUNTIME_REQUIRED'}
        # The old package is an actual unmodified fixed TC3 runtime supplied by
        # the caller. New qualification below is explicitly simulated in temp.
        $originalBinding=Get-AiwDistributionBinding $OriginalArchiveRuntimeRoot '2.0.0' -Required
        $sourceRoot=Split-Path -Parent $scriptsRoot
        $oldFixed=Join-Path $fixtureRoot 'old-fixed';$newFixed=Join-Path $fixtureRoot 'new-fixed';$consumer=Join-Path $fixtureRoot 'consumer'
        $null=[IO.Directory]::CreateDirectory($fixtureRoot);Copy-Item -LiteralPath $OriginalArchiveRuntimeRoot -Destination $oldFixed -Recurse
        $oldBinding=Get-AiwDistributionBinding $oldFixed '2.0.0' -Required
        Assert-True ($oldBinding.contentIdentity-ceq$originalBinding.contentIdentity-and$oldBinding.manifestIdentity-ceq$originalBinding.manifestIdentity) 'archive-old-package-copy-preserves-every-original-byte'
        function Archive-Json($Path,$Value){Write-TestText $Path (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
        function Archive-Id($Path){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($Path))}
        function Archive-CurrentIdentity($Path){
            if(-not(Test-Path -LiteralPath $Path)){return 'MISSING'}
            $item=Get-Item -LiteralPath $Path -Force
            if($item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'ARCHIVE_FIXTURE_NON_REGULAR_OBJECT'}
            return Archive-Id $Path
        }
        function Archive-Reference($Path){[ordered]@{path=$Path;identity=Archive-Id $Path}}
        $runner=Join-Path $fixtureRoot 'run-tool.ps1'
        # Splat named arguments through a fixture wrapper; no string-built code.
        Write-TestText $runner 'param([string]$InputPath); $ErrorActionPreference="Stop"; $call=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json -Depth 100 -AsHashtable; Set-Location -LiteralPath $call.workingDirectory; [Environment]::CurrentDirectory=$call.workingDirectory; $env:CODEX_THREAD_ID="archive-owner-fixture"; $parameters=$call.parameters; & $call.tool @parameters; exit $LASTEXITCODE'
        function Archive-Run($Tool,$Parameters){
            $script:archiveSerial++;$inputFile=Join-Path $fixtureRoot ('call-'+$script:archiveSerial+'.json');Archive-Json $inputFile @{tool=$Tool;parameters=$Parameters;workingDirectory=$consumer}
            $lines=@(& ([Environment]::ProcessPath) -NoProfile -NonInteractive -File $runner -InputPath $inputFile 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
            $value=$null;try{$value=$lines[-1]|ConvertFrom-Json -Depth 100}catch{}
            return [pscustomobject]@{code=$code;text=($lines-join"`n");value=$value}
        }
        $script:archiveSerial=0
        $active='.ai-workspace/tasks/active/ARCHIVE-CHILD-001.md';$archive='.ai-workspace/tasks/archive/ARCHIVE-CHILD-001.md';$scope=@($active,$archive)
        $taskRelative='.ai-workspace/tasks/active/ARCHIVE-OWNER-001.md';$initialTask=Join-Path $fixtureRoot 'initial-task.md'
        Write-TestText $initialTask @"
# ARCHIVE-OWNER-001 — Complete the fixture's adoption and governed archive action
- Task schema: 2.0.0
- Profile: STANDARD; reason=Finite isolated original-action completion test.
- Owner: archive-owner-fixture
- Work route: actor=archive-owner-fixture; role=CONTROLLER; phase=IMPLEMENT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[$active|$archive]; actual_paths=[$active|$archive]
- Writer / reviewer / authorization: archive-owner-fixture / NONE / separate exact package
- Stable candidate: NONE
- Git / push / external: DEFERRED / NONE / NONE
## Current
- Goal: Complete the test-only adoption and one real archive boundary.
- Scope: Only two task cards; product and private bytes are excluded.
- Implementation: Existing registration and original single action admission.
- Acceptance: Real original old failure and new completion, unchanged state.
- Next action: Archive the superseded finite child.
"@
        $null=[IO.Directory]::CreateDirectory($consumer)
        $registration=Archive-Run (Join-Path $oldFixed 'scripts/register-project.ps1') @{ProjectId='archive-completion-fixture';DisplayName='Archive completion fixture';RepositoryPath=$consumer;FrameworkVersion='2.0.0';ControllerId='archive-owner-fixture';LocalCandidatePilot=$true;InitialTaskPath=$initialTask;ExpectedInitialTaskIdentity=Archive-Id $initialTask;InitialTaskRelativePath=$taskRelative;Apply=$true}
        if($registration.code-ne0){throw ('ARCHIVE_REAL_REGISTRATION_FAILED|'+$registration.text)}
        $runtime=Join-Path $consumer '.ai-workspace/runtime/ARCHIVE-OWNER-001/archive-owner-fixture';$null=[IO.Directory]::CreateDirectory($runtime)
        $taskPath=Join-Path $consumer $taskRelative;$configPath=Join-Path $consumer '.ai-workspace/project.json';$statePath=Join-Path $consumer '.ai-workspace/upgrade-recovery/2.0.0/state.json'
        $oldText="# ARCHIVE-CHILD-001 — Superseded finite fixture`n- Task schema: 2.0.0`n- Owner: archive-owner-fixture`n- Work route: actor=archive-owner-fixture; role=TASK_OWNER; phase=IMPLEMENT`n- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[docs/result.md]; actual_paths=[]`n"
        Write-TestText (Join-Path $consumer $active) $oldText
        $history=Join-Path $runtime 'original-full-child.md';Write-TestText $history $oldText
        $authPath=Join-Path $runtime 'original-authorization.json'
        $package=[ordered]@{schemaVersion=1;frameworkVersion='2.0.0';taskId='ARCHIVE-OWNER-001';profile='STANDARD';lifecycle='ACTIVE';owner='archive-owner-fixture';issuer='archive-owner-fixture';issuerRole='TASK_OWNER';grantee='archive-owner-fixture';bundle='ORIGINAL_ARCHIVE_TEST';decisionClass='ROUTINE_LOCAL';userConfirmation='NOT_REQUIRED';reviewIndependence='NOT_APPLICABLE';delegatedGitCloser=$false;taskIdentity=Archive-Id $taskPath;projectConfigIdentity=Archive-Id $configPath;actions=@('CONTROL_WRITE');exactPaths=$scope;objectIdentities=@(@{path=$active;identity=Archive-Id $history},@{path=$archive;identity='NEW'});invalidatesOn=@('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')}
        Archive-Json $authPath $package
        $check=Archive-Run (Join-Path $oldFixed 'framework/versions/2.0.0/scripts/check-authorization.ps1') @{PackagePath=$authPath;ObservedActor='archive-owner-fixture';ObservedTaskId='ARCHIVE-OWNER-001';ObservedOwner='archive-owner-fixture';ObservedAction=@('CONTROL_WRITE');ObservedPath=$scope;ObservedIdentity=@(($active+'='+(Archive-Id $history)),($archive+'=NEW'));TaskPath=$taskRelative;ExpectedTaskIdentity=Archive-Id $taskPath;ExpectedProjectConfigIdentity=Archive-Id $configPath;ProjectConfigPath='.ai-workspace/project.json';ControllerControlPath='.ai-workspace/controller.json'}
        Assert-True ($check.code-eq0) ('archive-original-real-checker|'+$check.text)
        $discoverPath=Join-Path $runtime 'original-discover-input.json';$compactPath=Join-Path $runtime 'original-compact.json'
        $discover=[ordered]@{schemaVersion=4;mode='DISCOVER';projectRoot=$consumer;frameworkRoot=$oldFixed;taskPath=$taskPath;expectedProjectConfigIdentity=Archive-Id $configPath;expectedCorrectionsIdentity=Archive-Id (Join-Path $consumer '.ai-workspace/corrections.json');expectedTaskIdentity=Archive-Id $taskPath;observedActor='archive-owner-fixture';capabilities=@();exactPaths=$scope;forbiddenPaths=@('private');protectedPaths=@('private');authorizationPackagePath=$authPath;expectedAuthorizationIdentity=Archive-Id $authPath;userDecision='NOT_REQUIRED';recoveryState='WARM';hostEnforcementGrade='INSTRUCTION_BOUND';invocationState='PROVEN_EXPLICIT';contextType='TASK';readOnlyContext='NOT_APPLICABLE';evaluationOnly=$false;intentEnvelope=[ordered]@{schemaVersion=2;objective='Complete the finite superseded task archive under the original fixed TC3 rules';requestedActionKind='CONTROL_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('task archive');pathHints=$scope;capabilityHints=@();mutationHints=@('control');externalHints=@();ambiguityState='CLEAR';facets=@{domain=@{state='KNOWN';values=@('aiw:governance')};workType=@{state='KNOWN';values=@('aiw:implementation')};deliverableType=@{state='KNOWN';values=@('aiw:configuration')};stage=@{state='KNOWN';values=@('aiw:closure')}}}}
        Archive-Json $discoverPath $discover
        $oldResolver=Join-Path $oldFixed 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'
        $d=Archive-Run $oldResolver @{InputPath=$discoverPath;CompactReceiptPath=$compactPath;AsJson=$true};if($d.code-ne0){throw ('ARCHIVE_REAL_DISCOVER_FAILED|'+$d.text)}
        $receipt=$d.value.compactReceipt;$admitPath=Join-Path $runtime 'original-admit-input.json'
        $boundary=[ordered]@{schemaVersion=3;mode='ADMIT_ACTION';discoverReceiptPath=$compactPath;expectedDiscoverReceiptIdentity=Archive-Id $compactPath;preparationReceipts=@($receipt.selectedObligations.preparationRequirements|Sort-Object -Unique);resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@()}
        Archive-Json $admitPath $boundary;$admitted=Archive-Run $oldResolver @{InputPath=$admitPath;AsJson=$true};Assert-True ($admitted.code-eq0-and$admitted.value.status-ceq'PASS') 'archive-original-admit-is-real-old-runtime-result'
        $admitResult=Join-Path $runtime 'original-admit-result.json';Write-TestText $admitResult ($admitted.text+"`n")
        $candidatePath=Join-Path $runtime 'reviewed-archive.md';$closedText=$oldText.Replace('lifecycle=ACTIVE;','lifecycle=CLOSED;')+"- Closure outcome: SUPERSEDED`n- Closure basis: test-only successor; original obligations remain in full history.`n"
        Write-TestText $candidatePath $closedText;Write-TestText (Join-Path $consumer $archive) $closedText;[IO.File]::Delete((Join-Path $consumer $active))
        $objectsPath=Join-Path $runtime 'original-objects.json'
        Archive-Json $objectsPath @(@{path=$active;operation='DELETE_AFTER_ARCHIVE_AND_FULL_HISTORY_WRITTEN';oldIdentity=Archive-Id $history;newIdentity='MISSING';candidatePath='NOT_APPLICABLE';activation='ISOLATED_REVIEWED_TEST_FIXTURE'},@{path=$archive;operation='WRITE';oldIdentity='MISSING';newIdentity=Archive-Id $candidatePath;candidatePath=$candidatePath;activation='ISOLATED_REVIEWED_TEST_FIXTURE'})
        $boundary.mode='FINALIZE_OUTPUT';$boundary.resultReceipts=@($receipt.selectedObligations.resultRequirements|Sort-Object -Unique)+@(('OBJECT_POSTIMAGE|'+$active+'|MISSING'),('OBJECT_POSTIMAGE|'+$archive+'|'+(Archive-Id $candidatePath)))
        $finalPath=Join-Path $runtime 'original-finalize-input.json';Archive-Json $finalPath $boundary
        $failed=Archive-Run $oldResolver @{InputPath=$finalPath;AsJson=$true};Assert-True ($failed.code-ne0-and$failed.value.reason-ceq'EVIDENCE_OBJECT_MISSING') 'unmodified-original-fixed-runtime-reproduces-exact-archive-failure'
        $failurePath=Join-Path $runtime 'original-finalize-failure.json';Write-TestText $failurePath ($failed.text+"`n")
        Copy-Item -LiteralPath $oldFixed -Destination $newFixed -Recurse
        $writePaths=@('scripts/ProjectAdoptionTransaction.psm1','scripts/upgrade-project.ps1','framework/versions/2.0.0/scripts/ResultEvidence.psm1','framework/versions/2.0.0/scripts/WorkflowDelivery.psm1','framework/versions/2.0.0/tests/result-acceptance-tests.ps1','framework/versions/2.0.0/tests/workflow-delivery-tests.ps1','framework/versions/2.0.0/tests/authorization-receipt-regression-tests.ps1','framework/versions/2.0.0/TOOL_CONTRACT.md','framework/versions/2.0.0/CHANGELOG.md','framework/PROJECT_ADOPTION.md','framework/FRAMEWORK_RELEASE.md')
        foreach($path in $writePaths){if(Test-Path -LiteralPath (Join-Path $newFixed $path)){[IO.File]::Copy((Join-Path $sourceRoot $path),(Join-Path $newFixed $path),$true)}}
        function Archive-SealFixture($Root){
            # Simulated release evidence, solely to exercise the real qualifier.
            $vr=Join-Path $Root 'framework/versions/2.0.0';$mp=Join-Path $vr 'RELEASE_MANIFEST.json';$m=(Read-AiwProjectJson $mp 'FIXTURE_MANIFEST').Value
            [string[]]$paths=@(Get-ChildItem -LiteralPath $vr -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($vr,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'RELEASE_MANIFEST.json'});[Array]::Sort($paths,[StringComparer]::Ordinal)
            $rows=@();[long]$total=0;foreach($path in $paths){$id=Archive-Id (Join-Path $vr $path);$total+=[long]$id.Split('|')[0];$rows+=($path+'|'+$id)}
            $canonical=(Get-AiwByteIdentity ($utf8.GetBytes($rows-join"`n"))).Split('|')[1]
            $m.PSObject.Properties.Remove('validationProof');$m.schemaVersion=2;$m.scope='all release payload files except RELEASE_MANIFEST.json';$m|Add-Member completeSuite ([pscustomobject]@{}) -Force;$m.fileCount=$paths.Count;$m.totalBytes=$total;$m.canonical=$canonical;$m.sourceReview='APPROVED';$m.sourceCandidate='ISOLATED_ARCHIVE_SIMULATED_QUALIFICATION';$m.completeSuite=[pscustomobject]@{status='PASS';passed=1;total=1;payloadCanonical=$canonical;evidenceIdentity=('1|'+('A'*64))};$m.sourceReviewEvidence=[pscustomobject]@{status='APPROVED';reviewer='fixture-reviewer';packageIdentity=('1|'+('B'*64));reviewedPayloadCanonical=$canonical;reviewedManifestIdentity=Archive-Id $mp};Archive-Json $mp $m
            [string[]]$files=@(Get-ChildItem -LiteralPath $Root -Recurse -File|ForEach-Object{[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')}|Where-Object{$_-cne'PACKAGE_MANIFEST.json'});[Array]::Sort($files,[StringComparer]::Ordinal);$entries=@();$rows=@()
            foreach($path in $files){$id=Archive-Id (Join-Path $Root $path);$entries+=@(@{path=$path;identity=$id});$rows+=($path+'='+$id)}
            Archive-Json (Join-Path $Root 'PACKAGE_MANIFEST.json') @{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;distributionId='2.0.0-snapshot.991';canonical=(Get-AiwByteIdentity ($utf8.GetBytes(($rows-join"`n")+"`n"))).Split('|')[1];files=$entries}
        }
        Archive-SealFixture $newFixed
        $decisionPath=Join-Path $runtime 'human-completion-fixture.txt';Write-TestText $decisionPath 'SIMULATED HUMAN SOURCE: original Owner completes this exact admitted archive with the new fixed validator. No adoption or object write.'
        $planPath=Join-Path $runtime 'completion-plan.json'
        function Archive-BindTool($Plan,$Root){
            $Plan.newDistribution=Get-AiwDistributionBinding $Root '2.0.0' -Required
            $manifest=(Read-AiwProjectJson (Join-Path $Root 'PACKAGE_MANIFEST.json') 'FIXTURE_PACKAGE').Value
            $additional=@($manifest.files.path|Where-Object{$_.StartsWith('framework/versions/2.0.0/',[StringComparison]::Ordinal)-and-not$_.Contains('/tests/')})
            $revision=Get-AiwRootToolRevision $Root (Get-AiwProjectAdoptionToolDependency UPGRADE $additional);$Plan.rootToolRevision=$revision.revision;$Plan.rootToolDependencies=@($revision.dependencies)
        }
        $plan=[ordered]@{schemaVersion=1;kind='ORIGINAL_TASK_ARCHIVE_FINALIZE';originals=@{discoverReceipt=Archive-Reference $compactPath;admitInput=Archive-Reference $admitPath;admitResult=Archive-Reference $admitResult;finalizeInput=Archive-Reference $finalPath;finalizeResult=Archive-Reference $failurePath;objects=Archive-Reference $objectsPath};deletedTasks=@(@{activePath=$active;archivePath=$archive;historyRef=Archive-Reference $history});completionDecisionRef=Archive-Reference $decisionPath;oldDistribution=$oldBinding;newDistribution=$null;rootToolRevision='';rootToolDependencies=@();outputDirectory=(Join-Path $runtime 'completion-evidence')}
        Archive-BindTool $plan $newFixed;Archive-Json $planPath $plan
        function Archive-Arguments($Root){@{ProjectId='archive-completion-fixture';ToVersion='2.0.0';RepositoryPath=$consumer;ActorRouteActor='archive-owner-fixture';OriginalTaskArchiveFinalizePlanPath=$planPath;ExpectedOriginalTaskArchiveFinalizePlanIdentity=Archive-Id $planPath;OriginalTaskArchiveForbiddenPath=@('private')}}
        function Archive-LiveSnapshot {
            $paths=@($taskPath,$configPath,$statePath,(Join-Path $consumer '.ai-workspace/controller.json'),(Join-Path $consumer 'AGENTS.md'),(Join-Path $consumer '.ai-workspace/process-policy.json'),(Join-Path $consumer '.ai-workspace/BOOTSTRAP.md'),(Join-Path $consumer $active),(Join-Path $consumer $archive),$history,$compactPath,$admitPath,$admitResult,$finalPath,$failurePath,$objectsPath)
            return (@($paths|ForEach-Object{$_+'='+(Archive-CurrentIdentity $_)})-join"`n")
        }
        $before=Archive-LiveSnapshot;$arguments=Archive-Arguments $newFixed;$entry=Join-Path $newFixed 'scripts/upgrade-project.ps1'
        $preview=Archive-Run $entry $arguments
        Assert-True ($preview.code-eq0-and$preview.value.status-ceq'WHAT_IF'-and(Archive-LiveSnapshot)-ceq$before-and-not(Test-Path $plan.outputDirectory)) ('archive-completion-preview-zero-write|'+$preview.text)
        foreach($case in @('wrong-actor','apply','adoption','rollback','source-root','missing-admit','forged-admission','task-drift','epoch-drift','third-party','history-drift','missing-object','forged-missing','mixed-preimage','bad-package','extra-implementation')){
            $savedPlan=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -AsHashtable;$args=Archive-Arguments $newFixed;$toolEntry=$entry;$changedPath=$null;$savedBytes=$null
            switch($case){
                'wrong-actor'{$args.ActorRouteActor='wrong'}
                'apply'{$args.Apply=$true}
                'adoption'{$args.LocalCandidatePilot=$true}
                'rollback'{$args.ProjectRuleRecoveryDirection='ROLLBACK'}
                'source-root'{$toolEntry=Join-Path $sourceRoot 'scripts/upgrade-project.ps1'}
                'missing-admit'{$plan.originals.admitResult.path=Join-Path $runtime 'no-admit.json'}
                'forged-admission'{$changedPath=$admitResult;$savedBytes=[IO.File]::ReadAllBytes($changedPath);$fake=$admitted.value|ConvertTo-Json -Depth 100|ConvertFrom-Json;$fake.decisionIdentity='F'*64;Archive-Json $changedPath $fake;$plan.originals.admitResult=Archive-Reference $changedPath}
                'task-drift'{$changedPath=$taskPath}
                'epoch-drift'{$changedPath=Join-Path $consumer '.ai-workspace/controller.json';$savedBytes=[IO.File]::ReadAllBytes($changedPath);$fake=(Read-AiwProjectJson $changedPath 'CONTROLLER').Value;$fake.controllerEpoch++;Archive-Json $changedPath $fake}
                'third-party'{$changedPath=Join-Path $consumer $archive}
                'history-drift'{$changedPath=$history}
                'missing-object'{$changedPath=$objectsPath;$savedBytes=[IO.File]::ReadAllBytes($changedPath);$o=(Read-AiwProjectJson $changedPath 'OBJECTS').Value;Archive-Json $changedPath @($o[0]);$plan.originals.objects=Archive-Reference $changedPath}
                'forged-missing'{$changedPath=$finalPath;$savedBytes=[IO.File]::ReadAllBytes($changedPath);$fake=$boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json;$fake.resultReceipts[($fake.resultReceipts.Count-2)]='OBJECT_POSTIMAGE|'+$active+'|NEW';Archive-Json $changedPath $fake;$plan.originals.finalizeInput=Archive-Reference $changedPath}
                'mixed-preimage'{$changedPath=Join-Path $consumer $archive;$savedBytes=[IO.File]::ReadAllBytes($changedPath);Write-TestText $changedPath $oldText}
                'bad-package'{$changedPath=Join-Path $newFixed 'framework/versions/2.0.0/scripts/ResultEvidence.psm1'}
                'extra-implementation'{$changedPath=Join-Path $newFixed 'framework/versions/2.0.0/scripts/resolve-process-requirements.ps1'}
            }
            if($changedPath-and$null-eq$savedBytes){$savedBytes=[IO.File]::ReadAllBytes($changedPath);[IO.File]::AppendAllText($changedPath,"`n# third party drift",$utf8)}
            if($case-ceq'extra-implementation'){Archive-SealFixture $newFixed;Archive-BindTool $plan $newFixed}
            Archive-Json $planPath $plan;$args.ExpectedOriginalTaskArchiveFinalizePlanIdentity=Archive-Id $planPath;$guardBefore=Archive-LiveSnapshot
            $rejected=Archive-Run $toolEntry $args
            $expectedReason=switch($case){
                'wrong-actor'{'ORIGINAL_ARCHIVE_CONTEXT'}
                {$_-cin@('apply','adoption','rollback')}{'ORIGINAL_ARCHIVE_OPERATION_EXCLUSIVE'}
                'source-root'{'DISTRIBUTION_RUNTIME_ROOT_DRIFT'}
                'missing-admit'{'ORIGINAL_ARCHIVE_EVIDENCE_DRIFT'}
                'forged-admission'{'ORIGINAL_ARCHIVE_ADMISSION_DECISION'}
                {$_-cin@('task-drift','epoch-drift')}{'ORIGINAL_ARCHIVE_SOURCE_DRIFT'}
                {$_-cin@('third-party','mixed-preimage')}{'ORIGINAL_ARCHIVE_THIRD_PARTY_OBJECT'}
                'history-drift'{'ORIGINAL_ARCHIVE_EVIDENCE_DRIFT'}
                'missing-object'{'ORIGINAL_ARCHIVE_OBJECT_SET'}
                'forged-missing'{'ORIGINAL_ARCHIVE_FINAL_POSTIMAGE'}
                'bad-package'{'DISTRIBUTION_CONTENT_DRIFT'}
                'extra-implementation'{'ORIGINAL_ARCHIVE_INCOMPATIBLE_DEPENDENCY'}
            }
            Assert-True ($rejected.code-ne0-and$rejected.text.Contains($expectedReason)-and(Archive-LiveSnapshot)-ceq$guardBefore-and-not(Test-Path $plan.outputDirectory)) ('archive-completion-rejects-'+$case+'-at-'+$expectedReason+'-zero-write|'+$rejected.text)
            if($changedPath){[IO.File]::WriteAllBytes($changedPath,$savedBytes)}
            $plan=$savedPlan
            if($case-ceq'extra-implementation'){Archive-SealFixture $newFixed;Archive-BindTool $plan $newFixed}
            Archive-Json $planPath $plan
        }
        # A separate intact copy is legal; location alone is not authority.
        $independentCopy=Join-Path $fixtureRoot 'independent-fixed-copy';Copy-Item -LiteralPath $newFixed -Destination $independentCopy -Recurse
        Archive-BindTool $plan $independentCopy;Archive-Json $planPath $plan;$arguments=Archive-Arguments $independentCopy;$arguments.CompleteOriginalTaskArchive=$true
        $completedArchive=Archive-Run (Join-Path $independentCopy 'scripts/upgrade-project.ps1') $arguments
        Assert-True ($completedArchive.code-eq0-and$completedArchive.value.status-ceq'PASS'-and$completedArchive.value.reason-ceq'ORIGINAL_ADMITTED_ARCHIVE_FINALIZED_WITH_COMPATIBLE_FIXED_TOOL') ('archive-real-original-finalize-via-compatible-independent-fixed-copy|'+$completedArchive.text)
        Assert-True ((Archive-LiveSnapshot)-ceq$before-and-not$completedArchive.value.projectWritePerformed-and-not$completedArchive.value.authorityGranted-and-not$completedArchive.value.userAuthorizationProven) 'archive-completion-preserves-task-pin-state-history-all-postimages-and-old-failure'
        $command=(Read-AiwProjectJson (Join-Path $plan.outputDirectory 'command.json') 'REAL_COMMAND').Value
        Assert-True ($command.exitCode-eq0-and$completedArchive.value.executionPath.StartsWith($independentCopy)-and$completedArchive.value.originalFinalize.identity-ceq(Archive-Id $finalPath)) 'archive-completion-has-actual-isolated-command-and-unchanged-original-input'
        $stillOld=Archive-Run $oldResolver @{InputPath=$finalPath;AsJson=$true}
        Assert-True ($stillOld.code-ne0-and$stillOld.value.reason-ceq'EVIDENCE_OBJECT_MISSING') 'original-fixed-tool-still-fails-proving-no-hotpatch-or-pretend-old-pass'
        Write-Output ('PASS|original-task-archive-finalize|'+$passed+'/'+$passed+'|new-qualification=SIMULATED_TEST_ONLY');return
    }
    Reset-TestProject
    $packageModule=Get-Module ProjectAdoptionTransaction
    $packagePath=Join-Path $fixtureRoot 'process-package.json'
    $configIdentity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $fixtureRoot '.ai-workspace/project.json')))
    $context=[pscustomobject]@{actor='actor';taskOwner='owner';taskIdentity='task-bytes';taskId='task';userDecision='decision';exactScope=@('AGENTS.md')}
    $receipt=[pscustomobject]@{sourceLocators=[pscustomobject]@{authorizationPackagePath=$packagePath};sourceBindings=[pscustomobject]@{projectConfigIdentity=$configIdentity}}
    $basePackage=[ordered]@{schemaVersion=1;grantee='actor';owner='owner';taskIdentity='task-bytes';taskId='task';projectConfigIdentity=$configIdentity;userConfirmation='decision';actions=@('CONTROL_WRITE');exactPaths=@('AGENTS.md')}
    foreach($case in @('schema1','schema2','schema3','actor','owner','task','taskIdentity','config','decision','continuation','action','scope','identity')){
        $pkg=$basePackage|ConvertTo-Json -Depth 10|ConvertFrom-Json
        switch($case){
            'schema2'{$pkg.schemaVersion=2};'schema3'{$pkg.schemaVersion=3}
            'actor'{$pkg.grantee='wrong'};'owner'{$pkg.owner='wrong'};'task'{$pkg.taskId='wrong'}
            'taskIdentity'{$pkg.taskIdentity='wrong'};'config'{$pkg.projectConfigIdentity='wrong'};'decision'{$pkg.userConfirmation='wrong'}
            'continuation'{$pkg|Add-Member continuationPlan @()};'action'{$pkg.actions=@('SOURCE_WRITE')};'scope'{$pkg.exactPaths=@('other.md')}
        }
        Write-TestText $packagePath (($pkg|ConvertTo-Json -Depth 10 -Compress)+"`n")
        $context|Add-Member authorizationIdentity (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($packagePath))) -Force
        if($case-ceq'identity'){$context.authorizationIdentity='1|INVALID'}
        $reason='';try{$null=& $packageModule {param($r,$c,$root) Get-AiwAdoptionProcessPackage $r $c $root} $receipt $context $fixtureRoot}catch{$reason=$_.Exception.Message}
        Assert-True (($case-in@('schema1','schema2')-and$reason-eq'')-or($case-notin@('schema1','schema2')-and$reason-like'ADOPTION_PROCESS_*')) ('adoption-process-package-'+$case)
    }
    $cfgPath=Join-Path $fixtureRoot '.ai-workspace/project.json'
    $cfg=Get-Content -LiteralPath $cfgPath -Raw|ConvertFrom-Json
    $cfg|Add-Member controlPlaneLayout 'framework-maintenance-sibling'
    Write-TestText $cfgPath (($cfg|ConvertTo-Json -Depth 10 -Compress)+"`n")
    foreach($schema in @(1,2)){
        $pkg=$basePackage|ConvertTo-Json -Depth 10|ConvertFrom-Json;$pkg.schemaVersion=$schema
        $pkg.projectConfigIdentity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes($cfgPath));$receipt.sourceBindings.projectConfigIdentity=$pkg.projectConfigIdentity
        Write-TestText $packagePath (($pkg|ConvertTo-Json -Depth 10 -Compress)+"`n")
        $context.authorizationIdentity=Get-AiwByteIdentity ([IO.File]::ReadAllBytes($packagePath))
        $reason='';try{$null=& $packageModule {param($r,$c,$root) Get-AiwAdoptionProcessPackage $r $c $root} $receipt $context $fixtureRoot}catch{$reason=$_.Exception.Message}
        Assert-True (($schema-eq1-and$reason-ceq'ADOPTION_PROCESS_PACKAGE_BINDING')-or($schema-eq2-and$reason-eq'')) ('maintenance-process-package-'+$schema)
    }
    if($AdoptionPackageOnly){Write-Output ('PASS|adoption-process-package|'+$passed+'/'+$passed);return}
    if($ActorStorageOnly){
        if(-not$LegacyRuntimeRoot){throw 'ACTOR_STORAGE_LEGACY_RUNTIME_REQUIRED'}
        $sourceRoot=Split-Path -Parent $scriptsRoot
        New-Item -ItemType Directory -Path $fixtureRoot -Force|Out-Null
        & git -C $fixtureRoot init -q
        $actors=@('Actor','/root/review_actor','01a0b915-e25c-73c1-96a6-0f6e50b13417')
        function Identity($Path){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($Path))}
        function Expected-Key($Actor){if($Actor-ceq$actors[2]){return $Actor};return 'actor-sha256-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($Actor))).ToLowerInvariant()}
        # Exercise the exact private Maintenance cleanup body with its original script-root binding.
        $tokens=$null;$errors=$null;$maintenancePath=Join-Path $scriptsRoot 'resolve-framework-maintenance-process-requirements.ps1'
        $ast=[Management.Automation.Language.Parser]::ParseFile($maintenancePath,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'MAINTENANCE_TEST_PARSE'}
        $fn=$ast.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Assert-AdoptionCleanupPath'},$true)
        . ([scriptblock]::Create($fn.Extent.Text.Replace('$PSScriptRoot',("'"+$scriptsRoot.Replace("'","''")+"'"))))
        $controlRoot=[IO.Path]::GetFullPath($fixtureRoot)
        $serial=0
        # New -> old -> new detects stale exports from another imported runtime.
        foreach($runtimeRoot in @($sourceRoot,$LegacyRuntimeRoot,$sourceRoot)){
            $runtimeVersion=if($runtimeRoot-ceq$sourceRoot){'2.0.0'}else{'1.16.0'}
            $runtimeComposer=Import-Module (Join-Path $runtimeRoot ('framework/versions/'+$runtimeVersion+'/scripts/ProcessRequirementComposition.psm1')) -Force -PassThru
            $hasStorageExport=$runtimeComposer.ExportedFunctions.ContainsKey('Get-AiwRuntimeActorStorageKey')
            foreach($actor in $actors){
                $serial++;$expected=if($hasStorageExport){Expected-Key $actor}else{$actor}
                $reason='';$key='';try{$key=Get-AiwBoundRuntimeActorStorageKey $runtimeRoot $runtimeVersion $actor}catch{$reason=$_.Exception.Message}
                if(-not$hasStorageExport-and$actor.Contains('/')){Assert-True ($reason-ceq'RUNTIME_ACTOR_LEGACY_CONTEXT') 'old-runtime-rejects-slash-without-borrowing-new-export';continue}
                Assert-True ($reason-eq''-and$key-ceq$expected) ('actual-runtime-storage-contract-'+$serial)
                $taskId='ACTOR-STORAGE-001'
                $context=[ordered]@{projectRoot=$controlRoot;frameworkVersion=$runtimeVersion;actor=$actor;taskId=$taskId;authorizedActions=@('CONTROL_WRITE');exactScope=@('.ai-workspace/BOOTSTRAP.md',('.ai-workspace/upgrade-recovery/'+$runtimeVersion+'/state.json'))}
                $intent=[ordered]@{requestedActionKind='CONTROL_WRITE';ambiguityState='CLEAR'}
                $contextIdentity=(Get-AiwByteIdentity ($utf8.GetBytes(($context|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1]
                $receipt=[ordered]@{schemaVersion=2;inputContractVersion=3;status='PASS';mode='DISCOVER';receiptType='PROCESS_REQUIREMENTS_DISCOVER';authorityGranted=$false;semanticCorrectnessProven=$false;binding=$context;intentEnvelope=$intent;contextIdentity=$contextIdentity;sourceLocators=@{frameworkRoot=$runtimeRoot}}
                $receiptPath=Join-Path $fixtureRoot ('receipt-'+$serial+'.json');Write-TestText $receiptPath (($receipt|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $boundary=[ordered]@{schemaVersion=2;mode='ADMIT_ACTION';discoverReceiptPath=$receiptPath;expectedDiscoverReceiptIdentity=Identity $receiptPath;preparationReceipts=@();resultReceipts=@();deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND'}
                $inputFull=Join-Path $fixtureRoot ('.ai-workspace/runtime/'+$taskId+'/'+$expected+'/input.json')
                New-Item -ItemType Directory -Path (Split-Path -Parent $inputFull) -Force|Out-Null
                Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                Assert-AdoptionCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)
                Assert-True (Test-Path $inputFull) ('maintenance-validates-without-deleting-'+$serial)
                # Stop at absent preparation, after the real root API validates cleanup scope.
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actor -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_EVIDENCE_REQUIRED|PREPARATION'-and-not(Test-Path $inputFull)) ('root-boundary-cleans-bound-input-on-later-failure-'+$serial)
                Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor 'wrong-actor' -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_ACTOR_ROOT'-and(Test-Path $inputFull)) ('root-wrong-actor-keeps-input-'+$serial)
                $inputFull=Join-Path $fixtureRoot ('.ai-workspace/runtime/'+$taskId+'/wrong-storage/input.json');New-Item -ItemType Directory -Path (Split-Path -Parent $inputFull) -Force|Out-Null;Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
                $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actor -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'ADOPTION_PROCESS_CLEANUP_SCOPE'-and(Test-Path $inputFull)) ('root-wrong-path-keeps-input-'+$serial)
                $reason='';try{Assert-AdoptionCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)}catch{$reason=$_.Exception.Message}
                Assert-True ($reason-ceq'MAINTENANCE_CLEANUP_SCOPE'-and(Test-Path $inputFull)) ('maintenance-wrong-path-keeps-input-'+$serial)
            }
        }
        # A junction in the actor directory must not authorize cleanup of its destination.
        $junction=Join-Path $fixtureRoot ('.ai-workspace/runtime/ACTOR-STORAGE-001/'+(Expected-Key $actors[0]))
        $destination=Join-Path $fixtureRoot 'junction-destination';New-Item -ItemType Directory -Path $destination -Force|Out-Null
        if(-not[IO.Path]::GetFullPath($junction).StartsWith([IO.Path]::GetFullPath($fixtureRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'ACTOR_JUNCTION_TEST_SCOPE'}
        if(Test-Path $junction){Remove-Item -LiteralPath $junction -Recurse -Force}
        New-Item -ItemType Junction -Path $junction -Target $destination|Out-Null
        try{
            $receipt.binding.actor=$actors[0];$receipt.sourceLocators.frameworkRoot=$sourceRoot
            $receipt.contextIdentity=(Get-AiwByteIdentity ($utf8.GetBytes(($receipt.binding|ConvertTo-Json -Depth 30 -Compress)+"`n"+($receipt.intentEnvelope|ConvertTo-Json -Depth 30 -Compress)))).Split('|')[1]
            Write-TestText $receiptPath (($receipt|ConvertTo-Json -Depth 30 -Compress)+"`n");$boundary.expectedDiscoverReceiptIdentity=Identity $receiptPath
            $inputFull=Join-Path $junction 'input.json';Write-TestText $inputFull (($boundary|ConvertTo-Json -Depth 30 -Compress)+"`n")
            $reason='';try{Assert-AdoptionCleanupPath ($receipt|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30)}catch{$reason=$_.Exception.Message}
            Assert-True ($reason-ceq'MAINTENANCE_CLEANUP_REPARSE'-and(Test-Path $inputFull)) 'maintenance-reparse-keeps-target'
            $reason='';try{$null=Invoke-AiwAdoptionProcessBoundary -RepositoryRoot $fixtureRoot -InputPath $inputFull -ExpectedInputIdentity (Identity $inputFull) -ObservedActor $actors[0] -ExpectedMode ADMIT_ACTION -DeleteInputOnExit}catch{$reason=$_.Exception.Message}
            Assert-True ($reason.Contains('REPARSE')-and(Test-Path $inputFull)) 'root-reparse-keeps-target'
        }finally{Remove-Item -LiteralPath $junction -Force}
        if($CleanupOnly){Write-Output ('PASS|adoption-cleanup|'+$passed+'/'+$passed);return}
        # Reuse the real source-recovery suite with only its anonymous actor fixture varied.
        $copy=Join-Path $fixtureRoot 'recovery-source';$copyVersion=Join-Path $copy 'framework/versions/1.16.0'
        New-Item -ItemType Directory -Path (Split-Path -Parent $copyVersion) -Force|Out-Null
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'framework/versions/1.16.0') -Destination $copyVersion -Recurse
        Copy-Item -LiteralPath $scriptsRoot -Destination (Join-Path $copy 'scripts') -Recurse
        $testPath=Join-Path $copyVersion 'tests/source-postimage-transition-tests.ps1'
        $original=[IO.File]::ReadAllText($testPath)
        foreach($actor in $actors){
            [IO.File]::WriteAllText($testPath,$original.Replace('executor-fixture',$actor),$utf8)
            $output=@(& pwsh -NoProfile -NonInteractive -File $testPath 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE
            if($code-ne0){throw ('ACTOR_RECOVERY_FAILED|'+$actor+'|'+($output-join';'))}
            Assert-True (@($output|Where-Object{$_-ceq'PASS|authorized-mixed-state-original-action-finalized'}).Count-eq1) ('real-rule-recovery-finalized-'+$actor)
            Write-Output ('PASS|actor-recovery|actor='+$actor+'|'+$output[-1])
        }
        Write-Output ('PASS|actor-storage-root-consumers|'+$passed+'/'+$passed)
        return
    }
    $custom = "# Project conventions`nOnly the approved project goal is delegated.`n"
    Assert-True ((Get-AiwStandingDelegationProjection -Text $custom) -ceq $custom) 'viewing-does-not-create-adoption'
    $sourceRoot=Split-Path -Parent $scriptsRoot
    $entryCases=@(
        @{version='1.16.0';template='framework/versions/1.16.0/project-starter/AGENTS.md'},
        @{version='2.0.0';template='framework/versions/2.0.0/project-starter/AGENTS.md'},
        @{version='2.0.0';template='framework/maintenance-overlay/AGENTS.md'}
    )
    foreach($entryCase in $entryCases){
        $templatePath=Join-Path $sourceRoot $entryCase.template
        $navigation=Get-AiwNavigationContract (Get-Content -LiteralPath (Join-Path $sourceRoot ('framework/versions/'+$entryCase.version+'/TOOLCHAIN.json')) -Raw|ConvertFrom-Json)
        $projection=@{AdoptionRequested=$true;TemplatePath=$templatePath;RouterSkillName=[string]$navigation.SkillName;NavigationKind=[string]$navigation.Kind}
        $delegated=Get-AiwStandingDelegationProjection -Text $custom @projection
        $block=Get-AiwAgentsTemplateBlock $delegated
        $bootstrap=$navigation.Kind-ceq'PROJECT_BOOTSTRAP'
        Assert-True ($(if($bootstrap){$block.Contains('.ai-workspace/BOOTSTRAP.md')-and-not$block.Contains('Skill')}else{$block.Contains('`'+$navigation.SkillName+'`')})-and-not$block.Contains('{{ROUTER_SKILL_NAME}}')) ('entry-name-from-target-contract-'+$entryCase.version+'-'+$entryCase.template)
        Assert-True ($delegated.StartsWith($custom)-and$(if($bootstrap){-not$delegated.Contains('在本项目内，AI')}else{$block.Contains('在本项目内，AI')})) 'existing-entry-does-not-reintroduce-default-grant'
        $freshEntry=Get-AiwStandingDelegationProjection -Text '' @projection
        Assert-True ($freshEntry.Contains('在本项目内，AI 根据当前采用的 Framework、当前生效的项目纠正及永久规则作出的具体工作决定，均视为用户明确决定')-and$(if($bootstrap){(Get-AiwAgentsTemplateBlock $freshEntry -Block USER-DECISION).Contains('在本项目内，AI')-and-not(Get-AiwAgentsTemplateBlock $freshEntry).Contains('在本项目内，AI')}else{$true})) 'new-explicit-adoption-keeps-complete-grant-in-owning-region'
        Assert-True ((Get-AiwStandingDelegationProjection -Text $delegated @projection)-ceq$delegated) 'template-projection-idempotent'
        $changed=($custom+$freshEntry).Replace('在本项目内，AI','HAND_EDITED_MANAGED')+"`n用户撤回持续委托。`n"
        $updated=Get-AiwStandingDelegationProjection -Text $changed @projection
        Assert-True ($updated.Contains('HAND_EDITED_MANAGED')-eq$bootstrap-and$updated.EndsWith("`n用户撤回持续委托。`n")-and$updated.StartsWith($custom)) 'navigation-refresh-preserves-current-user-owned-edit-and-revocation'
        if($bootstrap){
            $oldBlock=[IO.File]::ReadAllText((Join-Path $sourceRoot 'framework/versions/1.16.0/project-starter/AGENTS.md')).TrimEnd("`r","`n")
            $oldBlock=$oldBlock.Replace('无须逐任务、逐步骤再次确认。','仅限本次明确目标，不得发布；无须逐任务、逐步骤再次确认。')
            $grant=[regex]::Match($oldBlock,'(?m)^在本项目内[^\r\n]*').Value
            $outside="`r`n<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->`r`n用户将委托收窄为只读分析。`r`n<!-- AI-WORKSPACE-USER-DECISION:END -->"
            $legacy=$custom+$oldBlock+$outside
            $migrated=Get-AiwStandingDelegationProjection -Text $legacy @projection
            $managedPattern='(?s)<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->.*?<!-- AI-WORKSPACE-FRAMEWORK:END -->'
            Assert-True ($migrated.StartsWith($custom)-and$migrated.EndsWith($outside)-and$migrated.Contains($grant)-and$migrated.IndexOf($grant)-lt$migrated.IndexOf($outside)-and-not(Get-AiwAgentsTemplateBlock $migrated).Contains($grant)) 'upgrade-preserves-grant-before-complete-later-user-restriction'
            Assert-True ((Get-AiwStandingDelegationProjection -Text $migrated @projection)-ceq$migrated) 'legacy-migration-idempotent'
            $sourceNav1=Get-AiwNavigationContract (Get-Content -LiteralPath (Join-Path $sourceRoot 'framework/versions/1.16.0/TOOLCHAIN.json') -Raw|ConvertFrom-Json)
            $migrationSources=@(@{name='source-nav1-ordinary';path=(Join-Path $sourceRoot 'framework/versions/1.16.0/project-starter/AGENTS.md');router=$sourceNav1.SkillName})
            if($LegacyRuntimeRoot){
                foreach($legacyVersion in @('1.16.0','2.0.0')){
                    $legacyTemplate=Join-Path $LegacyRuntimeRoot ('framework/versions/'+$legacyVersion+'/project-starter/AGENTS.md')
                    if(-not(Test-Path -LiteralPath $legacyTemplate -PathType Leaf)){continue}
                    $legacyNav=Get-AiwNavigationContract (Get-Content -LiteralPath (Join-Path $LegacyRuntimeRoot ('framework/versions/'+$legacyVersion+'/TOOLCHAIN.json')) -Raw|ConvertFrom-Json)
                    if($legacyNav.Kind-cne'SKILL'){throw 'MIGRATION_TEST_REQUIRES_ORIGINAL_NAV1_OR_NAV2_RUNTIME'}
                    $migrationSources+=@(@{name=($legacyVersion+'-ordinary');path=$legacyTemplate;router=$legacyNav.SkillName},@{name=($legacyVersion+'-maintenance');path=(Join-Path $LegacyRuntimeRoot 'framework/maintenance-overlay/AGENTS.md');router=$legacyNav.SkillName})
                }
            }
            $seenMigrationBodies=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($migrationSource in $migrationSources){
                $sourceTemplate=[IO.File]::ReadAllText($migrationSource.path)
                $sourceTemplate=$sourceTemplate.Replace('{{ROUTER_SKILL_NAME}}',[string]$migrationSource.router)
                $sourceBlock=Get-AiwAgentsTemplateBlock $sourceTemplate
                if(-not$seenMigrationBodies.Add($sourceBlock.Replace("`r`n","`n"))){continue}
                $sourceGrant=[regex]::Match($sourceBlock,'(?m)^在本项目内[^\r\n]*').Value
                Assert-True ($sourceGrant.Length-gt0) ('bootstrap-reference-source-has-real-grant-'+$migrationSource.name)
                $restrictedGrant=$sourceGrant+' 恢复时另读 .ai-workspace/BOOTSTRAP.md；仅限只读，禁止发布。'
                $restrictedBlock=$sourceBlock.Replace($sourceGrant,$restrictedGrant)
                $collaboration=[regex]::Match($sourceBlock,'(?m)^已批准协作工作流内的[^\r\n]*').Value
                $restrictedCollaboration=if($collaboration){$collaboration+' .ai-workspace/BOOTSTRAP.md 只用于导航，不扩大许可。'}else{''}
                if($collaboration){$restrictedBlock=$restrictedBlock.Replace($collaboration,$restrictedCollaboration)}
                $before=$custom+$restrictedBlock+$outside
                $after=Get-AiwStandingDelegationProjection -Text $before @projection
                $beforeOutside=[regex]::Replace($before,$managedPattern,'')
                $afterOutside=[regex]::Replace($after,$managedPattern,'')
                Assert-True ($after.StartsWith($custom)-and$after.EndsWith($outside)-and$after.Contains($restrictedGrant)-and$after.IndexOf($restrictedGrant)-lt$after.IndexOf($outside)-and-not(Get-AiwAgentsTemplateBlock $after).Contains($restrictedGrant)-and(-not$collaboration-or$after.Contains($restrictedCollaboration))) ('bootstrap-reference-preserves-complete-current-grants-and-later-outside-'+$migrationSource.name)
                Assert-True ((Get-AiwStandingDelegationProjection -Text $after @projection)-ceq$after) ('bootstrap-reference-migration-idempotent-'+$migrationSource.name)
                $unknownBlock=$sourceBlock.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`n未知职责：阅读 .ai-workspace/BOOTSTRAP.md 仅作导航，禁止修改。`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
                $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text ($custom+$unknownBlock+$outside) @projection}catch{$rejected=$_.ToString().Contains('AGENTS_AUTHORIZATION_MIGRATION_CONFLICT')}
                Assert-True $rejected ('bootstrap-reference-unknown-source-conflicts-'+$migrationSource.name)
            }
            $pureNav=Get-AiwAgentsTemplateBlock $delegated
            $plainDecision="## 项目工作约定（用户拥有）`r`n`r`n在本项目内，AI 只可读取；保留原有空格。  `r`n`r`n用户已撤回创建和发布许可。`r`n"
            $unlabelled=$custom+$pureNav+$plainDecision+"## 其他约定`r`n保持后文。`r`n"
            $labelled=Get-AiwStandingDelegationProjection -Text $unlabelled @projection
            Assert-True ($labelled.Contains($plainDecision)-and$labelled.Contains('<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->')-and-not$labelled.Contains('均视为用户明确决定')-and$labelled.EndsWith("## 其他约定`r`n保持后文。`r`n")) 'unlabelled-user-section-preserves-raw-crlf-context-and-revocation'
            Assert-True ((Get-AiwStandingDelegationProjection -Text $labelled @projection)-ceq$labelled) 'unlabelled-migration-is-idempotent'
            $withdrawn=$custom+"用户撤回持续委托，只能只读分析。`r`n"
            $withdrawnEntry=Get-AiwStandingDelegationProjection -Text $withdrawn @projection
            Assert-True ($withdrawnEntry.StartsWith($withdrawn)-and-not$withdrawnEntry.Contains('均视为用户明确决定')) 'unlabelled-withdrawal-without-managed-entry-does-not-revive-template-grant'
            $tagged=$custom+$pureNav+$outside
            Assert-True ((Get-AiwStandingDelegationProjection -Text $tagged @projection)-ceq$tagged) 'existing-labelled-restriction-remains-byte-exact'
            $transactionRoot=Join-Path $fixtureRoot ('entry-'+[guid]::NewGuid().ToString('N'))
            $null=[IO.Directory]::CreateDirectory($transactionRoot)
            $agentsFile=Join-Path $transactionRoot 'AGENTS.md';[IO.File]::WriteAllText($agentsFile,$unlabelled,$utf8)
            $projectionObjects=New-AiwProjectProjection $transactionRoot @([pscustomobject]@{path='AGENTS.md';text=$labelled})
            $journal='.ai-workspace/runtime/project-adoption/entry/state.json'
            $interrupted=Invoke-AiwProjectProjectionTransaction $transactionRoot $projectionObjects $journal {$true} {$true} -InterruptAfterWrite 1
            Assert-True ([IO.File]::ReadAllText($agentsFile)-ceq$labelled) 'real-projection-interruption-has-complete-user-preserving-postimage'
            $restored=Resume-AiwProjectProjectionRollback $transactionRoot $journal (Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $transactionRoot $journal)))) {$true}
            Assert-True ($restored.status-ceq'ROLLED_BACK'-and[IO.File]::ReadAllText($agentsFile)-ceq$unlabelled) 'real-rollback-restores-entire-original-agents-bytes'
            [IO.File]::WriteAllText($agentsFile,'Third-party withdrawal must survive.',$utf8)
            $driftRefused=$false;try{$null=Invoke-AiwProjectProjectionTransaction $transactionRoot $projectionObjects '.ai-workspace/runtime/project-adoption/drift/state.json' {$true} {$true}}catch{$driftRefused=$true}
            Assert-True ($driftRefused-and[IO.File]::ReadAllText($agentsFile)-ceq'Third-party withdrawal must survive.') 'real-projection-refuses-third-party-change-before-overwrite'
            $crlfNav=$pureNav.Replace("`r`n","`n").Replace("`n","`r`n").TrimEnd("`r","`n")
            $crlfInput=$delegated.Replace($pureNav.TrimEnd("`r","`n"),$crlfNav)
            $crlfResult=Get-AiwStandingDelegationProjection -Text $crlfInput @projection
            Assert-True ($crlfResult-ceq$delegated-and(Get-AiwStandingDelegationProjection -Text $crlfResult @projection)-ceq$crlfResult) 'pure-nav3-crlf-refresh-canonical-and-idempotent'
            $customNav=$pureNav.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`n未知nav3职责 .ai-workspace/BOOTSTRAP.md：仅限只读。`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
            $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text ($delegated.Replace($pureNav,$customNav)) @projection}catch{$rejected=$_.ToString().Contains('AGENTS_AUTHORIZATION_MIGRATION_CONFLICT')}
            Assert-True $rejected 'nav3-extra-custom-cannot-be-silently-replaced'
            foreach($unknown in @($oldBlock.Replace('按需开展治理工作。','按需开展治理工作。只允许本次读取。'),$oldBlock.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"自定未知职责。`n<!-- AI-WORKSPACE-FRAMEWORK:END -->"))){
                $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text ($custom+$unknown+$outside) @projection}catch{$rejected=$_.ToString().Contains('AGENTS_AUTHORIZATION_MIGRATION_CONFLICT')}
                Assert-True $rejected 'unknown-mixed-custom-is-preserved-by-refusing-projection'
            }
        }
        $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text ($custom+'<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->') @projection}catch{$rejected=$_.ToString().Contains('AGENTS_MANAGED_MARKERS_MALFORMED')}
        Assert-True $rejected 'malformed-managed-markers-rejected'
    }
    $oldTemplate=Join-Path $sourceRoot 'framework/versions/1.16.0/project-starter/AGENTS.md'
    foreach($badName in @('', '../router', 'Router')){
        $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text $custom -AdoptionRequested $true -TemplatePath $oldTemplate -RouterSkillName $badName}catch{$rejected=$_.ToString().Contains('AGENTS_ROUTER_NAME_REQUIRED')}
        Assert-True $rejected 'missing-or-invalid-router-name-rejected'
    }
    $rejected=$false;try{$null=Get-AiwStandingDelegationProjection -Text $custom -AdoptionRequested $true -TemplatePath $oldTemplate -RouterSkillName 'ai-workspace-router-v2'}catch{$rejected=$_.ToString().Contains('AGENTS_ROUTER_TEMPLATE_MISMATCH')}
    Assert-True $rejected 'fixed-old-template-cannot-claim-v2'
    # Exercise the upgrader's actual source-fact -> projection call, not a
    # test-owned adapter or a hand-built trusted navigation value. These helper
    # definitions come from the real entry; the entry's top-level actions are
    # deliberately not invoked by this bounded EntryTemplatesOnly consumer.
    $upgradeTokens=$null;$upgradeErrors=$null
    $upgradeAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptsRoot 'upgrade-project.ps1'),[ref]$upgradeTokens,[ref]$upgradeErrors)
    if($upgradeErrors.Count){throw 'ENTRY_UPGRADER_SYNTAX'}
    $upgradeDefinitions=@($upgradeAst.FindAll({param($node)
        if($node-isnot[Management.Automation.Language.FunctionDefinitionAst]){return $false}
        $parent=$node.Parent
        while($null-ne$parent){if($parent-is[Management.Automation.Language.FunctionDefinitionAst]){return $false};$parent=$parent.Parent}
        return $true
    },$true)|ForEach-Object{$_.Extent.Text})-join"`n"
    $upgradeOwner=New-Module -ArgumentList $scriptsRoot,$upgradeDefinitions -ScriptBlock {
        param($root,$definitions)
        Set-StrictMode -Version Latest
        $utf8NoBom=[Text.UTF8Encoding]::new($false);$utf8Strict=[Text.UTF8Encoding]::new($false,$true)
        Import-Module (Join-Path $root 'ProjectAdoptionState.psm1')
        Import-Module (Join-Path $root 'ProjectAdoptionProjection.psm1')
        Import-Module (Join-Path $root 'MaintenanceOverlay.psm1')
        . ([scriptblock]::Create($definitions))
    }
    try{
        $oldEntries=@{
            'repo-local'=@'
<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework

本项目采用AI Workspace Framework。项目工作从本项目 `.ai-workspace/BOOTSTRAP.md` 恢复；以项目pin和原采用记录定位固定规则与工具。首次、压缩或换主体时实际读取该入口及当前必需完整规则，健康上下文按固定版本复用。区外人类授权、项目约定及后续用户决定继续有效。
<!-- AI-WORKSPACE-FRAMEWORK:END -->
'@
            'framework-maintenance-sibling'=@'
<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework Maintenance

本项目是维护治理项目。项目工作从本项目 `.ai-workspace/BOOTSTRAP.md` 恢复，任务/权限取本项目；独立Framework target只承载源码与通用合同，从其README理解，不要求开发根AGENTS/CLAUDE。首次、压缩或换主体实际读取入口及当前必需完整规则，健康上下文按固定版本复用；区外人类授权和后续决定继续有效。
<!-- AI-WORKSPACE-FRAMEWORK:END -->
'@
        }
        $guidance=@(
            '首次开展项目工作、上下文压缩后续作或更换执行主体时，先沿本项目 Bootstrap，按当前意图取得并实际读取全部必需规则正文，再开展依赖项目规则的分析、回答或操作。摘要和旧加载记录不能替代正文。',
            '正常连续工作中，同一工作活动及适用要求未变化时，不重复调用规则加载。普通进度推进、新增普通文件、更换动作授权包或同活动中的本地配套操作，本身不触发重新加载；当前操作仍独立核权限、范围和要求。',
            '真正切换工作活动（如实际自测、自查或返修），或适用要求、实际规则来源发生变化时，按当前意图重新完整加载。同次规则去重；不比较上下文做增量裁剪，不预加载未来动作。')
        $sourceRoot=Split-Path -Parent $scriptsRoot
        foreach($layout in @('repo-local','framework-maintenance-sibling')){
            $entryRoot=Join-Path $fixtureRoot ('resident-'+$layout);$fixed=Join-Path $entryRoot 'old-fixed';$projectRoot=Join-Path $entryRoot 'project'
            $templateRelative=if($layout-ceq'repo-local'){'framework/versions/2.0.0/project-starter/AGENTS.md'}else{'framework/maintenance-overlay/AGENTS.md'}
            $oldManifestRows=@();$oldManifestFiles=@()
            foreach($oldLayout in @('repo-local','framework-maintenance-sibling')){
                $relative=if($oldLayout-ceq'repo-local'){'framework/versions/2.0.0/project-starter/AGENTS.md'}else{'framework/maintenance-overlay/AGENTS.md'}
                $bytes=$utf8.GetBytes($oldEntries[$oldLayout]+"`n");Write-TestText (Join-Path $fixed $relative) ($oldEntries[$oldLayout]+"`n")
                $identity=Get-AiwByteIdentity $bytes;$oldManifestFiles+=@{path=$relative;identity=$identity};$oldManifestRows+=($relative+'='+$identity)
            }
            # A two-template immutable fixture, not a runnable runtime or a
            # release qualification. The real distribution reader validates it.
            $oldManifest=[ordered]@{schemaVersion=2;frameworkVersion='2.0.0';provisional=$true;distributionId='2.0.0-snapshot.991';canonical=(Get-AiwByteIdentity ($utf8.GetBytes(($oldManifestRows-join"`n")+"`n"))).Split('|')[1];files=$oldManifestFiles}
            Write-TestText (Join-Path $fixed 'PACKAGE_MANIFEST.json') (($oldManifest|ConvertTo-Json -Depth 20)+"`n")
            $binding=Get-AiwDistributionBinding $fixed '2.0.0' -Required
            $taskRelative='.ai-workspace/tasks/active/ENTRY-001.md'
            $oldUser="<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->`n原安装约定。`n<!-- AI-WORKSPACE-USER-DECISION:END -->`n"
            $installed=$oldEntries[$layout]+"`n`n"+$oldUser
            $projectBinding=if($layout-ceq'framework-maintenance-sibling'){'Project ID=`entry-fixture`；layout=`framework-maintenance-sibling`；control plane=`.ai-workspace/`；pinned Framework=`2.0.0`。'}else{'Project ID=`entry-fixture`；repo-local control plane=`.ai-workspace/`；pinned Framework=`2.0.0`。'}
            $bootstrap="<!-- FRAMEWORK-MANAGED:BEGIN -->`n"+$projectBinding+"`nfixture navigation`n<!-- FRAMEWORK-MANAGED:END -->`n<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
            $contents=[ordered]@{'.ai-workspace/project.json'=(@{id='entry-fixture';frameworkVersion='2.0.0';controlPlaneLayout=$layout}|ConvertTo-Json -Compress);'.ai-workspace/BOOTSTRAP.md'=$bootstrap;'AGENTS.md'=$installed}
            $contents['.ai-workspace/process-policy.json']=@{schemaVersion=1;contractVersion='2.0.0';projectId='entry-fixture';rules=@()}|ConvertTo-Json -Compress
            $contents['.ai-workspace/corrections.json']=@{schemaVersion=2;contractVersion='2.0.0';projectId='entry-fixture';corrections=@()}|ConvertTo-Json -Compress
            $contents[$taskRelative]="# ENTRY-001 - original navigation fixture`n- Owner: entry-owner`n- Work route: actor=entry-owner; role=TASK_OWNER; phase=IMPLEMENT`n"
            $recovery=Join-Path $projectRoot '.ai-workspace/upgrade-recovery/2.0.0';$objects=@();$projections=@()
            foreach($relative in $contents.Keys){
                $text=[string]$contents[$relative];Write-TestText (Join-Path $projectRoot $relative) $text;Write-TestText (Join-Path $recovery ('new/'+$relative)) $text
                $identity=Get-AiwByteIdentity ($utf8.GetBytes($text));$objects+=@{relative=$relative;oldIdentity='MISSING';newIdentity=$identity}
                $projections+=& $upgradeOwner {param($r,$i,$b,$a) New-PilotProjectionRecord $r $i $b $a} $relative $identity $bootstrap $installed
            }
            $state=[ordered]@{schemaVersion=6;projectId='entry-fixture';fromVersion='2.0.0';toVersion='2.0.0';targetReleaseCanonical=('A'*64);targetReleaseManifestIdentity=('1|'+('B'*64));actor='entry-owner';taskId='ENTRY-001';taskOwner='entry-owner';taskRelative=$taskRelative;authorizationIdentity=('1|'+('C'*64));objects=$objects;projectionMode='LOCAL_CANDIDATE_MANAGED';projectionObjects=$projections;transactionComplete=$true;projectFormat='repo-local/project-config-7';projectCapabilities=@();rootToolRevision=('D'*64);rootToolDependencies=@();distributionBinding=$binding}
            $stateRaw=($state|ConvertTo-Json -Depth 50)+"`n";Write-TestText (Join-Path $recovery 'state.json') $stateRaw;$state=$stateRaw|ConvertFrom-Json -Depth 50
            $migration=[pscustomobject]@{Actor='entry-owner';TaskId='ENTRY-001';Owner='entry-owner';Relative=$taskRelative}
            $contract=& $upgradeOwner {param($root,$recovery,$state,$raw,$migration) Get-ActorBoundRecoveryContract $root $recovery $state $raw 'entry-fixture' '2.0.0' $migration} $projectRoot $recovery $state $stateRaw $migration
            $editedUser="<!-- AI-WORKSPACE-USER-DECISION:BEGIN -->`r`n用户已撤回实施和发布；当前仅可读取。  `r`n<!-- AI-WORKSPACE-USER-DECISION:END -->`r`n"
            $prefix="# Current custom text`r`n保留当前定制。`r`n`r`n"
            $current=$prefix+$oldEntries[$layout].Replace("`r`n","`n").Replace("`n","`r`n")+"`r`n`r`n"+$editedUser
            $navigation=Get-AiwNavigationContract (Get-Content (Join-Path $sourceRoot 'framework/versions/2.0.0/TOOLCHAIN.json') -Raw|ConvertFrom-Json)
            $arguments=@{RepositoryRoot=$projectRoot;Text=$current;TemplatePath=(Join-Path $sourceRoot $templateRelative);Navigation=$navigation;SourceState=$state;SourceBinding=$binding;SourceVersion='2.0.0';Layout=$layout;ProjectionRecords=$contract.ProjectionRecords}
            $after=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments
            Assert-True (@($guidance|Where-Object{-not$after.Contains($_)}).Count-eq0-and$after.StartsWith($prefix)-and$after.EndsWith($editedUser)-and-not$after.Contains('原安装约定')) ('resident-upgrader-old-nav3-complete-guidance-and-current-withdrawal-'+$layout)
            # Also execute the real same-pin refresh plan, so leaving its old
            # call site unwired cannot pass by testing the new helper alone.
            # Only unrelated capability/Bootstrap/correction/preflight work is
            # stubbed. Original recovery, fixed source, live AGENTS, projection
            # construction and the actual upgrader call are all real.
            Write-TestText (Join-Path $projectRoot 'AGENTS.md') $current
            $refresh=& $upgradeOwner {
                param($root,$framework,$layout,$migration,$bootstrap)
                $script:ActiveAdoptionProfile=[pscustomobject]@{schemaVersion=2;frameworkVersion='2.0.0';projectControl=[pscustomobject]@{processCarrierContractVersion='2.0.0';runtimeGitIgnoreRule='/.ai-workspace/runtime/'}}
                $script:ActiveTargetSnapshot=[pscustomobject]@{LocalCandidate=$true;Canonical=('E'*64);ManifestIdentity=('1|'+('F'*64))}
                $script:ActiveDistributionBinding=$null;$script:ActiveRootToolRevision=[pscustomobject]@{revision=('D'*64);dependencies=@()}
                $AdoptionCorrectionsPlanPath='';$SelectedRulePackBytes=32768
                function Assert-TargetProjectCapabilities {}
                function Render-Bootstrap {param($template,$project,$version) $bootstrap}
                function Invoke-CorrectionEvaluation {[pscustomobject]@{incorporated=@()}}
                function Get-TargetProjectedProcessPreflight {$null}
                function Get-AiwProjectFormat {[pscustomobject]@{projectFormat='repo-local/project-config-7';capabilities=@()}}
                $migration=$migration|ConvertTo-Json -Depth 10|ConvertFrom-Json
                $migration|Add-Member SnapshotRebindRequired $true
                $migration|Add-Member Path (Join-Path $root $migration.Relative)
                $migration|Add-Member OldIdentity (Get-MinimalFileIdentity $migration.Path)
                Get-LocalCandidateSamePinProjectionRefreshPlan $root $framework (Join-Path $framework 'framework/versions/2.0.0') '2.0.0' (Join-Path $root '.ai-workspace/project.json') (Join-Path $root '.ai-workspace/BOOTSTRAP.md') $layout 'entry-fixture' $migration
            } $projectRoot $sourceRoot $layout $migration $bootstrap
            $agentChange=@($refresh.Records|Where-Object relative -CEQ 'AGENTS.md')
            Assert-True ($agentChange.Count-eq1-and$agentChange[0].content-ceq$after-and$agentChange[0].oldIdentity-ceq(Get-AiwByteIdentity ($utf8.GetBytes($current)))) ('resident-real-same-pin-call-site-passes-old-source-and-binds-live-user-preimage-'+$layout)
            $arguments.Text=$after;$again=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments
            Assert-True ($again-ceq$after) ('resident-upgrader-idempotent-'+$layout)
            $grant="在本项目内，AI 仅可实施本次任务，禁止发布；保留这一整段。`r`n第二行条件仍有效。"
            $collaboration='已批准协作工作流内的补充只可发给当前Owner。'
            $arguments.Text=$current.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`r`n"+$grant+"`r`n`r`n"+$collaboration+"`r`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
            $moved=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments
            Assert-True ($moved.Contains($grant)-and$moved.Contains($collaboration)-and$moved.IndexOf($grant)-lt$moved.IndexOf($collaboration)-and$moved.IndexOf($collaboration)-lt$moved.IndexOf($editedUser)-and-not(Get-AiwAgentsTemplateBlock $moved).Contains($grant)-and$moved.EndsWith($editedUser)) ('resident-upgrader-preserves-complete-managed-grants-before-revocation-'+$layout)
            $arguments.Text=$current.Replace('<!-- AI-WORKSPACE-FRAMEWORK:END -->',"`r`n未知混合职责不得丢弃。`r`n<!-- AI-WORKSPACE-FRAMEWORK:END -->")
            $reason='';try{$null=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments}catch{$reason=$_.Exception.Message}
            Assert-True ($reason.Contains('AGENTS_AUTHORIZATION_MIGRATION_CONFLICT')) ('resident-upgrader-refuses-unknown-mixed-navigation-'+$layout)
            $arguments.Text=$current;$arguments.Layout=if($layout-ceq'repo-local'){'framework-maintenance-sibling'}else{'repo-local'}
            $reason='';try{$null=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments}catch{$reason=$_.Exception.Message}
            Assert-True ($reason.Contains('AGENTS_SOURCE_TEMPLATE_MISMATCH')) ('resident-upgrader-refuses-wrong-layout-source-'+$layout);$arguments.Layout=$layout
            $oldTemplatePath=Join-Path $fixed $templateRelative;$oldTemplateBytes=[IO.File]::ReadAllBytes($oldTemplatePath)
            try{
                Write-TestText $oldTemplatePath 'changed source template'
                $reason='';try{$null=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments}catch{$reason=$_.Exception.Message}
                Assert-True ($reason.Contains('AGENTS_SOURCE_TEMPLATE_DRIFT')) ('resident-upgrader-refuses-wrong-source-bytes-'+$layout)
                [IO.File]::Delete($oldTemplatePath)
                $reason='';try{$null=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments}catch{$reason=$_.Exception.Message}
                Assert-True ($reason.Contains('AGENTS_SOURCE_TEMPLATE_REQUIRED')) ('resident-upgrader-refuses-missing-old-template-'+$layout)
            }finally{[IO.File]::WriteAllBytes($oldTemplatePath,$oldTemplateBytes)}
            # Legacy records without managedIdentity use the original recovery
            # bytes already validated by the real recovery-contract function.
            @($state.projectionObjects|Where-Object relative -CEQ 'AGENTS.md')[0].PSObject.Properties.Remove('managedIdentity')
            $stateRaw=($state|ConvertTo-Json -Depth 50)+"`n";Write-TestText (Join-Path $recovery 'state.json') $stateRaw
            $contract=& $upgradeOwner {param($root,$recovery,$state,$raw,$migration) Get-ActorBoundRecoveryContract $root $recovery $state $raw 'entry-fixture' '2.0.0' $migration} $projectRoot $recovery $state $stateRaw $migration
            $arguments.ProjectionRecords=$contract.ProjectionRecords
            $fromOriginal=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments
            Assert-True ($fromOriginal-ceq$after) ('resident-upgrader-uses-verified-original-image-without-managed-identity-'+$layout)
            $imagePath=Join-Path $recovery 'new/AGENTS.md';$imageBytes=[IO.File]::ReadAllBytes($imagePath)
            try{
                [IO.File]::Delete($imagePath)
                $reason='';try{$null=& $upgradeOwner {param($a) Get-UpgradeAgentsProjection @a} $arguments}catch{$reason=$_.Exception.Message}
                Assert-True ($reason.Contains('AGENTS_SOURCE_ORIGINAL_REQUIRED')) ('resident-upgrader-missing-original-does-not-use-current-user-text-'+$layout)
            }finally{[IO.File]::WriteAllBytes($imagePath,$imageBytes)}
        }
    }finally{Remove-Module $upgradeOwner -Force}

    if($EntryTemplatesOnly){Write-Output ('PASS|entry-template-projections|'+$passed+'/'+$passed);return}
    Reset-TestProject
    $format = Get-AiwProjectFormat $fixtureRoot
    Assert-True (
        $format.projectFormat -ceq 'repo-local/project-config-4' -and
        $format.capabilities -ccontains 'PROJECT_BACKEND_SELECTION' -and
        $format.capabilities -ccontains 'PROCESS_POLICY_LOCATOR' -and
        $format.capabilities -ccontains 'STRUCTURED_CORRECTIONS' -and
        $format.capabilities -ccontains 'PROCESS_POLICY' -and
        $format.capabilities -ccontains 'LEGACY_PROJECT_CUSTOM_REGION' -and
        $format.capabilities -ccontains 'ROOT_AGENTS_ENTRY'
    ) 'format-from-observed-structure'

    $policyPath = Join-Path $fixtureRoot '.ai-workspace/process-policy.json'
    Write-TestJson '.ai-workspace/process-policy.json' ([ordered]@{ schemaVersion = 1; rules = @() })
    $format = Get-AiwProjectFormat $fixtureRoot
    Assert-True ($format.capabilities -cnotcontains 'PROCESS_POLICY') 'capability-not-inferred-from-schema-alone'

    Write-TestText (Join-Path $fixtureRoot '.ai-workspace/project.json') "{`"schemaVersion`":4,`"SchemaVersion`":4}`n"
    $duplicateRejected = $false
    try {
        Read-AiwProjectJson (Join-Path $fixtureRoot '.ai-workspace/project.json') 'PROJECT_CONFIG' | Out-Null
    }
    catch {
        $duplicateRejected = $_.Exception.Message -cmatch '^PROJECT_CONFIG_DUPLICATE_MEMBER'
    }
    Assert-True $duplicateRejected 'duplicate-json-member-rejected'

    Reset-TestProject
    $tool = Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
        'scripts/ProjectAdoptionTransaction.psm1',
        'scripts/ProjectAdoptionProjection.psm1',
        'scripts/ProjectAdoptionState.psm1'
    )
    $toolReordered = Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
        'scripts/ProjectAdoptionState.psm1',
        'scripts/ProjectAdoptionTransaction.psm1',
        'scripts/ProjectAdoptionProjection.psm1'
    )
    Assert-True (
        $tool.dependencies.Count -eq 3 -and
        $tool.revision -cmatch '^[A-F0-9]{64}$' -and
        $tool.revision -ceq $toolReordered.revision
    ) 'tool-revision-ordinal-and-order-independent'

    $declaredDependencies = Get-AiwProjectAdoptionToolDependency UPGRADE
    $runtimeIdentity = Get-AiwProjectAdoptionRuntimeIdentity $fixtureRoot (Split-Path -Parent $scriptsRoot) UPGRADE
    Assert-True (
        $declaredDependencies -ccontains 'scripts/upgrade-project.ps1' -and
        $declaredDependencies -ccontains 'scripts/ProjectAdoptionTransaction.psm1' -and
        $runtimeIdentity.frameworkPin -ceq '1.16.0' -and
        $runtimeIdentity.projectFormat -ceq 'repo-local/project-config-4' -and
        $runtimeIdentity.rootToolRevision -cmatch '^[A-F0-9]{64}$'
    ) 'runtime-identity-binds-pin-format-and-root-tool'

    Assert-True ($declaredDependencies -ccontains 'scripts/ProjectCorrectionLifecycle.psm1') 'upgrade-revision-includes-its-correction-lifecycle-dependency'
    $dependencyFixture=Join-Path $fixtureRoot 'root-tool-dependencies'
    $allDependencies=@(@(Get-AiwProjectAdoptionToolDependency REGISTER)+$declaredDependencies|Sort-Object -Unique)
    foreach($relative in $allDependencies){
        $destination=Join-Path $dependencyFixture $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
        [IO.File]::Copy((Join-Path (Split-Path -Parent $scriptsRoot) $relative),$destination)
    }
    $upgradeBefore=Get-AiwRootToolRevision $dependencyFixture $declaredDependencies
    $registerBefore=Get-AiwRootToolRevision $dependencyFixture (Get-AiwProjectAdoptionToolDependency REGISTER)
    $dependencyPath=Join-Path $dependencyFixture 'scripts/ProjectCorrectionLifecycle.psm1'
    [IO.File]::AppendAllText($dependencyPath,"`n# Isolated dependency-only change.`n",[Text.UTF8Encoding]::new($false))
    $upgradeAfter=Get-AiwRootToolRevision $dependencyFixture $declaredDependencies
    $registerAfter=Get-AiwRootToolRevision $dependencyFixture (Get-AiwProjectAdoptionToolDependency REGISTER)
    Assert-True ($upgradeBefore.revision-cne$upgradeAfter.revision-and$registerBefore.revision-ceq$registerAfter.revision) 'dependency-only-change-invalidates-only-its-consuming-root-tool-revision'

    $projectedText = "{`"schemaVersion`":5,`"id`":`"fixture`",`"frameworkVersion`":`"1.16.0`",`"frameworkToolBackend`":`"powershell7`",`"processPolicy`":{`"schemaVersion`":1,`"locator`":`".ai-workspace/process-policy.json`"}}`n"
    $projected = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '.ai-workspace/project.json'; text = $projectedText })
    $projectedFormat = Get-AiwProjectedProjectFormat $fixtureRoot $projected
    Assert-True ($projectedFormat.projectFormat -ceq 'repo-local/project-config-5') 'projected-format-uses-target-bytes'

    $duplicateDependencyRejected = $false
    try {
        Get-AiwRootToolRevision (Split-Path -Parent $scriptsRoot) @(
            'scripts/ProjectAdoptionState.psm1',
            'scripts/ProjectAdoptionState.psm1'
        ) | Out-Null
    }
    catch {
        $duplicateDependencyRejected = $_.Exception.Message -cmatch '^TOOL_DEPENDENCY_DUPLICATE'
    }
    Assert-True $duplicateDependencyRejected 'tool-dependency-duplicate-rejected'

    $invalidPathRejected = $false
    try {
        New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '../escape.txt'; text = 'bad' }) | Out-Null
    }
    catch {
        $invalidPathRejected = $_.Exception.Message -ceq 'RELATIVE_PATH_INVALID'
    }
    Assert-True $invalidPathRejected 'projection-path-escape-rejected'

    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $transactionRelative = '.ai-workspace/upgrade-recovery/test/state.json'
    $transactionPath = Join-Path $fixtureRoot $transactionRelative

    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    Write-TestText $fileA 'drift'
    $preflightRejected = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } | Out-Null
    }
    catch {
        $preflightRejected = $_.Exception.Message -cmatch '^PREFLIGHT_OBJECT_DRIFT'
    }
    Assert-True ($preflightRejected -and -not (Test-Path -LiteralPath $transactionPath)) 'preflight-failure-zero-transaction-write'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $semanticPreflightRejected = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } -Preflight { $false } | Out-Null
    }
    catch {
        $semanticPreflightRejected = $_.Exception.Message -ceq 'PREFLIGHT_FAILED'
    }
    Assert-True (
        $semanticPreflightRejected -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old' -and
        -not (Test-Path -LiteralPath $transactionPath)
    ) 'semantic-preflight-failure-zero-managed-write'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'a.txt'; text = 'new' },
        [pscustomobject]@{ path = 'nested/new.txt'; text = 'created' }
    )
    $applyFailed = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true } -FailAfterWrite 1 | Out-Null
    }
    catch {
        $applyFailed = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True (
        $applyFailed -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old' -and
        -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'nested'))
    ) 'apply-failure-restores-bytes-and-created-directories'

    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $postcheckFailed = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $false } { $true } | Out-Null
    }
    catch {
        $postcheckFailed = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True ($postcheckFailed -and (Get-Content -LiteralPath $fileA -Raw) -ceq 'old') 'postcheck-failure-restores-old-behavior'

    $result = Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $transactionRelative { $true } { $true }
    Assert-True (
        $result.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'new' -and
        $result.transactionIdentity -cmatch '^\d+\|[A-F0-9]{64}$'
    ) 'apply-complete'

    $deleteProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; exists = $false })
    $deleteResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $deleteProjection '.ai-workspace/upgrade-recovery/delete/state.json' { $true } { $true }
    Assert-True ($deleteResult.status -ceq 'COMPLETE' -and -not (Test-Path -LiteralPath $fileA)) 'managed-delete-complete'

    Reset-TestProject
    $existingEmptyPath = Join-Path $fixtureRoot 'existing-empty.txt'
    $existingNonemptyPath = Join-Path $fixtureRoot 'existing-nonempty.txt'
    $createdEmptyPath = Join-Path $fixtureRoot 'created-empty.bin'
    [IO.File]::WriteAllBytes($existingEmptyPath, [byte[]]::new(0))
    Write-TestText $existingNonemptyPath 'preserve-on-rollback'
    $emptyIdentity = '0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
    $zeroByteProjection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'existing-empty.txt'; text = 'filled-after-apply' },
        [pscustomobject]@{ path = 'existing-nonempty.txt'; text = '' },
        [pscustomobject]@{ path = 'created-empty.bin'; bytes = [byte[]]::new(0) }
    )
    Assert-True (
        [string]$zeroByteProjection.objects[0].oldIdentity -ceq $emptyIdentity -and
        [string]$zeroByteProjection.objects[1].newIdentity -ceq $emptyIdentity -and
        [string]$zeroByteProjection.objects[2].oldIdentity -ceq 'MISSING' -and
        [string]$zeroByteProjection.objects[2].newIdentity -ceq $emptyIdentity
    ) 'zero-byte-projection-distinguishes-empty-files-from-missing'

    $zeroByteRollback = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $zeroByteProjection '.ai-workspace/upgrade-recovery/zero-byte/state.json' { $false } { $true } | Out-Null
    }
    catch {
        $zeroByteRollback = $_.Exception.Message -ceq 'TRANSACTION_ROLLED_BACK|POSTCHECK_FAILED'
    }
    Assert-True (
        $zeroByteRollback -and
        (Test-Path -LiteralPath $existingEmptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($existingEmptyPath).Length -eq 0 -and
        (Get-Content -LiteralPath $existingNonemptyPath -Raw) -ceq 'preserve-on-rollback' -and
        -not (Test-Path -LiteralPath $createdEmptyPath)
    ) 'zero-byte-postcheck-failure-restores-existing-empty-and-nonempty-and-removes-created-empty'

    $zeroByteResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $zeroByteProjection '.ai-workspace/upgrade-recovery/zero-byte/state.json' {
        param($root)
        (Get-Content -LiteralPath (Join-Path $root 'existing-empty.txt') -Raw) -ceq 'filled-after-apply' -and
        [IO.File]::ReadAllBytes((Join-Path $root 'existing-nonempty.txt')).Length -eq 0 -and
        (Test-Path -LiteralPath (Join-Path $root 'created-empty.bin') -PathType Leaf) -and
        [IO.File]::ReadAllBytes((Join-Path $root 'created-empty.bin')).Length -eq 0
    } { $true }
    Assert-True (
        $zeroByteResult.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath $existingEmptyPath -Raw) -ceq 'filled-after-apply' -and
        (Test-Path -LiteralPath $existingNonemptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($existingNonemptyPath).Length -eq 0 -and
        (Test-Path -LiteralPath $createdEmptyPath -PathType Leaf) -and
        [IO.File]::ReadAllBytes($createdEmptyPath).Length -eq 0
    ) 'zero-byte-apply-preserves-empty-target-files-as-existing'

    Reset-TestProject
    $directoryProjection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = '.ai-workspace/tasks/active'; kind = 'DIRECTORY' },
        [pscustomobject]@{ path = '.ai-workspace/tasks/archive'; kind = 'DIRECTORY' }
    )
    $directoryResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $directoryProjection '.ai-workspace/upgrade-recovery/directories/state.json' { $true } { $true }
    Assert-True (
        $directoryResult.status -ceq 'COMPLETE' -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/tasks/active') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/tasks/archive') -PathType Container)
    ) 'managed-directories-created'

    Reset-TestProject
    $directoryProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = '.ai-workspace/generated/nested'; kind = 'DIRECTORY' })
    $directoryFailure = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $directoryProjection '.ai-workspace/upgrade-recovery/directory-failure/state.json' { $true } { $true } -FailAfterWrite 1 | Out-Null
    }
    catch {
        $directoryFailure = $_.Exception.Message -cmatch '^TRANSACTION_ROLLED_BACK'
    }
    Assert-True ($directoryFailure -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot '.ai-workspace/generated'))) 'directory-failure-restores-created-tree'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projectPath = Join-Path $fixtureRoot '.ai-workspace/project.json'
    $oldProject = [IO.File]::ReadAllBytes($projectPath)
    $newProject = [Text.UTF8Encoding]::new($false).GetBytes("{`"schemaVersion`":4,`"id`":`"fixture`",`"frameworkVersion`":`"target`"}`n")
    $projection = New-AiwProjectProjection $fixtureRoot @(
        [pscustomobject]@{ path = 'a.txt'; text = 'new' },
        [pscustomobject]@{ path = '.ai-workspace/project.json'; bytes = $newProject }
    )
    $rollbackBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection '.ai-workspace/upgrade-recovery/drift/state.json' {
            param($root)
            Write-TestText (Join-Path $root 'a.txt') 'third-party'
            return $false
        } { $true } | Out-Null
    }
    catch {
        $rollbackBlocked = $_.Exception.Message -cmatch '^ROLLBACK_BLOCKED\|ROLLBACK_THIRD_PARTY_DRIFT'
    }
    Assert-True (
        $rollbackBlocked -and
        (Get-AiwByteIdentity ([IO.File]::ReadAllBytes($projectPath))) -ceq (Get-AiwByteIdentity $oldProject) -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'third-party'
    ) 'rollback-restores-pin-before-third-party-drift-stop'

    Reset-TestProject
    $fileA = Join-Path $fixtureRoot 'a.txt'
    Write-TestText $fileA 'old'
    $projection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'new' })
    $resumeRelative = '.ai-workspace/upgrade-recovery/resume/state.json'
    $resumePath = Join-Path $fixtureRoot $resumeRelative
    $behaviorBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $resumeRelative { $false } { $false } | Out-Null
    }
    catch {
        $behaviorBlocked = $_.Exception.Message -ceq 'ROLLBACK_BLOCKED|ROLLBACK_BEHAVIOR_POSTCHECK_FAILED'
    }
    $resumeIdentity = Get-AiwByteIdentity ([IO.File]::ReadAllBytes($resumePath))
    $reuseBlocked = $false
    try {
        Invoke-AiwProjectProjectionTransaction $fixtureRoot $projection $resumeRelative { $true } { $true } | Out-Null
    }
    catch {
        $reuseBlocked = $_.Exception.Message -cmatch '^TRANSACTION_RECOVERY_REQUIRED\|'
    }
    Assert-True $reuseBlocked 'incomplete-transaction-must-resume-before-reuse'
    $resumed = Resume-AiwProjectProjectionRollback $fixtureRoot $resumeRelative $resumeIdentity { $true }
    Assert-True (
        $behaviorBlocked -and
        $resumed.status -ceq 'ROLLED_BACK' -and
        (Get-Content -LiteralPath $fileA -Raw) -ceq 'old'
    ) 'interrupted-rollback-resume'

    $runtimeProjection = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'runtime-fixture.txt'; text = 'runtime' })
    $runtimeTransactionRelative = '.ai-workspace/runtime/project-adoption/register/state.json'
    $runtimeResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $runtimeProjection $runtimeTransactionRelative { $true } { $true }
    Assert-True (
        $runtimeResult.status -ceq 'COMPLETE' -and
        (Get-Content -LiteralPath (Join-Path $fixtureRoot 'runtime-fixture.txt') -Raw) -ceq 'runtime' -and
        (Test-Path -LiteralPath (Join-Path $fixtureRoot $runtimeTransactionRelative) -PathType Leaf)
    ) 'runtime-transaction-root-supported'

    $noOp = New-AiwProjectProjection $fixtureRoot @([pscustomobject]@{ path = 'a.txt'; text = 'old' })
    $noTransactionRelative = '.ai-workspace/upgrade-recovery/noop/state.json'
    $noTransactionPath = Join-Path $fixtureRoot $noTransactionRelative
    $noOpResult = Invoke-AiwProjectProjectionTransaction $fixtureRoot $noOp $noTransactionRelative { $true } { $true }
    Assert-True (
        $noOpResult.status -ceq 'NO_CHANGE' -and
        -not (Test-Path -LiteralPath $noTransactionPath)
    ) 'no-op-no-transaction'

    Test-AdoptionSourceMaterial
    Test-AdoptionClosureContext
    Test-TargetPreflightPermanentSources
    if($CoreOnly){Write-Output ('PASS|project-adoption-core|' + $passed + '/' + $passed);return}
    Write-Output ('PASS|project-adoption-tests|' + $passed + '/' + $passed)
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
        $resolvedTemp = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
        if (-not $resolvedFixture.StartsWith($resolvedTemp + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolvedFixture)).StartsWith('aiw-adoption-', [StringComparison]::Ordinal)) {
            throw 'TEST_FIXTURE_CLEANUP_SCOPE_INVALID'
        }
        [IO.Directory]::Delete($resolvedFixture, $true)
    }
}
