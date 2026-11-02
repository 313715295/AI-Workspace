[CmdletBinding()]param([switch]$KeepFixture,[switch]$ClosureRecheckOnly)
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly
Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-content-'+[guid]::NewGuid().ToString('N'));$junction=$null
function Binding([string]$Id,[string]$Root,[object[]]$Paths){[pscustomobject]@{id=$Id;provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$Root};allowedPaths=$Paths;decisionLocator='fixture:user-source-choice'}}
function FilePermission([string]$Locator){[pscustomobject]@{kind='FILE';locator=$Locator}}
function Document([string]$Id,[string]$BindingId,[string]$Locator,[string]$Identity,[string[]]$Dependencies=@()){[pscustomobject]@{sourceId=$Id;bindingId=$BindingId;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=$Identity};locator=$Locator;identity=$Identity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=$Dependencies}}
function Descriptor([string]$Id,[object[]]$Documents,[object[]]$Bindings){$d=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$Documents[0].bindingId;itemId=$Id;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};itemIdentity='';rootSourceId=$Documents[0].sourceId;documents=$Documents};foreach($doc in $Documents){$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $Bindings};$d.revision=Get-AiwContentRevision $d $Bindings;$d.itemIdentity=Get-AiwContentItemIdentity $d;return $d}
function Adopt([string]$Root,$Configuration,[object[]]$Descriptors){Store (Join-Path $Root '.ai-workspace/project.json') $Configuration;$rules=@($Descriptors|ForEach-Object{[pscustomobject]@{ruleId=$_.itemId;requirementReason='Fixture source';decisionLocator='fixture:user-choice';source=$_;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}});Store (Join-Path $Root '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$Configuration.id;rules=$rules})}
function Context([string]$Root){New-AiwContentContext $Root (Identity (Join-Path $Root '.ai-workspace/project.json'))}
function TestObtainedClosureProtection {
    $linkRoot=Join-Path $temp 'closure-link-origin';$linkStage=Join-Path $temp 'closure-link-stage'
    $linkConfig=NewTestProject $linkRoot closurelinks
    $linkPath=Join-Path $linkRoot 'rules/rule.md';WriteText $linkPath 'Original closure member.'
    $linkConfig.sourceBindings=@((Binding links '.' @((FilePermission 'rules/rule.md'))))
    $linkDescriptor=Descriptor CLOSURE_LINK @((Document ROOT links 'rules/rule.md' (Identity $linkPath))) $linkConfig.sourceBindings
    Adopt $linkRoot $linkConfig @($linkDescriptor);Adopt $linkStage $linkConfig @($linkDescriptor)
    $stageLinkPath=Join-Path $linkStage 'rules/rule.md';[IO.Directory]::CreateDirectory((Split-Path -Parent $stageLinkPath))|Out-Null
    [IO.File]::Copy($linkPath,$stageLinkPath,$false)
    $linkRules=(Get-Content -LiteralPath (Join-Path $linkRoot '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100).rules
    $linkForbidden=@(((Split-Path -Parent $linkPath)+'.retained'),((Split-Path -Parent $stageLinkPath)+'.retained'))
    $linkContext=New-AiwContentContext $linkRoot (Identity (Join-Path $linkRoot '.ai-workspace/project.json')) $linkForbidden
    $plainClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $linkRoot -Rules $linkRules -ContentContext $linkContext
    $projectionObject=[pscustomobject]@{kind='FILE';path='rules/rule.md';newExists=$true;newIdentity=(Identity $linkPath);newBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($linkPath))}
    $linkProjection=New-AiwAdoptionContentContext -ProjectRoot $linkStage -SourceProjectRoot $linkRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $linkStage '.ai-workspace/project.json')) -ForbiddenPaths $linkForbidden -ProjectedSourceObjects @($projectionObject)
    $projectedClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $linkStage -Rules $linkRules -ContentContext $linkProjection
    Assert-AiwProjectPolicySourceClosure $plainClosure
    Assert-AiwProjectPolicySourceClosure $projectedClosure
    # One representative per actual ordinary/original/projected read decision.
    # Generic leaf/ancestor checks below cover path forms; do not cross-multiply
    # those forms here or require privileged file-symlink creation.
    foreach($case in @(@{closure=$plainClosure;path=$linkPath;label='ordinary-origin'},@{closure=$projectedClosure;path=$linkPath;label='projected-origin'},@{closure=$projectedClosure;path=$stageLinkPath;label='projected-member'})){
        $moving=Split-Path -Parent $case.path;$retained=$moving+'.retained'
        foreach($candidate in @($moving,$retained)){
            if(-not[IO.Path]::GetFullPath($candidate).StartsWith([IO.Path]::GetFullPath($temp)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'CLOSURE_LINK_FIXTURE_BOUNDARY'}
        }
        [IO.Directory]::Move($moving,$retained);$linked=$false;$locked=$null
        try{
            $null=New-Item -ItemType Junction -Path $moving -Target $retained;$linked=$true
            $target=Join-Path $retained ([IO.Path]::GetFileName($case.path))
            $locked=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
            Reject {Assert-AiwProjectPolicySourceClosure $case.closure} 'SOURCE_DENIED|REPARSE' ($case.label+'-closure-refuses-reparse-before-read')
        }finally{
            if($null-ne$locked){$locked.Dispose()}
            if($linked){[IO.Directory]::Delete($moving)}
            [IO.Directory]::Move($retained,$moving)
        }
        Assert-AiwProjectPolicySourceClosure $case.closure
        Check $true ($case.label+'-closure-restored-path-valid')
    }
    $missingOriginBytes=[IO.File]::ReadAllBytes($linkPath);[IO.File]::Delete($linkPath)
    try{Assert-AiwProjectPolicySourceClosure $projectedClosure;Check $true 'projected-closure-still-permits-missing-new-original-leaf'}finally{[IO.File]::WriteAllBytes($linkPath,$missingOriginBytes)}
}

function Convert-LegacyContentCanonicalJson($Value) {
    # Independent pre-optimization algorithm: retain its recursive encoding,
    # rather than sharing the new ordered-value builder or its expectations.
    if($null-eq$Value){return 'null'}
    if($Value-is[string]-or$Value-is[bool]-or$Value-is[ValueType]){return ($Value|ConvertTo-Json -Compress -Depth 100)}
    if($Value-is[Collections.IDictionary]){
        [string[]]$keys=@($Value.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal)
        return '{'+[string]::Join(',',@($keys|ForEach-Object{($_|ConvertTo-Json -Compress)+':'+(Convert-LegacyContentCanonicalJson $Value[$_])}))+'}'
    }
    if($Value-is[Array]-or$Value-is[Collections.IList]){
        return '['+[string]::Join(',',@($Value|ForEach-Object{Convert-LegacyContentCanonicalJson $_}))+']'
    }
    [string[]]$keys=@($Value.PSObject.Properties|ForEach-Object{$_.Name});[Array]::Sort($keys,[StringComparer]::Ordinal)
    return '{'+[string]::Join(',',@($keys|ForEach-Object{($_|ConvertTo-Json -Compress)+':'+(Convert-LegacyContentCanonicalJson $Value.$_)}))+'}'
}
function TestContentCanonicalCompatibility {
    $ordinal=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $ordinal.Add('a',2);$ordinal.Add('A',1);$ordinal.Add('中文',@($null,@(),@{z=0}));$ordinal.Add('',"quote`"slash\`n`r`t");$ordinal.Add("quote`"slash\`n",'key')
    $list=[Collections.ArrayList]::new();$null=$list.Add(@());$null=$list.Add(@($null));$null=$list.Add(@(1,2))
    $cases=@(
        @{name='null';value=$null},@{name='empty-string';value=''},@{name='empty-object';value=[pscustomobject]@{}},@{name='empty-map';value=@{}},
        @{name='empty-array';value=@()},@{name='one-null';value=@($null)},@{name='one-empty-array';value=,@()},
        @{name='nested-arrays';value=@(@(),@(1),@($null),@(1,2),@(@(),@(3,4)))},@{name='list';value=$list},
        @{name='ordinal-case-distinct-map';value=$ordinal},
        @{name='unicode-escaping';value=("中文😀`"\`n`r`t"+[char]0+[char]8+[char]0x2028+'<>/&')},
        @{name='object-and-array-order';value=[pscustomobject]@{z=@(@{B=$false;a=$true},'x');A=@{z=@();a=[pscustomobject]@{}}}},
        @{name='pipeline-wrapped-strings';value=@(@('a.md','b.md')|ForEach-Object{[pscustomobject]@{path=$_}}|ForEach-Object path)},
        @{name='json-parsed-descriptor';value=('{"revision":{"value":"A","kind":"CONTENT_IDENTITY"},"documents":[{"dependencies":[],"identity":"1|A","locator":"a.md"}],"capabilities":{},"value":null}'|ConvertFrom-Json -Depth 100 -DateKind String)}
    )
    $numbers=@([byte]255,[sbyte]-128,[int16]::MinValue,[uint16]::MaxValue,[int]::MinValue,[uint32]::MaxValue,[long]::MinValue,[ulong]::MaxValue,[decimal]::MaxValue,[decimal]1.2300,[double]1.0,[double]-1.25e-20,[float]1.5,[double]::MaxValue,[Numerics.BigInteger]::Parse('123456789012345678901234567890'),$true,$false)
    for($n=0;$n-lt$numbers.Count;$n++){$cases+=@{name=('scalar-'+$n);value=$numbers[$n]}}
    $cases+=@{name='nested-number-types';value=[pscustomobject]@{values=$numbers}}
    $deep=[pscustomobject]@{value=@()};for($n=0;$n-lt40;$n++){$deep=[pscustomobject]@{z=$deep;a=@($null,'x')}}
    $cases+=@{name='nested-supported-depth';value=$deep}
    foreach($case in $cases){
        $expected=Convert-LegacyContentCanonicalJson $case.value
        $actual=@(ConvertTo-AiwContentCanonicalJson $case.value)
        Check ($actual.Count-eq1-and$actual[0]-is[string]-and$actual[0]-ceq$expected) ('canonical-original-json-bytes-'+$case.name)
        Check ((Get-AiwContentDescriptorIdentity $case.value)-ceq(Get-AiwContentByteIdentity $utf8.GetBytes($expected))) ('canonical-original-identity-'+$case.name)
    }
}
function RejectBeforeSourceResolution($PublicContext,[scriptblock]$Action,[string]$Name){
    $owner=(Get-Command Resolve-AiwKnowledgeSnapshot).Module
    & $owner {
        $script:CsEarlyResolutionCount=0;$script:CsEarlySavedResolve=(Get-Command Resolve-CsDocument).ScriptBlock
        Set-Item Function:script:Resolve-CsDocument -Value {param($Context,$Document);$script:CsEarlyResolutionCount++;& $script:CsEarlySavedResolve $Context $Document}
    }
    $original=$PublicContext.Config;$PublicContext.Config=Clone $original
    $PublicContext.Config.sourceBindings[0].allowedPaths+=@((FilePermission 'unapproved-extra.md'))
    try{
        $caught='';try{& $Action $PublicContext|Out-Null}catch{$caught=$_.Exception.Message}
        $count=& $owner {$script:CsEarlyResolutionCount}
        Check ($caught.Contains('CONTENT_IDENTITY_DRIFT|CONTEXT')-and$count-eq0) $Name
    }finally{
        $PublicContext.Config=$original
        & $owner {Set-Item Function:script:Resolve-CsDocument -Value $script:CsEarlySavedResolve}
    }
}
try{
    if($ClosureRecheckOnly){
        Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1')
        TestObtainedClosureProtection
        Write-Output 'PARTIAL|CLOSURE_RECHECK_ONLY'
        Write-Output ('CONTENT_SOURCES_LOCAL_TESTS|PASS|'+$passed)
        return
    }
    TestContentCanonicalCompatibility
    $pathModule=(Get-Command New-AiwContentContext).Module
    $literalPath=Join-Path $temp 'literal [path]/中文.txt';WriteText $literalPath 'literal'
    & $pathModule {param($p)Assert-CsPath $p} $literalPath
    Check ([IO.File]::Exists($literalPath)) 'current-path-metadata-keeps-literal-unicode-and-brackets'
    $missingPath=Join-Path $temp 'missing-parent/missing-leaf.md'
    Reject {& $pathModule {param($p)Assert-CsPath $p} $missingPath} 'SOURCE_UNAVAILABLE|MISSING' 'current-path-missing-ancestor-is-rejected'
    & $pathModule {param($p)Assert-CsPath $p -AllowMissing} $missingPath
    Check (-not[IO.Directory]::Exists((Split-Path -Parent $missingPath))) 'allow-missing-path-validation-does-not-create-paths'
    Reject {& $pathModule {param($p,$ban)Assert-CsPath $p @($ban) -AllowMissing} $missingPath $temp} 'SOURCE_DENIED|FORBIDDEN_PATH' 'forbidden-precedes-missing-metadata'
    $supply=Join-Path $temp 'supply';WriteText (Join-Path $supply 'A.md') 'A';WriteText (Join-Path $supply 'B.md') 'B';WriteText (Join-Path $supply 'C.md') 'C';WriteText (Join-Path $supply 'other.md') 'Other item'
    $p1=Join-Path $temp 'project-one';$p2=Join-Path $temp 'project-two';$c1=NewTestProject $p1 one;$c2=NewTestProject $p2 two
    $bindings=@((Binding main $supply @((FilePermission 'A.md'),(FilePermission 'B.md'))),(Binding dependency $supply @((FilePermission 'C.md'))))
    $c1.sourceBindings=$bindings;$c2.sourceBindings=@((Binding main $supply @((FilePermission 'other.md'))))
    $graph=Descriptor GRAPH @((Document A main 'A.md' (Identity (Join-Path $supply 'A.md')) @('B')),(Document B main 'B.md' (Identity (Join-Path $supply 'B.md')) @('C')),(Document C dependency 'C.md' (Identity (Join-Path $supply 'C.md')))) $bindings
    $other=Descriptor OTHER @((Document O main 'other.md' (Identity (Join-Path $supply 'other.md')))) $c2.sourceBindings
    Adopt $p1 $c1 @($graph);Adopt $p2 $c2 @($other);$ctx=Context $p1;$ctx2=Context $p2
    $snapshot=Resolve-AiwContentSnapshot $ctx $graph
    Check (($snapshot.facts.documents.document.sourceId-join',')-ceq'C,B,A') 'complete-A-B-C-fixed-dependency-order'
    $read=Read-AiwContentExact $ctx $snapshot $graph.documents[2]
    Check ($read.identity-ceq$graph.documents[2].identity-and$read.observation-ceq'LOCAL') 'cross-binding-dependency-exact-read'
    Check ((Test-AiwContentSnapshot $ctx $snapshot).status-ceq'VERIFIED') 'verify-entire-fixed-graph'
    $s2=Resolve-AiwContentSnapshot $ctx2 $other;$r2=Read-AiwContentExact $ctx2 $s2 $other.documents[0]
    Check ($read.cachePath.StartsWith($p1)-and$r2.cachePath.StartsWith($p2)-and$r2.cachePath-cne$read.cachePath) 'two-project-caches-isolated'
    WriteText (Join-Path $supply 'other.md') 'Other item changed'
    Check ((Test-AiwContentSnapshot $ctx $snapshot).status-ceq'VERIFIED') 'different-item-change-does-not-drift-adopted-item'
    Reject {Read-AiwContentExact $ctx2 $s2 $other.documents[0]} 'CONTENT_IDENTITY_DRIFT' 'actual-adopted-item-byte-drift'
    $bad=Clone $graph;$bad.documents[1].dependencies=@('UNADOPTED');$bad.revision=Get-AiwContentRevision $bad $bindings;$bad.itemIdentity=Get-AiwContentItemIdentity $bad;Adopt $p1 $c1 @($bad);$badCtx=Context $p1
    Reject {Resolve-AiwContentSnapshot $badCtx $bad} 'DEPENDENCY_NOT_ADOPTED' 'graph-reference-must-be-actually-adopted'
    $bad=Clone $graph;$bad.documents[2].dependencies=@('A');$bad.revision=Get-AiwContentRevision $bad $bindings;$bad.itemIdentity=Get-AiwContentItemIdentity $bad;Adopt $p1 $c1 @($bad);$badCtx=Context $p1
    Reject {Resolve-AiwContentSnapshot $badCtx $bad} 'DEPENDENCY_CYCLE' 'closed-graph-cycle-rejected'
    $revoked=Clone $c1;$revoked.sourceBindings=@($revoked.sourceBindings[0]);Adopt $p1 $revoked @($graph);$denied=Context $p1
    Reject {Resolve-AiwContentSnapshot $denied $graph} 'DEPENDENCY_NOT_ADOPTED' 'cross-binding-without-current-permission-rejected'
    Adopt $p1 $c1 @($graph);$ctx=Context $p1;$snapshot=Resolve-AiwContentSnapshot $ctx $graph
    $read=Read-AiwContentExact $ctx $snapshot $graph.documents[0];Remove-Item -LiteralPath (Join-Path $supply 'A.md')
    Check ((Read-AiwContentExact $ctx $snapshot $graph.documents[0]).observation-ceq'PINNED_CACHE') 'pinned-offline-exact-cache'
    $newRule=[pscustomobject]@{ruleId='LOCAL_OTHER';requirementReason='Unrelated local change';effectiveRule='Unrelated local policy.';decisionLocator='fixture:local-change';selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
    $policyPath=Join-Path $p1 '.ai-workspace/process-policy.json';$changedPolicy=Get-Content $policyPath -Raw|ConvertFrom-Json -Depth 100;$changedPolicy.rules+=@($newRule);Store $policyPath $changedPolicy;$freshContext=Context $p1;$freshSnapshot=Resolve-AiwContentSnapshot $freshContext $graph
    Check ((Read-AiwContentExact $freshContext $freshSnapshot $graph.documents[0]).observation-ceq'PINNED_CACHE') 'unrelated-policy-change-reuses-unchanged-pinned-fact-with-fresh-permission'
    $ctx=$freshContext;$snapshot=$freshSnapshot
    $following=Resolve-AiwContentSnapshot $ctx $graph FOLLOW
    Reject {Read-AiwContentExact $ctx $following $graph.documents[0]} 'SOURCE_UNAVAILABLE' 'follow-offline-never-falls-back-to-cache'
    $revoked=Clone $c1;$revoked.sourceBindings[0].allowedPaths=@((FilePermission 'B.md'));Adopt $p1 $revoked @($graph);$denied=Context $p1
    Reject {Resolve-AiwContentSnapshot $denied $graph} 'SOURCE_DENIED' 'cache-cannot-bypass-revoked-permission'
    $escape=Clone $graph;$escape.documents[0].locator='../secret.md';Adopt $p1 $c1 @($escape);$escapeCtx=Context $p1
    Reject {Resolve-AiwContentSnapshot $escapeCtx $escape} 'SOURCE_DENIED' 'relative-escape-before-any-read'
    $a=[pscustomobject]@{z=1;A=[pscustomobject]@{b=2;a=1};array=@(1,2)};$b=[pscustomobject]@{array=@(1,2);A=[pscustomobject]@{a=1;b=2};z=1}
    Check ((Get-AiwContentDescriptorIdentity $a)-ceq(Get-AiwContentDescriptorIdentity $b)-and(Get-AiwContentByteIdentity $utf8.GetBytes(($a|ConvertTo-Json -Compress)))-cne(Get-AiwContentByteIdentity $utf8.GetBytes(($b|ConvertTo-Json -Compress)))) 'ordinal-descriptor-order-distinct-from-raw-byte-identity'
    $b.array=@(2,1);Check ((Get-AiwContentDescriptorIdentity $a)-cne(Get-AiwContentDescriptorIdentity $b)) 'descriptor-array-order-preserved'
    WriteText (Join-Path $supply 'A.md') 'A';Adopt $p1 $c1 @($graph);$ctx=Context $p1
    $forbidden=New-AiwContentContext $p1 (Identity (Join-Path $p1 '.ai-workspace/project.json')) @($supply)
    Reject {Resolve-AiwContentSnapshot $forbidden $graph} 'SOURCE_DENIED|FORBIDDEN_PATH' 'forbidden-source-before-metadata'
    $junction=Join-Path $temp 'junction';$null=New-Item -ItemType Junction -Path $junction -Target $supply
    $reparse=Clone $c1;$reparse.sourceBindings[0].locator.root=$junction;$reparseGraph=Descriptor GRAPH (Clone $graph.documents) $reparse.sourceBindings;Adopt $p1 $reparse @($reparseGraph);$reparseCtx=Context $p1
    Reject {Resolve-AiwContentSnapshot $reparseCtx $reparseGraph} 'SOURCE_DENIED|REPARSE' 'reparse-source-rejected-before-read'
    $c1.sourceBindings[0].allowedPaths+=@((FilePermission 'catalog.json'),(FilePermission 'other.md'));$c2.sourceBindings[0].allowedPaths+=@((FilePermission 'catalog.json'))
    WriteText (Join-Path $supply 'other.md') 'Other item';Adopt $p1 $c1 @($graph);Adopt $p2 $c2 @($other);$ctx=Context $p1;$ctx2=Context $p2
    function SupplyItem($D){$docs=@();foreach($doc in $D.documents){$row=Clone $doc;$ref=if($row.bindingId-ceq'main'){'SELF'}else{'extra'};$row.PSObject.Properties.Remove('bindingId');$row|Add-Member sourceRef $ref;$docs+=$row};[pscustomobject]@{id=$D.itemId;kind='RULE';title=$D.itemId;description='Synthetic supplied rule';facets=[pscustomobject]@{};tags=@();revision=$D.revision;descriptor=[pscustomobject]@{rootSourceId=$D.rootSourceId;documents=$docs};maintenance='fixture';provenance='isolated fixture'}}
    $catalog=[pscustomobject]@{schemaVersion=1;catalogId='SUPPLY';items=@((SupplyItem $graph),(SupplyItem $other));sourceRefs=@([pscustomobject]@{id='extra';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root=$supply}})}
    $catalogPath=Join-Path $supply 'catalog.json';Store $catalogPath $catalog
    $catalog1=Read-AiwContentCatalog $ctx main 'catalog.json' (Identity $catalogPath);$catalog2=Read-AiwContentCatalog $ctx2 main 'catalog.json' (Identity $catalogPath)
    Reject {Convert-AiwContentCatalogItem $ctx $catalog1 GRAPH @{SELF='main'}} 'DEPENDENCY_NOT_ADOPTED' 'catalog-cross-source-requires-explicit-map'
    $preview1=Convert-AiwContentCatalogItem $ctx $catalog1 GRAPH @{SELF='main';extra='dependency'};$preview2=Convert-AiwContentCatalogItem $ctx2 $catalog2 OTHER @{SELF='main'}
    Check ($preview1.status-ceq'ADOPTION_PREVIEW'-and$preview2.source.itemId-ceq'OTHER'-and-not$preview1.authority) 'one-supply-two-independent-item-previews'
    $notAdopted=Convert-AiwContentCatalogItem $ctx $catalog1 OTHER @{SELF='main'}
    Reject {Resolve-AiwContentSnapshot $ctx $notAdopted.source} 'DEPENDENCY_NOT_ADOPTED' 'catalog-preview-does-not-automatically-adopt-rule'
    $tampered=Clone $catalog1;$tampered.catalog.items[0].title='tampered'
    Reject {Convert-AiwContentCatalogItem $ctx $tampered GRAPH @{SELF='main';extra='dependency'}} 'CONTENT_IDENTITY_DRIFT|CATALOG_SNAPSHOT' 'catalog-frozen-representation-tamper-rejected'
    RejectBeforeSourceResolution $ctx {param($c)Read-AiwContentCatalog $c main 'catalog.json' (Identity $catalogPath)} 'catalog-read-admits-private-context-before-provider-resolution'
    RejectBeforeSourceResolution $ctx {param($c)Convert-AiwContentCatalogItem $c $catalog1 GRAPH @{SELF='main';extra='dependency'}} 'catalog-conversion-admits-private-context-before-source-mapping'
    $knowledgeRoot=Join-Path $temp 'knowledge-project';$knowledge=NewTestProject $knowledgeRoot knowledge
    WriteText (Join-Path $supply 'method.md') 'A supplied method.'
    $entry=[pscustomobject]@{id='METHOD';kind='METHOD';state='CURRENT';title='Method';summary='Fixture method';tags=@('fixture');locator='method.md';identity=(Identity (Join-Path $supply 'method.md'));verifiedAt='2026-09-30T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','CONTENT_VERSION_CHANGE');tokenEstimate=1;originalSources=@([pscustomobject]@{title='Synthetic';url='https://example.invalid/fixture';accessedAt='2026-09-30T00:00:00Z';licenseNotice='Fixture'});applicability=@('fixture');contentVersion='fixture-1';maintenance=[pscustomobject]@{owner='fixture';locator='README.md'}}
    $indexPath=Join-Path $supply 'index.json';Store $indexPath ([pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@($entry)})
    $knowledge.sourceBindings=@((Binding library $supply @((FilePermission 'index.json'),(FilePermission 'method.md'))))
    $knowledge.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='methods';bindingId='library';indexLocator='index.json';selectionHints=@('fixture');updatePolicy='FOLLOW';revisionSelector='index.json'})}}
    Adopt $knowledgeRoot $knowledge @();$knowledgeContext=Context $knowledgeRoot
    $opened=Resolve-AiwKnowledgeSnapshot $knowledgeContext $knowledge.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
    RejectBeforeSourceResolution $knowledgeContext {param($c)Resolve-AiwKnowledgeSnapshot $c $knowledge.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]} 'knowledge-snapshot-admits-private-context-before-follow-provider'
    $changedOpened=Clone $opened;$changedOpened.Snapshot.descriptor.documents[0].locator='unlisted-index.json'
    Reject {Read-AiwKnowledgeReference $knowledgeContext $changedOpened 'method.md' $entry.identity} 'CONTENT_IDENTITY_DRIFT|SNAPSHOT' 'knowledge-reference-factory-revalidates-opened-index-snapshot'
    $changed=Clone $entry;$changed.identity='1|'+('A'*64);Store $indexPath ([pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@($changed)})
    $reference=Read-AiwKnowledgeReference $knowledgeContext $opened 'method.md' $entry.identity
    Check ($reference.identity-ceq$entry.identity) 'follow-query-keeps-once-resolved-index-for-all-entries'
    Import-Module (Join-Path $versionRoot 'scripts/KnowledgeSources.psm1') -Force
    Store $indexPath ([pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@($entry)})
    $query=Invoke-AiwKnowledgeQuery -ProjectRoot $knowledgeRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $knowledgeRoot '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:METHOD') -ContentMode FULLTEXT
    Check ($query.entries.Count-eq1-and$query.entries[0].status-ceq'CURRENT'-and$query.entries[0].fullText-ceq'A supplied method.') 'actual-knowledge-consumer-project-six-shared-provider'
    Remove-Item -LiteralPath $indexPath
    $unavailable=Invoke-AiwKnowledgeQuery -ProjectRoot $knowledgeRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $knowledgeRoot '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:METHOD')
    Check (@($unavailable.entries|Where-Object status -CEQ CURRENT).Count-eq0) 'knowledge-follow-offline-not-current'
    $liveRoot=Join-Path $temp 'prospective-live';$projectedRoot=Join-Path $temp 'prospective-control'
    WriteText (Join-Path $liveRoot '.ai-workspace/project.json') '{"schemaVersion":5,"id":"original-fact"}'
    $oldConfigIdentity=Identity (Join-Path $liveRoot '.ai-workspace/project.json')
    WriteText (Join-Path $liveRoot 'rule.md') 'Exact approved prospective rule.'
    $future=NewTestProject $projectedRoot prospective
    $future.sourceBindings=@((Binding prospective '.' @((FilePermission 'rule.md'))))
    $futureItem=Descriptor PROSPECTIVE @((Document R prospective 'rule.md' (Identity (Join-Path $liveRoot 'rule.md')))) $future.sourceBindings
    Adopt $projectedRoot $future @($futureItem)
    $prospectiveContext=New-AiwContentContext -ProjectRoot $projectedRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $projectedRoot '.ai-workspace/project.json')) -SourceProjectRoot $liveRoot
    $prospectiveSnapshot=Resolve-AiwContentSnapshot $prospectiveContext $futureItem
    $prospectiveRead=Read-AiwContentExact $prospectiveContext $prospectiveSnapshot $futureItem.documents[0]
    Check ($prospectiveRead.physicalSource-ceq(Join-Path $liveRoot 'rule.md')-and$prospectiveRead.identity-ceq$futureItem.documents[0].identity-and(Identity (Join-Path $liveRoot '.ai-workspace/project.json'))-ceq$oldConfigIdentity) 'prospective-config-reads-exact-live-document-without-changing-old-project'
    $prospectiveForbidden=New-AiwContentContext -ProjectRoot $projectedRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $projectedRoot '.ai-workspace/project.json')) -SourceProjectRoot $liveRoot -ForbiddenPaths @('rule.md')
    Reject {Resolve-AiwContentSnapshot $prospectiveForbidden $futureItem} 'SOURCE_DENIED|FORBIDDEN_PATH' 'prospective-relative-forbidden-path-remains-anchored-to-live-root'
    $future.sourceBindings[0].allowedPaths=@((FilePermission 'different.md'));Adopt $projectedRoot $future @($futureItem)
    Reject {Read-AiwContentExact $prospectiveContext $prospectiveSnapshot $futureItem.documents[0]} 'CONTENT_IDENTITY_DRIFT|CURRENT_PERMISSION_OR_ADOPTION' 'prospective-permission-drift-invalidates-original-context'
    $revokedProspective=New-AiwContentContext -ProjectRoot $projectedRoot -ExpectedProjectConfigIdentity (Identity (Join-Path $projectedRoot '.ai-workspace/project.json')) -SourceProjectRoot $liveRoot
    Reject {Resolve-AiwContentSnapshot $revokedProspective $futureItem} 'SOURCE_DENIED|OUTSIDE_ALLOWED_PATHS' 'prospective-cache-cannot-bypass-current-file-permission'

    # One raw physical file, multiple complete units: actual provider/parser
    # tests, preserving the unchanged transport/cache/protection cases above.
    $unitProject=Join-Path $temp 'unit-project';$unitConfig=NewTestProject $unitProject units
    $unitPath=Join-Path $unitProject 'units.md'
    $unitText="<OUTER>`nOuter head`n<A>`nAlpha`n</A>`nOuter tail`n</OUTER>`n<B>`nBeta`n</B>`n<X>`nEqual words`n</X>`n<Y>`nEqual words`n</Y>"
    WriteText $unitPath $unitText
    $unitConfig.sourceBindings=@((Binding units '.' @((FilePermission 'units.md'))),(Binding alias $unitProject @((FilePermission 'units.md'))))
    function UnitDoc([string]$Id,[string]$Start,[string]$End,[string[]]$Deps=@(),[string]$BindingId='units'){
        $doc=Document $Id $BindingId 'units.md' (Identity $unitPath) $Deps
        if($Start){$doc.mode='MARKED_SECTION';$doc.sectionStart=$Start;$doc.sectionEnd=$End}
        return $doc
    }
    function UnitGraph([object[]]$Docs){
        $descriptor=Descriptor UNITS $Docs $unitConfig.sourceBindings
        Adopt $unitProject $unitConfig @($descriptor);$context=Context $unitProject
        return Read-AiwContentUnitGraph $context (Resolve-AiwContentSnapshot $context $descriptor)
    }
    $units=UnitGraph @((UnitDoc A '<A>' '</A>' @('B')),(UnitDoc B '<B>' '</B>'))
    Check (($units.units.document.sourceId-join',')-ceq'B,A'-and($units.units.unit.body-join',')-ceq'Beta,Alpha'-and$units.units[0].unit.identity-cne$units.units[1].unit.identity) 'same-physical-file-complete-sections-dependency-postorder'
    $units=UnitGraph @((UnitDoc ALL '' '' @('OUTER')),(UnitDoc OUTER '<OUTER>' '</OUTER>' @('A')),(UnitDoc A '<A>' '</A>'))
    Check ($units.units.Count-eq3-and$units.units[1].unit.body.Contains("<A>`nAlpha`n</A>")-and$units.units[2].unit.body-ceq$unitText) 'contained-sections-and-full-file-remain-complete-without-clipping'
    $units=UnitGraph @((UnitDoc X '<X>' '</X>' @('Y')),(UnitDoc Y '<Y>' '</Y>'))
    Check ($units.units[0].unit.body-ceq$units.units[1].unit.body-and$units.units[0].unit.identity-cne$units.units[1].unit.identity) 'equal-body-at-different-positions-has-distinct-unit-identity'
    Reject {UnitGraph @((UnitDoc A '<A>' '</A>' @('ALIAS')),(UnitDoc ALIAS '<A>' '</A>' @() alias))} 'UNIT_DUPLICATE' 'same-unit-binding-and-source-id-alias-cannot-evade-duplicate'
    # Diamond visits the same declared node once; this is not an alias node.
    $units=UnitGraph @((UnitDoc ALL '' '' @('OUTER','B')),(UnitDoc OUTER '<OUTER>' '</OUTER>' @('A')),(UnitDoc B '<B>' '</B>' @('A')),(UnitDoc A '<A>' '</A>'))
    Check (($units.units.document.sourceId-join',')-ceq'A,OUTER,B,ALL') 'diamond-shared-node-once-per-graph-in-declared-postorder'
    $unitConfig.sourceBindings[1].allowedPaths=@((FilePermission 'other.md'))
    Reject {UnitGraph @((UnitDoc A '<A>' '</A>' @('B')),(UnitDoc B '<B>' '</B>' @() alias))} 'SOURCE_DENIED' 'each-unit-permission-checked-despite-same-file-cache'
    $unitConfig.sourceBindings[1].allowedPaths=@((FilePermission 'units.md'))
    $unitDescriptor=Descriptor UNITS @((UnitDoc A '<A>' '</A>')) $unitConfig.sourceBindings
    Adopt $unitProject $unitConfig @($unitDescriptor);$unitContext=Context $unitProject;$unitSnapshot=Resolve-AiwContentSnapshot $unitContext $unitDescriptor
    $null=Read-AiwContentUnitGraph $unitContext $unitSnapshot
    WriteText $unitPath ($unitText.Replace('Beta','Unselected changed Beta'))
    Reject {Read-AiwContentUnitGraph $unitContext $unitSnapshot} 'CONTENT_IDENTITY_DRIFT|DOCUMENT' 'unselected-section-drift-rejects-whole-file-snapshot-not-cache-fallback'
    WriteText $unitPath "<A>`nAlpha start`n<B>`nOverlap`n</A>`nBeta tail`n</B>"
    $units=UnitGraph @((UnitDoc A '<A>' '</A>' @('B')),(UnitDoc B '<B>' '</B>'))
    Check ($units.units[0].unit.body-ceq"Overlap`n</A>`nBeta tail"-and$units.units[1].unit.body-ceq"Alpha start`n<B>`nOverlap") 'overlapping-complete-units-preserve-both-full-bodies'
    WriteText $unitPath "<A>`nOne`n</A>`n<A>`nTwo`n</A>"
    Reject {UnitGraph @((UnitDoc A '<A>' '</A>'))} 'SECTION_CARDINALITY' 'ambiguous-repeated-marker-refused-by-provider-unit-parser'

    # Explicit NORMATIVE_UNIT is independent of legacy whole-file snapshots.
    # Expected identities are fixture data from the public canonical contract.
    function NormDoc([string]$Id,[string[]]$Conditions=@(),[string[]]$Dependencies=@()){
        [pscustomobject]@{sourceId=$Id;bindingId='units';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='units.md';mode='NORMATIVE_UNIT';unitId=$Id;sectionStart=('<'+$Id+'>');sectionEnd=('</'+$Id+'>');normativeIdentity='';commonConditionSourceIds=$Conditions;dependencies=$Dependencies}
    }
    function NormDescriptor([object[]]$Docs,[hashtable]$Bodies){
        $identities=@{}
        foreach($doc in $Docs){
            $unit=[ordered]@{provider='LOCAL_DIRECTORY';physicalSource=$unitPath.ToUpperInvariant();permissionIdentity=(Get-AiwContentDescriptorIdentity $unitConfig.sourceBindings[0]);mode='NORMATIVE_UNIT';unitId=$doc.unitId;parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart=$doc.sectionStart;sectionEnd=$doc.sectionEnd;bodyIdentity=(Get-AiwContentByteIdentity $utf8.GetBytes($Bodies[$doc.sourceId]))}
            $doc.normativeIdentity=Get-AiwContentDescriptorIdentity ([ordered]@{unit=$unit;commonConditions=@($doc.commonConditionSourceIds|ForEach-Object{$identities[$_]});dependencies=@($doc.dependencies|ForEach-Object{$identities[$_]})})
            $identities[$doc.sourceId]=$doc.normativeIdentity
        }
        # Root is last in this explicit postorder fixture, not document zero.
        $root=$Docs[-1].sourceId
        $descriptor=Descriptor NORMATIVE $Docs $unitConfig.sourceBindings
        $descriptor.rootSourceId=$root;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
        return $descriptor
    }
    function ReadNorm($Descriptor){
        Adopt $unitProject $unitConfig @($Descriptor);$context=Context $unitProject
        return Read-AiwContentUnitGraph $context (Resolve-AiwContentSnapshot $context $Descriptor)
    }
    $normText="<C>`nShared condition`n</C>`n<D>`nDependency`n</D>`n<A>`nEqual obligation`n</A>`n<Z>`nUnrelated section`n</Z>"
    WriteText $unitPath $normText
    $norm=NormDescriptor @((NormDoc C),(NormDoc D),(NormDoc A @('C') @('D'))) @{C='Shared condition';D='Dependency';A='Equal obligation'}
    $normRead=ReadNorm $norm;$oldUnitIdentity=$normRead.units[-1].unit.identity
    Check (($normRead.units.document.sourceId-join',')-ceq'C,D,A'-and$normRead.units[-1].unit.body-ceq'Equal obligation') 'normative-common-condition-before-ordered-dependency-and-root'
    WriteText $unitPath ("Moved introduction`n"+$normText.Replace('Unrelated section','Changed unselected section'))
    $moved=ReadNorm $norm
    Check ($moved.units[-1].unit.identity-ceq$oldUnitIdentity-and$moved.units[-1].read.identity-cne$normRead.units[-1].read.identity) 'normative-relocation-and-unrelated-edit-keep-semantic-identity-with-new-physical-observation'
    WriteText $unitPath ($normText.Replace('Equal obligation','Changed obligation'))
    Reject {ReadNorm $norm} 'NORMATIVE_UNIT' 'normative-actual-body-drift-rejected'
    WriteText $unitPath ($normText.Replace('Shared condition','Changed condition'))
    Reject {ReadNorm $norm} 'NORMATIVE_UNIT' 'normative-common-condition-drift-rejected'
    $new=NormDescriptor @((NormDoc C),(NormDoc D),(NormDoc A @('C') @('D'))) @{C='Changed condition';D='Dependency';A='Equal obligation'}
    $stale=Clone $new;$stale.documents[-1].normativeIdentity=$norm.documents[-1].normativeIdentity
    $stale=Descriptor NORMATIVE $stale.documents $unitConfig.sourceBindings;$stale.rootSourceId='A';$stale.itemIdentity=Get-AiwContentItemIdentity $stale
    Reject {ReadNorm $stale} 'NORMATIVE_UNIT' 'normative-updated-condition-cannot-rescue-stale-root'
    Check ((ReadNorm $new).units[-1].unit.identity-cne$oldUnitIdentity) 'normative-explicitly-readopted-condition-changes-root-identity'
    WriteText $unitPath $normText
    $ordered=NormDescriptor @((NormDoc C),(NormDoc D),(NormDoc A @() @('C','D'))) @{C='Shared condition';D='Dependency';A='Equal obligation'}
    $reversed=Clone $ordered;$reversed.documents[-1].dependencies=@('D','C')
    $reversed=Descriptor NORMATIVE $reversed.documents $unitConfig.sourceBindings;$reversed.rootSourceId='A';$reversed.itemIdentity=Get-AiwContentItemIdentity $reversed
    Reject {ReadNorm $reversed} 'NORMATIVE_UNIT' 'normative-dependency-reordering-rejects-stale-identity'
    $duplicate=Clone $norm;$duplicate.documents[-1].unitId='C';$duplicate=NormDescriptor $duplicate.documents @{C='Shared condition';D='Dependency';A='Equal obligation'}
    Reject {ReadNorm $duplicate} 'UNIT_DUPLICATE' 'normative-unit-id-cannot-alias-another-complete-unit'
    WriteText $unitPath ($normText+"`n<A>`nEqual obligation`n</A>")
    Reject {ReadNorm $norm} 'SECTION_CARDINALITY' 'normative-duplicate-marker-refused'
    WriteText $unitPath $normText
    $permission=Clone $unitConfig.sourceBindings[0];$unitConfig.sourceBindings[0].allowedPaths=@((FilePermission 'other.md'))
    Reject {ReadNorm $norm} 'SOURCE_DENIED' 'normative-current-permission-before-body-reuse'
    $unitConfig.sourceBindings[0]=$permission

    # Reuse must remove repeated work without making caller objects or prior
    # calls a private proof. These hooks delegate the actual module functions.
    WriteText $unitPath "<C>`nShared condition`n</C>`n<D>`nShared dependency`n</D>`n<A>`nFirst obligation`n</A>`n<B>`nSecond obligation`n</B>`n<Z>`nUnselected unit`n</Z>"
    $sharedOne=NormDescriptor @((NormDoc C),(NormDoc D),(NormDoc A @('C') @('D'))) @{C='Shared condition';D='Shared dependency';A='First obligation'}
    $sharedOne.itemId='SHARED_ONE';$sharedOne.itemIdentity=Get-AiwContentItemIdentity $sharedOne
    $sharedTwo=NormDescriptor @((NormDoc D),(NormDoc C),(NormDoc B @('D') @('C'))) @{C='Shared condition';D='Shared dependency';B='Second obligation'}
    $sharedTwo.itemId='SHARED_TWO';$sharedTwo.itemIdentity=Get-AiwContentItemIdentity $sharedTwo
    $unselected=Descriptor UNSELECTED @((UnitDoc Z '<Z>' '</Z>')) $unitConfig.sourceBindings
    Adopt $unitProject $unitConfig @($sharedOne,$sharedTwo,$unselected)
    $composer=@(Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -PassThru)[0]
    $rules=(Get-Content -LiteralPath (Join-Path $unitProject '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100).rules
    # Publication borrows only private raw closure material. Compare against
    # independent public construction, including a normative raw-file change
    # that must rebuild successfully rather than being treated as unit drift.
    function ReadPublicationClosure([object[]]$SelectedRules,$Previous=$null,[string[]]$Forbidden=@()){
        $context=New-AiwContentContext -ProjectRoot $unitProject -ExpectedProjectConfigIdentity (Identity (Join-Path $unitProject '.ai-workspace/project.json')) -ForbiddenPaths $Forbidden
        $observation=& $composer {param($r,$rules,$c,$previous)Get-AiwProjectPolicySourceClosureCore -ProjectRoot $r -Rules $rules -ContentContext $c -PreviousMaterial $previous} $unitProject $SelectedRules $context $Previous
        Assert-AiwProjectPolicySourceClosure $observation.Closure
        return $observation
    }
    $normativeRules=@($rules[0],$rules[1]);$closureBefore=ReadPublicationClosure $normativeRules
    TestObtainedClosureProtection
    $borrowed=ReadPublicationClosure $normativeRules $closureBefore.Material
    $independent=Get-AiwProjectPolicySourceClosure -ProjectRoot $unitProject -Rules $normativeRules
    Check ($borrowed.Closure.Identity-ceq$independent.Identity-and$null-eq$independent.PSObject.Properties['Material']) 'publication-private-material-matches-independent-public-closure-and-stays-private'
    $originalClosureBytes=[IO.File]::ReadAllBytes($unitPath)
    try{
        WriteText $unitPath ($utf8.GetString($originalClosureBytes).Replace('Unselected unit','Unselected unit changed'))
        $rebuilt=ReadPublicationClosure $normativeRules $closureBefore.Material
        $independent=Get-AiwProjectPolicySourceClosure -ProjectRoot $unitProject -Rules $normativeRules
        Check ($rebuilt.Closure.Identity-ceq$independent.Identity-and$rebuilt.Closure.Identity-cne$closureBefore.Closure.Identity) 'publication-raw-drift-rebuilds-unchanged-normative-units-with-current-whole-identity'
        WriteText $unitPath ($utf8.GetString($originalClosureBytes).Replace('Shared condition','Changed condition'))
        Reject {ReadPublicationClosure $normativeRules $closureBefore.Material} 'NORMATIVE_UNIT' 'publication-borrow-cannot-hide-shared-condition-drift'
        Reject {Get-AiwProjectPolicySourceClosure -ProjectRoot $unitProject -Rules $normativeRules} 'NORMATIVE_UNIT' 'independent-closure-rejects-the-same-condition-drift'
    }finally{[IO.File]::WriteAllBytes($unitPath,$originalClosureBytes)}
    Reject {ReadPublicationClosure $normativeRules $closureBefore.Material @($unitPath)} 'SOURCE_DENIED|FORBIDDEN_PATH' 'publication-borrow-rechecks-current-protected-members'
    $forgedRules=Clone $normativeRules;$forgedRules[0].requirementReason='Caller-forged rule'
    Reject {ReadPublicationClosure $forgedRules $closureBefore.Material} 'POLICY_SOURCE_SET' 'publication-borrow-binds-request-to-actual-current-adoption'
    $closureConfigPath=Join-Path $unitProject '.ai-workspace/project.json';$closureConfigBytes=[IO.File]::ReadAllBytes($closureConfigPath)
    try{
        $revoked=Clone $unitConfig;$revoked.sourceBindings[0].allowedPaths=@((FilePermission 'other.md'));Store $closureConfigPath $revoked
        Reject {ReadPublicationClosure $normativeRules $closureBefore.Material} 'SOURCE_DENIED' 'publication-config-change-falls-back-and-current-revocation-rejects'
    }finally{[IO.File]::WriteAllBytes($closureConfigPath,$closureConfigBytes)}
    $closurePolicyPath=Join-Path $unitProject '.ai-workspace/process-policy.json';$closurePolicyBytes=[IO.File]::ReadAllBytes($closurePolicyPath)
    try{
        foreach($mutation in @('DEPENDENCY','UNIT')){
            $changedPolicy=$utf8.GetString($closurePolicyBytes)|ConvertFrom-Json -Depth 100
            $descriptor=$changedPolicy.rules[0].source
            if($mutation-ceq'DEPENDENCY'){$descriptor.documents[-1].dependencies=@('MISSING');$reason='DEPENDENCY_NOT_ADOPTED'}
            else{$descriptor.documents[-1].normativeIdentity='1|'+('A'*64);$reason='NORMATIVE_UNIT'}
            $descriptor.revision=Get-AiwContentRevision $descriptor $unitConfig.sourceBindings;$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
            Store $closurePolicyPath $changedPolicy
            $changedRules=@($changedPolicy.rules[0],$changedPolicy.rules[1])
            Reject {ReadPublicationClosure $changedRules $closureBefore.Material} $reason ('publication-changed-'+$mutation+'-must-rebuild-complete-graph')
        }
    }finally{[IO.File]::WriteAllBytes($closurePolicyPath,$closurePolicyBytes)}
    $afterFailure=ReadPublicationClosure $normativeRules
    Check ($afterFailure.Closure.Identity-ceq$closureBefore.Closure.Identity) 'publication-new-request-after-failure-reconstructs-current-closure'
    $trace=[Collections.Generic.List[object]]::new()
    $shared=& $composer {param($root,$rules,$trace) Get-AiwProjectStandardsSnapshot -ProjectRoot $root -Rules $rules -ReadTrace $trace} $unitProject $rules $trace
    Check (($trace[0..5].sourceId-join',')-ceq'C,D,A,D,C,B'-and$shared.Rules.SHARED_ONE.FullText.Contains('First obligation')-and$shared.Rules.SHARED_TWO.FullText.Contains('Second obligation')) 'owned-composition-retains-each-rule-complete-conditions-and-dependency-order'
    foreach($rule in @($rules[0],$rules[1])){
        $reference=& $composer {param($root,$rule) Get-AiwProjectSourceRule -ProjectRoot $root -Rule $rule -Label ('PROCESS_POLICY_'+$rule.ruleId)} $unitProject $rule
        Check ($shared.Rules[$rule.ruleId].Identity-ceq$reference.Identity-and$shared.Rules[$rule.ruleId].FullText-ceq$reference.FullText) ('owned-normative-composition-matches-independent-public-graph-'+$rule.ruleId)
    }
    $expectedSharedText=$shared.Rules.SHARED_ONE.FullText
    $shared.Rules.SHARED_ONE.Blocks[0].RawBody='Caller mutation'
    $freshShared=& $composer {param($root,$rules) Get-AiwProjectStandardsSnapshot -ProjectRoot $root -Rules $rules} $unitProject $rules
    Check ($freshShared.Rules.SHARED_ONE.FullText-ceq$expectedSharedText-and$freshShared.Rules.SHARED_ONE.Blocks[0].RawBody-ceq'Shared condition') 'owned-composition-return-mutation-does-not-cross-independent-call'
    $sharedFileBefore=[IO.File]::ReadAllBytes($unitPath)
    try{
        WriteText $unitPath ($utf8.GetString($sharedFileBefore).Replace('Shared condition','Changed condition'))
        Reject {& $composer {param($root,$rules) Get-AiwProjectStandardsSnapshot -ProjectRoot $root -Rules $rules} $unitProject $rules} 'CONTENT_IDENTITY_DRIFT|NORMATIVE_UNIT' 'owned-composition-reobserves-changed-shared-condition'
    }finally{[IO.File]::WriteAllBytes($unitPath,$sharedFileBefore)}
    $sharedContext=Context $unitProject;$sharedSnapshot=Resolve-AiwContentSnapshot $sharedContext $sharedOne
    $returned=Read-AiwContentUnitGraph $sharedContext $sharedSnapshot
    $returned.units[0].document.sectionStart='<Caller mutation>';$returned.units[0].unit.body='Caller mutation'
    Check ((Read-AiwContentUnitGraph $sharedContext $sharedSnapshot).units[0].unit.body-ceq'Shared condition') 'returned-graph-mutation-cannot-poison-private-inputs'
    $originalConfig=Clone $sharedContext.Config
    $sharedContext.Config.sourceBindings[0].allowedPaths=@((FilePermission 'unapproved.md'))
    Reject {Read-AiwContentUnitGraph $sharedContext $sharedSnapshot} 'CONTENT_IDENTITY_DRIFT|CONTEXT' 'caller-context-mutation-is-not-a-private-validation-proof'
    $sharedContext.Config=$originalConfig
    $oldForbidden=@($sharedContext.Forbidden);$sharedContext.Forbidden=@($unitPath)
    Reject {Read-AiwContentUnitGraph $sharedContext $sharedSnapshot} 'CONTENT_IDENTITY_DRIFT|CONTEXT' 'changed-forbidden-scope-cannot-reuse-private-inputs'
    $sharedContext.Forbidden=$oldForbidden
    $policyFile=Join-Path $unitProject '.ai-workspace/process-policy.json';$policyBytes=[IO.File]::ReadAllBytes($policyFile);$policyTime=[IO.File]::GetLastWriteTimeUtc($policyFile)
    & (Get-Command Read-AiwContentUnitGraph).Module {
        param($path,$bytes,$time)
        $script:CsBoundaryCalls=0;$script:CsBoundaryPath=$path;$script:CsBoundaryBytes=$bytes;$script:CsBoundaryTime=$time
        $script:CsSavedExact=(Get-Item Function:Read-CsExactCore).ScriptBlock
        Set-Item Function:script:Read-CsExactCore -Value {
            param($Context,$Snapshot,$Document,$PhysicalReadCache)
            $script:CsBoundaryCalls++
            if($script:CsBoundaryCalls-eq2){$changed=[byte[]]$script:CsBoundaryBytes.Clone();$index=[Array]::IndexOf($changed,[byte]32);$changed[$index]=9;[IO.File]::WriteAllBytes($script:CsBoundaryPath,$changed);[IO.File]::SetLastWriteTimeUtc($script:CsBoundaryPath,$script:CsBoundaryTime)}
            & $script:CsSavedExact $Context $Snapshot $Document $PhysicalReadCache
        }
    } $policyFile $policyBytes $policyTime
    try{Reject {Read-AiwContentUnitGraph $sharedContext $sharedSnapshot} 'CONTENT_IDENTITY_DRIFT|CURRENT_PERMISSION_OR_ADOPTION' 'same-length-time-policy-drift-between-nodes-still-rejected'}
    finally{
        [IO.File]::WriteAllBytes($policyFile,$policyBytes);[IO.File]::SetLastWriteTimeUtc($policyFile,$policyTime)
        & (Get-Command Read-AiwContentUnitGraph).Module {Set-Item Function:script:Read-CsExactCore -Value $script:CsSavedExact;Remove-Variable CsBoundaryCalls,CsBoundaryPath,CsBoundaryBytes,CsBoundaryTime,CsSavedExact -Scope Script}
    }
    Check ((Read-AiwContentUnitGraph $sharedContext $sharedSnapshot).units.Count-eq3) 'fresh-graph-after-failure-reobserves-restored-bytes'
    Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -Force
    Check ((Read-AiwContentUnitGraph $sharedContext $sharedSnapshot).units.Count-eq3) 'module-reload-performs-independent-current-context-admission'
    # Actual ordinary and two-root contexts share physical source identity,
    # but only the isolated config root owns new cache and transport output.
    $compat=Join-Path $temp 'context-compatibility';$compatStage=Join-Path $temp 'context-compatibility-stage'
    $cc=NewTestProject $compat contextcompat;$cc.routineExcludedPaths=@('denied/')
    WriteText (Join-Path $compat 'rule.md') 'Current isolated cache compatibility.'
    $cc.sourceBindings=@((Binding compat '.' @((FilePermission 'rule.md'))))
    $cd=Descriptor COMPAT @((Document ROOT compat 'rule.md' (Identity (Join-Path $compat 'rule.md')))) $cc.sourceBindings
    Adopt $compat $cc @($cd);$ordinary=New-AiwContentContext $compat (Identity (Join-Path $compat '.ai-workspace/project.json')) @('denied','denied/')
    $cs=Resolve-AiwContentSnapshot $ordinary $cd;$cached=Read-AiwContentExact $ordinary $cs $cd.documents[0]
    $null=[IO.Directory]::CreateDirectory((Join-Path $compatStage '.ai-workspace'))
    foreach($name in @('project.json','process-policy.json')){[IO.File]::Copy((Join-Path $compat ('.ai-workspace/'+$name)),(Join-Path $compatStage ('.ai-workspace/'+$name)),$false)}
    $dual=New-AiwContentContext $compatStage (Identity (Join-Path $compatStage '.ai-workspace/project.json')) @('denied/','denied') -SourceProjectRoot $compat
    Check ($ordinary.Forbidden.Count-eq1-and$dual.Forbidden.Count-eq2-and$dual.CacheRoot-ceq(Join-Path $compatStage '.ai-workspace/runtime/content-sources')) 'projection-forbidden-is-idempotent-and-cache-root-is-config-root'
    $saved=[IO.File]::ReadAllBytes((Join-Path $compat 'rule.md'));[IO.File]::Delete((Join-Path $compat 'rule.md'))
    try{
        $ds=Resolve-AiwContentSnapshot $dual $cd;$read=Read-AiwContentExact $dual $ds $cd.documents[0]
        Check ($read.observation-ceq'PINNED_CACHE'-and$read.cachePath-ceq$cached.cachePath-and-not[IO.Directory]::Exists($dual.CacheRoot)) 'projection-reads-exact-original-pinned-cache-without-copy-or-live-write'
    }finally{[IO.File]::WriteAllBytes((Join-Path $compat 'rule.md'),$saved)}
    $liveCacheBefore=Identity $cached.cachePath
    $local=Read-AiwContentExact $dual (Resolve-AiwContentSnapshot $dual $cd) $cd.documents[0]
    Check ($local.observation-ceq'LOCAL'-and$local.cachePath.StartsWith($compatStage+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-and[IO.File]::Exists($local.cachePath)-and(Identity $cached.cachePath)-ceq$liveCacheBefore) 'projection-populates-only-isolated-cache-and-preserves-original-raw'
    $originalCache=$dual.CacheRoot;$dual.CacheRoot=Join-Path $compat 'arbitrary-cache'
    Reject {Resolve-AiwContentSnapshot $dual $cd} 'CONTENT_IDENTITY_DRIFT|CONTEXT' 'public-cache-root-mutation-is-not-a-private-proof'
    $dual.CacheRoot=$originalCache
    $copyRoot=Join-Path $temp 'context-module-copy';$null=[IO.Directory]::CreateDirectory($copyRoot)
    foreach($name in @('ContentSources.psm1','ProjectSourcePublication.psm1','StrictJsonInput.psm1')){[IO.File]::Copy((Join-Path $versionRoot ('scripts/'+$name)),(Join-Path $copyRoot $name),$false)}
    $copy=Import-Module (Join-Path $copyRoot 'ContentSources.psm1') -PassThru -Force
    foreach($pair in @(@{context=$ordinary;label='ordinary'},@{context=$dual;label='projection'})){
        $snapshot=& $copy.ExportedCommands['Resolve-AiwContentSnapshot'] $pair.context $cd
        $read=& $copy.ExportedCommands['Read-AiwContentExact'] $pair.context $snapshot $cd.documents[0]
        Check ($read.identity-ceq$cd.documents[0].identity) ($pair.label+'-nonempty-exclusions-module-copy-independently-admits-context')
    }
    Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -Force
    foreach($pair in @(@{context=$ordinary;label='ordinary'},@{context=$dual;label='projection'})){
        Check ((Read-AiwContentExact $pair.context (Resolve-AiwContentSnapshot $pair.context $cd) $cd.documents[0]).identity-ceq$cd.documents[0].identity) ($pair.label+'-nonempty-exclusions-module-reload-independently-admits-context')
    }
    Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1')
    $deletion=[pscustomobject]@{kind='FILE';path='rule.md';newExists=$false;newIdentity='MISSING';newBase64=''}
    $removed=New-AiwAdoptionContentContext -ProjectRoot $compatStage -ExpectedProjectConfigIdentity (Identity (Join-Path $compatStage '.ai-workspace/project.json')) -SourceProjectRoot $compat -ProjectedSourceObjects @($deletion)
    Reject {Resolve-AiwContentSnapshot $removed $cd} 'SOURCE_DENIED|FORBIDDEN_PATH' 'actual-adoption-deletion-factory-refuses-still-adopted-live-and-cache-source'
    Adopt $compatStage $cc @()
    $removed=New-AiwAdoptionContentContext -ProjectRoot $compatStage -ExpectedProjectConfigIdentity (Identity (Join-Path $compatStage '.ai-workspace/project.json')) -SourceProjectRoot $compat -ProjectedSourceObjects @($deletion)
    Check ((Get-AiwProjectPolicySourceClosure -ProjectRoot $compatStage -Rules @() -ContentContext $removed).Documents.Count-eq0) 'actual-adoption-deletion-with-withdrawn-adoption-has-empty-legal-closure'
    # The compositor's closed batch must preserve public graph meaning, reject
    # caller pollution and never return a mixed successful adoption snapshot.
    $obRoot=Join-Path $temp 'owned-batch';$obSupply=Join-Path $temp 'owned-batch-supply'
    foreach($name in @('A','B','D')){WriteText (Join-Path $obSupply ($name+'.md')) $name}
    $obConfig=NewTestProject $obRoot 'owned-batch'
    $obConfig.sourceBindings=@((Binding main $obSupply @((FilePermission 'A.md'),(FilePermission 'B.md'),(FilePermission 'D.md'))))
    $obDependency=Document D main 'D.md' (Identity (Join-Path $obSupply 'D.md'))
    $obFirst=Descriptor FIRST @((Document A main 'A.md' (Identity (Join-Path $obSupply 'A.md')) @('D')),$obDependency) $obConfig.sourceBindings
    $obSecond=Descriptor SECOND @((Document B main 'B.md' (Identity (Join-Path $obSupply 'B.md')) @('D')),$obDependency) $obConfig.sourceBindings
    Adopt $obRoot $obConfig @($obFirst,$obSecond)
    $obRules=(Get-Content -LiteralPath (Join-Path $obRoot '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100).rules
    $obContext=Context $obRoot;$obModule=(Get-Command Resolve-AiwContentSnapshot).Module
    $obInvoke={param($m,$root,$rules,$context) & $m {param($r,$rs,$c) Invoke-CsOwnedStandardsBatch -ProjectRoot $r -Rules $rs -ContentContext $c} $root $rules $context}
    $obValues=@(& $obInvoke $obModule $obRoot $obRules $null)
    Check ($obValues.Count-eq1-and$obValues[0].rules.Count-eq2-and-not$obModule.ExportedCommands.ContainsKey('Invoke-CsOwnedStandardsBatch')) 'owned-batch-is-private-and-returns-one-complete-value'
    $obBatch=$obValues[0]
    foreach($entry in @(@{id='FIRST';descriptor=$obFirst},@{id='SECOND';descriptor=$obSecond})){
        $obSnapshot=Resolve-AiwContentSnapshot $obContext $entry.descriptor
        $obPublic=Read-AiwContentUnitGraph $obContext $obSnapshot
        $obActual=$obBatch.rules[$entry.id]
        Check ($obActual.snapshot.identity-ceq$obSnapshot.identity-and$obActual.graph.identity-ceq$obPublic.identity-and[bool]$obActual.graph.authority-eq$false) ('owned-batch-'+$entry.id+'-same-public-snapshot-and-ordered-unit-identity')
        Check ((@($obActual.graph.units|ForEach-Object{$_.document.sourceId+':'+$_.unit.body})-join'|')-ceq(@($obPublic.units|ForEach-Object{$_.document.sourceId+':'+$_.unit.body})-join'|')) ('owned-batch-'+$entry.id+'-same-complete-bodies-and-dependency-order')
    }
    $obForged=Clone $obRules;$obForged[1].source.documents[0].locator='not-adopted.md'
    Reject {& $obInvoke $obModule $obRoot $obForged $null} 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET' 'owned-batch-does-not-normalize-untrusted-request-into-current-adoption'

    # The independently verified request is a subset, including the empty set.
    # Observe actual body/cache reader calls; a faulty expansion to all adopted
    # rules must fail even though FIRST and SECOND were read earlier.
    & $obModule {
        $script:SubsetBodyReads=[Collections.Generic.List[string]]::new()
        $script:SubsetCacheReads=0
        $script:SubsetSavedRead=(Get-Command Read-CsResolvedExact).ScriptBlock
        $script:SubsetSavedCache=(Get-Command Read-CsPinnedCache).ScriptBlock
        Set-Item Function:script:Read-CsResolvedExact -Value {
            param($Context,$Snapshot,$Document,$PhysicalReadCache,$resolved,$cacheKey)
            $script:SubsetBodyReads.Add([string]$Document.sourceId)
            if($Document.sourceId-ceq'B'){throw 'TEST_UNSELECTED_PHYSICAL_READ'}
            & $script:SubsetSavedRead $Context $Snapshot $Document $PhysicalReadCache $resolved $cacheKey
        }
        Set-Item Function:script:Read-CsPinnedCache -Value {
            param($Context,$Key,$MaxObjectBytes)
            $script:SubsetCacheReads++
            & $script:SubsetSavedCache $Context $Key $MaxObjectBytes
        }
    }
    try{
        $obEmpty=& $obInvoke $obModule $obRoot @() $null
        $obEmptyIo=& $obModule {@{body=$script:SubsetBodyReads.Count;cache=$script:SubsetCacheReads}}
        Check ($obEmpty.rules.Count-eq0-and$obEmptyIo.body-eq0-and$obEmptyIo.cache-eq0) 'owned-empty-request-does-not-open-adopted-bodies-or-caches'
        $obSubset=& $obInvoke $obModule $obRoot @($obRules[0]) $null
        $obSubsetIo=& $obModule {@{body=@($script:SubsetBodyReads);cache=$script:SubsetCacheReads}}
        Check ($obSubset.rules.Count-eq1-and$obSubset.rules.ContainsKey('FIRST')-and($obSubsetIo.body-join',')-ceq'D,A'-and$obSubsetIo.cache-eq0-and$obSubset.rules.FIRST.graph.identity-ceq$obBatch.rules.FIRST.graph.identity) 'owned-subset-reads-complete-selected-dependency-only-with-original-meaning'
        $obNotAdopted=Clone $obRules[0];$obNotAdopted.ruleId='FORGED'
        Reject {& $obInvoke $obModule $obRoot @($obNotAdopted) $null} 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET' 'owned-subset-rejects-unadopted-rule-id'
        Reject {& $obInvoke $obModule $obRoot @($obRules[0],$obRules[0]) $null} 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET' 'owned-subset-rejects-duplicate-request-members'
        $obChanged=Clone $obRules[0];$obChanged.resultRequirements=@('FORGED_OBLIGATION')
        Reject {& $obInvoke $obModule $obRoot @($obChanged) $null} 'CONTENT_IDENTITY_DRIFT|POLICY_SOURCE_SET' 'owned-subset-rejects-changed-adopted-record'
    }finally{
        & $obModule {
            Set-Item Function:script:Read-CsResolvedExact -Value $script:SubsetSavedRead
            Set-Item Function:script:Read-CsPinnedCache -Value $script:SubsetSavedCache
        }
    }
    $obForbidden=$obContext.Forbidden;$obContext.Forbidden=@($obForbidden)+@((Join-Path $obSupply 'D.md'))
    try{Reject {& $obInvoke $obModule $obRoot $obRules $obContext} 'CONTENT_IDENTITY_DRIFT|CONTEXT' 'owned-batch-public-context-pollution-remains-rejected'}finally{$obContext.Forbidden=$obForbidden}
    $obBatch.rules.FIRST.graph.units[0].unit.body='caller mutation'
    $obFresh=& $obInvoke $obModule $obRoot $obRules $null
    Check ($obFresh.rules.FIRST.graph.units[0].unit.body-ceq'D') 'owned-batch-output-mutation-cannot-pollute-next-independent-call'
    $obPolicy=Join-Path $obRoot '.ai-workspace/process-policy.json';$obPolicyBefore=[IO.File]::ReadAllBytes($obPolicy)
    & $obModule {
        param($path)
        $script:OwnedBatchPolicyPath=$path;$script:OwnedBatchChanged=$false;$script:OwnedBatchSavedRead=(Get-Command Read-CsResolvedExact).ScriptBlock
        Set-Item Function:script:Read-CsResolvedExact -Value {
            param($Context,$Snapshot,$Document,$PhysicalReadCache,$resolved,$cacheKey)
            $read=& $script:OwnedBatchSavedRead $Context $Snapshot $Document $PhysicalReadCache $resolved $cacheKey
            if(-not$script:OwnedBatchChanged){[IO.File]::AppendAllText($script:OwnedBatchPolicyPath,"`n",[Text.UTF8Encoding]::new($false));$script:OwnedBatchChanged=$true}
            return $read
        }
    } $obPolicy
    try{
        $obError='';$obMixed=@();try{$obMixed=@(& $obInvoke $obModule $obRoot $obRules $null)}catch{$obError=$_.Exception.Message}
        Check ($obError-cmatch'CONTENT_IDENTITY_DRIFT\|CURRENT_PERMISSION_OR_ADOPTION'-and$obMixed.Count-eq0) 'owned-batch-mid-policy-drift-never-delivers-mixed-success'
    }finally{& $obModule {Set-Item Function:script:Read-CsResolvedExact -Value $script:OwnedBatchSavedRead};[IO.File]::WriteAllBytes($obPolicy,$obPolicyBefore)}

    Write-Output ('CONTENT_SOURCES_LOCAL_TESTS|PASS|'+$passed)
}finally{if($junction-and(Test-Path -LiteralPath $junction)){Remove-Item -LiteralPath $junction -Force};if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{RemoveTestRoot $temp}}
