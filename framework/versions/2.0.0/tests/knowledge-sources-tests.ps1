[CmdletBinding()]param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/KnowledgeSources.psm1') -Force
$utf8=[Text.UTF8Encoding]::new($false);$passed=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-knowledge-sources-'+[guid]::NewGuid().ToString('N'))
$junctions=@()
function Text([string]$Path,[string]$Value){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Value,$utf8)}
function Json([string]$Path,$Value){Text $Path (($Value|ConvertTo-Json -Depth 100 -Compress)+"`n")}
function Id([string]$Path){$b=[IO.File]::ReadAllBytes($Path);return $b.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b))}
function CopyValue($Value){$raw=$Value|ConvertTo-Json -Depth 100;$args=@{Depth=100};if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$args.DateKind='String'};return $raw|ConvertFrom-Json @args}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Action,[string]$Reason,[string]$Name){$caught='';try{$null=& $Action}catch{$caught=$_.Exception.Message};Check ($caught.Contains($Reason)) ($Name+'|reason='+$caught)}
function Source([string]$Id,[string]$Kind,[string]$Root,[string]$Index='index.json'){
    return [pscustomobject]@{id=$Id;root=[pscustomobject]@{kind=$Kind;locator=$Root};indexLocator=$Index;selectionHints=@('fixture');updatePolicy='FOLLOW'}
}
function Config([string]$Id,$Sources){return [pscustomobject]@{schemaVersion=5;id=$Id;displayName='Knowledge fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@($Sources)}};processPolicy=[pscustomobject]@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}}
function Entry([string]$Id,[string]$Path,[string]$Kind){
    return [pscustomobject]@{id=$Id;kind=$Kind;state='CURRENT';title='Fixture method';summary='Bounded synthetic content.';tags=@('fixture');locator=$Path;identity='0|'+('A'*64);verifiedAt='2026-09-27T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','CONTENT_VERSION_CHANGE');tokenEstimate=1}
}
function Query([string[]]$Ids,[string]$Mode='LOCATOR_ONLY',[string[]]$Forbidden=@()){
    return Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -Operation QUERY -EntryId $Ids -ContentMode $Mode -ForbiddenPaths $Forbidden
}
try{
    Check (@(Assert-AiwFrameworkCapabilities ([pscustomobject]@{})).Count-eq0) 'empty-capability-set-is-valid-for-new-projects'
    Check (@(Assert-AiwFrameworkCapabilities ([pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$false;sources=@()}})).Count-eq0) 'disabled-empty-source-list-is-valid'
    $project=Join-Path $temp 'project';$shared=Join-Path $temp 'shared';$official=Join-Path $temp 'official'
    $configPath=Join-Path $project '.ai-workspace/project.json';$projectIndexPath=Join-Path $project '.ai-workspace/knowledge/index.json'
    Text (Join-Path $project 'src/core.txt') 'Actual project authority.'
    Text (Join-Path $project '.ai-workspace/knowledge/note.md') "项目知识全文。`nsecond line 🎮`n"
    Text (Join-Path $shared 'method.md') "共享方法全文。`nNo project authority.`n"
    Text (Join-Path $official 'method.md') "Official fixture method.`n"
    $derived=Entry 'SAME' '.ai-workspace/knowledge/note.md' 'PROJECT_DERIVED';$derived.identity=Id (Join-Path $project $derived.locator)
    $derived.invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');$derived|Add-Member projectId 'knowledge-fixture'
    $derived|Add-Member authorityDependencies @([pscustomobject]@{locator='src/core.txt';identity=(Id (Join-Path $project 'src/core.txt'))})
    $method=Entry 'SAME' 'method.md' 'METHOD';$method.identity=Id (Join-Path $shared 'method.md')
    $method|Add-Member originalSources @([pscustomobject]@{title='Fixture provenance';url='https://example.invalid/source';accessedAt='2026-09-27T00:00:00Z';licenseNotice='Synthetic test content; URL must never be fetched.'})
    $method|Add-Member applicability @('isolated test only');$method|Add-Member contentVersion 'fixture-1';$method|Add-Member maintenance ([pscustomobject]@{owner='fixture';locator='README.md'})
    $projectIndex=[pscustomobject]@{schemaVersion=3;libraryId='project-library';entries=@($derived)}
    $sharedIndex=[pscustomobject]@{schemaVersion=3;libraryId='shared-library';entries=@($method)}
    $officialMethod=CopyValue $method;$officialMethod.identity=Id (Join-Path $official 'method.md')
    $officialIndex=[pscustomobject]@{schemaVersion=3;libraryId='official-library';entries=@($officialMethod)}
    Json $projectIndexPath $projectIndex;Json (Join-Path $shared 'index.json') $sharedIndex;Json (Join-Path $official 'index.json') $officialIndex
    $sources=@((Source project PROJECT '.' '.ai-workspace/knowledge/index.json'),(Source shared LOCAL_DIRECTORY $shared),(Source official LOCAL_DIRECTORY $official),(Source idle LOCAL_DIRECTORY (Join-Path $temp 'unmounted')))
    $config=Config 'knowledge-fixture' $sources;Json $configPath $config
    $capabilities=@(Assert-AiwFrameworkCapabilities $config.frameworkCapabilities)
    Check ($capabilities.Count-eq1-and$capabilities[0]-ceq'KNOWLEDGE_REFERENCE') 'capability-structure-does-not-open-unavailable-root'
    $discovery=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath)
    Check ($discovery.status-ceq'KNOWLEDGE_SOURCES'-and$discovery.sources.Count-eq4-and$discovery.entries.Count-eq0) 'default-discovery-lists-source-metadata-without-reading-indexes'
    $catalog=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -SourceId project,shared
    Check ($catalog.entries.Count-eq2-and($catalog|ConvertTo-Json -Depth 20)-notmatch'fullText|summary') 'selected-index-discovery-contains-no-body-or-summary'
    $loaded=Query @('project:SAME','shared:SAME','official:SAME')
    Check (@($loaded.entries|Where-Object{$_.status-ceq'CURRENT'}).Count-eq3) 'project-shared-and-official-sources-query-independently'
    Check ($loaded.entries[0].libraryId-cne$loaded.entries[1].libraryId-and$loaded.entries[0].id-ceq'project:SAME') 'same-entry-id-remains-source-qualified'
    Check (@($loaded.entries|Where-Object{$null-ne$_.PSObject.Properties['fullText']}).Count-eq0) 'default-query-is-locator-only'
    $full=Query @('project:SAME','shared:SAME') FULLTEXT
    Check ($full.entries[0].fullText-ceq[IO.File]::ReadAllText((Join-Path $project $derived.locator))-and$full.entries[1].fullText-ceq[IO.File]::ReadAllText((Join-Path $shared 'method.md'))) 'explicit-batch-fulltext-is-complete'
    Check ($full.entries[0].authorityDependencies[0].observedIdentity-ceq$derived.authorityDependencies[0].identity) 'project-root-includes-real-src-authority-dependency'
    Check (-not(Test-Path -LiteralPath (Join-Path $project '.git'))-and-not$full.authority-and$full.referenceOnly) 'knowledge-does-not-create-git-or-authority'

    # Entry kind describes the knowledge, independently of who supplies it.
    $original=CopyValue $method;$original.id='ORIGINAL';$original.locator='.ai-workspace/knowledge/original-method.md';$original.originalSources=@()
    Text (Join-Path $project $original.locator) 'Project-authored reusable method without an external quotation.'
    $original.identity=Id (Join-Path $project $original.locator)
    $projectIndex.entries=@($derived,$original);Json $projectIndexPath $projectIndex
    $knowledgeSchema=Join-Path $PSScriptRoot '../KNOWLEDGE_SCHEMA.json'
    Check (($projectIndex|ConvertTo-Json -Depth 100|Test-Json -SchemaFile $knowledgeSchema)) 'schema-allows-project-derived-and-original-method-together'
    $own=Query @('project:ORIGINAL','project:SAME') FULLTEXT
    Check ($own.entries[0].status-ceq'CURRENT'-and$own.entries[0].kind-ceq'METHOD'-and$own.entries[0].originalSources.Count-eq0-and$own.entries[0].fullText-ceq[IO.File]::ReadAllText((Join-Path $project $original.locator))) 'project-original-method-fulltext-needs-no-web-citation'
    Check ($own.entries[0].authorityDependencies.Count-eq0-and$own.entries[1].kind-ceq'PROJECT_DERIVED'-and$own.entries[1].authorityDependencies.Count-eq1) 'project-location-does-not-convert-method-into-project-facts'
    $sharedOriginal=CopyValue $method;$sharedOriginal.originalSources=@()
    Json (Join-Path $shared 'index.json') ([pscustomobject]@{schemaVersion=3;libraryId='shared-library';entries=@($sharedOriginal)})
    $origins=Query @('project:ORIGINAL','shared:SAME','official:SAME') FULLTEXT
    Check (@($origins.entries|Where-Object{$_.status-ceq'CURRENT'-and$_.kind-ceq'METHOD'}).Count-eq3-and$origins.entries[1].originalSources.Count-eq0-and$origins.entries[2].originalSources.Count-eq1) 'project-shared-and-framework-methods-keep-independent-provenance'
    Json (Join-Path $shared 'index.json') $sharedIndex
    foreach($badCase in @('sources-type','citation-url','maintenance')){
      $bad=CopyValue $original
      if($badCase-ceq'sources-type'){$bad.originalSources='not-an-array';$expectedReason='KNOWLEDGE_ORIGINAL_SOURCES'}
      elseif($badCase-ceq'citation-url'){$bad.originalSources=@([pscustomobject]@{title='Invalid cited source';url='file:///not-a-web-citation';accessedAt='2026-09-27T00:00:00Z';licenseNotice='Fixture only.'});$expectedReason='KNOWLEDGE_ORIGINAL_SOURCE_URL'}
      else{$bad.maintenance.PSObject.Properties.Remove('owner');$expectedReason='KNOWLEDGE_MAINTENANCE_FIELDS'}
      $projectIndex.entries=@($derived,$bad);Json $projectIndexPath $projectIndex
      $badResult=Query @('project:ORIGINAL')
      Check ($badResult.entries[0].status-ceq'UNAVAILABLE'-and$badResult.entries[0].reason-ceq$expectedReason) ('original-method-still-rejects-'+$badCase)
    }
    $projectIndex.entries=@($derived);Json $projectIndexPath $projectIndex

    $partial=Query @('idle:SAME','shared:SAME') FULLTEXT
    Check ($partial.entries[0].status-ceq'UNAVAILABLE'-and$partial.entries[1].status-ceq'CURRENT') 'unavailable-selected-source-does-not-hide-healthy-result'
    $unknown=Query @('shared:MISSING','project:SAME')
    Check ($unknown.entries[0].reason-ceq'ENTRY_ID_UNKNOWN'-and$unknown.entries[1].status-ceq'CURRENT') 'missing-entry-never-substitutes-same-name-from-another-source'
    Reject {Query @('SAME')} 'KNOWLEDGE_QUERY_ID_INVALID' 'unqualified-entry-rejected'
    Reject {Query @('shared:SAME','shared:SAME')} 'KNOWLEDGE_QUERY_ID_INVALID' 'duplicate-request-rejected'
    Reject {Query @('unknown:SAME')} 'KNOWLEDGE_SOURCE_UNKNOWN' 'unconfigured-source-rejected'
    Reject {Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ContentMode FULLTEXT} 'KNOWLEDGE_DISCOVER_METADATA_ONLY' 'discovery-cannot-smuggle-fulltext'

    $other=Join-Path $temp 'other-project';$otherConfig=Join-Path $other '.ai-workspace/project.json';Json $otherConfig (Config other-fixture @($sources[1]))
    $otherResult=Invoke-AiwKnowledgeQuery -ProjectRoot $other -ExpectedProjectConfigIdentity (Id $otherConfig) -EntryId shared:SAME -Operation QUERY
    Check ($otherResult.entries[0].status-ceq'CURRENT'-and$otherResult.entries[0].libraryId-ceq'shared-library') 'one-method-library-serves-another-project-without-rewriting-index'
    $forged=[pscustomobject]@{schemaVersion=3;libraryId='forged';entries=@($derived)};Json (Join-Path $shared 'index.json') $forged
    $forgedResult=Query @('shared:SAME','project:SAME')
    Check ($forgedResult.entries[0].reason-ceq'KNOWLEDGE_PROJECT_DERIVED_SOURCE_MISMATCH'-and$forgedResult.entries[1].status-ceq'CURRENT') 'external-library-cannot-borrow-another-project-authority'
    Json (Join-Path $shared 'index.json') $sharedIndex

    $config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].updatePolicy='PINNED';$config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1]|Add-Member indexIdentity (Id (Join-Path $shared 'index.json'));Json $configPath $config
    Check ((Query @('shared:SAME')).entries[0].status-ceq'CURRENT') 'pinned-index-exact-identity-accepted'
    $sharedIndex.entries[0].summary='A changed index.';Json (Join-Path $shared 'index.json') $sharedIndex
    $drift=Query @('shared:SAME','project:SAME') FULLTEXT
    Check ($drift.entries[0].status-ceq'STALE'-and$drift.entries[0].reason-ceq'INDEX_IDENTITY_DRIFT'-and$drift.entries[1].status-ceq'CURRENT') 'pinned-index-drift-is-local-and-reported'
    $config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].updatePolicy='FOLLOW';$config.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].PSObject.Properties.Remove('indexIdentity');Json $configPath $config
    $follow=Query @('shared:SAME') FULLTEXT
    Check ($follow.entries[0].status-ceq'CURRENT'-and$follow.entries[0].indexIdentity-ceq(Id (Join-Path $shared 'index.json'))-and$full.entries[1].indexIdentity-cne$follow.entries[0].indexIdentity) 'follow-returns-current-identity-without-rewriting-old-observation'
    Text (Join-Path $shared 'method.md') 'Changed body without new index identity.'
    Check ((Query @('shared:SAME')).entries[0].reason-ceq'REFERENCE_IDENTITY_CHANGE') 'follow-still-checks-body-identity'
    Text (Join-Path $shared 'method.md') $full.entries[1].fullText
    Text (Join-Path $project 'src/core.txt') 'Changed actual authority.'
    $stale=Query @('project:SAME') FULLTEXT
    Check ($stale.entries[0].status-ceq'STALE'-and$null-eq$stale.entries[0].PSObject.Properties['fullText']) 'stale-dependency-withholds-fulltext'
    $impact=Invoke-AiwKnowledgeImpact -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ChangedAuthorityPath src/core.txt
    Check ($impact.entries[0].impact-ceq'DIRECT_AFFECTED'-and$impact.sources.Count-eq1) 'impact-defaults-to-project-sources-and-real-dependency'
    $impact=Invoke-AiwKnowledgeImpact -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ChangedAuthorityPath docs/other.md
    Check ($impact.entries[0].impact-ceq'UNKNOWN') 'unrelated-change-cannot-hide-stale-authority'
    Text (Join-Path $project 'src/core.txt') 'Actual project authority.'
    Check ((Invoke-AiwKnowledgeImpact -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ChangedAuthorityPath docs/other.md).entries[0].impact-ceq'NONE_DIRECT') 'no-overlap-with-current-identities-is-none-direct'

    $forbidden=CopyValue $derived;$forbidden.id='FORBIDDEN';$forbidden.locator='private/missing.md';$projectIndex.entries+=@($forbidden);Json $projectIndexPath $projectIndex
    $denied=Query @('project:FORBIDDEN') FULLTEXT @('private/')
    Check ($denied.entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH') 'forbidden-body-rejected-before-existence-read-or-hash'
    $denied=Query @('project:SAME') FULLTEXT @('src/core.txt')
    Check ($denied.entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH'-and$null-eq$denied.entries[0].PSObject.Properties['fullText']) 'forbidden-dependency-withholds-body'
    $config.routineExcludedPaths=@('src/');Json $configPath $config
    Check ((Query @('project:SAME')).entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH') 'routine-exclusion-applies-to-actual-dependencies'
    $config.routineExcludedPaths=@();Json $configPath $config
    $denied=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -SourceId project -ForbiddenPaths '.ai-workspace/knowledge/index.json'
    Check ($denied.sources[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH'-and$denied.entries.Count-eq0) 'forbidden-index-not-read'
    $bad=CopyValue $projectIndex;$bad.entries[0].locator='../outside.md';Json $projectIndexPath $bad
    Check ((Query @('project:SAME')).entries[0].reason-ceq'KNOWLEDGE_PATH_COMPONENT') 'index-body-escape-rejected'
    Json $projectIndexPath $projectIndex
    $junction=Join-Path $project 'linked';$null=New-Item -ItemType Junction -Path $junction -Target $shared;$junctions+=@($junction)
    $linked=CopyValue $derived;$linked.id='LINKED';$linked.locator='linked/method.md';$projectIndex.entries+=@($linked);Json $projectIndexPath $projectIndex
    Check ((Query @('project:LINKED')).entries[0].reason-ceq'KNOWLEDGE_PATH_REPARSE') 'body-junction-rejected-before-read'
    $alias=Join-Path $temp 'shared-alias';$null=New-Item -ItemType Junction -Path $alias -Target $shared;$junctions+=@($alias)
    $aliasConfig=CopyValue $config;$aliasConfig.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[1].root.locator=$alias;Json $configPath $aliasConfig
    Check ((Query @('shared:SAME')).entries[0].reason-ceq'KNOWLEDGE_PATH_REPARSE') 'source-root-junction-rejected'
    Json $configPath $config

    foreach($mutator in @(
        {param($c)$c.KNOWLEDGE_REFERENCE.enabled=$false;$c.KNOWLEDGE_REFERENCE.sources[0].indexLocator='../escape.json'},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources[0].root.locator='.ai-workspace/knowledge'},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources[1].root.locator='relative/shared'},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources[1].root.locator=([IO.Path]::GetPathRoot($shared)+'folder/../escape')},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources[1].updatePolicy='PINNED'},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources[1]|Add-Member unexpected $true},
        {param($c)$c.KNOWLEDGE_REFERENCE.sources+=@($c.KNOWLEDGE_REFERENCE.sources[0])}
    )){$bad=CopyValue $config.frameworkCapabilities;& $mutator $bad;Reject {Assert-AiwFrameworkCapabilities $bad} 'KNOWLEDGE_' 'malformed-capability-rejected-without-source-io'}
    $raw=[IO.File]::ReadAllText($configPath);Text $configPath $raw.Replace('"schemaVersion":5','"schemaVersion":5,"schemaVersion":5')
    Reject {Query @('project:SAME')} 'INPUT_FIELD_COUNT' 'duplicate-config-field-rejected'
    Json $configPath $config
    $old=CopyValue $projectIndex;$old.schemaVersion=2;Json $projectIndexPath $old
    Check ((Query @('project:SAME')).entries[0].reason-ceq'KNOWLEDGE_INDEX_SCHEMA') 'legacy-index-is-not-a-second-runtime-mode'
    $projectIndex.entries=@($derived);Json $projectIndexPath $projectIndex
    $legacyEntry=[pscustomobject]@{id=$derived.id;state=$derived.state;title=$derived.title;summary=$derived.summary;locator=$derived.locator;identity=$derived.identity;authorityLocator=$derived.authorityDependencies[0].locator;authorityIdentity=$derived.authorityDependencies[0].identity;verifiedAt=$derived.verifiedAt;invalidatesOn=@('LOCATOR_IDENTITY_CHANGE','AUTHORITY_IDENTITY_CHANGE');tokenEstimate=$derived.tokenEstimate}
    $legacy=[pscustomobject]@{schemaVersion=1;projectId='knowledge-fixture';entries=@($legacyEntry)};$before=Id $projectIndexPath
    $converted=Convert-AiwLegacyKnowledgeIndex $legacy knowledge-fixture migrated
    Check ($converted.schemaVersion-eq3-and$converted.entries[0].authorityDependencies[0].locator-ceq'src/core.txt'-and(Id $projectIndexPath)-ceq$before) 'legacy-one-conversion-preserves-authority-and-does-not-write'
    $legacy.schemaVersion=2;$legacyEntry.PSObject.Properties.Remove('authorityLocator');$legacyEntry.PSObject.Properties.Remove('authorityIdentity');$legacyEntry|Add-Member tags @('fixture');$legacyEntry|Add-Member authorityDependencies $derived.authorityDependencies;$legacyEntry.invalidatesOn=$derived.invalidatesOn
    Check ((Convert-AiwLegacyKnowledgeIndex $legacy knowledge-fixture migrated).entries[0].tags[0]-ceq'fixture') 'legacy-two-conversion-preserves-tags-and-dependencies'
    Reject {Convert-AiwLegacyKnowledgeIndex $legacy different-project migrated} 'LEGACY_KNOWLEDGE_INDEX_VALUES' 'legacy-conversion-binds-original-project'

    $large=('完整方法正文🎮'*2500)+"`nEND`n";Text (Join-Path $shared 'method.md') $large;$sharedIndex.entries[0].identity=Id (Join-Path $shared 'method.md');$sharedIndex.entries[0].tokenEstimate=20000;Json (Join-Path $shared 'index.json') $sharedIndex
    Check ((Query @('shared:SAME') FULLTEXT).entries[0].fullText-ceq$large) 'fulltext-does-not-truncate-or-enforce-old-token-quota'
    $projectIndex.entries=@(foreach($n in 1..5){$entry=CopyValue $derived;$entry.id='ENTRY-'+$n;$entry});Json $projectIndexPath $projectIndex
    Check ((Query @(1..5|ForEach-Object{'project:ENTRY-'+$_}) FULLTEXT).entries.Count-eq5) 'explicit-batch-has-no-legacy-three-entry-quota'
    $cli=Join-Path $PSScriptRoot '../scripts/check-knowledge-entry.ps1'
    $output=@(& pwsh -NoProfile -File $cli -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -EntryId project:ENTRY-1 -ContentMode FULLTEXT -AsJson);$code=$LASTEXITCODE;$value=($output-join"`n")|ConvertFrom-Json
    Check ($code-eq0-and$value.entries[0].status-ceq'CURRENT'-and$value.entries[0].fullText-ceq[IO.File]::ReadAllText((Join-Path $project $derived.locator))) 'actual-query-cli-returns-complete-body'
    $impactCli=Join-Path $PSScriptRoot '../scripts/check-knowledge-impact.ps1'
    $output=@(& pwsh -NoProfile -File $impactCli -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ChangedAuthorityPath src/core.txt -AsJson);$code=$LASTEXITCODE;$value=($output-join"`n")|ConvertFrom-Json
    Check ($code-eq0-and@($value.entries|Where-Object{$_.impact-ceq'DIRECT_AFFECTED'}).Count-eq5) 'actual-impact-cli-uses-same-multi-source-validator'
    # Preserve the failure mechanisms from the old single-index suite under
    # the new protocol, including both CLI consumers and decoded duplicates.
    $projectIndex.entries=@($derived);Json $projectIndexPath $projectIndex
    $savedProject=[IO.File]::ReadAllText($configPath);$savedIndex=[IO.File]::ReadAllText($projectIndexPath)
    Text $configPath ($savedProject.Replace('"locator":".ai-workspace/process-policy.json"','"locator":".ai-workspace/process-policy.json","\u006cocator":"duplicate"'))
    Reject {Query @('project:SAME')} 'INPUT_FIELD_COUNT' 'unicode-nested-project-policy-duplicate-rejected'
    Text $configPath $savedProject
    Text $projectIndexPath ($savedIndex.Replace('"libraryId":"project-library"','"libraryId":"project-library","\u006cibraryId":"duplicate"'))
    Check ((Query @('project:SAME')).entries[0].reason.Contains('INPUT_FIELD_COUNT')) 'unicode-top-level-index-duplicate-rejected'
    Text $projectIndexPath ($savedIndex.Replace('"locator":"src/core.txt"','"locator":"src/core.txt","\u006cocator":"duplicate"'))
    Check ((Query @('project:SAME')).entries[0].reason.Contains('INPUT_FIELD_COUNT')) 'unicode-nested-dependency-duplicate-rejected'
    Text $projectIndexPath $savedIndex
    foreach($badTime in @(7,'2026-09-27 00:00:00','2026-99-27T00:00:00Z')){
        $badIndex=CopyValue $projectIndex;$badIndex.entries[0].verifiedAt=$badTime;Json $projectIndexPath $badIndex
        Check ((Query @('project:SAME')).entries[0].reason-ceq'KNOWLEDGE_VERIFIED_AT') ('invalid-timestamp-rejected-'+[string]$badTime)
    }
    $badIndex=CopyValue $projectIndex;$badIndex.entries+=@($badIndex.entries[0]);Json $projectIndexPath $badIndex
    Check ((Query @('project:SAME')).entries[0].status-ceq'UNAVAILABLE') 'duplicate-index-entry-rejected'
    $badIndex=CopyValue $projectIndex;$badIndex|Add-Member unexpected 'no';Json $projectIndexPath $badIndex
    Check ((Query @('project:SAME')).entries[0].status-ceq'UNAVAILABLE') 'unknown-index-field-rejected'
    Text $projectIndexPath $savedIndex
    $badConfig=CopyValue $config;$badConfig.schemaVersion=4;Json $configPath $badConfig
    Reject {Query @('project:SAME')} 'PROJECT_CONFIG_VALUES' 'old-project-requires-explicit-migration'
    $badConfig=CopyValue $config;$badConfig.processPolicy.locator='.ai-workspace/other.json';Json $configPath $badConfig
    Reject {Query @('project:SAME')} 'PROJECT_CONFIG_POLICY' 'query-rejects-invalid-policy-locator'
    Reject {Invoke-AiwKnowledgeImpact -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -ChangedAuthorityPath src/core.txt} 'PROJECT_CONFIG_POLICY' 'impact-rejects-invalid-policy-locator'
    Text $configPath $savedProject
    $bundleRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $bundleSource=Source bundled LOCAL_DIRECTORY $bundleRoot 'knowledge/index.json'
    $bundleConfig=Config 'knowledge-fixture' @($bundleSource);Json $configPath $bundleConfig
    $bundle=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Id $configPath) -SourceId bundled
    Check ($bundle.entries.Count-eq3-and$bundle.sources[0].libraryId-ceq'ai-workspace-methods') 'actual-bundled-index-discovers-three-methods'
    $methods=Query @('bundled:UI_INPUT_CANCELLATION','bundled:PRESENTATION_AUTHORITY','bundled:BEHAVIOR_AND_PERFORMANCE') FULLTEXT
    Check (@($methods.entries|Where-Object{$_.status-ceq'CURRENT'-and$_.fullText.Length-gt0}).Count-eq3) 'actual-bundled-method-identities-and-fulltext-validate'
    Check (@($methods.entries|Where-Object{$_.kind-ceq'METHOD'-and$_.authorityDependencies.Count-eq0}).Count-eq3) 'bundled-methods-have-no-project-authority-dependencies'
    # A Maintenance library may point at TARGET or a nested directory. Its
    # configured exclusions must remain anchored to TARGET, before any I/O.
    $maintParent=Join-Path $temp 'maintenance';$maintRoot=Join-Path $maintParent 'control';$maintTarget=Join-Path $maintParent 'target'
    $null=[IO.Directory]::CreateDirectory($maintRoot);$null=[IO.Directory]::CreateDirectory($maintTarget)
    foreach($repo in @($maintRoot,$maintTarget)){& git -C $repo init -q;if($LASTEXITCODE-ne0){throw 'MAINTENANCE_FIXTURE_GIT_INIT'}}
    $maintConfigPath=Join-Path $maintRoot '.ai-workspace/project.json'
    $maintSource=Source target LOCAL_DIRECTORY $maintTarget 'library/index.json'
    $maintConfig=Config 'maintenance-fixture' @($maintSource);$maintConfig.controlPlaneLayout='framework-maintenance-sibling'
    $maintConfig.routineExcludedPaths=@('private')
    $maintConfig|Add-Member frameworkTarget ([pscustomobject]@{repositoryId='framework-target';siblingDirectory='target';routineExcludedPaths=@('protected','library/blocked')})
    Text (Join-Path $maintTarget 'protected/body.md') 'Synthetic forbidden sentinel; no test reads or hashes these bytes.'
    Text (Join-Path $maintTarget 'private/body.md') 'Allowed TARGET content; CONTROL private exclusion is separate.'
    function Maint-Query {Invoke-AiwKnowledgeQuery -ProjectRoot $maintRoot -ExpectedProjectConfigIdentity (Id $maintConfigPath) -EntryId target:SAME -Operation QUERY -ContentMode FULLTEXT}
    foreach($locator in @('protected/body.md','protected/missing.md')){
        $entry=CopyValue $method;$entry.locator=$locator;$entry.identity='0|'+('A'*64)
        Json (Join-Path $maintTarget 'library/index.json') ([pscustomobject]@{schemaVersion=3;libraryId='target-library';entries=@($entry)})
        Json $maintConfigPath $maintConfig
        $answer=Maint-Query
        Check ($answer.entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH'-and$null-eq$answer.entries[0].PSObject.Properties['fullText']) ('maintenance-target-body-protection-before-hash-or-existence-'+$locator)
    }
    $maintSource.indexLocator='protected/missing-index.json';Json $maintConfigPath $maintConfig
    Check ((Maint-Query).entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH') 'maintenance-target-index-protection-before-existence'
    $maintSource.root.locator=Join-Path $maintTarget 'library';$maintSource.indexLocator='index.json'
    $entry=CopyValue $method;$entry.locator='blocked/missing.md';Json (Join-Path $maintTarget 'library/index.json') ([pscustomobject]@{schemaVersion=3;libraryId='target-library';entries=@($entry)});Json $maintConfigPath $maintConfig
    Check ((Maint-Query).entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH') 'maintenance-nested-local-root-keeps-target-exclusions'
    $maintSource.root.locator=Join-Path $maintTarget 'protected/nonexistent';Json $maintConfigPath $maintConfig
    Check ((Maint-Query).entries[0].reason-ceq'KNOWLEDGE_FORBIDDEN_PATH') 'maintenance-forbidden-source-root-before-existence'
    $maintSource.root.locator=$maintTarget;$maintSource.indexLocator='library/index.json'
    $entry=CopyValue $method;$entry.locator='private/body.md';$entry.identity=Id (Join-Path $maintTarget $entry.locator)
    Json (Join-Path $maintTarget 'library/index.json') ([pscustomobject]@{schemaVersion=3;libraryId='target-library';entries=@($entry)});Json $maintConfigPath $maintConfig
    Check ((Maint-Query).entries[0].status-ceq'CURRENT') 'maintenance-control-exclusions-do-not-borrow-target-relative-paths'
    $maintConfig.frameworkTarget.siblingDirectory='../target';Json $maintConfigPath $maintConfig
    Reject {Maint-Query} 'KNOWLEDGE_' 'maintenance-invalid-target-topology-fails-before-source-read'
    Write-Output ('RESULT|'+$passed+'/'+$passed+' passed|scope=knowledge-sources|evidence=ISOLATED_REFERENCE_PROTOCOL_ONLY')
}finally{
    foreach($junction in $junctions){if(Test-Path -LiteralPath $junction){Remove-Item -LiteralPath $junction -Force}}
    $resolved=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if([IO.Path]::GetDirectoryName($resolved)-cne$parent-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-knowledge-sources-[a-f0-9]{32}$'){throw 'KNOWLEDGE_FIXTURE_CLEANUP_BOUNDARY'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
