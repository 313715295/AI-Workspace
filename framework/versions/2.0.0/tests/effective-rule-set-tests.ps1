[CmdletBinding()]param([switch]$KeepFixture,[switch]$ContextCompatibilityOnly)
. (Join-Path $PSScriptRoot 'object-formats-tests.ps1') -FixtureHelpersOnly -KeepFixture:$KeepFixture
Import-Module (Join-Path $versionRoot 'scripts/ProcessRequirementComposition.psm1') -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-effective-'+[guid]::NewGuid().ToString('N'))
function Rule([string]$Id,[string]$Body){[pscustomobject]@{ruleId=$Id;effectiveRule=$Body;selectors=[pscustomobject]@{roles=@('REVIEWER')};preparationRequirements=@('P_'+$Id);resultRequirements=@('R_'+$Id)}}
function Correction([string]$Id,[string]$Body){[pscustomobject]@{correctionId=$Id;effectiveRule=$Body;selectors=[pscustomobject]@{roles=@('EXECUTOR')}}}
function Custom([string]$Body){[pscustomobject]@{HasNormativeContent=($Body.Length-gt0);Text=$Body;Identity=(Get-AiwContentByteIdentity $utf8.GetBytes($Body))}}
function LifecycleRecord([string]$Body){[pscustomobject]@{correctionId='LIFE';introducedAgainstFramework='2.0.0';requirementReason='Current lifecycle fixture';effectiveRule=$Body;applicability='Fixture';decisionLocator='fixture:explicit-decision';selectors=[pscustomobject]@{profiles=@();roles=@('EXECUTOR');phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()}}
function LifecyclePlan([string]$Root,[string]$Operation,$Record,[string]$Batch){
    $install=$Operation-ceq'INSTALL'
    [pscustomobject]@{schemaVersion=1;operation=$Operation;correctionId='LIFE';expectedCorrectionsIdentity=(Identity (Join-Path $Root '.ai-workspace/corrections.json'));decisionLocator='fixture:explicit-decision';record=$Record;installation=$(if($install){[pscustomobject]@{schemaVersion=1;correctionId='LIFE';decisionLocator='fixture:explicit-decision';dependsOn=@();changes=@()}}else{'NOT_APPLICABLE'});installationRelativePath=$(if($install){'.ai-workspace/upgrade-recovery/corrections/LIFE/'+$Batch+'/installation.json'}else{'NOT_APPLICABLE'});transactionRelativePath=('.ai-workspace/upgrade-recovery/corrections/LIFE/'+$Batch+'/state.json');impact=[pscustomobject]@{stoppedObligations=@();independentObligations=@();inFlightEffects=@();recovery='Original projection recovery';semanticAssessment='Compare the complete future effective set'};forbiddenPaths=@()}
}
function Test-SourceLifeContextCompatibility {
    param([switch]$ContextOnly)
    Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionTransaction.psm1')
    Import-Module (Join-Path $sourceRoot 'scripts/ProjectCorrectionLifecycle.psm1')
    # Public lifecycle preview with genuine installation-owned config, policy
    # and source effects. Persist previews using the real storage engine only;
    # these isolated storage callbacks are not project action authorization.
    $sourceLife=Join-Path $temp 'source-lifecycle';$sourceLifeConfig=NewTestProject $sourceLife
    WriteText (Join-Path $sourceLife '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    $sourceLifeOriginalConfig=[IO.File]::ReadAllBytes((Join-Path $sourceLife '.ai-workspace/project.json'))
    $sourceLifeOriginalPolicy=[IO.File]::ReadAllBytes((Join-Path $sourceLife '.ai-workspace/process-policy.json'))
    function SourceLifeSignature([string]$Root=$sourceLife) {
        $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($Root)
        $rows=[Collections.Generic.List[string]]::new()
        while($pending.Count){
            $directory=$pending.Pop()
            if((Get-Item -LiteralPath $directory -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'SOURCE_LIFE_SNAPSHOT_REPARSE'}
            foreach($entry in Get-ChildItem -LiteralPath $directory -Force){
                if($entry.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'SOURCE_LIFE_SNAPSHOT_REPARSE'}
                $relative=[IO.Path]::GetRelativePath($Root,$entry.FullName).Replace('\','/')
                $rows.Add($relative+'|'+$(if($entry.PSIsContainer){'DIRECTORY'}else{Identity $entry.FullName}))
                if($entry.PSIsContainer){$pending.Push($entry.FullName)}
            }
        }
        [string[]]$paths=$rows.ToArray();[Array]::Sort($paths,[StringComparer]::Ordinal);return $paths-join"`n"
    }
    function Test-SourceLifePreviewPreserved([string]$Before,[string]$Root=$sourceLife){
        try{$after=SourceLifeSignature $Root}catch{if($_.Exception.Message-ceq'SOURCE_LIFE_SNAPSHOT_REPARSE'){return $false};throw}
        if($after-ceq$Before){return $true}
        $beforeRows=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $afterRows=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($row in ($Before-split"`n")){if($row.Length){$null=$beforeRows.Add($row)}}
        foreach($row in ($after-split"`n")){if($row.Length){$null=$afterRows.Add($row)}}
        foreach($row in $beforeRows){if(-not$afterRows.Contains($row)){return $false}}
        $added=@($afterRows|Where-Object{-not$beforeRows.Contains($_)})
        # First synchronized observation may create this empty carrier and its
        # parents. Existing rows, other runtime content and links never qualify.
        $lockRow='.ai-workspace/runtime/source-publication.lock|0|E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855'
        if($lockRow-cnotin$added){return $false}
        $allowed=@($lockRow,'.ai-workspace|DIRECTORY','.ai-workspace/runtime|DIRECTORY')
        return @($added|Where-Object{$_-cnotin$allowed}).Count-eq0
    }
    if(-not$ContextOnly){
    # Counterexamples protect the widened oracle, independently of production.
    foreach($kind in @('lock-only','existing-parents','parents-only','nonempty-lock','directory-lock','extra-file','extra-directory','changed-file','removed-file','reparse-lock','reparse-parent')){
        $root=Join-Path $temp ('snapshot-'+$kind);$null=[IO.Directory]::CreateDirectory($root)
        $existing=Join-Path $root 'existing.bin';WriteText $existing 'Preserve these exact bytes.'
        $runtime=Join-Path $root '.ai-workspace/runtime';$lock=Join-Path $runtime 'source-publication.lock';$junction=$null
        if($kind-ceq'existing-parents'){$null=[IO.Directory]::CreateDirectory($runtime)}
        $before=SourceLifeSignature $root
        try{
            $null=[IO.Directory]::CreateDirectory($runtime)
            if($kind-cnotin@('parents-only','directory-lock','reparse-lock','reparse-parent')){[IO.File]::WriteAllBytes($lock,[byte[]]@())}
            switch($kind){
                'nonempty-lock' {WriteText $lock 'not empty'}
                'directory-lock' {$null=[IO.Directory]::CreateDirectory($lock)}
                'extra-file' {WriteText (Join-Path $runtime 'unexpected.json') '{}'}
                'extra-directory' {$null=[IO.Directory]::CreateDirectory((Join-Path $runtime 'unexpected'))}
                'changed-file' {WriteText $existing 'Changed bytes must fail.'}
                'removed-file' {[IO.File]::Delete($existing)}
                'reparse-lock' {$outside=Join-Path $temp 'snapshot-outside-lock';$null=[IO.Directory]::CreateDirectory($outside);$null=New-Item -ItemType Junction -Path $lock -Target $outside;$junction=$lock}
                'reparse-parent' {$outside=Join-Path $temp 'snapshot-outside-parent';$null=[IO.Directory]::CreateDirectory($outside);[IO.Directory]::Delete($runtime);$null=New-Item -ItemType Junction -Path $runtime -Target $outside;$junction=$runtime}
            }
            Check ((Test-SourceLifePreviewPreserved $before $root)-eq($kind-cin@('lock-only','existing-parents'))) ('source-lifecycle-snapshot-carrier-'+$kind)
        }finally{
            if($junction){
                $full=[IO.Path]::GetFullPath($junction);$base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))+[IO.Path]::DirectorySeparatorChar
                if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'SNAPSHOT_JUNCTION_CLEANUP_SCOPE'}
                [IO.Directory]::Delete($full)
            }
        }
    }
    }
    function SourceLifePlan([string]$Operation,[string]$Batch,[string]$Body='Owned prospective source body.'){
        $plan=LifecyclePlan $sourceLife $Operation $(if($Operation-cin@('INSTALL','REVISE')){LifecycleRecord 'Unique source lifecycle increment.'}else{'NOT_APPLICABLE'}) $Batch
        if($Operation-cin@('INSTALL','REVISE')){
            $candidate=Clone $sourceLifeConfig;$candidate.sourceBindings=@([pscustomobject]@{id='life-source';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='owned/source.md'});decisionLocator='fixture:source-installation-permission'})
            $doc=[pscustomobject]@{sourceId='LIFE_SOURCE';bindingId='life-source';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator='owned/source.md';identity=(Get-AiwContentByteIdentity $utf8.GetBytes($Body));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@()}
            $doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $candidate.sourceBindings
            $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='life-source';itemId='LIFE_SOURCE';revision=$doc.revision;itemIdentity='';rootSourceId='LIFE_SOURCE';documents=@($doc)};$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
            $sourceRule=[pscustomobject]@{ruleId='LIFE_SOURCE';requirementReason='Installation-owned source';decisionLocator='fixture:source-installation-adoption';source=$descriptor;selectors=[pscustomobject]@{profiles=@();roles=@('EXECUTOR');phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@()}
            $candidatePolicy=[pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@($sourceRule)}
            $plan.installation=[pscustomobject]@{schemaVersion=1;correctionId='LIFE';decisionLocator='fixture:source-installation';dependsOn=@();changes=@(
                [pscustomobject]@{kind='FILE';path='.ai-workspace/project.json';beforeExists=$true;afterExists=$true;beforeBase64=[Convert]::ToBase64String($sourceLifeOriginalConfig);afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($candidate|ConvertTo-Json -Depth 100 -Compress)+"`n"))},
                [pscustomobject]@{kind='FILE';path='.ai-workspace/process-policy.json';beforeExists=$true;afterExists=$true;beforeBase64=[Convert]::ToBase64String($sourceLifeOriginalPolicy);afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($candidatePolicy|ConvertTo-Json -Depth 100 -Compress)+"`n"))},
                [pscustomobject]@{kind='FILE';path='owned/source.md';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes($Body))})}
            $plan.installationRelativePath='.ai-workspace/upgrade-recovery/corrections/LIFE/'+$Batch+'/installation.json'
        }
        return $plan
    }
    function SourceLifePreview($Plan){
        $path=Join-Path $temp ('source-life-'+[IO.Path]::GetFileName([IO.Path]::GetDirectoryName($Plan.transactionRelativePath))+'.json');Store $path $Plan
        return Invoke-AiwCorrectionLifecycle -RepositoryRoot $sourceLife -PlanPath $path -ExpectedPlanIdentity (Identity $path) -ProjectId fixture -Version '2.0.0'
    }
    function SourceLifeStore($Plan){
        $before=SourceLifeSignature;$prepared=SourceLifePreview $Plan
        Check ($prepared.status-ceq'READY'-and(Test-SourceLifePreviewPreserved $before)) ('public-source-lifecycle-'+$Plan.operation+'-preview-preserves-live-bytes-and-fixed-carrier') | Out-Host
        $verify={param($root,$projection)foreach($entry in $projection.objects){$id=if(Test-Path -LiteralPath (Join-Path $root $entry.path) -PathType Leaf){Identity (Join-Path $root $entry.path)}else{'MISSING'};if($id-cne$entry.newIdentity){throw 'SOURCE_LIFECYCLE_POSTIMAGE'}};return $true}
        $stored=Invoke-AiwProjectProjectionTransaction $sourceLife $prepared.projection $Plan.transactionRelativePath $verify {$true}
        Check ($stored.status-ceq'COMPLETE') ('source-lifecycle-'+$Plan.operation+'-actual-owned-storage') | Out-Host
        return $prepared
    }

    if(-not$ContextOnly){
    # Public lifecycle consumes actual current config/policy bytes, never a
    # silently converted preview. Each rejection preserves the original scene.
    $fmtConfig=Join-Path $sourceLife '.ai-workspace/project.json';$fmtPolicy=Join-Path $sourceLife '.ai-workspace/process-policy.json'
    foreach($fault in @('legacy-config','invalid-config','legacy-policy','invalid-policy')){
        try{
            if($fault-clike'*-config'){
                $bad=$utf8.GetString($sourceLifeOriginalConfig)|ConvertFrom-Json -Depth 100
                if($fault-ceq'legacy-config'){$bad.schemaVersion=6;$bad.processPolicy.schemaVersion=2}else{$bad|Add-Member unexpectedCurrentField 'rejected'}
                Store $fmtConfig $bad
            }else{
                $bad=$utf8.GetString($sourceLifeOriginalPolicy)|ConvertFrom-Json -Depth 100
                if($fault-ceq'legacy-policy'){$bad.schemaVersion=2}else{$bad|Add-Member unexpectedCurrentField 'rejected'}
                Store $fmtPolicy $bad
            }
            $before=SourceLifeSignature;$caught=''
            $plan=LifecyclePlan $sourceLife INSTALL (LifecycleRecord 'Current format probe.') ('format-'+$fault)
            try{$null=SourceLifePreview $plan}catch{$caught=$_.Exception.Message}
            $signal=if($fault-clike'legacy-*'){'FORMAT_WRITE_REQUIRED'}else{'FORMAT_CURRENT_VALIDATION_FAILED'}
            Check ($caught.Contains($signal)-and(Test-SourceLifePreviewPreserved $before)) ('public-source-lifecycle-'+$fault+'-rejects-without-live-write|'+$caught)
        }finally{[IO.File]::WriteAllBytes($fmtConfig,$sourceLifeOriginalConfig);[IO.File]::WriteAllBytes($fmtPolicy,$sourceLifeOriginalPolicy)}
    }
    foreach($kind in @('config','policy')){
        $bad=SourceLifePlan INSTALL ('projected-format-'+$kind)
        $index=if($kind-ceq'config'){0}else{1};$effect=$bad.installation.changes[$index]
        $value=$utf8.GetString([Convert]::FromBase64String($effect.afterBase64))|ConvertFrom-Json -Depth 100
        if($kind-ceq'config'){$value.schemaVersion=6;$value.processPolicy.schemaVersion=2}else{$value.schemaVersion=2}
        $effect.afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($value|ConvertTo-Json -Depth 100 -Compress)+"`n"))
        $before=SourceLifeSignature;$caught='';try{$null=SourceLifePreview $bad}catch{$caught=$_.Exception.Message}
        Check ($caught.Contains('FORMAT_WRITE_REQUIRED')-and(Test-SourceLifePreviewPreserved $before)) ('public-source-lifecycle-projected-'+$kind+'-requires-formal-format-adoption')
    }

    }
    # Transparent observers delegate to the actual cmdlets and actual private
    # guard. Assertions compare actual event order and target metadata probes;
    # a final exception alone never proves a deny-before-probe result.
    # We do not claim that observing one cmdlet alone measures arbitrary .NET IO.
    $audit=[Collections.Generic.List[object]]::new()
    $lifecycleModule=(Get-Command Invoke-AiwCorrectionLifecycle).Module
    $auditModules=@(
        $lifecycleModule,
        (& $lifecycleModule {(Get-Command New-AiwContentContext).Module}),
        (& $lifecycleModule {(Get-Command Get-AiwContainedPath).Module})
    )
    foreach($module in $auditModules){
        & $module {
            param($Trace)
            $script:CacheAuditTrace=$Trace
            $script:CacheAuditDeniedTarget=''
            $script:CacheAuditPattern='[\\/]\.ai-workspace[\\/]runtime[\\/]content-sources(?:[\\/]|$)'
            function script:Test-Path {
                [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[string[]]$LiteralPath,[Microsoft.PowerShell.Commands.TestPathType]$PathType)
                foreach($value in @($Path)+@($LiteralPath)){if($value-match$script:CacheAuditPattern-or($script:CacheAuditDeniedTarget-and[string]::Equals($value,$script:CacheAuditDeniedTarget,[StringComparison]::OrdinalIgnoreCase))){$script:CacheAuditTrace.Add([pscustomobject]@{operation='EXISTENCE';path=$value})}}
                Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
            }
            function script:Get-Item {
                [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[string[]]$LiteralPath,[switch]$Force)
                foreach($value in @($Path)+@($LiteralPath)){if($value-match$script:CacheAuditPattern-or($script:CacheAuditDeniedTarget-and[string]::Equals($value,$script:CacheAuditDeniedTarget,[StringComparison]::OrdinalIgnoreCase))){$script:CacheAuditTrace.Add([pscustomobject]@{operation='METADATA';path=$value})}}
                Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
            }
        } $audit
    }
    $guardModule=$auditModules[1]
    & $guardModule {
        $script:CacheAuditOriginalGuard=(Get-Command Assert-CsPath -CommandType Function).ScriptBlock
        function script:Assert-CsPath {
            param([string]$Path,[string[]]$Forbidden=@(),[switch]$AllowMissing)
            if($Path-match$script:CacheAuditPattern){$script:CacheAuditTrace.Add([pscustomobject]@{operation='GUARD';path=$Path})}
            & $script:CacheAuditOriginalGuard $Path $Forbidden -AllowMissing:$AllowMissing
        }
    }
    & $lifecycleModule {
        $script:LifecycleAuditOriginalGuard=(Get-Command Assert-AiwLifecycleReadPath -CommandType Function).ScriptBlock
        function script:Assert-AiwLifecycleReadPath {
            param([string]$Root,[string]$Relative,[string[]]$Forbidden=@())
            $target=Get-AiwLifecycleLexicalPath $Root $Relative
            if($script:CacheAuditDeniedTarget-and$target.Equals($script:CacheAuditDeniedTarget,[StringComparison]::OrdinalIgnoreCase)){$script:CacheAuditTrace.Add([pscustomobject]@{operation='GUARD';path=$target})}
            & $script:LifecycleAuditOriginalGuard $Root $Relative $Forbidden
        }
    }
    try{
    if(-not$ContextOnly){
        # Two real isolated roots, a forbidden junction, trailing slash and a
        # neighboring prefix exercise the same private lexical implementation.
        $lexA=Join-Path $temp 'lexical-a';$lexB=Join-Path $temp 'lexical-b';$outside=Join-Path $temp 'lexical-outside'
        foreach($root in @($lexA,$lexB,$outside)){$null=[IO.Directory]::CreateDirectory($root)}
        $junction=Join-Path $lexA '.ai-workspace/runtime/content-sources';$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $junction))
        $null=New-Item -ItemType Junction -Path $junction -Target $outside
        try{
            $audit.Clear()
            $mapped=& $lifecycleModule {
                param($A,$B)
                $relative='.ai-workspace/runtime/content-sources/'
                $one=Get-AiwLifecycleLexicalPath $A $relative;$two=Get-AiwLifecycleLexicalPath $B $relative
                $neighbor=Assert-AiwLifecycleReadPath $A '.ai-workspace/runtime/content-sources-other/file.md' @($relative)
                $caught='';try{$null=Assert-AiwLifecycleReadPath $A '.ai-workspace/runtime/content-sources/file.md' @($relative)}catch{$caught=$_.Exception.Message}
                [pscustomobject]@{one=$one;two=$two;neighbor=$neighbor;exception=$caught}
            } $lexA $lexB
            Check ($mapped.one-ceq$junction-and$mapped.two-ceq(Join-Path $lexB '.ai-workspace/runtime/content-sources')-and$mapped.neighbor-ceq(Join-Path $lexA '.ai-workspace/runtime/content-sources-other/file.md')-and$mapped.exception-ceq'SOURCE_DENIED|FORBIDDEN_PATH'-and$audit.Count-eq0) 'lifecycle-forbidden-description-two-roots-junction-missing-trailing-slash-prefix-with-zero-probes'
        }finally{
            $full=[IO.Path]::GetFullPath($junction);$base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp))+[IO.Path]::DirectorySeparatorChar
            if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw 'LEXICAL_JUNCTION_CLEANUP_SCOPE'}
            [IO.Directory]::Delete($full)
        }
        foreach($relative in @('.ai-workspace/project.json','.ai-workspace/process-policy.json')){
            $plan=LifecyclePlan $sourceLife INSTALL (LifecycleRecord 'Denied read probe.') ('denied-'+[IO.Path]::GetFileName($relative))
            $plan.forbiddenPaths=@($relative);$target=Join-Path $sourceLife $relative
            foreach($module in $auditModules){& $module {param($Target)$script:CacheAuditDeniedTarget=$Target} $target}
            $before=SourceLifeSignature;$audit.Clear();$caught=''
            try{$null=SourceLifePreview $plan}catch{$caught=$_.Exception.Message}
            $events=@($audit.ToArray())
            foreach($module in $auditModules){& $module {$script:CacheAuditDeniedTarget=''}}
            Check ($caught-ceq'SOURCE_DENIED|FORBIDDEN_PATH'-and$events.Count-eq1-and$events[0].operation-ceq'GUARD'-and(Test-SourceLifePreviewPreserved $before)) ('public-source-lifecycle-denied-object-before-any-probe-'+[IO.Path]::GetFileName($relative))
        }
    }
    # Current policy3 normative units have no persistent raw cache. A forbidden
    # unused cache must not become a new source permission requirement.
    $normPlan=SourceLifePlan INSTALL current-normative-format 'Current complete normative lifecycle unit.'
    $candidate=$utf8.GetString([Convert]::FromBase64String($normPlan.installation.changes[0].afterBase64))|ConvertFrom-Json -Depth 100
    $normPolicy=$utf8.GetString([Convert]::FromBase64String($normPlan.installation.changes[1].afterBase64))|ConvertFrom-Json -Depth 100
    $normDoc=$normPolicy.rules[0].source.documents[0];$normDoc.PSObject.Properties.Remove('identity');$normDoc.mode='NORMATIVE_UNIT'
    $normDoc.sectionStart='<!-- LIFE:BEGIN -->';$normDoc.sectionEnd='<!-- LIFE:END -->'
    $normDoc|Add-Member unitId 'LIFE_SOURCE';$normDoc|Add-Member commonConditionSourceIds @()
    $normBody='Current complete normative lifecycle unit.'
    $facts=[ordered]@{provider='LOCAL_DIRECTORY';physicalSource=(Join-Path $sourceLife 'owned/source.md').ToUpperInvariant();permissionIdentity=(Get-AiwContentDescriptorIdentity $candidate.sourceBindings[0]);mode='NORMATIVE_UNIT';unitId='LIFE_SOURCE';parserVersion='UTF8_LF_COMPLETE_UNIT_V1';sectionStart=$normDoc.sectionStart;sectionEnd=$normDoc.sectionEnd;bodyIdentity=(Get-AiwContentByteIdentity $utf8.GetBytes($normBody))}
    $normDoc|Add-Member normativeIdentity (Get-AiwContentDescriptorIdentity ([ordered]@{unit=$facts;commonConditions=@();dependencies=@()}))
    $normDoc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($normDoc)}) $candidate.sourceBindings
    $normPolicy.rules[0].source.revision=Get-AiwContentRevision $normPolicy.rules[0].source $candidate.sourceBindings
    $normPolicy.rules[0].source.itemIdentity=Get-AiwContentItemIdentity $normPolicy.rules[0].source
    $normPlan.installation.changes[1].afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($normPolicy|ConvertTo-Json -Depth 100 -Compress)+"`n"))
    $normPlan.installation.changes[2].afterBase64=[Convert]::ToBase64String($utf8.GetBytes($normDoc.sectionStart+"`n"+$normBody+"`n"+$normDoc.sectionEnd))
    $normPlan.forbiddenPaths=@('.ai-workspace/runtime/content-sources')
    $before=SourceLifeSignature;$audit.Clear();$normPreview=SourceLifePreview $normPlan;$normEvents=@($audit.ToArray())
    Check ($normPreview.status-ceq'READY'-and$normEvents.Count-eq0-and(Test-SourceLifePreviewPreserved $before)) 'public-source-lifecycle-current-normative-unit-never-probes-unused-persistent-cache'
    if(-not$ContextOnly){
    $installedSource=SourceLifeStore (SourceLifePlan INSTALL source-install)
    $installedCarrier=Get-Content (Join-Path $sourceLife '.ai-workspace/corrections.json') -Raw|ConvertFrom-Json -Depth 100
    Check ($installedCarrier.corrections[0].lifecycle.installation-is[pscustomobject]-and[IO.File]::ReadAllText((Join-Path $sourceLife 'owned/source.md'))-ceq'Owned prospective source body.') 'source-lifecycle-install-retains-real-installation-ownership'
    $null=SourceLifeStore (SourceLifePlan PAUSE source-pause)
    Check (-not(Test-Path -LiteralPath (Join-Path $sourceLife 'owned/source.md'))-and(Identity (Join-Path $sourceLife '.ai-workspace/project.json'))-ceq(Get-AiwContentByteIdentity $sourceLifeOriginalConfig)) 'source-lifecycle-pause-withdraws-source-and-permission-effects'
    $null=SourceLifeStore (SourceLifePlan RESUME source-resume)
    Check ([IO.File]::ReadAllText((Join-Path $sourceLife 'owned/source.md'))-ceq'Owned prospective source body.') 'source-lifecycle-resume-consumes-prospective-new-adoption'
    $revise=SourceLifePlan REVISE source-revise 'Updated prospective normative source.'
    $null=SourceLifeStore $revise
    Check ([IO.File]::ReadAllText((Join-Path $sourceLife 'owned/source.md'))-ceq'Updated prospective normative source.') 'source-lifecycle-revise-consumes-updated-source-bytes'
    $cacheContext=New-AiwContentContext $sourceLife (Identity (Join-Path $sourceLife '.ai-workspace/project.json'))
    $cachePolicy=Get-Content (Join-Path $sourceLife '.ai-workspace/process-policy.json') -Raw|ConvertFrom-Json -Depth 100
    $cacheSnapshot=Resolve-AiwContentSnapshot $cacheContext $cachePolicy.rules[0].source
    $cachedBody=Read-AiwContentExact $cacheContext $cacheSnapshot $cacheSnapshot.descriptor.documents[0]
    $ownedPath=Join-Path $sourceLife 'owned/source.md';$ownedBytes=[IO.File]::ReadAllBytes($ownedPath)
    try{
        [IO.File]::Delete($ownedPath)
        $offlineBody=Read-AiwContentExact $cacheContext $cacheSnapshot $cacheSnapshot.descriptor.documents[0]
        Check ($offlineBody.observation-ceq'PINNED_CACHE'-and$offlineBody.identity-ceq$cachedBody.identity) 'source-lifecycle-exact-local-source-offline-cache-remains-supported'
    }finally{[IO.File]::WriteAllBytes($ownedPath,$ownedBytes)}
    $healthy=SourceLifePlan REVISE cache-healthy 'Updated prospective normative source.'
    $before=SourceLifeSignature;$healthyPreview=SourceLifePreview $healthy
    Check ($healthyPreview.status-ceq'READY'-and(SourceLifeSignature)-ceq$before) 'source-lifecycle-existing-exact-cache-preview-zero-live-write'
    # The production path no longer copies an unused cache. Make the original
    # deny-before-cache oracle reach a genuinely required exact PINNED fallback.
    $cacheSupply=Join-Path $temp 'cache-required-source';$cacheSource=Join-Path $cacheSupply 'owned/source.md'
    WriteText $cacheSource 'Updated prospective normative source.'
    $cacheTemplate=SourceLifePlan REVISE cache-required 'Updated prospective normative source.'
    $cacheConfig=$utf8.GetString([Convert]::FromBase64String($cacheTemplate.installation.changes[0].afterBase64))|ConvertFrom-Json -Depth 100
    $cacheConfig.sourceBindings[0].locator.root=$cacheSupply
    $cachePolicy=$utf8.GetString([Convert]::FromBase64String($cacheTemplate.installation.changes[1].afterBase64))|ConvertFrom-Json -Depth 100
    $cacheItem=$cachePolicy.rules[0].source
    $cacheItem.documents[0].revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($cacheItem.documents[0])}) $cacheConfig.sourceBindings
    $cacheItem.revision=Get-AiwContentRevision $cacheItem $cacheConfig.sourceBindings;$cacheItem.itemIdentity=Get-AiwContentItemIdentity $cacheItem
    $cacheConfigBytes=$utf8.GetBytes(($cacheConfig|ConvertTo-Json -Depth 100 -Compress)+"`n")
    $cachePolicyBytes=$utf8.GetBytes(($cachePolicy|ConvertTo-Json -Depth 100 -Compress)+"`n")
    $liveConfig=Join-Path $sourceLife '.ai-workspace/project.json';$livePolicy=Join-Path $sourceLife '.ai-workspace/process-policy.json'
    $savedConfig=[IO.File]::ReadAllBytes($liveConfig);$savedPolicy=[IO.File]::ReadAllBytes($livePolicy)
    try{
        [IO.File]::WriteAllBytes($liveConfig,$cacheConfigBytes);[IO.File]::WriteAllBytes($livePolicy,$cachePolicyBytes)
        $seedContext=New-AiwContentContext $sourceLife (Identity $liveConfig)
        $seedSnapshot=Resolve-AiwContentSnapshot $seedContext $cacheItem
        $cachedBody=Read-AiwContentExact $seedContext $seedSnapshot $cacheItem.documents[0]
    }finally{[IO.File]::WriteAllBytes($liveConfig,$savedConfig);[IO.File]::WriteAllBytes($livePolicy,$savedPolicy)}
    [IO.File]::Delete($cacheSource)
    function CacheRequiredLifePlan([string]$Batch){
        $plan=SourceLifePlan REVISE $Batch 'Updated prospective normative source.'
        $plan.installation.changes[0].afterBase64=[Convert]::ToBase64String($cacheConfigBytes)
        $plan.installation.changes[1].afterBase64=[Convert]::ToBase64String($cachePolicyBytes)
        return $plan
    }
    $before=SourceLifeSignature;$audit.Clear()
    $requiredCachePreview=SourceLifePreview (CacheRequiredLifePlan cache-required-positive)
    $requiredCacheEvents=@($audit.ToArray())
    Check ($requiredCachePreview.status-ceq'READY'-and(SourceLifeSignature)-ceq$before-and@($requiredCacheEvents|Where-Object{$_.operation-ceq'EXISTENCE'-and$_.path-ceq$cachedBody.cachePath}).Count-gt0) 'public-source-lifecycle-required-pinned-cache-positive-baseline'
        foreach($origin in @('PLAN','ROUTINE')){
            foreach($kind in @('DIRECTORY','FILE')){
                $bad=CacheRequiredLifePlan ('cache-deny-'+$origin+'-'+$kind)
                $denied=if($kind-ceq'DIRECTORY'){'.ai-workspace/runtime/content-sources'}else{[IO.Path]::GetRelativePath($sourceLife,$cachedBody.cachePath).Replace('\','/')}
                if($origin-ceq'PLAN'){$bad.forbiddenPaths=@($denied)}
                else{
                    $effect=$bad.installation.changes[0]
                    $future=$utf8.GetString([Convert]::FromBase64String($effect.afterBase64))|ConvertFrom-Json -Depth 100
                    $future.routineExcludedPaths=@($denied)
                    $effect.afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($future|ConvertTo-Json -Depth 100 -Compress)+"`n"))
                }
                $before=SourceLifeSignature;$audit.Clear();$caught=''
                try{$null=SourceLifePreview $bad}catch{$caught=$_.Exception.Message}
                $events=@($audit.ToArray())
                $zeroProbes=@($events|Where-Object{$_.operation-cne'GUARD'}).Count-eq0
                $early=$events.Count-gt0-and$events[0].operation-ceq'GUARD'
                Store (Join-Path $temp ('cache-deny-'+$origin+'-'+$kind+'-observation.json')) ([pscustomobject]@{denied=$denied;origin=$origin;exception=$caught;events=$events;zeroCacheMetadataOrExistenceProbe=$zeroProbes;firstCacheEventIsRealGuard=$early;liveBefore=$before;liveAfter=(SourceLifeSignature);interpretation='Recorded actual guard and metadata/existence events; the adjacent assertion evaluates deny-first ordering, zero probes and unchanged live bytes. No arbitrary IO instrumentation claim.'})
                Check ($caught.Contains('SOURCE_DENIED|FORBIDDEN_PATH')-and$early-and$zeroProbes-and(SourceLifeSignature)-ceq$before) ('public-source-lifecycle-cache-'+$origin+'-'+$kind+'-denied-before-cache-io-zero-live-write')
            }
        }
    }
    }finally{
        & $guardModule {Set-Item -LiteralPath function:script:Assert-CsPath -Value $script:CacheAuditOriginalGuard}
        & $lifecycleModule {Set-Item -LiteralPath function:script:Assert-AiwLifecycleReadPath -Value $script:LifecycleAuditOriginalGuard}
        foreach($module in $auditModules){& $module {Remove-Item -LiteralPath function:script:Test-Path,function:script:Get-Item}}
    }
    if(-not$ContextOnly){
    foreach($fault in @('DUPLICATE','UNADOPTED','PERMISSION','BYTES','REMOVAL')){
        $bad=SourceLifePlan REVISE ('source-reject-'+$fault) $(if($fault-ceq'DUPLICATE'){'Unique source lifecycle increment.'}else{'Next prospective normative source.'})
        $effect=$bad.installation.changes[1];$future=$utf8.GetString([Convert]::FromBase64String($effect.afterBase64))|ConvertFrom-Json -Depth 100
        if($fault-ceq'UNADOPTED'){$future.rules[0].source.documents[0].bindingId='missing-binding';$future.rules[0].source.bindingId='missing-binding';$future.rules[0].source.itemIdentity=Get-AiwContentItemIdentity $future.rules[0].source}
        if($fault-ceq'BYTES'){$future.rules[0].source.documents[0].identity='1|'+('A'*64);$future.rules[0].source.itemIdentity=Get-AiwContentItemIdentity $future.rules[0].source}
        $effect.afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($future|ConvertTo-Json -Depth 100 -Compress)+"`n"))
        if($fault-ceq'PERMISSION'){$effect=$bad.installation.changes[0];$future=$utf8.GetString([Convert]::FromBase64String($effect.afterBase64))|ConvertFrom-Json -Depth 100;$future.sourceBindings[0].allowedPaths[0].locator='other.md';$effect.afterBase64=[Convert]::ToBase64String($utf8.GetBytes(($future|ConvertTo-Json -Depth 100 -Compress)+"`n"))}
        if($fault-ceq'REMOVAL'){$bad.installation.changes[2].afterExists=$false;$bad.installation.changes[2].afterBase64=''}
        $before=SourceLifeSignature;$caught='';try{$null=SourceLifePreview $bad}catch{$caught=$_.Exception.Message}
        $expected=switch($fault){DUPLICATE{'DUPLICATE_EFFECTIVE_RULE'} UNADOPTED{'DEPENDENCY_NOT_ADOPTED'} PERMISSION{'SOURCE_DENIED'} BYTES{'CONTENT_IDENTITY_DRIFT'} REMOVAL{'SOURCE_DENIED'}}
        Check ($caught.Contains($expected)-and(SourceLifeSignature)-ceq$before) ('public-source-lifecycle-reject-'+$fault+'-zero-live-write|'+$caught)
    }
    }
}
try{
    if($ContextCompatibilityOnly){
        Test-SourceLifeContextCompatibility -ContextOnly
        Write-Output ('PARTIAL|CONTEXT_COMPATIBILITY_ONLY|checks='+$passed+'|scope=actual-original-lifecycle-normative-case')
        return
    }
    $null=NewTestProject $temp
    $rules=@((Rule 'ONE' " A`r`nB "),(Rule 'TWO' "A`nB"))
    Reject {Test-AiwEffectiveRuleSet $temp @() $rules (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'nonoverlapping-selector-still-compared'
    Reject {Test-AiwEffectiveRuleSet $temp @((Correction C "A`rB")) @((Rule P "A`nB")) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'correction-policy-pair'
    Reject {Test-AiwEffectiveRuleSet $temp @((Correction C "A`rB"),(Correction D " A`nB ")) @() (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'correction-correction-pair'
    Reject {Test-AiwEffectiveRuleSet $temp @((Correction C 'same')) @() (Custom ' same ')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'correction-custom-pair'
    Reject {Test-AiwEffectiveRuleSet $temp @() @((Rule P 'same')) (Custom 'same')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'policy-custom-pair'
    $paused=Correction C 'same';$paused|Add-Member lifecycle ([pscustomobject]@{state='PAUSED'})
    Check ((Test-AiwEffectiveRuleSet $temp @($paused) @((Rule P 'same')) (Custom '')).members.Count-eq1) 'paused-member-retains-history-without-effect'
    $uninstalled=Clone $paused;$uninstalled.lifecycle.state='UNINSTALLED'
    Check ((Test-AiwEffectiveRuleSet $temp @($uninstalled) @((Rule P 'same')) (Custom '')).members.Count-eq1) 'uninstalled-member-retains-history-without-effect'
    Check ((Test-AiwEffectiveRuleSet $temp @() @((Rule P ' A  B '),(Rule Q 'A B')) (Custom '')).members.Count-eq2) 'internal-space-not-normalized'
    $sourced1=Rule S1 ''; $sourced1.PSObject.Properties.Remove('effectiveRule');$sourced1|Add-Member source ([pscustomobject]@{})
    $sourced2=Clone $sourced1;$sourced2.ruleId='S2';$sourced2.preparationRequirements=@('SECOND_OBLIGATION')
    $shared=[pscustomobject]@{Unavailable=$false;Drift=$false;RawBody='shared';FullText='shared';Identity='source-fact';Blocks=@([pscustomobject]@{Key='A|raw|full';SourcePath='A'},[pscustomobject]@{Key='B|raw|full';SourcePath='B'})}
    $facts=[pscustomobject]@{Rules=@{S1=$shared;S2=(Clone $shared)};Identity='standards-facts'}
    $result=Test-AiwEffectiveRuleSet $temp @() @($sourced1,$sourced2) (Custom '') -StandardsSnapshot $facts
    Check ($result.members.Count-eq2-and$result.members[0].memberIdentity-cne$result.members[1].memberIdentity) 'complete-ordered-physical-chain-retains-both-obligations'
    $facts.Rules.S2.Blocks=@($facts.Rules.S2.Blocks[1],$facts.Rules.S2.Blocks[0])
    Reject {Test-AiwEffectiveRuleSet $temp @() @($sourced1,$sourced2) (Custom '') -StandardsSnapshot $facts} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'reordered-chain-no-exemption'
    $facts.Rules.S2.Blocks=@($shared.Blocks[0])
    Reject {Test-AiwEffectiveRuleSet $temp @() @($sourced1,$sourced2) (Custom '') -StandardsSnapshot $facts} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'partial-shared-chain-no-exemption'
    $facts.Rules.S2.Unavailable=$true
    Reject {Test-AiwEffectiveRuleSet $temp @() @($sourced1,$sourced2) (Custom '') -StandardsSnapshot $facts} 'EFFECTIVE_SET_UNPROVEN' 'unknown-fact-separated-from-proven-duplicate'
    $configuration=NewTestProject $temp
    function AdoptRealRules([object[]]$Rules,[string]$Root=$temp){Store (Join-Path $Root '.ai-workspace/project.json') $configuration;Store (Join-Path $Root '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=$Rules})}
    WriteText (Join-Path $temp 'docs/A.md') 'Physical dependency.';WriteText (Join-Path $temp 'docs/B.md') 'Physical root.'
    $configuration.sourceBindings=@([pscustomobject]@{id='shared';provider='LOCAL_DIRECTORY';locator=[pscustomobject]@{root='.'};allowedPaths=@([pscustomobject]@{kind='FILE';locator='docs/A.md'},[pscustomobject]@{kind='FILE';locator='docs/B.md'});decisionLocator='fixture:explicit-read'})
    $documents=@();foreach($name in @('A','B')){$doc=[pscustomobject]@{sourceId=$name;bindingId='shared';revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=('docs/'+$name+'.md');identity=(Identity (Join-Path $temp ('docs/'+$name+'.md')));mode='FULL_FILE';sectionStart='NOT_APPLICABLE';sectionEnd='NOT_APPLICABLE';dependencies=@($(if($name-ceq'B'){'A'}))};$doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $configuration.sourceBindings;$documents+=$doc}
    $descriptor=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId='shared';itemId='SHARED_ONE';revision=(Get-AiwContentRevision ([pscustomobject]@{documents=$documents}) $configuration.sourceBindings);itemIdentity='';rootSourceId='B';documents=$documents};$descriptor.itemIdentity=Get-AiwContentItemIdentity $descriptor
    $one=Rule SHARED_ONE ''; $one.PSObject.Properties.Remove('effectiveRule');$one|Add-Member source $descriptor
    $two=Clone $one;$two.ruleId='SHARED_TWO';$two.source.itemId='SHARED_TWO';$two.source.itemIdentity=Get-AiwContentItemIdentity $two.source;$two.preparationRequirements=@('SECOND_PHYSICAL_OBLIGATION')
    AdoptRealRules @($one,$two)
    $real=Test-AiwEffectiveRuleSet $temp @() @($one,$two) (Custom '')
    Check ($real.members.Count-eq2-and$real.members[0].sharedKey-ceq$real.members[1].sharedKey-and$real.members[0].memberIdentity-cne$real.members[1].memberIdentity) 'actual-provider-complete-shared-chain-with-independent-obligations'
    $projected=Join-Path $temp 'projected'
    foreach($relative in @('.ai-workspace/project.json','.ai-workspace/process-policy.json','docs/A.md','docs/B.md')){
        $destination=Join-Path $projected $relative;$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $destination));[IO.File]::WriteAllBytes($destination,[IO.File]::ReadAllBytes((Join-Path $temp $relative)))
    }
    $projectedSet=Test-AiwEffectiveRuleSet $projected @() @($one,$two) (Custom '')
    Check ($projectedSet.identity-cne$real.identity-and$projectedSet.members[0].sharedKey-cne$real.members[0].sharedKey) 'bare-directory-copy-never-proves-original-physical-source'
    $changedObligation=Clone $two;$changedObligation.resultRequirements=@('NEW_ACTUAL_RESULT')
    AdoptRealRules @($one,$changedObligation) -Root $projected
    $changedSet=Test-AiwEffectiveRuleSet $projected @() @($one,$changedObligation) (Custom '')
    Write-Output ('OBSERVE|same-root-obligation-identity|'+([ordered]@{memberCount=$changedSet.members.Count;setIdentityChanged=($changedSet.identity-cne$projectedSet.identity);firstMemberIdentityChanged=($changedSet.members[0].memberIdentity-cne$projectedSet.members[0].memberIdentity);targetMemberIdentityChanged=($changedSet.members[1].memberIdentity-cne$projectedSet.members[1].memberIdentity);physicalSharedKeyUnchanged=($changedSet.members[1].sharedKey-ceq$projectedSet.members[1].sharedKey)}|ConvertTo-Json -Compress))
    Check ($changedSet.members.Count-eq2-and$changedSet.identity-cne$projectedSet.identity-and$changedSet.members[1].memberIdentity-cne$projectedSet.members[1].memberIdentity-and$changedSet.members[1].sharedKey-ceq$projectedSet.members[1].sharedKey) 'stable-projection-still-binds-every-rule-obligation'
    AdoptRealRules @($one,$two) -Root $projected
    WriteText (Join-Path $projected 'docs/A.md') 'Changed dependency bytes.'
    Reject {Test-AiwEffectiveRuleSet $projected @() @($one,$two) (Custom '')} 'CONTENT_IDENTITY_DRIFT|DOCUMENT' 'stable-projection-rejects-real-dependency-drift'
    $rawBody=[IO.File]::ReadAllText((Join-Path $temp 'docs/A.md'))+"`n`n"+[IO.File]::ReadAllText((Join-Path $temp 'docs/B.md'))
    $sameInline=Rule SAME_INLINE $rawBody;AdoptRealRules @($one,$sameInline)
    Reject {Test-AiwEffectiveRuleSet $temp @() @($one,$sameInline) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'real-provider-ordered-raw-body-versus-inline'
    Reject {Test-AiwEffectiveRuleSet $temp @((Correction SAME_CORRECTION $rawBody)) @($one) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'real-provider-ordered-raw-body-versus-correction'
    Reject {Test-AiwEffectiveRuleSet $temp @() @($one) (Custom $rawBody)} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'real-provider-ordered-raw-body-versus-normative-custom'
    $differentInline=Rule DIFFERENT_INTERNAL_NEWLINE $rawBody.Replace("`n`n","`n");AdoptRealRules @($one,$differentInline)
    Check ((Test-AiwEffectiveRuleSet $temp @() @($one,$differentInline) (Custom '')).members.Count-eq2) 'provider-does-not-collapse-internal-body-separators'

    function RealSourceRule([string]$Id,[string]$BindingId,[string]$Locator,[string]$Mode='FULL_FILE',[string]$Begin='NOT_APPLICABLE',[string]$End='NOT_APPLICABLE'){
        $binding=@($configuration.sourceBindings|Where-Object id -ceq $BindingId)[0]
        $root=if([IO.Path]::IsPathRooted($binding.locator.root)){$binding.locator.root}else{Join-Path $temp $binding.locator.root}
        $doc=[pscustomobject]@{sourceId=$Id;bindingId=$BindingId;revision=[pscustomobject]@{kind='CONTENT_IDENTITY';value=''};locator=$Locator;identity=(Identity (Join-Path $root $Locator));mode=$Mode;sectionStart=$Begin;sectionEnd=$End;dependencies=@()}
        $doc.revision=Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $configuration.sourceBindings
        $source=[pscustomobject]@{kind='BOUND_SOURCE_ITEM';bindingId=$BindingId;itemId=$Id;revision=(Get-AiwContentRevision ([pscustomobject]@{documents=@($doc)}) $configuration.sourceBindings);itemIdentity='';rootSourceId=$Id;documents=@($doc)};$source.itemIdentity=Get-AiwContentItemIdentity $source
        $rule=Rule $Id '';$rule.PSObject.Properties.Remove('effectiveRule');$rule|Add-Member source $source;return $rule
    }
    $configuration.sourceBindings[0].allowedPaths=@([pscustomobject]@{kind='DIRECTORY';locator='docs'})
    $absolute=Clone $configuration.sourceBindings[0];$absolute.id='absolute';$absolute.locator.root=$temp;$configuration.sourceBindings+=@($absolute)
    WriteText (Join-Path $temp 'docs/sections.md') "<ONE>`nSame selected body`n</ONE>`n<TWO>`nSame selected body`n</TWO>"
    $first=RealSourceRule FIRST shared 'docs/sections.md' MARKED_SECTION '<ONE>' '</ONE>'
    $second=RealSourceRule SECOND shared 'docs/sections.md' MARKED_SECTION '<TWO>' '</TWO>'
    AdoptRealRules @($first,$second)
    Reject {Test-AiwEffectiveRuleSet $temp @() @($first,$second) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'same-file-different-selection-is-not-shared-physical-block'
    $alias=RealSourceRule ALIAS absolute 'docs/sections.md' MARKED_SECTION '<ONE>' '</ONE>';AdoptRealRules @($first,$alias)
    $aliases=Test-AiwEffectiveRuleSet $temp @() @($first,$alias) (Custom '')
    Check ($aliases.members.Count-eq2-and$aliases.members[0].sharedKey-ceq$aliases.members[1].sharedKey) 'declared-relative-absolute-alias-same-exact-physical-selection'
    WriteText (Join-Path $temp 'docs/copy.md') "<ONE>`nSame selected body`n</ONE>"
    $copy=RealSourceRule COPY shared 'docs/copy.md' MARKED_SECTION '<ONE>' '</ONE>';AdoptRealRules @($first,$copy)
    Reject {Test-AiwEffectiveRuleSet $temp @() @($first,$copy) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'different-physical-files-same-selected-body-rejected'
    $markedBody="<!-- PROJECT-SOURCE:user:BEGIN -->`nUser literal marker`n<!-- PROJECT-SOURCE:user:END -->"
    WriteText (Join-Path $temp 'docs/markers.md') $markedBody;$marked=RealSourceRule MARKED shared 'docs/markers.md';AdoptRealRules @($marked)
    $identicalMarkers=Rule IDENTICAL_MARKERS $markedBody;AdoptRealRules @($marked,$identicalMarkers)
    Reject {Test-AiwEffectiveRuleSet $temp @() @($marked,$identicalMarkers) (Custom '')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'user-source-markers-remain-normative-body'
    $strippedMarkers=Rule STRIPPED_MARKERS 'User literal marker';AdoptRealRules @($marked,$strippedMarkers)
    Check ((Test-AiwEffectiveRuleSet $temp @() @($marked,$strippedMarkers) (Custom '')).members.Count-eq2) 'source-marker-text-never-stripped-with-regex'
    $client=Join-Path $temp 'relative-client';$clientConfig=NewTestProject $client
    WriteText (Join-Path $temp 'shared/rule.md') 'Relative external source.'
    $relativeBinding=Clone $configuration.sourceBindings[0];$relativeBinding.locator.root='../shared';$relativeBinding.allowedPaths=@([pscustomobject]@{kind='FILE';locator='rule.md'})
    $clientConfig.sourceBindings=@($relativeBinding)
    $relativeRule=Clone $marked;$relativeRule.source.bindingId=$relativeBinding.id
    $relativeRule.source.documents[0].bindingId=$relativeBinding.id;$relativeRule.source.documents[0].locator='rule.md';$relativeRule.source.documents[0].identity=Identity (Join-Path $temp 'shared/rule.md')
    $relativeRule.source.documents[0].revision=Get-AiwContentRevision ([pscustomobject]@{documents=$relativeRule.source.documents}) $clientConfig.sourceBindings
    $relativeRule.source.revision=Get-AiwContentRevision $relativeRule.source $clientConfig.sourceBindings;$relativeRule.source.itemIdentity=Get-AiwContentItemIdentity $relativeRule.source
    Store (Join-Path $client '.ai-workspace/project.json') $clientConfig
    Store (Join-Path $client '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@($relativeRule)})
    $relativeClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $client -Rules @($relativeRule)
    Check ($relativeClosure.Documents[0].locatorKind-ceq'PROJECT_RELATIVE'-and$relativeClosure.Documents[0].locator-ceq'../shared/rule.md'-and$relativeClosure.Documents[0].relativePath-ceq'NOT_APPLICABLE') 'relative-external-binding-keeps-declaration-without-stage-copy-path'

    # Provider-level prospective context test; public authorization and recovery
    # are separately exercised by the root adoption bridge fixture.
    Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionProjection.psm1') -Force
    $stage=Join-Path $temp 'new-source-stage';$stageConfig=NewTestProject $stage
    $stageConfig.sourceBindings=$configuration.sourceBindings
    $newBody='Explicit projected new normative bytes.'
    $overlay=New-AiwProjectProjection $temp @([pscustomobject]@{path='docs/markers.md';text=$newBody})
    $newRule=Clone $marked;$newRule.source.documents[0].identity=$overlay.objects[0].newIdentity
    $newRule.source.documents[0].revision=Get-AiwContentRevision ([pscustomobject]@{documents=$newRule.source.documents}) $configuration.sourceBindings
    $newRule.source.revision=Get-AiwContentRevision $newRule.source $configuration.sourceBindings;$newRule.source.itemIdentity=Get-AiwContentItemIdentity $newRule.source
    Store (Join-Path $stage '.ai-workspace/project.json') $stageConfig
    Store (Join-Path $stage '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@($newRule)})
    $stagePath=Join-Path $stage 'docs/markers.md';$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $stagePath));[IO.File]::WriteAllBytes($stagePath,[Convert]::FromBase64String($overlay.objects[0].newBase64))
    $liveBefore=Identity (Join-Path $temp 'docs/markers.md')
    $projectedContext=New-AiwContentContext -ProjectRoot $stage -SourceProjectRoot $temp -ExpectedProjectConfigIdentity (Identity (Join-Path $stage '.ai-workspace/project.json')) -ProjectedSourceObjects $overlay.objects
    $newClosure=Get-AiwProjectPolicySourceClosure -ProjectRoot $stage -Rules @($newRule) -ContentContext $projectedContext
    Check ($newClosure.Documents[0].sourcePath-ceq(Join-Path $temp 'docs/markers.md')-and$utf8.GetString($newClosure.Documents[0].bytes)-ceq$newBody-and(Identity (Join-Path $temp 'docs/markers.md'))-ceq$liveBefore) 'projected-source-reads-exact-new-bytes-at-original-physical-location'
    WriteText $stagePath 'Unauthorized stage drift.'
    Reject {Get-AiwProjectPolicySourceClosure -ProjectRoot $stage -Rules @($newRule) -ContentContext $projectedContext} 'CONTENT_IDENTITY_DRIFT' 'projected-source-never-falls-back-to-old-live-bytes'
    Test-SourceLifeContextCompatibility
    $lifeRoot=Join-Path $temp 'lifecycle';$null=NewTestProject $lifeRoot
    WriteText (Join-Path $lifeRoot '.ai-workspace/BOOTSTRAP.md') "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    $inline=Rule LIFE_POLICY 'Duplicate lifecycle body';$inline|Add-Member requirementReason 'Current future-set check';$inline|Add-Member decisionLocator 'fixture:explicit-decision'
    $inline.selectors=[pscustomobject]@{profiles=@();roles=@('REVIEWER');phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()}
    Store (Join-Path $lifeRoot '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';rules=@($inline)})
    $carrierPath=Join-Path $lifeRoot '.ai-workspace/corrections.json';$beforeCarrier=Identity $carrierPath
    $duplicateRecord=LifecycleRecord 'Duplicate lifecycle body'
    Reject {New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot INSTALL $duplicateRecord 'install-duplicate')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'actual-lifecycle-install-uses-complete-set-before-write'
    Check ((Identity $carrierPath)-ceq$beforeCarrier) 'lifecycle-conflict-has-zero-carrier-write'
    $unique=LifecycleRecord 'Unique lifecycle increment'
    Check ((New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot INSTALL $unique 'install-unique')).status-ceq'READY') 'lifecycle-unique-install-is-preview-only'
    Store $carrierPath ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';corrections=@($unique)})
    Reject {New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot REVISE $duplicateRecord 'revise')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'actual-lifecycle-revise-cannot-introduce-policy-duplicate'
    $paused=LifecycleRecord 'Duplicate lifecycle body';$paused|Add-Member lifecycle ([pscustomobject]@{state='PAUSED';installation='NOT_APPLICABLE';decisionLocator='fixture:unknown-installation'})
    Store $carrierPath ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';corrections=@($paused)})
    Reject {New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot RESUME 'NOT_APPLICABLE' 'resume')} 'CONFLICT_PROJECT_RULE_DUPLICATE_EFFECTIVE_RULE' 'actual-lifecycle-resume-restores-full-effective-set-check'
    $unknownActive=LifecycleRecord 'Duplicate lifecycle body'
    Store $carrierPath ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId='fixture';corrections=@($unknownActive)})
    $pause=New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot PAUSE 'NOT_APPLICABLE' 'pause')
    $pausedObject=@($pause.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/corrections.json'})[0]
    $futurePaused=$utf8.GetString([Convert]::FromBase64String($pausedObject.newBase64))|ConvertFrom-Json -Depth 100
    Check ($pause.status-ceq'READY'-and$futurePaused.corrections[0].lifecycle.state-ceq'PAUSED'-and$futurePaused.corrections[0].lifecycle.installation-ceq'NOT_APPLICABLE') 'unknown-installation-pause-exits-effect-with-history-and-no-invented-ownership'
    $uninstall=New-AiwCorrectionLifecycleProjection $lifeRoot (LifecyclePlan $lifeRoot UNINSTALL 'NOT_APPLICABLE' 'uninstall')
    $uninstalledObject=@($uninstall.projection.objects|Where-Object{$_.path-ceq'.ai-workspace/corrections.json'})[0]
    $futureUninstalled=$utf8.GetString([Convert]::FromBase64String($uninstalledObject.newBase64))|ConvertFrom-Json -Depth 100
    Check ($uninstall.status-ceq'READY'-and$futureUninstalled.corrections[0].lifecycle.state-ceq'UNINSTALLED'-and$futureUninstalled.corrections[0].lifecycle.installation-ceq'NOT_APPLICABLE') 'unknown-installation-uninstall-exits-effect-with-history-and-no-invented-ownership'
    Write-Output ('EFFECTIVE_RULE_SET_TESTS|PASS|'+$passed)
}finally{if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{RemoveTestRoot $temp}}
