[CmdletBinding()]param([switch]$LiveRemote,[switch]$KeepFixture)
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly -KeepFixture:$KeepFixture
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
Import-Module (Join-Path $versionRoot 'scripts/KnowledgeSources.psm1') -Force
$content=Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -PassThru
$composer=Get-Module ProcessRequirementComposition
$temp=Join-Path ([IO.Path]::GetTempPath()) ('r-'+[guid]::NewGuid().ToString('N'))
function Permission([string]$Path,[string]$Kind='FILE'){[pscustomobject]@{kind=$Kind;locator=$Path}}
function RemoteBinding([string]$Id,[string]$Provider,[string]$Location,[object[]]$Paths){$field=if($Provider-ceq'GIT_REVISION'){'repository'}else{'baseUrl'};[pscustomobject]@{id=$Id;provider=$Provider;locator=[pscustomobject]@{$field=$Location};allowedPaths=$Paths;decisionLocator='fixture:approved-public-or-isolated-source'}}
function RemoteDoc([string]$Id,[string]$Binding,[string]$Path,[string]$Identity,$Revision){[pscustomobject]@{sourceId=$Id;bindingId=$Binding;revision=$Revision;locator=$Path;identity=$Identity;mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}}
function RemoteDescriptor([string]$Id,[object[]]$Documents,[object[]]$Bindings){
 $revision=if($Documents[0].revision.kind-ceq'GIT_COMMIT'){$Documents[0].revision}else{Get-AiwContentRevision ([pscustomobject]@{documents=$Documents}) $Bindings}
 $d=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$Documents[0].bindingId;itemId=$Id;revision=$revision;itemIdentity='';rootSourceId=$Documents[0].sourceId;documents=$Documents};$d.itemIdentity=Get-AiwContentItemIdentity $d;return $d
}
function AdoptRemote($Root,$Config,[object[]]$Descriptors){
 Store (Join-Path $Root '.ai-workspace/project.json') $Config
 $rules=@($Descriptors|ForEach-Object{[pscustomobject]@{ruleId=$_.itemId;requirementReason='Bounded remote fixture';decisionLocator='fixture:adopt-exact';source=$_;selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}})
 Store (Join-Path $Root '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$Config.id;rules=$rules})
}
function Context($Root){New-AiwContentContext $Root (Identity (Join-Path $Root '.ai-workspace/project.json'))}
function BoundRule($Root,$Context){$rule=(Get-Content (Join-Path $Root '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100).rules[0];& $composer {param($p,$r,$c)Get-AiwBoundProjectSourceRule $p $r @() $c} $Root $rule $Context}
function MethodEntry([string]$Path,[string]$Identity){[pscustomobject]@{id='METHOD';kind='METHOD';state='CURRENT';title='Method';summary='Transport fixture';tags=@('fixture');locator=$Path;identity=$Identity;verifiedAt='2026-10-01T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','CONTENT_VERSION_CHANGE');tokenEstimate=1;originalSources=@([pscustomobject]@{title='Fixture';url='https://example.invalid/fixture';accessedAt='2026-10-01T00:00:00Z';licenseNotice='Synthetic fixture'});applicability=@('fixture');contentVersion='1';maintenance=[pscustomobject]@{owner='fixture';locator='README.md'}}}
function KnowledgeConfig($Config,[string]$Binding,[string]$Index,[string]$Selector){$Config.frameworkCapabilities=[pscustomobject]@{KNOWLEDGE_REFERENCE=[pscustomobject]@{enabled=$true;sources=@([pscustomobject]@{id='methods';bindingId=$Binding;indexLocator=$Index;selectionHints=@('fixture');updatePolicy='FOLLOW';revisionSelector=$Selector})}}}
function FixtureGit([string[]]$Arguments){$raw=@(& git -C $script:repo @Arguments 2>&1|ForEach-Object{[string]$_});if($LASTEXITCODE-ne0){throw ('FIXTURE_GIT|'+($raw-join' '))};return ,$raw}
try{
 $project=Join-Path $temp 'project';$configuration=NewTestProject $project remote
 if($LiveRemote){
  # Explicitly approved public repository, observed full commit; no moving ref
  # is substituted for the adopted sample. Network failure is a failed run.
  $commit='2f90aa5b71cb0217097ccf9e3bb7aa0d21e2c4b7'
  $repository='https://github.com/313715295/AI-Workspace.git'
  $base='https://raw.githubusercontent.com/313715295/AI-Workspace/'+$commit+'/framework/versions/2.0.0/'
  $configuration.sourceBindings=@((RemoteBinding publicgit GIT_REVISION $repository @((Permission 'README.md'))),(RemoteBinding publichttps HTTPS_RESOURCE $base @((Permission 'knowledge' DIRECTORY))))
  KnowledgeConfig $configuration publichttps 'knowledge/index.json' 'knowledge/index.json';AdoptRemote $project $configuration @();$ctx=Context $project
  $rev=[pscustomobject]@{kind='GIT_COMMIT';value=$commit};$doc=RemoteDoc README publicgit 'README.md' ('0|'+('0'*64)) $rev
  $bytes=& $content {param($c,$d)Read-CsTransport $c (Resolve-CsDocument $c $d)} $ctx $doc
  $doc.identity=Get-AiwContentByteIdentity $bytes;$descriptor=RemoteDescriptor PUBLIC @($doc) $configuration.sourceBindings
  AdoptRemote $project $configuration @($descriptor);$ctx=Context $project;$snap=Resolve-AiwContentSnapshot $ctx $descriptor;$read=Read-AiwContentExact $ctx $snap $doc
  Check ($read.identity-ceq$doc.identity-and$read.observation-ceq'REMOTE') 'LIVE_GIT-exact-approved-commit-object'
  $assembled=BoundRule $project $ctx
  Check ($assembled.RawBody-ceq$utf8.GetString($bytes)-and$assembled.Documents[0].locatorKind-ceq'GIT_REVISION') 'LIVE_GIT-composer-original-body-and-physical-commit'
  Check ((Test-AiwContentSnapshot $ctx $snap).observations[0]-ceq'PINNED_CACHE') 'LIVE_GIT-verify-uses-fixed-cache-not-latest'
  $followCommit=& $content {param($c,$d)Read-CsGit $c (Resolve-CsDocument $c $d) -ResolveRef -Selector HEAD} $ctx $doc
  $followDoc=Clone $doc;$followDoc.revision.value=$followCommit
  $followBytes=& $content {param($c,$d)Read-CsTransport $c (Resolve-CsDocument $c $d)} $ctx $followDoc
  Check ($followCommit-cmatch'^(?:[a-f0-9]{40}|[a-f0-9]{64})$'-and$followBytes.Length-gt0) 'LIVE_GIT-follow-resolves-commit-and-reads-same-object'
  [IO.File]::WriteAllBytes((Join-Path $project 'live-follow-readme.bin'),$followBytes)
  $opened=Resolve-AiwKnowledgeSnapshot $ctx $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
  $index=$utf8.GetString($opened.IndexBytes)|ConvertFrom-Json -Depth 100 -DateKind String;$entry=@($index.entries|Where-Object kind -CEQ METHOD)[0]
  $query=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Identity (Join-Path $project '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:'+$entry.id) -ContentMode FULLTEXT
  Check ($query.entries[0].status-ceq'CURRENT'-and$query.entries[0].observedIdentity-ceq$entry.identity) 'LIVE_HTTPS-public-index-and-method-query'
  $httpDoc=RemoteDoc METHOD publichttps $entry.locator $entry.identity ([pscustomobject]@{kind='CONTENT_IDENTITY';value=$entry.identity})
  $httpDescriptor=RemoteDescriptor PUBLIC_HTTP @($httpDoc) $configuration.sourceBindings
  AdoptRemote $project $configuration @($httpDescriptor);$ctx=Context $project;$assembled=BoundRule $project $ctx
  Check ($assembled.RawBody-ceq$query.entries[0].fullText-and$assembled.Documents[0].locatorKind-ceq'HTTPS_RESOURCE') 'LIVE_HTTPS-composer-exact-same-method-bytes'
  Store (Join-Path $project 'live-observation.json') ([ordered]@{evidence='ACTUAL_PUBLIC_READ_ONLY_NETWORK';repository=$repository;commit=$commit;gitDocument=$doc;gitFollowCommit=$followCommit;gitFollowDocumentIdentity=(Get-AiwContentByteIdentity $followBytes);httpsBase=$base;indexIdentity=$opened.IndexIdentity;method=$httpDoc;decision='Approved W4 Framework public repository and exact raw commit sample';privateCredentials='UNAVAILABLE_NOT_TESTED';gitKnowledge='DETERMINISTIC_LOCAL_GIT_FIXTURE_ONLY: public index locators are relative to version root, not repository root'})
  Write-Output ('LIVE_REMOTE_EVIDENCE|'+(Join-Path $project 'live-observation.json')+'|'+(Identity (Join-Path $project 'live-observation.json')))
  Write-Output ('CONTENT_SOURCES_REMOTE_LIVE_TESTS|PASS|'+$passed);return
 }
 $repo=Join-Path $temp 'supply';$null=[IO.Directory]::CreateDirectory($repo);$null=FixtureGit @('init','-q');$null=FixtureGit @('config','user.name','Fixture');$null=FixtureGit @('config','user.email','fixture@example.invalid')
 WriteText (Join-Path $repo 'rule.md') 'First fixed rule.';WriteText (Join-Path $repo 'method.md') 'First method.'
 $entry=MethodEntry 'method.md' (Identity (Join-Path $repo 'method.md'));Store (Join-Path $repo 'index.json') ([pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@($entry)})
 $null=FixtureGit @('add','--','rule.md','method.md','index.json');$null=FixtureGit @('commit','-qm','first');$first=(FixtureGit @('rev-parse','HEAD'))[0]
 $firstId=Identity (Join-Path $repo 'rule.md');WriteText (Join-Path $repo 'rule.md') 'Second fixed rule.';$null=FixtureGit @('add','--','rule.md');$null=FixtureGit @('commit','-qm','second');$second=(FixtureGit @('rev-parse','HEAD'))[0]
 $configuration.sourceBindings=@((RemoteBinding git GIT_REVISION $repo @((Permission '.' DIRECTORY))))
 $d1=RemoteDescriptor FIRST @((RemoteDoc R git 'rule.md' $firstId ([pscustomobject]@{kind='GIT_COMMIT';value=$first}))) $configuration.sourceBindings
 $d2=RemoteDescriptor SECOND @((RemoteDoc R git 'rule.md' (Identity (Join-Path $repo 'rule.md')) ([pscustomobject]@{kind='GIT_COMMIT';value=$second}))) $configuration.sourceBindings
 KnowledgeConfig $configuration git 'index.json' HEAD;AdoptRemote $project $configuration @($d1,$d2);$ctx=Context $project
 $hook=Join-Path $repo '.git/hooks/post-checkout';WriteText $hook "#!/bin/sh`necho bad > hooked`n";$null=FixtureGit @('config','core.fsmonitor','echo bad > hooked')
 $s1=Resolve-AiwContentSnapshot $ctx $d1;$s2=Resolve-AiwContentSnapshot $ctx $d2;$r1=Read-AiwContentExact $ctx $s1 $d1.documents[0];$r2=Read-AiwContentExact $ctx $s2 $d2.documents[0]
 Check ($utf8.GetString($r1.bytes)-ceq'First fixed rule.'-and$utf8.GetString($r2.bytes)-ceq'Second fixed rule.'-and$r1.physicalSource-cne$r2.physicalSource) 'git-one-binding-two-exact-commits'
 Check (-not(Test-Path (Join-Path $repo 'hooked'))-and[IO.File]::ReadAllText((Join-Path $repo 'rule.md'))-ceq'Second fixed rule.') 'git-never-checks-out-or-invokes-source-hooks'
 $stage=Join-Path $temp 'git-projection';$null=[IO.Directory]::CreateDirectory((Join-Path $stage '.ai-workspace'))
 foreach($name in @('project.json','process-policy.json')){[IO.File]::Copy((Join-Path $project ('.ai-workspace/'+$name)),(Join-Path $stage ('.ai-workspace/'+$name)),$false)}
 $projection=New-AiwContentContext $stage (Identity (Join-Path $stage '.ai-workspace/project.json')) -SourceProjectRoot $project
 $originalRaw=Identity $r1.cachePath
 $pinned=Read-AiwContentExact $projection (Resolve-AiwContentSnapshot $projection $d1) $d1.documents[0]
 Check ($pinned.observation-ceq'PINNED_CACHE'-and$pinned.cachePath-ceq$r1.cachePath-and-not[IO.Directory]::Exists($projection.CacheRoot)) 'git-projection-pinned-reads-original-exact-cache-without-scratch'
 $owner=(Get-Command Read-AiwContentExact).Module
 & $owner {
  $script:CsProjectionWork=[Collections.Generic.List[string]]::new();$script:CsProjectionSavedGit=(Get-Command Invoke-CsGit).ScriptBlock
  Set-Item Function:script:Invoke-CsGit -Value {param($Context,$Work,$Arguments,$Limits,$MonitorRoot='',$ObjectDirectory='');$script:CsProjectionWork.Add($Work);& $script:CsProjectionSavedGit $Context $Work $Arguments $Limits $MonitorRoot $ObjectDirectory}
 }
 try{
  $follow=Read-AiwContentExact $projection (Resolve-AiwContentSnapshot $projection $d1 FOLLOW) $d1.documents[0]
  $works=@(& $owner {$script:CsProjectionWork.ToArray()})
  Check ($works.Count-gt0-and@($works|Where-Object{-not$_.StartsWith($projection.CacheRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}).Count-eq0-and@([IO.Directory]::EnumerateDirectories($projection.CacheRoot)).Count-eq0-and(Identity $r1.cachePath)-ceq$originalRaw) 'git-projection-follow-real-scratch-stays-isolated-and-is-released'
  $missing=RemoteDescriptor MISSING @((RemoteDoc M git 'missing.md' ('1|'+('A'*64)) ([pscustomobject]@{kind='GIT_COMMIT';value=$first}))) $configuration.sourceBindings
  AdoptRemote $stage $configuration @($d1,$missing)
  $broken=New-AiwContentContext $stage (Identity (Join-Path $stage '.ai-workspace/project.json')) -SourceProjectRoot $project
  Reject {Read-AiwContentExact $broken (Resolve-AiwContentSnapshot $broken $missing FOLLOW) $missing.documents[0]} 'SOURCE_UNAVAILABLE' 'git-projection-real-transport-failure-keeps-source-error'
  Check (@([IO.Directory]::EnumerateDirectories($projection.CacheRoot)).Count-eq0-and(Identity $r1.cachePath)-ceq$originalRaw) 'git-projection-real-transport-failure-releases-scratch-and-preserves-live-cache'
 }finally{& $owner {Set-Item Function:script:Invoke-CsGit -Value $script:CsProjectionSavedGit}}

 $opened=Resolve-AiwKnowledgeSnapshot $ctx $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
 $null=FixtureGit @('config','--unset','core.fsmonitor');WriteText (Join-Path $repo 'method.md') 'Later method.';$null=FixtureGit @('add','--','method.md');$null=FixtureGit @('commit','-qm','later')
 $reference=Read-AiwKnowledgeReference $ctx $opened 'method.md' $entry.identity
 Check ($utf8.GetString($reference.bytes)-ceq'First method.'-and$opened.Snapshot.facts.resolvedRevision.value-ceq$second) 'git-follow-fixes-one-commit-for-index-and-all-entries'
 # Real Git parent-config counterexample. The approved URL is deliberately
 # unreachable; inherited insteadOf makes an unisolated query succeed elsewhere.
 # Keep this one Windows counterexample at the previously rejected depth;
 # ordinary fixtures use the shorter names. These are fixture inputs, not limits.
 $parentName='config-parent';$deepPadding=0
 if($IsWindows){
  $unpaddedCache=Join-Path (Join-Path $temp 'config-parent/nested/project') '.ai-workspace/runtime/content-sources'
  $unpaddedWork=Join-Path $unpaddedCache ('g'+('0'*32))
  $deepPadding=[Math]::Max(0,232-$unpaddedWork.Length)
  if($deepPadding-gt128){throw 'DEEP_GIT_FIXTURE_PADDING_RANGE'}
  $parentName+=('x'*$deepPadding)
 }
 $parent=Join-Path $temp $parentName;$nested=Join-Path $parent 'nested/project';$isolation=NewTestProject $nested isolation
 $fakeUrl='https://127.0.0.1:1/approved.git';$fileUrl=([Uri]($repo+[IO.Path]::DirectorySeparatorChar)).AbsoluteUri.TrimEnd('/')
 $null=& git -C $parent init -q;if($LASTEXITCODE-ne0){throw 'FIXTURE_PARENT_INIT'}
 $null=& git -C $parent config ('url.'+$fileUrl+'.insteadOf') $fakeUrl;if($LASTEXITCODE-ne0){throw 'FIXTURE_PARENT_CONFIG'}
 $isolation.sourceBindings=@((RemoteBinding git GIT_REVISION $fakeUrl @((Permission '.' DIRECTORY))))
 KnowledgeConfig $isolation git index.json HEAD;AdoptRemote $nested $isolation @();$isolatedContext=Context $nested
 $probe=RemoteDoc INDEX git index.json ('0|'+('0'*64)) ([pscustomobject]@{kind='GIT_COMMIT';value=('0'*40)})
 $resolved=& $content {param($c,$d)Resolve-CsDocument $c $d} $isolatedContext $probe
 $unisolated=& $content {param($c,$w,$u,$l)Invoke-CsGit $c $w @('ls-remote','--',$u,'HEAD') $l} $isolatedContext $nested $fakeUrl $resolved.Limits
 Check ($utf8.GetString($unisolated).Contains((FixtureGit @('rev-parse','HEAD'))[0])) 'git-parent-insteadOf-counterexample-is-real'
 function ObserveIsolation([bool]$RemoveIsolation){
  & $content {param($mutate)
   $script:IsolationOriginalGit=(Get-Command Invoke-CsGit).ScriptBlock
   $script:IsolationCalls=[Collections.Generic.List[object]]::new();$script:IsolationMutation=$mutate
   function script:Invoke-CsGit($Context,[string]$Work,[string[]]$Arguments,$Limits,[string]$MonitorRoot='',[string]$ObjectDirectory=''){
    $effective=$Arguments
    # Deliberate reverted-isolation control only. The normal probe delegates
    # every argument unchanged; both probes execute real Git/config/transport.
    if($script:IsolationMutation-and'ls-remote'-cin$Arguments){$effective=[string[]]@($Arguments|Where-Object{-not$_.StartsWith('--git-dir=',[StringComparison]::Ordinal)})}
    $call=[pscustomobject]@{arguments=@($effective);work=$Work;completed=$false;error='NONE'};$script:IsolationCalls.Add($call)
    try{$bytes=& $script:IsolationOriginalGit $Context $Work $effective $Limits $MonitorRoot $ObjectDirectory;$call.completed=$true;return ,$bytes}
    catch{$call.error=$_.Exception.Message;throw}
   }
  } $RemoveIsolation
  $failure='NONE'
  try{$null=Resolve-AiwKnowledgeSnapshot $isolatedContext $isolation.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]}
  catch{$failure=$_.Exception.Message}
  finally{
   $calls=& $content {return ,$script:IsolationCalls.ToArray()}
   & $content {Set-Item -LiteralPath Function:script:Invoke-CsGit -Value $script:IsolationOriginalGit;Remove-Variable IsolationOriginalGit,IsolationCalls,IsolationMutation -Scope Script}
  }
  return [pscustomobject]@{mutation=$RemoveIsolation;error=$failure;calls=@($calls)}
 }
 function IsolationRejectedAtRef($Observation){
  $refs=@($Observation.calls|Where-Object{'ls-remote'-cin$_.arguments});$fetches=@($Observation.calls|Where-Object{'fetch'-cin$_.arguments})
  return ($Observation.error-ceq'SOURCE_UNAVAILABLE|GIT_COMMAND'-and$refs.Count-eq1-and-not$refs[0].completed-and$fetches.Count-eq0)
 }
 $isolatedTrace=ObserveIsolation $false
 $normalInit=@($isolatedTrace.calls|Where-Object{($_.arguments-join'|')-ceq'init|--bare|--template=|refs.git'})
 $deepReady=$normalInit.Count-eq1-and$normalInit[0].completed
 $deepWork='';$deepGitDir='';$deepHeads=''
 if($normalInit.Count-eq1){$deepWork=$normalInit[0].work;$deepGitDir=Join-Path $deepWork 'refs.git';$deepHeads=Join-Path $deepGitDir 'refs/heads'}
 if($IsWindows){$deepReady=$deepReady-and$deepWork.Length-ge232-and$deepGitDir.Length-le241-and$deepHeads.Length-ge252}
 Check ($deepReady-and(IsolationRejectedAtRef $isolatedTrace)) 'git-isolation-fails-at-ref-query-before-any-fixed-object-fetch'
 $revertedTrace=ObserveIsolation $true
 Check (-not(IsolationRejectedAtRef $revertedTrace)-and$revertedTrace.error-ceq$isolatedTrace.error-and@($revertedTrace.calls|Where-Object{'ls-remote'-cin$_.arguments-and$_.completed}).Count-eq1-and@($revertedTrace.calls|Where-Object{'fetch'-cin$_.arguments}).Count-eq1) 'git-isolation-assertion-rejects-reverted-parameter-despite-same-error'
 Store (Join-Path $project 'git-isolation-regression.json') ([ordered]@{evidence='ACTUAL_GIT_CALLS_UNCHANGED_DELEGATION_AND_EXPLICIT_REVERTED_ISOLATION_CONTROL';isolated=$isolatedTrace;reverted=$revertedTrace;currentAssertion=$true;revertedAssertion=$false;deepFixture=@{windows=$IsWindows;padding=$deepPadding;work=$deepWork;workLength=$deepWork.Length;gitDir=$deepGitDir;gitDirLength=$deepGitDir.Length;refsHeads=$deepHeads;refsHeadsLength=$deepHeads.Length;precondition=$deepReady;meaning='Original Windows failing directory depth retained; ordinary fixtures shortened'}})
 # Exercise loose, packed, nested and non-commit tags through real Git and
 # the public knowledge consumer, retaining a single fixed commit per query.
 $null=FixtureGit @('tag','-a','annotated','-m','fixture',$second)
 $null=FixtureGit @('tag','lightweight',$second)
 $null=FixtureGit @('tag','-a','nested-tag','-m','fixture','annotated')
 $null=FixtureGit @('tag','-a','blob-tag','-m','fixture',(FixtureGit @('rev-parse',($second+':method.md')))[0])
 $null=FixtureGit @('tag','-a','tree-tag','-m','fixture',(FixtureGit @('rev-parse',($second+'^{tree}')))[0])
 function TagQuery([string]$Selector,[string]$Expected,[string]$Label){
  KnowledgeConfig $configuration git index.json $Selector;AdoptRemote $project $configuration @($d1,$d2)
  $c=Context $project;$o=Resolve-AiwKnowledgeSnapshot $c $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
  $q=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Identity (Join-Path $project '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:METHOD') -ContentMode FULLTEXT
  Check ($o.Snapshot.facts.resolvedRevision.value-ceq$Expected-and$q.entries[0].status-ceq'CURRENT'-and$q.entries[0].fullText-ceq'First method.') $Label
 }
 TagQuery refs/tags/annotated $second 'git-loose-annotated-tag-knowledge-query'
 TagQuery refs/tags/lightweight $second 'git-lightweight-tag-knowledge-query'
 TagQuery refs/tags/nested-tag $second 'git-nested-annotated-tag-peels-to-commit'
 $null=FixtureGit @('pack-refs','--all','--prune')
 TagQuery refs/tags/annotated $second 'git-packed-annotated-tag-knowledge-query'
 foreach($tag in @('blob-tag','tree-tag')){
  KnowledgeConfig $configuration git index.json ('refs/tags/'+$tag);AdoptRemote $project $configuration @($d1,$d2);$c=Context $project
  Reject {Resolve-AiwKnowledgeSnapshot $c $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]} 'SOURCE_DENIED|GIT_COMMIT_REQUIRED' ('git-rejects-noncommit-'+$tag)
 }
 KnowledgeConfig $configuration git index.json refs/tags/annotated;AdoptRemote $project $configuration @($d1,$d2);$c=Context $project
 $tagOpened=Resolve-AiwKnowledgeSnapshot $c $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
 $null=FixtureGit @('tag','-f','annotated','HEAD')
 $tagRead=Read-AiwKnowledgeReference $c $tagOpened method.md $entry.identity
 Check ($tagOpened.Snapshot.facts.resolvedRevision.value-ceq$second-and$utf8.GetString($tagRead.bytes)-ceq'First method.') 'git-moving-tag-does-not-change-open-query'
 # The remote-ref parser gets real Git advertisements and fetches via a local
 # file transport adapter. This is not HTTPS evidence; P1 above is unmodified.
 & $content {param($url,$local)
  $script:FixtureInvokeGit=(Get-Command Invoke-CsGit).ScriptBlock;$script:FixtureGitUrl=$url;$script:FixtureGitLocal=$local
  function script:Invoke-CsGit($Context,[string]$Work,[string[]]$Arguments,$Limits,[string]$MonitorRoot='',[string]$ObjectDirectory=''){
   $mapped=[string[]]@($Arguments|ForEach-Object{if($_-ceq$script:FixtureGitUrl){$script:FixtureGitLocal}else{$_}})
   return ,(& $script:FixtureInvokeGit $Context $Work $mapped $Limits $MonitorRoot $ObjectDirectory)
  }
 } 'https://fixture.invalid/git' $fileUrl
 try{
  $configuration.sourceBindings[0].locator.repository='https://fixture.invalid/git'
  $advertised=FixtureGit @('ls-remote','--',$fileUrl,'refs/tags/nested-tag','refs/tags/nested-tag^{}')
  Check ($advertised.Count-eq2-and($advertised[0]-split'\s+')[0]-cne($advertised[1]-split'\s+')[0]) 'git-remote-tag-advertisement-has-distinct-peeled-object'
  TagQuery refs/tags/nested-tag $second 'git-remote-annotated-tag-parser-with-real-git-file-transport'
  TagQuery refs/tags/lightweight $second 'git-remote-lightweight-tag-parser-with-real-git-file-transport'
  KnowledgeConfig $configuration git index.json refs/tags/blob-tag;AdoptRemote $project $configuration @();$c=Context $project
  Reject {Resolve-AiwKnowledgeSnapshot $c $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]} 'SOURCE_DENIED|GIT_COMMIT_REQUIRED' 'git-remote-peeled-noncommit-rejected'
 }finally{
  & $content {Set-Item -LiteralPath Function:script:Invoke-CsGit -Value $script:FixtureInvokeGit;Remove-Variable FixtureInvokeGit,FixtureGitUrl,FixtureGitLocal -Scope Script}
  $configuration.sourceBindings[0].locator.repository=$repo
 }
 KnowledgeConfig $configuration git index.json HEAD;AdoptRemote $project $configuration @($d1,$d2);$ctx=Context $project
 $assembled=BoundRule $project $ctx;Check ($assembled.RawBody-ceq'First fixed rule.'-and$assembled.Blocks[0].SourcePath.Contains($first)-and$assembled.Blocks[0].Key-cmatch'^\d+\|[A-F0-9]{64}$') 'git-composer-preserves-raw-body-and-exact-physical-commit-unit'
 $wrong=Clone $d1;$wrong.documents[0].revision.value=$second;$wrong.revision.value=$second;$wrong.itemIdentity=Get-AiwContentItemIdentity $wrong
 AdoptRemote $project $configuration @($wrong);$wc=Context $project;$ws=Resolve-AiwContentSnapshot $wc $wrong
 Reject {Read-AiwContentExact $wc $ws $wrong.documents[0]} 'CONTENT_IDENTITY_DRIFT|DOCUMENT' 'git-other-commit-cannot-reuse-first-commit-body-or-cache'
 $null=FixtureGit @('update-index','--add','--cacheinfo',('120000,'+(FixtureGit @('rev-parse',($first+':rule.md')))[0]+',link.md'))
 $null=FixtureGit @('update-index','--add','--cacheinfo',('160000,'+$first+',submodule'))
 $null=FixtureGit @('commit','-qm','special');$special=(FixtureGit @('rev-parse','HEAD'))[0]
 foreach($path in @('link.md','submodule')){$d=RemoteDescriptor SPECIAL @((RemoteDoc S git $path $firstId ([pscustomobject]@{kind='GIT_COMMIT';value=$special}))) $configuration.sourceBindings;AdoptRemote $project $configuration @($d);$c=Context $project;$s=Resolve-AiwContentSnapshot $c $d;Reject {Read-AiwContentExact $c $s $d.documents[0]} 'SOURCE_DENIED|GIT_SPECIAL_OBJECT' ('git-rejects-'+$path)}
 AdoptRemote $project $configuration @($d1);$ctx=Context $project;$s1=Resolve-AiwContentSnapshot $ctx $d1;$null=Read-AiwContentExact $ctx $s1 $d1.documents[0]
 $offline=$repo+'-offline';[IO.Directory]::Move($repo,$offline)
 try{Check ((Read-AiwContentExact $ctx $s1 $d1.documents[0]).observation-ceq'PINNED_CACHE') 'git-pinned-offline-exact-cache';Reject {Resolve-AiwKnowledgeSnapshot $ctx $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]} 'SOURCE_UNAVAILABLE' 'git-follow-offline-fails'}finally{[IO.Directory]::Move($offline,$repo)}
 $commitDocs=@((RemoteDoc A git 'rule.md' $firstId ([pscustomobject]@{kind='GIT_COMMIT';value=$first})),(RemoteDoc B git 'rule.md' $d2.documents[0].identity ([pscustomobject]@{kind='GIT_COMMIT';value=$second})))
 $commitDocs[0].dependencies=@('B');$commitGraph=RemoteDescriptor COMMITS $commitDocs $configuration.sourceBindings
 AdoptRemote $project $configuration @($commitGraph);$ctx=Context $project
 $commitUnits=Read-AiwContentUnitGraph $ctx (Resolve-AiwContentSnapshot $ctx $commitGraph)
 Check ($commitUnits.units.Count-eq2-and$commitUnits.units[0].unit.identity-cne$commitUnits.units[1].unit.identity-and($commitUnits.units.document.sourceId-join',')-ceq'B,A') 'git-exact-commits-remain-distinct-physical-versions-in-one-graph'
 # Inject a deterministic HttpMessageHandler, not a weakened TLS/network mode.
 # The production redirect/stream/timeout code still runs unchanged.
 if(-not('AiwRemoteFixtureHandler'-as[type])){Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Net; using System.Net.Http; using System.Threading; using System.Threading.Tasks;
public sealed class AiwRemoteResponse { public byte[] Bytes=Array.Empty<byte>(); public int Status=200; public string Location=null; public string Type="text/plain"; public long Length=-1; public int Delay=0; }
public sealed class AiwUnboundedFixtureContent : HttpContent {
 private readonly byte[] data; public AiwUnboundedFixtureContent(byte[] b){data=b;}
 protected override bool TryComputeLength(out long n){n=0;return false;}
 protected override Task SerializeToStreamAsync(Stream s,TransportContext c){return s.WriteAsync(data,0,data.Length);}
}
public sealed class AiwRemoteFixtureHandler : HttpMessageHandler {
 public static readonly Dictionary<string,AiwRemoteResponse> Routes=new Dictionary<string,AiwRemoteResponse>(StringComparer.Ordinal);
 public static readonly List<string> Requests=new List<string>();
 protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken c) {
  Requests.Add(r.RequestUri.AbsoluteUri); if(!Routes.TryGetValue(r.RequestUri.AbsoluteUri,out var x)) throw new HttpRequestException("offline");
  if(x.Delay>0) await Task.Delay(x.Delay,c);
  var response=new HttpResponseMessage((HttpStatusCode)x.Status);response.Content=new AiwUnboundedFixtureContent(x.Bytes);
  response.Content.Headers.ContentType=new System.Net.Http.Headers.MediaTypeHeaderValue(x.Type);
  if(x.Length>=0)response.Content.Headers.ContentLength=x.Length;else response.Content.Headers.ContentLength=null;
  if(x.Location!=null)response.Headers.Location=new Uri(x.Location,UriKind.RelativeOrAbsolute);return response;
 }
}
'@}
 & $content {function script:New-CsHttpClient {return [Net.Http.HttpClient]::new([AiwRemoteFixtureHandler]::new())}}
 function Response([string]$Path,[string]$Text,[int]$Status=200,[string]$Location=''){$v=[AiwRemoteResponse]::new();$v.Bytes=$utf8.GetBytes($Text);$v.Status=$Status;if($Location){$v.Location=$Location};[AiwRemoteFixtureHandler]::Routes['https://fixture.invalid/base/'+$Path]=$v;return $v}
 $body='Exact HTTPS rule.';$null=Response 'rule.md' $body
 $configuration.sourceBindings=@((RemoteBinding https HTTPS_RESOURCE 'https://fixture.invalid/base/' @((Permission '.' DIRECTORY))))
 $identity=Get-AiwContentByteIdentity $utf8.GetBytes($body);$hd=RemoteDescriptor HTTP @((RemoteDoc H https 'rule.md' $identity ([pscustomobject]@{kind='CONTENT_IDENTITY';value=$identity}))) $configuration.sourceBindings
 AdoptRemote $project $configuration @($hd);$ctx=Context $project;$hs=Resolve-AiwContentSnapshot $ctx $hd;$hr=Read-AiwContentExact $ctx $hs $hd.documents[0]
 Check ($hr.observation-ceq'REMOTE'-and$utf8.GetString($hr.bytes)-ceq$body) 'https-exact-stream-read-and-cache'
 $null=Response 'rule.md' 'Changed remote body.';$following=Resolve-AiwContentSnapshot $ctx $hd FOLLOW
 Reject {Read-AiwContentExact $ctx $following $hd.documents[0]} 'CONTENT_IDENTITY_DRIFT|DOCUMENT' 'https-changed-body-is-not-an-adopted-revision'
 [AiwRemoteFixtureHandler]::Routes.Clear();Check ((Test-AiwContentSnapshot $ctx $hs).observations[0]-ceq'PINNED_CACHE') 'https-pinned-offline-verification-keeps-original-snapshot'
 $p2=Join-Path $temp 'other-project';$c2=NewTestProject $p2 other;$c2.sourceBindings=$configuration.sourceBindings;AdoptRemote $p2 $c2 @($hd);$ctx2=Context $p2;$hs2=Resolve-AiwContentSnapshot $ctx2 $hd
 Reject {Read-AiwContentExact $ctx2 $hs2 $hd.documents[0]} 'SOURCE_UNAVAILABLE' 'https-same-hash-other-project-has-no-cache-authority'
 $revoked=Clone $configuration;$revoked.sourceBindings[0].allowedPaths=@((Permission 'different.md'));AdoptRemote $project $revoked @($hd);$denied=Context $project
 Reject {Read-AiwContentExact $ctx $hs $hd.documents[0]} 'CONTENT_IDENTITY_DRIFT' 'permission-change-invalidates-existing-context-before-cache'
 Reject {Resolve-AiwContentSnapshot $denied $hd} 'SOURCE_DENIED' 'revoked-current-permission-cannot-read-cache'
 AdoptRemote $project $configuration @($hd);$ctx=Context $project
 function Transport([string]$Path){& $content {param($c,$p)Read-CsTransport $c (Resolve-CsDocument $c ([pscustomobject]@{bindingId='https';locator=$p}))} $ctx $Path}
 $null=Response 'target.md' 'redirect target';$null=Response 'redirect.md' '' 302 'target.md'
 Check ($utf8.GetString((Transport 'redirect.md'))-ceq'redirect target') 'https-same-origin-permitted-redirect'
 $null=Response 'escape.md' '' 302 'https://other.invalid/secret';Reject {Transport 'escape.md'} 'SOURCE_DENIED|HTTP_TARGET' 'https-cross-origin-redirect-denied'
 $null=Response 'base-escape.md' '' 302 '/outside';Reject {Transport 'base-escape.md'} 'SOURCE_DENIED|HTTP_TARGET' 'https-base-path-redirect-denied'
 $null=Response 'loop.md' '' 302 'loop.md';Reject {Transport 'loop.md'} 'TRANSPORT_LIMIT_EXCEEDED|REDIRECTS' 'https-redirect-budget'
 $v=Response 'html.md' '<html>error</html>';$v.Type='text/html';Reject {Transport 'html.md'} 'SOURCE_DENIED|CONTENT_TYPE' 'https-error-page-not-rule-text'
 $v=Response 'truncated.md' 'short';$v.Length=100;Reject {Transport 'truncated.md'} 'SOURCE_UNAVAILABLE' 'https-short-response-never-fulltext'
 $limited=Clone $configuration;$limited.sourceBindings[0]|Add-Member transportLimits ([pscustomobject]@{maxObjectBytes=8;timeoutMs=100;maxRedirects=0});AdoptRemote $project $limited @($hd);$ctx=Context $project
 $null=Response 'large.md' '0123456789abcdef';Reject {Transport 'large.md'} 'TRANSPORT_LIMIT_EXCEEDED|OBJECT_BYTES' 'https-stream-size-limit-without-length'
 $v=Response 'slow.md' 'slow';$v.Delay=1000;Reject {Transport 'slow.md'} 'TRANSPORT_LIMIT_EXCEEDED|TIMEOUT' 'https-total-request-timeout'
 Reject {Transport '../secret'} 'SOURCE_DENIED' 'https-locator-escape-before-request';Reject {Transport '%2e%2e/secret'} 'SOURCE_DENIED' 'https-encoded-escape-before-request'
 $private=Clone $configuration;$private.sourceBindings[0]|Add-Member credentialRef 'host:fixture';AdoptRemote $project $private @($hd);$ctx=Context $project
 Reject {Transport 'rule.md'} 'CREDENTIAL_UNAVAILABLE' 'unresolved-credential-reference-no-network-or-cache-fallback'
 $null=Response 'method.md' 'HTTPS method.';$entry=MethodEntry 'method.md' (Get-AiwContentByteIdentity $utf8.GetBytes('HTTPS method.'))
 $index=[pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@($entry)};$null=Response 'index.json' ($index|ConvertTo-Json -Depth 50 -Compress)
 KnowledgeConfig $configuration https 'index.json' 'index.json';AdoptRemote $project $configuration @($hd);$ctx=Context $project
 $before=@([AiwRemoteFixtureHandler]::Requests|Where-Object{$_-ceq'https://fixture.invalid/base/index.json'}).Count
 $opened=Resolve-AiwKnowledgeSnapshot $ctx $configuration.frameworkCapabilities.KNOWLEDGE_REFERENCE.sources[0]
 $null=Response 'index.json' '{"changed":true}';$rr=Read-AiwKnowledgeReference $ctx $opened 'method.md' $entry.identity
 Check ($utf8.GetString($rr.bytes)-ceq'HTTPS method.'-and@([AiwRemoteFixtureHandler]::Requests|Where-Object{$_-ceq'https://fixture.invalid/base/index.json'}).Count-eq($before+1)) 'https-follow-one-index-read-per-query'
 $null=Response 'index.json' ($index|ConvertTo-Json -Depth 50 -Compress)
 $query=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Identity (Join-Path $project '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:METHOD') -ContentMode FULLTEXT
 Check ($query.entries[0].status-ceq'CURRENT'-and$query.entries[0].fullText-ceq'HTTPS method.') 'https-actual-knowledge-query-consumer'
 $derived=[pscustomobject]@{schemaVersion=3;libraryId='methods';entries=@([pscustomobject]@{id='PROJECT';kind='PROJECT_DERIVED';state='CURRENT';title='Not project authority';summary='Must reject remote project facts';tags=@();locator='method.md';identity=$entry.identity;verifiedAt='2026-10-01T00:00:00Z';invalidatesOn=@('REFERENCE_IDENTITY_CHANGE','AUTHORITY_DEPENDENCY_IDENTITY_CHANGE');tokenEstimate=1;projectId=$configuration.id;authorityDependencies=@([pscustomobject]@{locator='method.md';identity=$entry.identity})})}
 $null=Response 'index.json' ($derived|ConvertTo-Json -Depth 50 -Compress)
 $badQuery=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Identity (Join-Path $project '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:PROJECT')
 Check (@($badQuery.entries|Where-Object status -CEQ CURRENT).Count-eq0) 'https-project-derived-cannot-claim-local-project-authority'
 [AiwRemoteFixtureHandler]::Routes.Clear();$query=Invoke-AiwKnowledgeQuery -ProjectRoot $project -ExpectedProjectConfigIdentity (Identity (Join-Path $project '.ai-workspace/project.json')) -Operation QUERY -EntryId @('methods:METHOD')
 Check (@($query.entries|Where-Object status -CEQ CURRENT).Count-eq0) 'https-follow-offline-never-current'
 $assembled=BoundRule $project (Context $project);Check ($assembled.RawBody-ceq$body-and$assembled.Blocks[0].SourcePath-ceq'https://fixture.invalid/base/rule.md'-and$assembled.Blocks[0].Key-cmatch'^\d+\|[A-F0-9]{64}$') 'https-composer-keeps-origin-case-and-raw-body-from-exact-cache'
 $null=Response 'Rule.md' $body;$other=Clone $hd;$other.itemId='CASE_OTHER';$other.documents[0].locator='Rule.md';$other.revision=Get-AiwContentRevision $other $configuration.sourceBindings;$other.itemIdentity=Get-AiwContentItemIdentity $other
 AdoptRemote $project $configuration @($hd,$other);$policy=Get-Content (Join-Path $project '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100
 Reject {Test-AiwEffectiveRuleSet -ProjectRoot $project -Corrections @() -PolicyRules $policy.rules -Custom ([pscustomobject]@{HasNormativeContent=$false;Text='';Identity='MISSING'})} 'DUPLICATE_EFFECTIVE_RULE' 'https-path-case-is-not-same-physical-shared-chain'
 $unitBody="<A>`nRemote Alpha`n</A>`n<B>`nRemote Beta`n</B>";$null=Response 'units.md' $unitBody
 $unitIdentity=Get-AiwContentByteIdentity $utf8.GetBytes($unitBody)
 $unitDocs=@((RemoteDoc A https 'units.md' $unitIdentity ([pscustomobject]@{kind='CONTENT_IDENTITY';value=$unitIdentity})),(RemoteDoc B https 'units.md' $unitIdentity ([pscustomobject]@{kind='CONTENT_IDENTITY';value=$unitIdentity})))
 foreach($doc in $unitDocs){$doc.mode='MARKED_SECTION';$doc.sectionStart='<'+$doc.sourceId+'>';$doc.sectionEnd='</'+$doc.sourceId+'>'}
 $unitDocs[0].dependencies=@('B');$unitGraph=RemoteDescriptor HTTP_UNITS $unitDocs $configuration.sourceBindings
 AdoptRemote $project $configuration @($unitGraph);$ctx=Context $project
 $requestCount=[AiwRemoteFixtureHandler]::Requests.Count
 $units=Read-AiwContentUnitGraph $ctx (Resolve-AiwContentSnapshot $ctx $unitGraph)
 Check (($units.units.unit.body-join',')-ceq'Remote Beta,Remote Alpha'-and[AiwRemoteFixtureHandler]::Requests.Count-eq$requestCount+1) 'https-complete-section-graph-reuses-one-whole-file-read-within-call'
 $unitDocs[1].sectionStart='<A>';$unitDocs[1].sectionEnd='</A>';$unitGraph=RemoteDescriptor HTTP_ALIAS $unitDocs $configuration.sourceBindings
 AdoptRemote $project $configuration @($unitGraph);$ctx=Context $project
 Reject {Read-AiwContentUnitGraph $ctx (Resolve-AiwContentSnapshot $ctx $unitGraph)} 'UNIT_DUPLICATE' 'https-content-revision-dependency-metadata-does-not-create-a-new-physical-unit'
 Write-Output ('CONTENT_SOURCES_REMOTE_TESTS|PASS|'+$passed+'|evidence=LOCAL_GIT_AND_ISOLATED_HTTP_TRANSPORT|liveRemote=NOT_RUN')
}finally{
 if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{
  $root=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar
  if(-not$root.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($root)-cnotmatch'^r-[a-f0-9]{32}$'){throw 'TEST_CLEANUP_SCOPE'}
  # Git marks loose objects read-only. Clean only this verified isolated root;
  # a cleanup failure must never replace the original test exception.
  try{if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}catch{Write-Warning ('FIXTURE_CLEANUP_FAILED|'+$root)}
 }
}
