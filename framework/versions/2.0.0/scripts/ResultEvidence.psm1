function Assert-EvArchiveClosedRecord([string]$Text){
    if($Text-cnotmatch'(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){throw 'ACCEPTANCE_CLOSE_NOT_CLOSED'}
    foreach($name in @('Closure outcome','Closure basis','Output disposition','Git disposition','Unresolved obligations','Writer','Reviewer','Authorization')){
        $m=[regex]::Matches($Text,('(?m)^- '+[regex]::Escape($name)+':[ \t]*(?<value>[^\r\n]+)$'))
        if($m.Count-ne1-or[string]::IsNullOrWhiteSpace($m[0].Groups['value'].Value)){throw ('ACCEPTANCE_CLOSE_FIELD|'+$name)}
        $value=$m[0].Groups['value'].Value.Trim()
        switch($name){
            'Closure outcome' {if($value-cnotin@('SUCCESS','CANCELLED','SUPERSEDED')){throw 'ACCEPTANCE_CLOSE_OUTCOME'};$outcome=$value}
            'Git disposition' {if($value-cnotmatch'^(READY|DEFERRED|EXCLUDED)(?:[; :].+)?$'){throw 'ACCEPTANCE_CLOSE_GIT_DISPOSITION'}}
            'Unresolved obligations' {if($value-cne'NONE'-and$value-cnotmatch'^TRANSFERRED: .+'){throw 'ACCEPTANCE_CLOSE_OBLIGATION_TRANSFER'}}
            {$_-in@('Writer','Reviewer','Authorization')} {if($value-cne'RELEASED'){throw 'ACCEPTANCE_CLOSE_LEASE_RELEASE'}}
        }
    }
    if($outcome-cin@('CANCELLED','SUPERSEDED')-and$Text-cnotmatch'(?m)^- Closure decision: .+#[0-9]+\|[A-F0-9]{64}[ \t]*$'){throw 'ACCEPTANCE_CLOSE_DECISION_REQUIRED'}
}
# Narrow actual postimage observation for the original current-task action.
# It neither rewrites the receipt nor substitutes arbitrary missing task files.
function Get-EvTaskArchiveObservation($Receipt,$Boundary){
    if($Boundary.mode-cne'FINALIZE_OUTPUT'-or$Receipt.actionKind-cne'CONTROL_WRITE'-or$Receipt.sourceLocators.taskRelativePath-cnotmatch'^\.ai-workspace/tasks/active/(?<name>[^/]+)\.md$'){return $null}
    $active=[string]$Receipt.sourceLocators.taskRelativePath;$archive='.ai-workspace/tasks/archive/'+$Matches.name+'.md'
    if(@($Receipt.exactPaths).Count-ne2-or$active-cnotin$Receipt.exactPaths-or$archive-cnotin$Receipt.exactPaths){return $null}
    $protected=if($null-ne$Receipt.authorityContext.PSObject.Properties['protectedScope']){@($Receipt.authorityContext.protectedScope)}else{@()}
    $ctx=New-AiwEvidenceContext $Receipt.sourceLocators.projectRoot '' $Receipt.sourceLocators.frameworkRoot @($Receipt.authorityContext.forbiddenScope) $protected
    $activeFull=Resolve-EvPath $ctx $active -Candidate
    if([IO.File]::Exists($activeFull)){return $null}
    if($Receipt.sourceLocators.authorizationPackagePath-ceq'NOT_REQUIRED'){throw 'ACCEPTANCE_ARCHIVE_ORIGINAL_PACKAGE_REQUIRED'}
    $package=Read-EvRef $ctx ([pscustomobject]@{path=$Receipt.sourceLocators.authorizationPackagePath;identity=$Receipt.authorityContext.authorizationIdentity}) -Json
    $ordinary=$package.schemaVersion-eq1-or($package.schemaVersion-eq2-and$package.repositoryId-ceq'CONTROL')
    if(-not$ordinary-or@($package.actions).Count-ne1-or$package.actions[0]-cne'CONTROL_WRITE'-or@($package.exactPaths).Count-ne2-or$active-cnotin$package.exactPaths-or$archive-cnotin$package.exactPaths-or@($package.objectIdentities).Count-ne2-or$Receipt.actor-cne$Receipt.taskActor){throw 'ACCEPTANCE_ARCHIVE_CURRENT_SCOPE'}
    foreach($name in @('transitionPlan','continuationPlan','repairReviewPlan','sourcePublicationBinding')){if($null-ne$package.PSObject.Properties[$name]){throw 'ACCEPTANCE_ARCHIVE_CURRENT_SCOPE'}}
    if($package.taskId-cne$Receipt.taskId-or$package.owner-cne$Receipt.taskOwner-or$package.grantee-cne$Receipt.actor-or$package.profile-cne$Receipt.profile-or$package.taskIdentity-cne$Receipt.sourceBindings.taskIdentity){throw 'ACCEPTANCE_ARCHIVE_ORIGINAL_BINDING'}
    $pre=@($package.objectIdentities|Where-Object path -CEQ $active)
    if($pre.Count-ne1-or$pre[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$pre[0].identity-cne$package.taskIdentity){throw 'ACCEPTANCE_ARCHIVE_DELETE_PREIMAGE'}
    $posts=@(Get-AiwFinalizedObjectPostimages $Boundary @($Receipt.exactPaths))
    if(@($Boundary.resultReceipts|Where-Object{$_-ceq('OBJECT_POSTIMAGE|'+$active+'|MISSING')}).Count-ne1){throw 'ACCEPTANCE_ARCHIVE_DELETE_POSTIMAGE'}
    $post=@($posts|Where-Object path -CEQ $archive)
    if($post.Count-ne1-or$post[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACCEPTANCE_ARCHIVE_TARGET_REQUIRED'}
    $archiveFull=Read-EvRef $ctx $post[0] -Candidate
    $transition=@(Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1') -PassThru)[0]
    $document=& $transition.ExportedCommands['Read-AiwControlTransitionTask'] $ctx.ProjectRoot $archiveFull
    if($document.Identity-cne$post[0].identity){throw 'ACCEPTANCE_ARCHIVE_TARGET_DRIFT'}
    $facts=& $transition {param($text) Get-TransitionTaskFacts $text} $document.Text
    $expected=@{TaskId=$Receipt.taskId;Owner=$Receipt.taskOwner;TaskActor=$Receipt.taskActor;Role=$Receipt.role;Phase=$Receipt.phase;Profile=$Receipt.profile}
    foreach($name in $expected.Keys){if($facts.$name-cne$expected[$name]){throw ('CONTROL_TASK_POSTIMAGE_BINDING_DRIFT|'+$name)}}
    $ctx|Add-Member TaskPath $archive
    Assert-AiwTaskClosure $ctx $document.Text $Receipt.taskId $Boundary -RequireExplicitClosure -ExcludedReviewActors @($package.issuer)
    return [pscustomobject]@{TaskRelativePath=$archive;Identity=$document.Identity;Text=$document.Text}
}

function Resolve-EvRecordTarget($Context,$Record,[switch]$FrozenCandidateEvidence){
    $hasTarget=$null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext
    if($Record.schemaVersion-eq1){
        if($null-ne$Record.PSObject.Properties['executionTargetRef']-or$null-ne$Record.PSObject.Properties['candidateTargetState']){throw 'EVIDENCE_SCHEMA1_TARGET_FIELDS'}
        if($hasTarget){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
        if($null-ne$Context.PSObject.Properties['TaskPath']-and$Context.TaskPath-and$Context.TaskPath-cne'NOT_APPLICABLE'){
            Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
            if((Read-AiwControlTransitionTask $Context.ProjectRoot $Context.TaskPath).Text-cmatch'(?m)^(?:- )?Execution target:'){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
        }
        return $Context
    }
    if($null-eq$Record.PSObject.Properties['executionTargetRef']-or$null-eq$Record.PSObject.Properties['candidateTargetState']){throw 'EVIDENCE_TARGET_BINDING_REQUIRED'}
    Assert-EvRef $Record.executionTargetRef
    Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
    if(-not$hasTarget){
        if($null-eq$Context.PSObject.Properties['TaskPath']-or-not$Context.TaskPath-or$Context.TaskPath-ceq'NOT_APPLICABLE'){throw 'EVIDENCE_EXECUTION_TARGET_TASK_REQUIRED'}
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText((Join-Path $Context.ProjectRoot '.ai-workspace/project.json')))
        $target=Resolve-AiwExecutionTargetContext $Context.ProjectRoot $cfg.id $Context.TaskPath $Record.executionTargetRef $Context.ForbiddenPaths $Context.CandidateProtectedPaths
        if($target.targetKind-cne'GIT_WORKTREE'){throw 'EVIDENCE_TARGET_BINDING_REQUIRED'}
        $nested=New-AiwEvidenceContext $Context.ProjectRoot $target.executionRoot '' $Context.ForbiddenPaths $Context.CandidateProtectedPaths
        $nested.Roots=@($Context.Roots+$nested.Roots|Select-Object -Unique);$nested.Reading=$Context.Reading
        $nested|Add-Member ExecutionContext $target;$nested|Add-Member TaskPath $Context.TaskPath
        $Context=$nested
    }
    if(-not(Test-EvSameRef $Record.executionTargetRef $Context.ExecutionContext.executionTargetRef $Context)){throw 'EVIDENCE_EXECUTION_TARGET_DRIFT'}
    $null=Assert-AiwExecutionTargetState $Context.ExecutionContext $Record.candidateTargetState
    return $Context
}
function Assert-AiwTaskClosure($Context,[string]$Text,[string]$TaskId,$Boundary,[switch]$RequireExplicitClosure,[string[]]$ExcludedReviewActors=@()) {
    if($RequireExplicitClosure){
        Assert-EvArchiveClosedRecord $Text
        $outcome=[regex]::Matches($Text,'(?m)^- Closure outcome:[ \t]*(?<value>[^\r\n]+)$')
        if($outcome.Count-ne1-or$outcome[0].Groups['value'].Value-cnotin@('SUCCESS','CANCELLED','SUPERSEDED')){throw 'ACCEPTANCE_CLOSURE_OUTCOME'}
        if($outcome[0].Groups['value'].Value-cin@('CANCELLED','SUPERSEDED')){
            if($Text-cnotmatch'(?m)^- Unfinished work: .+'){throw 'ACCEPTANCE_CLOSE_UNFINISHED_WORK_REQUIRED'}
            $decision=[regex]::Matches($Text,'(?m)^- Closure decision: (?<path>.+)#(?<identity>\d+\|[A-F0-9]{64})[ \t]*$')
            if($decision.Count-ne1){throw 'ACCEPTANCE_CLOSE_DECISION_REQUIRED'}
            $null=Read-EvRef $Context ([pscustomobject]@{path=$decision[0].Groups['path'].Value;identity=$decision[0].Groups['identity'].Value})
            return
        }
    }
        $closedPlan=Get-AiwAcceptancePlan $Text
        $profile=[regex]::Match($Text,'(?m)^- Range summary:\s*profile=(MICRO|STANDARD|CRITICAL);').Groups[1].Value
        $management=[pscustomobject]@{schemaVersion=1;profile=$profile;actions=@('CONTROL_WRITE');exactPaths=@();objectIdentities=@()}
        $null=Get-AiwPackageQuality $Context $management $closedPlan -Management -RequirePlan
        if($null-ne$closedPlan-and$closedPlan.schemaVersion-eq2){
            $repo=$closedPlan.qualityBinding.subject.repositoryId
            if($repo-cne'REPO_LOCAL'){
                $candidatePackage=[pscustomobject]@{schemaVersion=2;repositoryId=$repo}
                $Context=New-AiwPackageEvidenceContext $Context.ProjectRoot $candidatePackage '' $Context.ForbiddenPaths -ProtectedPaths $Context.CandidateProtectedPaths
            }
        }
        if($null-eq$closedPlan){if($RequireExplicitClosure){throw 'ACCEPTANCE_CLOSE_PLAN_REQUIRED'};return}
        $outcomes=[regex]::Matches($Text,'(?m)^- Closure outcome:[ \t]*(?<value>[^\r\n]+)$')
        if($outcomes.Count-gt1){throw 'ACCEPTANCE_CLOSURE_OUTCOME'}
        if($outcomes.Count-eq1){
            if($outcomes[0].Groups['value'].Value-cin@('CANCELLED','SUPERSEDED')){return}
            if($outcomes[0].Groups['value'].Value-cne'SUCCESS'){throw 'ACCEPTANCE_CLOSURE_OUTCOME'}
        }
        # No explicit outcome has the same success obligation as legacy cards;
        # removing the field cannot bypass a plan's required evidence.
        $ids=[regex]::Matches($Text,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
        if($ids.Count-ne1){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        $closedTaskId=$ids[0].Groups['id'].Value
        $userRefs=@()
        foreach($stage in $closedPlan.stages){
            if($stage.kind-ceq'USER_DECISION'){foreach($ref in $stage.candidateRef){if($ref.identity-ceq$Boundary.publicDecisionIdentity){$userRefs+=$ref}}}
            if($stage.kind-ceq'RESULT_ACCEPT'){
                $consumption=Get-EvConsumption $stage evidenceConsumption
                foreach($ref in $stage.evidenceRefs){
                    $record=Read-AiwResultEvidence $Context $ref $closedTaskId $stage.candidateRef $stage.requiredBy -RequireSuccess -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize
                    $original=Read-EvRef $Context $record.authorizationRef -Json
                    if($null-ne$original.PSObject.Properties['acceptanceBinding']){$userRefs+=@($original.acceptanceBinding.reservedUserDecisionRefs)}
                }
            }
        }
        $unique=@($userRefs|Group-Object path,identity|ForEach-Object{$_.Group[0]})
        $criticalClosure=if($closedPlan.schemaVersion-eq2){'RESULT_REVIEW'-cin$closedPlan.qualityBinding.effectiveStages}else{$Text-cmatch '(?m)^- (?:Profile: CRITICAL;|Range summary: profile=CRITICAL;)'}
        $closedOwner=[regex]::Match($Text,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$').Groups['owner'].Value
        if($closedTaskId-cne$TaskId){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        $excluded=@($closedOwner)+@($ExcludedReviewActors)
        Assert-AiwAcceptanceStages $Context $closedPlan $closedTaskId '' $unique -RequireIndependentReview:$criticalClosure -ExcludedReviewActors $excluded
}
Export-ModuleMember -Function Assert-AiwTaskClosure
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# File-backed evidence is instruction-bound. These checks prove bindings and
# structure, never model attention, the truth of prose or the origin of a user.
function Assert-EvFields($Value,[string[]]$Required,[string[]]$Optional=@()) {
    if($Value-isnot[pscustomobject]){throw 'EVIDENCE_OBJECT_REQUIRED'}
    $names=@($Value.PSObject.Properties.Name)
    if(@($Required|Where-Object{$_-cnotin$names}).Count-or@($names|Where-Object{$_-cnotin($Required+$Optional)}).Count){throw 'EVIDENCE_FIELD_SET'}
}
function Assert-EvString($Value) {
    if($Value-isnot[string]-or[string]::IsNullOrWhiteSpace($Value)-or$Value-cne$Value.Trim()){throw 'EVIDENCE_STRING'}
}
function Assert-EvArray($Value) { if($Value-isnot[Array]){throw 'EVIDENCE_ARRAY'} }
function Assert-EvInteger($Value) { if($Value-isnot[int]-and$Value-isnot[long]){throw 'EVIDENCE_INTEGER'} }
function Get-EvConsumption($Container,[string]$Property,[string]$DefaultPurpose='CURRENT_CANDIDATE',[object[]]$DefaultFinalize=@()) {
    # A declaration belongs to the current consumer, never to the old record.
    $value=if($null-ne$Container-and$null-ne$Container.PSObject.Properties[$Property]){$Container.$Property}else{[pscustomobject]@{purpose=$DefaultPurpose;originalFinalize=$DefaultFinalize}}
    Assert-EvFields $value @('purpose','originalFinalize')
    if($value.purpose-cnotin@('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')){throw 'EVIDENCE_CONSUMPTION_PURPOSE'}
    Assert-EvArray $value.originalFinalize
    if($value.purpose-ceq'CURRENT_CANDIDATE'-and$value.originalFinalize.Count){throw 'EVIDENCE_CURRENT_HISTORY_REFS'}
    if($value.purpose-ceq'HISTORICAL_SUCCESS'-and-not$value.originalFinalize.Count){throw 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND'}
    foreach($pair in $value.originalFinalize){
        Assert-EvFields $pair @('inputRef','resultRef');Assert-EvRef $pair.inputRef;Assert-EvRef $pair.resultRef
    }
    return $value
}
function Assert-EvMembers($Element) {
    if($Element.ValueKind-eq[Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($p in $Element.EnumerateObject()){if(-not$seen.Add($p.Name)){throw 'EVIDENCE_DUPLICATE_MEMBER'};Assert-EvMembers $p.Value}
    }elseif($Element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Assert-EvMembers $v}}
}
function ConvertFrom-EvJson([string]$Text) {
    $doc=[Text.Json.JsonDocument]::Parse($Text)
    try{Assert-EvMembers $doc.RootElement}finally{$doc.Dispose()}
    return ConvertFrom-Json -InputObject $Text -Depth 70
}
function Assert-EvRef($Ref,[switch]$Section,[switch]$Typed,[switch]$Candidate) {
    $fields=@('path','identity');if($Typed){$fields+='kind'}
    Assert-EvFields $Ref $fields $(if($Section){@('section')}else{@()})
    Assert-EvString $Ref.path;Assert-EvString $Ref.identity
    if($Ref.identity-cnotmatch '^\d+\|[A-F0-9]{64}$'-and-not($Candidate-and$Ref.identity-ceq'MISSING')){throw 'EVIDENCE_IDENTITY_FORMAT'}
    if($Typed-and$Ref.kind-cnotin@('SELF_CHECK','REVIEW_VERDICT','RESULT_ACCEPTANCE')){throw 'EVIDENCE_KIND'}
    if($null-ne$Ref.PSObject.Properties['section']){Assert-EvString $Ref.section;if($Ref.section-cnotmatch '^[A-Za-z0-9][A-Za-z0-9:._-]*$'){throw 'EVIDENCE_SECTION'}}
}
function Assert-EvRefs($Refs,[switch]$Typed,[switch]$Nonempty,[switch]$Candidate) {
    Assert-EvArray $Refs
    if($Nonempty-and$Refs.Count-eq0){throw 'EVIDENCE_REFS_EMPTY'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($ref in $Refs){Assert-EvRef $ref -Typed:$Typed -Candidate:$Candidate;if(-not$seen.Add([string]$ref.path)){throw 'EVIDENCE_DUPLICATE_REF'}}
}
function Get-AiwPackageCandidateReferences($Package) {
    # NEW is an authorization preimage; MISSING is the observed candidate state.
    foreach($ref in $Package.objectIdentities){
        Assert-EvFields $ref @('path','identity');Assert-EvString $ref.path
        if($ref.identity-cne'NEW'-and$ref.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'EVIDENCE_IDENTITY_FORMAT'}
        [pscustomobject]@{path=$ref.path;identity=$(if($ref.identity-ceq'NEW'){'MISSING'}else{$ref.identity})}
    }
}
function Assert-EvScopeObjects($Objects) {
    Assert-EvArray $Objects
    if($Objects.Count-eq0){throw 'REVIEW_SCOPE_EMPTY'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $Objects){
        Assert-EvFields $row @('path','identity');Assert-EvString $row.path;Assert-EvString $row.identity
        if($row.path.Contains('\')-or$row.path.Contains(':')-or[IO.Path]::IsPathRooted($row.path)-or
           @($row.path.Split('/')|Where-Object{$_-in@('','.','..')}).Count-or-not$seen.Add($row.path)){throw 'REVIEW_SCOPE_PATH'}
        if($row.identity-cne'NEW'-and$row.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'REVIEW_SCOPE_IDENTITY'}
    }
}
function Get-EvReviewParent($Context,$Package) {
    if($null-ne$Package.PSObject.Properties['repairReviewBinding']-and$Package.repairReviewBinding.phase-ceq'REPAIR'){
        if($null-eq$Context){throw 'REVIEW_SCOPE_PARENT_CONTEXT_REQUIRED'}
        $binding=$Package.repairReviewBinding
        $parent=Read-EvRef $Context ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity}) -Json
        if($null-ne$parent.PSObject.Properties['repairReviewBinding']){throw 'REVIEW_SCOPE_NESTED_PARENT'}
        return $parent
    }
    return $Package
}
function Get-AiwPlannedReviewScope($Package,$Context=$null) {
    $parent=Get-EvReviewParent $Context $Package
    $rows=@($parent.objectIdentities)
    if($null-ne$parent.PSObject.Properties['repairReviewPlan']-and$null-ne$parent.repairReviewPlan.PSObject.Properties['reviewScope']){
        $rows=$parent.repairReviewPlan.reviewScope
        if('REVIEW_ROUTE'-cnotin$parent.actions-or$null-eq$parent.PSObject.Properties['continuationPlan']-or
           $parent.continuationPlan[-1]-cne'REVIEW_ROUTE'){throw 'REVIEW_SCOPE_ROUTE_NOT_GRANTED'}
        Assert-EvScopeObjects $rows
        $frozen=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($row in $rows){$frozen.Add($row.path,$row.identity)}
        foreach($row in $parent.objectIdentities){
            if(-not$frozen.ContainsKey($row.path)-or$frozen[$row.path]-cne$row.identity){throw 'REVIEW_SCOPE_WRITE_PREIMAGE_DRIFT'}
        }
    }
    Assert-EvScopeObjects $rows
    foreach($row in $rows){[pscustomobject]@{path=$row.path;identity=$row.identity}}
}
function Get-AiwActionScopeObjects($Package,[string]$Action,$Context=$null) {
    if($Action-ceq'REVIEW_ROUTE'){Get-AiwPlannedReviewScope $Package $Context}
    else{foreach($row in $Package.objectIdentities){[pscustomobject]@{path=$row.path;identity=$row.identity}}}
}
function Get-EvReviewCandidateMembers($ExactPaths,$ReviewScope,$ProductionPostimages) {
    # Pure member composition; callers validate the provenance and required IO.
    Assert-EvArray $ExactPaths
    Assert-EvScopeObjects $ReviewScope
    Assert-EvScopeObjects $ProductionPostimages
    $modified=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $ProductionPostimages){$modified.Add($row.path,$row.identity)}
    if($modified.Count-ne$ExactPaths.Count-or@($ExactPaths|Where-Object{-not$modified.ContainsKey($_)-or$_-cnotin$ReviewScope.path}).Count){throw 'REVIEW_SCOPE_PRODUCTION_SET'}
    foreach($row in $ReviewScope){
        $identity=if($modified.ContainsKey($row.path)){$modified[$row.path]}else{$row.identity}
        [pscustomobject]@{path=$row.path;identity=$identity}
    }
}
function Get-AiwComposedReviewCandidate($Context,$Package,$ProductionPostimages) {
    # Public current-candidate consumers always verify every live A member.
    $rows=@(Get-EvReviewCandidateMembers @($Package.exactPaths) @(Get-AiwPlannedReviewScope $Package $Context) $ProductionPostimages)
    foreach($row in $rows){
        $candidate=[pscustomobject]@{path=$row.path;identity=$(if($row.identity-ceq'NEW'){'MISSING'}else{$row.identity})}
        $null=Read-EvRef $Context $candidate -Candidate
        $row
    }
}
function Get-AiwFinalizedObjectPostimages($FinalizeInput,[string[]]$ExactPaths) {
    $rows=@()
    foreach($value in $FinalizeInput.resultReceipts){
        if($value-cnotlike'OBJECT_POSTIMAGE|*'){continue}
        if($value-cnotmatch'^OBJECT_POSTIMAGE\|(?<path>[^|]+)\|(?<identity>MISSING|NEW|\d+\|[A-F0-9]{64})$'){throw 'REVIEW_SCOPE_POSTIMAGE_FORMAT'}
        $rows+=[pscustomobject]@{path=$Matches.path;identity=$(if($Matches.identity-ceq'MISSING'){'NEW'}else{$Matches.identity})}
    }
    Assert-EvScopeObjects $rows
    if($rows.Count-ne$ExactPaths.Count-or(@($rows.path|Sort-Object)-join'|')-cne(@($ExactPaths|Sort-Object)-join'|')){throw 'REVIEW_SCOPE_PRODUCTION_SET'}
    return $rows
}
function New-AiwEvidenceContext([string]$ProjectRoot,[string]$RepositoryRoot='', [string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()) {
    $project=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    if(-not$RepositoryRoot){$RepositoryRoot=$project}
    $repo=[IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    $roots=@($project,$repo);if($FrameworkRoot){$roots+=[IO.Path]::GetFullPath($FrameworkRoot).TrimEnd('\','/')}
    $excluded=@($ForbiddenPaths)
    $configPath=Join-Path $project '.ai-workspace/project.json'
    if(Test-Path -LiteralPath $configPath -PathType Leaf){
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText($configPath))
        if($null-ne$cfg.PSObject.Properties['routineExcludedPaths']){$excluded+=@($cfg.routineExcludedPaths)}
        if($null-ne$cfg.PSObject.Properties['frameworkTarget']-and$null-ne$cfg.frameworkTarget.PSObject.Properties['routineExcludedPaths']){$excluded+=@($cfg.frameworkTarget.routineExcludedPaths)}
    }
    return [pscustomobject]@{ProjectRoot=$project;RepositoryRoot=$repo;Roots=@($roots|Select-Object -Unique);ForbiddenPaths=@($excluded|Select-Object -Unique);CandidateProtectedPaths=@($ProtectedPaths);Reading=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
}
function Resolve-EvPath($Context,[string]$Path,[switch]$Candidate,[switch]$AllowMissing,[switch]$AllowDirectory) {
    Assert-EvString $Path
    if([IO.Path]::IsPathRooted($Path)-and-not[IO.Path]::IsPathFullyQualified($Path)){throw 'EVIDENCE_PATH_INVALID'}
    $value=$Path.Replace('\','/')
    if($value.Contains('//')-or$value-cne$value.Normalize([Text.NormalizationForm]::FormC)-or$value-match '[\x00-\x1f*?]'){throw 'EVIDENCE_PATH_INVALID'}
    foreach($part in $value.Split('/')){if($part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'EVIDENCE_PATH_INVALID'}}
    if($Candidate-and$null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext){
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        if([IO.Path]::IsPathRooted($Path)){
            $relative=[IO.Path]::GetRelativePath($Context.RepositoryRoot,[IO.Path]::GetFullPath($Path)).Replace('\','/')
        }else{$relative=$Path}
        return Resolve-AiwExecutionTargetCandidatePath $Context.ExecutionContext $relative $Context.ForbiddenPaths $Context.CandidateProtectedPaths
    }
    $base=if($Candidate){$Context.RepositoryRoot}else{$Context.ProjectRoot}
    $full=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path $base $Path}))
    if($null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext-and$full.StartsWith($Context.RepositoryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        $relative=[IO.Path]::GetRelativePath($Context.RepositoryRoot,$full).Replace('\','/')
        $full=Resolve-AiwExecutionTargetCandidatePath $Context.ExecutionContext $relative $Context.ForbiddenPaths $Context.CandidateProtectedPaths
    }
    $root=@($Context.Roots|Where-Object{$full.StartsWith($_+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}|Sort-Object Length -Descending|Select-Object -First 1)
    if($root.Count-ne1){throw 'EVIDENCE_PATH_OUTSIDE_BOUND_ROOTS'}
    # Protected candidates and forbidden references are rejected before metadata.
    $denied=@($Context.ForbiddenPaths);if($Candidate){$denied+=@($Context.CandidateProtectedPaths)}
    foreach($r in $Context.Roots){
        if(-not$full.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){continue}
        $rel=[IO.Path]::GetRelativePath($r,$full).Replace('\','/')
        foreach($forbidden in $denied){$f=([string]$forbidden).Replace('\','/').TrimEnd('/');if($rel.Equals($f,[StringComparison]::OrdinalIgnoreCase)-or$rel.StartsWith($f+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_PATH_FORBIDDEN'}}
    }
    foreach($forbidden in $denied){
        if(-not[IO.Path]::IsPathFullyQualified($forbidden)){continue}
        $ban=[IO.Path]::GetFullPath($forbidden).TrimEnd('\','/')
        if($full.Equals($ban,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($ban+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_PATH_FORBIDDEN'}
    }
    $cursor=[IO.Path]::GetPathRoot($full)
    $parts=$full.Substring($cursor.Length).Split([IO.Path]::DirectorySeparatorChar)
    foreach($part in $parts){if($part.Contains(':')){throw 'EVIDENCE_PATH_INVALID'}}
    foreach($part in $parts){
        $cursor=Join-Path $cursor $part
        $errors=@();$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue -ErrorVariable errors
        if($null-eq$item){
            if(@($errors|Where-Object{$_.CategoryInfo.Category-cne'ObjectNotFound'}).Count){throw 'EVIDENCE_PATH_UNAVAILABLE'}
            if($Candidate-or$AllowMissing){return $full}
            throw 'EVIDENCE_OBJECT_MISSING'
        }
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EVIDENCE_PATH_REPARSE'}
        if($cursor-cne$full-and-not$item.PSIsContainer){throw 'EVIDENCE_PATH_NOT_DIRECTORY'}
    }
    if($item.PSIsContainer-and-not$AllowDirectory){throw 'EVIDENCE_NOT_FILE'}
    return $full
}
function Get-EvCandidateIdentity([string]$ResolvedPath) {
    if(-not(Test-Path -LiteralPath $ResolvedPath)){return 'MISSING'}
    $bytes=[IO.File]::ReadAllBytes($ResolvedPath)
    return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
function Read-EvRef($Context,$Ref,[switch]$Candidate,[switch]$Section,[switch]$Json) {
    Assert-EvRef $Ref -Section:$Section -Candidate:$Candidate
    $full=Resolve-EvPath $Context $Ref.path -Candidate:$Candidate
    if($Candidate){
        if((Get-EvCandidateIdentity $full)-cne$Ref.identity){throw ('EVIDENCE_IDENTITY_DRIFT|'+$Ref.path)}
        if(-not$Json-and-not$Section){return $full}
        if($Ref.identity-ceq'MISSING'){throw 'EVIDENCE_OBJECT_MISSING'}
    }
    $bytes=[IO.File]::ReadAllBytes($full)
    $identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if($identity-cne$Ref.identity){throw ('EVIDENCE_IDENTITY_DRIFT|'+$Ref.path)}
    if(-not$Json-and-not$Section){return $full}
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'EVIDENCE_UTF8_BOM'}
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    if($text.Contains([char]0)){throw 'EVIDENCE_NUL'}
    if($Section-and$null-ne$Ref.PSObject.Properties['section']){
        $tag=[regex]::Escape($Ref.section)
        if([regex]::Matches($text,'<!-- '+$tag+':BEGIN -->').Count-ne1-or[regex]::Matches($text,'<!-- '+$tag+':END -->').Count-ne1-or-not[regex]::IsMatch($text,'(?s)<!-- '+$tag+':BEGIN -->.+?<!-- '+$tag+':END -->')){throw 'EVIDENCE_SECTION_UNBOUND'}
    }
    if($Json){return ConvertFrom-EvJson $text}
    return $full
}
function Test-EvSameRef($A,$B,$Context=$null,[switch]$Candidate) {
    # Equality is root-bound. Resolve both operands before comparing identities,
    # so a mismatching hash cannot hide an unsafe locator.
    if($null-ne$Context){
        $aPath=Resolve-EvPath $Context $A.path -Candidate:$Candidate -AllowMissing
        $bPath=Resolve-EvPath $Context $B.path -Candidate:$Candidate -AllowMissing
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        if(-not$aPath.Equals($bPath,$comparison)){return $false}
    }elseif($A.path-cne$B.path){return $false}
    if($A.identity-cne$B.identity){return $false}
    $as=if($null-ne$A.PSObject.Properties['section']){[string]$A.section}else{''}
    $bs=if($null-ne$B.PSObject.Properties['section']){[string]$B.section}else{''}
    return $as-ceq$bs
}
function Assert-EvSameCandidates($Actual,$Expected,$Context=$null) {
    Assert-EvRefs $Actual -Nonempty -Candidate;Assert-EvRefs $Expected -Nonempty -Candidate
    if($Actual.Count-ne$Expected.Count){throw 'EVIDENCE_CANDIDATE_SET'}
    # Normalize every member safely before comparing identities. These indexes
    # exist only for this comparison; matching never repeats physical path IO.
    $comparer=if($null-ne$Context-and$IsWindows){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
    $indexes=[Collections.Generic.List[object]]::new()
    foreach($set in @(@{refs=$Actual},@{refs=$Expected})){
        $index=[Collections.Generic.Dictionary[string,object]]::new($comparer)
        foreach($ref in $set.refs){
            $path=if($null-ne$Context){Resolve-EvPath $Context $ref.path -Candidate}else{$ref.path}
            if(-not$index.TryAdd($path,$ref)){throw 'EVIDENCE_DUPLICATE_REF'}
        }
        $indexes.Add($index)
    }
    foreach($entry in $indexes[1].GetEnumerator()){
        $actualRef=$null;$expectedRef=$entry.Value
        if(-not$indexes[0].TryGetValue($entry.Key,[ref]$actualRef)-or$actualRef.identity-cne$expectedRef.identity){throw 'EVIDENCE_CANDIDATE_DRIFT'}
        $actualSection=if($null-ne$actualRef.PSObject.Properties['section']){[string]$actualRef.section}else{''}
        $expectedSection=if($null-ne$expectedRef.PSObject.Properties['section']){[string]$expectedRef.section}else{''}
        if($actualSection-cne$expectedSection){throw 'EVIDENCE_CANDIDATE_DRIFT'}
    }
}
function Test-EvSameCandidates($Actual,$Expected,$Context=$null) {
    try{Assert-EvSameCandidates $Actual $Expected $Context;return $true}catch{return $false}
}
function Read-EvObservationLocator($Context,$Reference,$Candidates,[switch]$FrozenCandidateEvidence,[switch]$HistoricalSuccess) {
    if($FrozenCandidateEvidence-or$HistoricalSuccess){
        $full=Resolve-EvPath $Context $Reference.path -AllowMissing
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        foreach($candidate in $Candidates){
            $candidatePath=Resolve-EvPath $Context $candidate.path -Candidate
            if($candidate.identity-ceq$Reference.identity-and$candidatePath.Equals($full,$comparison)){return}
        }
        if($HistoricalSuccess-and$null-ne$Context.PSObject.Properties['HistoricalInputObservations']){
            foreach($originalInput in $Context.HistoricalInputObservations){
                # Unreferenced input carriers are not reads. Validate only the
                # exact carrier named by this already guarded locator.
                if(([IO.Path]::GetFullPath($originalInput.path)).Equals($full,$comparison)-and(Test-EvSameRef $originalInput $Reference $Context)){return}
            }
        }
    }
    $null=Read-EvRef $Context $Reference
}
function Get-AiwPlannedReviewFlatVerdict($Context,$Package,$Record){
    if($null-eq$Package.PSObject.Properties['repairReviewBinding']){return $null}
    $binding=$Package.repairReviewBinding
    if($binding.phase-cnotin@('INITIAL_REVIEW','REREVIEW')){throw 'EVIDENCE_PLANNED_REVIEW_PHASE'}
    $parent=Read-EvRef $Context ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity}) -Json
    if($null-eq$parent.PSObject.Properties['repairReviewPlan']){throw 'REPAIR_REVIEW_PLAN_REQUIRED'}
    $plan=$parent.repairReviewPlan;$found=@()
    foreach($ref in $Record.evidenceLocators){
        if([IO.Path]::GetExtension($ref.path)-ine'.json'){continue}
        $value=Read-EvRef $Context $ref -Json
        if($null-eq$value.PSObject.Properties['verdict']){continue}
        Assert-EvFields $value @('taskId','owner','reviewer','writer','cycle','verdict','exactPaths','objectIdentities','findingPaths','scopeChanged','decisionChanged')
        $found+=[pscustomobject]@{reference=$ref;value=$value}
    }
    if($found.Count-ne1){throw 'EVIDENCE_PLANNED_FLAT_VERDICT_REQUIRED'}
    $flat=$found[0].value
    Assert-EvInteger $flat.cycle;Assert-EvArray $flat.exactPaths;Assert-EvArray $flat.findingPaths
    if($flat.taskId-cne$Package.taskId-or$flat.owner-cne$Package.owner-or$flat.reviewer-cne$Record.actor-or$flat.reviewer-cne$Package.grantee-or$flat.writer-cne$plan.writer-or$Package.candidateWriter-cne$plan.writer-or$flat.cycle-ne$binding.cycle-or$flat.verdict-cne$Record.outcome-or$flat.scopeChanged-isnot[bool]-or$flat.decisionChanged-isnot[bool]){throw 'EVIDENCE_FLAT_TYPED_VERDICT_DRIFT'}
    if((@($flat.exactPaths|Sort-Object)-join'|')-cne(@($Package.exactPaths|Sort-Object)-join'|')){throw 'EVIDENCE_FLAT_VERDICT_SCOPE'}
    Assert-EvSameCandidates @(Get-AiwPackageCandidateReferences $flat) $Record.candidateObjects $Context
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $flat.findingPaths){if($path-isnot[string]-or[string]::IsNullOrWhiteSpace($path)-or-not$seen.Add($path)-or(-not$flat.scopeChanged-and$path-cnotin$Package.exactPaths)){throw 'EVIDENCE_FLAT_FINDING_PATHS'}}
    if(($flat.verdict-ceq'CHANGES_REQUESTED'-and$flat.findingPaths.Count-eq0)-or($flat.verdict-ceq'APPROVED'-and($flat.findingPaths.Count-or$flat.scopeChanged-or$flat.decisionChanged))){throw 'EVIDENCE_FLAT_VERDICT_OUTCOME'}
    if((@($Package.materialContributors|Sort-Object)-join'|')-cne(@($plan.materialContributors|Sort-Object)-join'|')){throw 'EVIDENCE_PLANNED_CONTRIBUTOR_DRIFT'}
    return $found[0]
}
function Get-AiwReviewExcludedActors([string]$Owner,[string]$Issuer,[string]$Writer,$Contributors){
    if($Contributors-isnot[array]){throw 'MATERIAL_CONTRIBUTOR_SET'}
    $members=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $excluded=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($actor in @($Owner,$Issuer,$Writer)){if([string]::IsNullOrWhiteSpace($actor)-or$actor-cne$actor.Trim()){throw 'MATERIAL_CONTRIBUTOR_SET'};$null=$excluded.Add($actor)}
    foreach($actor in $Contributors){if($actor-isnot[string]-or[string]::IsNullOrWhiteSpace($actor)-or$actor-cne$actor.Trim()-or$actor-ceq$Writer-or-not$members.Add($actor)){throw 'MATERIAL_CONTRIBUTOR_SET'};$null=$excluded.Add($actor)}
    return @($excluded)
}
Export-ModuleMember -Function Get-AiwReviewExcludedActors
function Assert-AiwFinalizedReviewFinding($Context,$Parent,$Binding,[switch]$FrozenCandidates){
    foreach($name in @('verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){if($null-eq$Binding.PSObject.Properties[$name]-or$Binding.$name-isnot[string]-or$Binding.$name-ceq'NOT_APPLICABLE'){throw 'REPAIR_REVIEW_FINALIZED_TYPED_VERDICT_REQUIRED'}}
    $input=Read-EvRef $Context ([pscustomobject]@{path=$Binding.verdictFinalizeInputPath;identity=$Binding.verdictFinalizeInputIdentity}) -Json
    $result=Read-EvRef $Context ([pscustomobject]@{path=$Binding.verdictFinalizeResultPath;identity=$Binding.verdictFinalizeResultIdentity}) -Json
    if($input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count-or$null-ne$result.PSObject.Properties['sourcePostimageTransition']){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_REQUIRED'}
    $source=Read-EvRef $Context ([pscustomobject]@{path=$input.discoverReceiptPath;identity=$input.expectedDiscoverReceiptIdentity}) -Json
    if($source.schemaVersion-notin@(3,4)-or$source.status-cne'PASS'-or$source.intentEnvelope.requestedActionKind-cne'REVIEW_EXECUTE'-or$source.intentEnvelope.requestedResultKind-cne'REVIEW_VERDICT'){throw 'REPAIR_REVIEW_VERDICT_SOURCE'}
    $authority=$source.binding
    $review=Read-EvRef $Context ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$authority.authorizationIdentity}) -Json
    if($authority.actor-cne$review.grantee-or$authority.taskId-cne$review.taskId-or$authority.taskOwner-cne$review.owner-or$authority.taskIdentity-cne$review.taskIdentity-or$authority.userDecision-cne$review.userConfirmation-or@($review.actions).Count-ne1-or$review.actions[0]-cne'REVIEW_EXECUTE'-or(@($authority.exactScope|Sort-Object)-join'|')-cne(@($review.exactPaths|Sort-Object)-join'|')){throw 'REPAIR_REVIEW_VERDICT_AUTHORITY_DRIFT'}
    $cycle=[int]$Binding.cycle-1
    if($null-eq$review.PSObject.Properties['repairReviewBinding']-or$review.repairReviewBinding.parentPackageIdentity-cne$Binding.parentPackageIdentity-or$review.repairReviewBinding.cycle-ne$cycle-or$review.repairReviewBinding.phase-cne$(if($cycle-eq0){'INITIAL_REVIEW'}else{'REREVIEW'})-or$review.owner-cne$Parent.owner-or$review.taskId-cne$Parent.taskId-or$review.taskIdentity-cne$Parent.taskIdentity-or$review.userConfirmation-cne$Parent.userConfirmation){throw 'REPAIR_REVIEW_VERDICT_PARENT_CYCLE'}
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    if($result.selectionIdentity-cne$source.selectionIdentity-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $source $input)){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_DECISION'}
    $refs=@($input.evidenceRefs|Where-Object kind -CEQ 'REVIEW_VERDICT')
    if($refs.Count-ne1){throw 'REPAIR_REVIEW_FINALIZED_TYPED_VERDICT_REQUIRED'}
    $raw=Read-EvRef $Context ([pscustomobject]@{path=$refs[0].path;identity=$refs[0].identity}) -Json
    $candidates=@(Get-AiwPackageCandidateReferences $review)
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwFinalizedObjectPostimages $input @($review.exactPaths))}))
    Assert-EvSameCandidates $post $candidates $Context
    $record=Read-AiwResultEvidence $Context $refs[0] $Parent.taskId $candidates $raw.requirementsRef -ExpectedActor $review.grantee -AuthorizationIdentity $authority.authorizationIdentity -RequireIndependentReview -ExcludedReviewActors (@($Parent.owner,$Parent.issuer,$Parent.repairReviewPlan.writer)+@($Parent.repairReviewPlan.materialContributors)) -FrozenCandidateEvidence:$FrozenCandidates
    $flat=Get-AiwPlannedReviewFlatVerdict $Context $review $record
    if($record.outcome-cne'CHANGES_REQUESTED'-or$flat.reference.path-cne$Binding.verdictPath-or$flat.reference.identity-cne$Binding.verdictIdentity-or$flat.value.scopeChanged-or$flat.value.decisionChanged){throw 'REPAIR_REVIEW_VERDICT_FLAT_LINK'}
    $allRefs=@($input.evidenceRefs);$allRecords=@()
    foreach($ref in $allRefs){
        if($ref.kind-ceq'REVIEW_VERDICT'){$allRecords+=$record;continue}
        $other=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $allRecords+=Read-AiwResultEvidence $Context $ref $Parent.taskId $candidates $other.requirementsRef -FrozenCandidateEvidence:($FrozenCandidates-and$ref.kind-ceq'SELF_CHECK')
    }
    $prep=@($input.preparationReceipts|Where-Object{$_-cne'SELF_CHECK_BOUND'});if(@($allRefs|Where-Object kind -CEQ 'SELF_CHECK').Count){$prep+='SELF_CHECK_BOUND'}
    $results=@($input.resultReceipts|Where-Object{$_-cnotin@('REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED','DELIVERY_RECEIPT')})+@('REVIEW_VERDICT_BOUND')
    if(@($allRefs|Where-Object kind -CEQ 'RESULT_ACCEPTANCE').Count){$results+='RESULT_ACCEPT_RECORDED'}
    Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
    $observed=Get-AiwBoundDelivery $source $input ([pscustomobject]@{references=$allRefs;records=$allRecords}) -ForbiddenPaths $Context.ForbiddenPaths -ProtectedPaths $Context.CandidateProtectedPaths
    if(-not$observed.closureSatisfied-or$null-eq$result.PSObject.Properties['consumer']-or($result.consumer|ConvertTo-Json -Compress)-cne($observed.consumer|ConvertTo-Json -Compress)){throw 'REPAIR_REVIEW_VERDICT_NOT_DELIVERED'}
    if($null-eq$result.PSObject.Properties['delivery']-or($result.delivery|ConvertTo-Json -Compress)-cne((Get-AiwDeliveryObservation $input.deliveryContext)|ConvertTo-Json -Compress)){throw 'REPAIR_REVIEW_VERDICT_DELIVERY_DRIFT'}
    $results+='DELIVERY_RECEIPT'
    foreach($obligation in $source.selectedObligations){if(@($obligation.preparationRequirements|Where-Object{$_-cnotin$prep}).Count-or@($obligation.resultRequirements|Where-Object{$_-cnotin$results}).Count){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_INCOMPLETE'}}
    return $flat
}
Export-ModuleMember -Function Get-AiwPlannedReviewFlatVerdict,Assert-AiwFinalizedReviewFinding
function Get-EvHistoricalFinalize($Context,$Reference,$Record,$OriginalFinalize) {
    # Original inputs/results are supplied by the finite consumer, never found
    # by scanning or written back into a typed record (which would form a cycle).
    Assert-EvArray $OriginalFinalize
    $matches=@()
    foreach($pair in $OriginalFinalize){
        Assert-EvFields $pair @('inputRef','resultRef')
        $input=Read-EvRef $Context $pair.inputRef -Json
        if($null-eq$input.PSObject.Properties['evidenceRefs']){continue}
        Assert-EvRefs $input.evidenceRefs -Typed
        if(@($input.evidenceRefs|Where-Object{$_.kind-ceq$Reference.kind-and(Test-EvSameRef $_ $Reference $Context)}).Count){$matches+=@([pscustomobject]@{input=$input;pair=$pair})}
    }
    if($matches.Count-ne1){throw 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND'}
    $input=$matches[0].input;$result=Read-EvRef $Context $matches[0].pair.resultRef -Json
    if($input.schemaVersion-ne3-or$input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'EVIDENCE_HISTORICAL_FINALIZE_INCOMPLETE'}
    $source=Read-EvRef $Context ([pscustomobject]@{path=$input.discoverReceiptPath;identity=$input.expectedDiscoverReceiptIdentity}) -Json
    if($source.schemaVersion-notin@(3,4)-or$source.status-cne'PASS'-or$source.mode-cne'DISCOVER'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'){throw 'EVIDENCE_HISTORICAL_SOURCE_UNSUPPORTED'}
    $a=$source.binding;$action=$source.intentEnvelope.requestedActionKind
    $allowed=switch($Reference.kind){'SELF_CHECK'{@('SOURCE_WRITE','CONTROL_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE')};'REVIEW_VERDICT'{@('REVIEW_EXECUTE')};'RESULT_ACCEPTANCE'{@('RESULT_ACCEPT')}}
    $packageRef=[pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity}
    $package=Read-EvRef $Context $packageRef -Json
    if($null-ne$package.PSObject.Properties['qualityBinding']){
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
        Assert-AiwQualityBinding $package.qualityBinding
        if($null-eq$source.sourceBindings.PSObject.Properties['policyIdentity']-or$package.qualityBinding.policyRef.identity-cne$source.sourceBindings.policyIdentity){throw 'QUALITY_HISTORICAL_POLICY_UNBOUND'}
        $repo=if($package.schemaVersion-in@(2,4)){$package.repositoryId}else{'REPO_LOCAL'}
        if($package.qualityBinding.subject.repositoryId-cne$repo-or@($package.exactPaths|Where-Object{$_-cnotin$package.qualityBinding.subject.exactPaths}).Count){throw 'QUALITY_HISTORICAL_SUBJECT_DRIFT'}
    }
    if($action-cnotin$allowed-or$action-cnotin$package.actions-or$action-cnotin$a.authorizedActions-or($action-cne'REVIEW_ROUTE'-and$a.actor-cne$Record.actor)-or$a.actor-cne$package.grantee-or$a.taskId-cne$Record.taskId-or$a.taskId-cne$package.taskId-or$a.taskOwner-cne$package.owner-or$a.taskIdentity-cne$package.taskIdentity-or$a.userDecision-cne$package.userConfirmation-or$a.projectConfigIdentity-cne$package.projectConfigIdentity){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-ceq'TASK_OWNER'-and$package.issuer-cne$package.owner){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-ceq'PROJECT_CONTROLLER'-and($package.issuer-cne$package.issuerControllerId-or$package.controllerControlIdentity-cne$a.controllerIdentity-or$package.issuerControllerEpoch-lt1)){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-cnotin@('TASK_OWNER','PROJECT_CONTROLLER')){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($null-ne$Record.PSObject.Properties['authorizationRef']-and-not(Test-EvSameRef $Record.authorizationRef $packageRef $Context)){throw 'EVIDENCE_AUTHORIZATION_DRIFT'}
    if(-not([IO.Path]::GetFullPath($a.projectRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
    # Merge original restrictions before any candidate metadata access. Later
    # live task/config/AGENTS bytes do not replace the original admitted facts.
    $historical=[pscustomobject]@{ProjectRoot=$Context.ProjectRoot;RepositoryRoot=$Context.RepositoryRoot;Roots=$Context.Roots;ForbiddenPaths=@($Context.ForbiddenPaths)+@($a.forbiddenScope)+@($Context.CandidateProtectedPaths)+@($a.protectedScope);CandidateProtectedPaths=@($Context.CandidateProtectedPaths)+@($a.protectedScope);Reading=$Context.Reading}
    if($source.schemaVersion-eq4){
        if(-not([IO.Path]::GetFullPath($a.objectRoot)).Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
        if($a.executionContext.targetKind-ceq'GIT_WORKTREE'){
            if($Record.schemaVersion-ne2){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
            $descriptor=Read-EvRef $historical $a.executionContext.executionTargetRef -Json
            if($descriptor.taskId-cne$Record.taskId-or$descriptor.controlRoot-cne$a.controlRoot-or$descriptor.targetRoot-cne$a.executionContext.executionRoot-or$descriptor.gitBinding.commonGitDir-cne$a.executionContext.targetObservation.commonGitDir-or$descriptor.gitBinding.worktreeGitDir-cne$a.executionContext.targetObservation.worktreeGitDir){throw 'EVIDENCE_EXECUTION_TARGET_DRIFT'}
            if(-not(Test-EvSameRef $Record.executionTargetRef $a.executionContext.executionTargetRef $historical)){throw 'EVIDENCE_EXECUTION_TARGET_DRIFT'}
            Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
            $null=Assert-AiwExecutionTargetState $a.executionContext $Record.candidateTargetState
            if($null-eq$result.PSObject.Properties['postTargetState']){throw 'EVIDENCE_HISTORICAL_TARGET_UNBOUND'}
            $null=Assert-AiwExecutionTargetState $a.executionContext $result.postTargetState
            # Keep the original target for the existing path/protection helper.
            # That helper observes control Git-top for protection projection;
            # it does not compare the current target HEAD with the old state.
            $historical|Add-Member ExecutionContext $a.executionContext
        }elseif($Record.schemaVersion-ne1){throw 'EVIDENCE_HISTORICAL_TARGET_UNBOUND'}
    }else{
        if($Record.schemaVersion-ne1-or$package.schemaVersion-eq4){throw 'EVIDENCE_HISTORICAL_TARGET_UNBOUND'}
        $originalRoot=if($package.schemaVersion-eq2){$a.repositoryGitTop}else{$a.projectRoot}
        if(-not[IO.Path]::IsPathFullyQualified($originalRoot)-or-not([IO.Path]::GetFullPath($originalRoot)).Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
    }
    $scope=@(Get-AiwActionScopeObjects $package $action $historical)
    if((@($scope.path|Sort-Object)-join'|')-cne(@($a.exactScope|Sort-Object)-join'|')){throw 'EVIDENCE_HISTORICAL_SCOPE_DRIFT'}
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwFinalizedObjectPostimages $input @($a.exactScope))}))
    Assert-EvSameCandidates $post $Record.candidateObjects $historical
    $routeQualification=$null;$routeRecipient=''
    if($action-ceq'REVIEW_ROUTE'){
        # Reuse the private original-package qualification, never the public
        # current gate or a caller-supplied trusted-history switch.
        $deliveryModule=@(Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1') -PassThru)[0]
        $routeQualification=& $deliveryModule {param($s,$b,$p,$c) Get-DeliveryReviewRouteQualification $s $b $p $c} $source $input $package $historical
        if($Record.actor-cne$routeQualification.writer){throw 'EVIDENCE_HISTORICAL_AUTHOR_DRIFT'}
        if($null-ne$routeQualification.review){Assert-EvSameCandidates @(Get-AiwPackageCandidateReferences $routeQualification.review) $post $historical}
        if($null-eq$input.PSObject.Properties['deliveryContext']){throw 'EVIDENCE_HISTORICAL_DELIVERY_UNPROVEN'}
        $routeRecipient=& $deliveryModule {param($s,$c,$p,$r) Get-DeliveryReviewRouteRecipient $s $c $p $r} $source $input.deliveryContext $package $routeQualification.review
    }
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    $postSource='NO_SOURCE_POSTIMAGE_TRANSITION';$changed=@()
    if($null-ne$result.PSObject.Properties['sourcePostimageTransition']){
        $transition=$result.sourcePostimageTransition
        Assert-EvFields $transition @('status','previousSourceCompositionIdentity','currentSourceCompositionIdentity','changedBindings','selectedPackBytes','selectedRequirementCount')
        Assert-EvArray $transition.changedBindings
        if($transition.status-cne'PASS'-or$transition.previousSourceCompositionIdentity-cne$source.sourceCompositionIdentity-or$transition.currentSourceCompositionIdentity-cnotmatch'^[A-F0-9]{64}$'-or$null-ne$result.PSObject.Properties['controlTransitionCompletion']){throw 'EVIDENCE_HISTORICAL_SOURCE_TRANSITION_UNPROVEN'}
        # Ordinary source postimage transitions record their complete changed
        # binding set. Task/controller transitions need their separate original
        # completion chain; they are not silently inferred here.
        $changed=@($transition.changedBindings)
        $carriers=@{projectAgentsIdentity='AGENTS.md';projectCustomIdentity='.ai-workspace/BOOTSTRAP.md';correctionsIdentity='.ai-workspace/corrections.json';policyIdentity='.ai-workspace/process-policy.json';projectConfigIdentity='.ai-workspace/project.json'}
        if($changed.Count-eq0-or@($changed|Select-Object -Unique).Count-ne$changed.Count-or@($changed|Where-Object{$_-cnotin(@($carriers.Keys)+@('projectStandardsIdentity','contentSnapshotIdentity','effectiveSetIdentity'))}).Count){throw 'EVIDENCE_HISTORICAL_SOURCE_TRANSITION_UNPROVEN'}
        foreach($name in $changed){if($carriers.ContainsKey($name)-and$carriers[$name]-cnotin$a.exactScope){throw 'EVIDENCE_HISTORICAL_SOURCE_TRANSITION_UNPROVEN'}}
        $postSource=$transition.currentSourceCompositionIdentity
    }
    if($result.selectionIdentity-cne$source.selectionIdentity-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $source $input $postSource $changed)){throw 'EVIDENCE_HISTORICAL_FINALIZE_DECISION'}
    if($null-eq$result.PSObject.Properties['actionOutcome']-or$result.actionOutcome-cne$(if($action-ceq'TEST_RUN'){'PASS'}else{'OBSERVED'})){throw 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL'}
    $prep=@($input.preparationReceipts|Where-Object{$_-cne'SELF_CHECK_BOUND'})
    $results=@($input.resultReceipts|Where-Object{$_-cnotin@('REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED','DELIVERY_RECEIPT')})
    foreach($ref in $input.evidenceRefs){
        $raw=Read-EvRef $historical ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        # The matching record is validated by our caller; other original typed
        # records are still immutable and must have a successful outcome.
        $ok=@{SELF_CHECK='PASS';REVIEW_VERDICT='APPROVED';RESULT_ACCEPTANCE='ACCEPTED'}
        if($raw.outcome-cne$ok[$ref.kind]){throw 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL'}
        if($action-ceq'REVIEW_ROUTE'-and$ref.kind-ceq'SELF_CHECK'){
            if($raw.actor-cne$routeQualification.writer-or$raw.taskId-cne$Record.taskId){throw 'EVIDENCE_HISTORICAL_AUTHOR_DRIFT'}
            Assert-EvSameCandidates $raw.candidateObjects $post $historical
        }
        switch($ref.kind){'SELF_CHECK'{$prep+='SELF_CHECK_BOUND'};'REVIEW_VERDICT'{$results+='REVIEW_VERDICT_BOUND'};'RESULT_ACCEPTANCE'{$results+='RESULT_ACCEPT_RECORDED'}}
    }
    if($null-ne$input.PSObject.Properties['deliveryContext']){
        Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
        $observation=Get-AiwDeliveryObservation $input.deliveryContext
        if($null-eq$result.PSObject.Properties['delivery']-or($result.delivery|ConvertTo-Json -Compress)-cne($observation|ConvertTo-Json -Compress)){throw 'EVIDENCE_HISTORICAL_DELIVERY_DRIFT'}
        if($action-ceq'REVIEW_ROUTE'){
            if($null-ne$input.deliveryContext.PSObject.Properties['userDecisionRef']){
                if($input.publicDecisionIdentity-cne$input.deliveryContext.userDecisionRef.identity){throw 'DELIVERY_USER_DECISION_UNBOUND'}
                $null=Read-EvRef $historical $input.deliveryContext.userDecisionRef
                $routeRecipient=[string]$input.deliveryContext.expectedRecipient
                if([string]::IsNullOrWhiteSpace($routeRecipient)-or$routeRecipient-cne$routeRecipient.Trim()-or$routeRecipient-cin@('USER','NOT_APPLICABLE','NOT_REQUIRED','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')){throw 'DELIVERY_EXPLICIT_TASK_RECIPIENT_REQUIRED'}
            }
            if($input.deliveryContext.channel-cne'TASK_MESSAGE'-or$input.deliveryContext.expectedRecipient-cne$routeRecipient-or$null-eq$result.PSObject.Properties['consumer']-or$result.consumer.recipient-cne$routeRecipient-or$result.consumer.channel-cne'TASK_MESSAGE'-or$result.consumer.authorizationIdentity-cne$packageRef.identity){throw 'EVIDENCE_HISTORICAL_DELIVERY_DRIFT'}
        }
        if($input.deliveryContext.channel-ceq'TASK_MESSAGE'){
            if(-not$observation.delivered-or$input.deliveryContext.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'EVIDENCE_HISTORICAL_DELIVERY_UNPROVEN'}
            $hostResult=Read-EvRef $historical ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
            $delivery=Get-AiwCodexSendOutcome $hostResult $input.deliveryContext.expectedRecipient
            if($delivery.outcome-cne'SUCCESS'){throw 'EVIDENCE_HISTORICAL_DELIVERY_UNPROVEN'}
        }
        $results+='DELIVERY_RECEIPT'
    }elseif(@($input.deliveryReceipts).Count){$results+='DELIVERY_RECEIPT'}
    foreach($obligation in $source.selectedObligations){if(@($obligation.preparationRequirements|Where-Object{$_-cnotin$prep}).Count-or@($obligation.resultRequirements|Where-Object{$_-cnotin$results}).Count){throw 'EVIDENCE_HISTORICAL_FINALIZE_INCOMPLETE'}}
    # Only known whole-file input bindings become historical observations.
    # Bootstrap fragments, selected-rule aggregates and fixed tool/catalog
    # identities do not prove a whole auxiliary file and are not included.
    $inputPaths=[ordered]@{projectAgentsIdentity='AGENTS.md';projectConfigIdentity='.ai-workspace/project.json';controllerIdentity='.ai-workspace/controller.json';correctionsIdentity='.ai-workspace/corrections.json';taskIdentity=$source.sourceLocators.taskRelativePath}
    $historical|Add-Member HistoricalInputObservations @(foreach($name in $inputPaths.Keys){
        if($null-eq$source.sourceBindings.PSObject.Properties[$name]){continue}
        $identity=[string]$source.sourceBindings.$name
        if($identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){continue}
        if($null-ne$a.PSObject.Properties[$name]-and$a.$name-cne$identity){throw 'EVIDENCE_HISTORICAL_INPUT_BINDING_DRIFT'}
        [pscustomobject]@{path=(Join-Path $historical.ProjectRoot $inputPaths[$name]);identity=$identity}
    })
    return $historical
}
function Read-AiwResultEvidence($Context,$Reference,[string]$TaskId,$CandidateObjects,$RequirementsRef,[switch]$RequireSuccess,[string]$ExpectedActor='',[string]$AuthorizationIdentity='',[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[switch]$FrozenCandidateEvidence,[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE') {
    Assert-EvRef $Reference -Typed
    # Continuation history cannot satisfy a success gate. Historical success
    # separately requires the original completed action and its exact postimage.
    if($FrozenCandidateEvidence-and($Reference.kind-cnotin@('SELF_CHECK','REVIEW_VERDICT')-or$RequireSuccess-or$EvidencePurpose-ceq'HISTORICAL_SUCCESS')){throw 'EVIDENCE_FROZEN_SUCCESS_GATE_DENIED'}
    $historical=$EvidencePurpose-ceq'HISTORICAL_SUCCESS'
    $key=(Resolve-EvPath $Context $Reference.path)+'|'+$Reference.identity
    if($Context.Reading.Count-ge32-or-not$Context.Reading.Add($key)){throw 'EVIDENCE_REFERENCE_CYCLE'}
    try{
        $ref=[pscustomobject]@{path=$Reference.path;identity=$Reference.identity}
        $record=Read-EvRef $Context $ref -Json
        Assert-EvFields $record @('schemaVersion','taskId','actor','candidateObjects','requirementsRef','outcome','checks','evidenceLocators') @('authorizationRef','acceptedCommit','executionTargetRef','candidateTargetState')
        Assert-EvInteger $record.schemaVersion;if($record.schemaVersion-notin@(1,2)){throw 'EVIDENCE_SCHEMA'}
        if($historical){$Context=Get-EvHistoricalFinalize $Context $Reference $record $OriginalFinalize}
        else{$Context=Resolve-EvRecordTarget $Context $record -FrozenCandidateEvidence:$FrozenCandidateEvidence}
        foreach($s in @('taskId','actor','outcome')){Assert-EvString $record.$s}
        if($record.taskId-cne$TaskId){throw 'EVIDENCE_TASK_DRIFT'}
        if($ExpectedActor-and$record.actor-cne$ExpectedActor){throw 'EVIDENCE_ACTOR_DRIFT'}
        Assert-EvSameCandidates $record.candidateObjects $CandidateObjects $Context
        if(-not($FrozenCandidateEvidence-or$historical)){foreach($candidate in $record.candidateObjects){$null=Read-EvRef $Context $candidate -Candidate}}
        Assert-EvRef $record.requirementsRef -Section
        if(-not(Test-EvSameRef $record.requirementsRef $RequirementsRef $Context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
        $null=Read-EvRef $Context $record.requirementsRef -Section
        $outcomes=@{SELF_CHECK=@('PASS','FAIL','INCOMPLETE');REVIEW_VERDICT=@('APPROVED','CHANGES_REQUESTED','REJECTED','INCOMPLETE');RESULT_ACCEPTANCE=@('ACCEPTED','REJECTED','INCOMPLETE')}
        if($record.outcome-cnotin$outcomes[$Reference.kind]){throw 'EVIDENCE_OUTCOME'}
        $success=$record.outcome-ceq$outcomes[$Reference.kind][0]
        if(($RequireSuccess-or$historical)-and-not$success){throw 'EVIDENCE_NOT_SUCCESSFUL'}
        Assert-EvRefs $record.evidenceLocators
        foreach($locator in $record.evidenceLocators){Read-EvObservationLocator $Context $locator $CandidateObjects -FrozenCandidateEvidence:$FrozenCandidateEvidence -HistoricalSuccess:$historical}
        Assert-EvArray $record.checks;if($record.checks.Count-eq0){throw 'EVIDENCE_CHECKS_EMPTY'}
        $checks=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($check in $record.checks){
            Assert-EvFields $check @('id','method','outcome','reason','evidenceLocators')
            foreach($s in @('id','method','outcome','reason')){Assert-EvString $check.$s}
            if(-not$checks.Add($check.id)){throw 'EVIDENCE_CHECK_DUPLICATE'}
            if($check.method-cnotin@('COMMAND','MODEL_JUDGMENT')-or$check.outcome-cnotin@('PASS','FAIL','INCOMPLETE')){throw 'EVIDENCE_CHECK_KIND'}
            if($success-and$check.outcome-cne'PASS'){throw 'EVIDENCE_SUCCESS_CONTRADICTION'}
            Assert-EvRefs $check.evidenceLocators -Nonempty
            if($check.method-ceq'COMMAND'){
                if($check.evidenceLocators.Count-ne1){throw 'EVIDENCE_COMMAND_LOCATOR_COUNT'}
                $command=Read-EvRef $Context $check.evidenceLocators[0] -Json
                Assert-EvFields $command @('command','exitCode','output')
                Assert-EvString $command.command;Assert-EvInteger $command.exitCode
                $null=Read-EvRef $Context $command.output
                if($check.outcome-ceq'PASS'-and$command.exitCode-ne0){throw 'EVIDENCE_COMMAND_FAILURE'}
            }else{foreach($locator in $check.evidenceLocators){Read-EvObservationLocator $Context $locator $CandidateObjects -FrozenCandidateEvidence:$FrozenCandidateEvidence -HistoricalSuccess:$historical}}
        }
        if($Reference.kind-ceq'SELF_CHECK'){
            if($null-ne$record.PSObject.Properties['authorizationRef']-or$null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
        }else{
            if($null-eq$record.PSObject.Properties['authorizationRef']){throw 'EVIDENCE_ORIGINAL_PACKAGE_REQUIRED'}
            $package=Read-EvRef $Context $record.authorizationRef -Json
            if($package.schemaVersion-eq4-and$record.schemaVersion-ne2){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
            $action=if($Reference.kind-ceq'REVIEW_VERDICT'){'REVIEW_EXECUTE'}else{'RESULT_ACCEPT'}
            if($package.taskId-cne$TaskId-or$package.grantee-cne$record.actor-or@($package.actions).Count-ne1-or$package.actions[0]-cne$action){throw 'EVIDENCE_ORIGINAL_PACKAGE_DRIFT'}
            if($AuthorizationIdentity-and$record.authorizationRef.identity-cne$AuthorizationIdentity){throw 'EVIDENCE_AUTHORIZATION_DRIFT'}
            if(-not$historical-and$null-ne$package.PSObject.Properties['qualityBinding']){
                $taskLocator=if($null-ne$Context.PSObject.Properties['TaskPath']-and$Context.TaskPath){$Context.TaskPath}else{'.ai-workspace/tasks/active/'+$package.taskId+'.md'}
                $taskFull=Resolve-EvPath $Context $taskLocator
                $activePlan=Get-AiwAcceptancePlan ([IO.File]::ReadAllText($taskFull))
                $null=Get-AiwPackageQuality $Context $package $activePlan
            }
            Assert-EvSameCandidates @(Get-AiwPackageCandidateReferences $package) $record.candidateObjects $Context
            if($Reference.kind-ceq'REVIEW_VERDICT'){
                $null=Get-AiwPlannedReviewFlatVerdict $Context $package $record
                if($null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
                if($package.reviewIndependence-ceq'INDEPENDENT'-or$RequireIndependentReview-or$package.profile-ceq'CRITICAL'-or$null-ne$package.PSObject.Properties['candidateWriter']-or$null-ne$package.PSObject.Properties['materialContributors']){
                    if($package.reviewIndependence-cne'INDEPENDENT'){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
                    foreach($field in @('candidateWriter','materialContributors')){if($null-eq$package.PSObject.Properties[$field]){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}}
                    if($package.materialContributors-isnot[Array]){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
                    $originalActors=@(Get-AiwReviewExcludedActors $package.owner $package.issuer $package.candidateWriter $package.materialContributors)
                    if($record.actor-cin($originalActors+@($ExcludedReviewActors))){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
                }
            }else{
                $prerequisitePurpose=if($historical){'HISTORICAL_SUCCESS'}else{$PrerequisiteEvidencePurpose}
                Assert-EvAcceptanceBinding $Context $package $null -Historical -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -EvidencePurpose $EvidencePurpose -OriginalFinalize $OriginalFinalize -PrerequisiteEvidencePurpose $prerequisitePurpose
                if($null-ne$package.PSObject.Properties['acceptanceBinding']-and-not(Test-EvSameRef $package.acceptanceBinding.requirementsRef $record.requirementsRef $Context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
                if($null-ne$record.PSObject.Properties['acceptedCommit']-and$record.acceptedCommit-cnotmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw 'EVIDENCE_ACCEPTED_COMMIT'}
            }
        }
        return $record
    }finally{$null=$Context.Reading.Remove($key)}
}

function Get-AiwAcceptancePlan([string]$TaskText) {
    $headers=[regex]::Matches($TaskText,'(?m)^```aiw-acceptance-plan\s*$')
    if($headers.Count-eq0){return $null}
    $blocks=[regex]::Matches($TaskText,'(?ms)^```aiw-acceptance-plan\s*\r?\n(?<json>.*?)^```\s*$')
    if($headers.Count-ne1-or$blocks.Count-ne1){throw 'ACCEPTANCE_PLAN_BLOCK_COUNT'}
    $plan=ConvertFrom-EvJson $blocks[0].Groups['json'].Value
    Assert-EvFields $plan @('schemaVersion','stages') @('qualityBinding');Assert-EvInteger $plan.schemaVersion
    if($plan.schemaVersion-notin@(1,2)){throw 'ACCEPTANCE_PLAN_SCHEMA'}
    if($plan.schemaVersion-eq1-and$null-ne$plan.PSObject.Properties['qualityBinding']){throw 'ACCEPTANCE_PLAN_SCHEMA'}
    if($plan.schemaVersion-eq2){Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1');if($null-eq$plan.PSObject.Properties['qualityBinding']){throw 'QUALITY_PLAN_REQUIRED'};Assert-AiwQualityBinding $plan.qualityBinding}
    Assert-EvArray $plan.stages;if(($plan.schemaVersion-eq1-and$plan.stages.Count-eq0)-or$plan.stages.Count-gt128){throw 'ACCEPTANCE_PLAN_STAGE_COUNT'}
    $stages=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($stage in $plan.stages){
        Assert-EvFields $stage @('id','kind','requiredBy','dependsOn','candidateRef','evidenceRefs') @('evidenceConsumption')
        Assert-EvString $stage.id
        if($stage.id-cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'-or$stages.ContainsKey($stage.id)){throw 'ACCEPTANCE_PLAN_STAGE_ID'}
        if($stage.kind-cnotin@('DESIGN','DESIGN_REVIEW','SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT','USER_DECISION')){throw 'ACCEPTANCE_PLAN_STAGE_KIND'}
        Assert-EvRef $stage.requiredBy -Section;Assert-EvArray $stage.dependsOn
        $deps=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($dep in $stage.dependsOn){Assert-EvString $dep;if(-not$deps.Add($dep)){throw 'ACCEPTANCE_PLAN_DUPLICATE_EDGE'}}
        Assert-EvRefs $stage.candidateRef -Candidate:($stage.kind-cne'USER_DECISION');Assert-EvRefs $stage.evidenceRefs -Typed
        if($stage.kind-cin@('DESIGN','USER_DECISION')-and$stage.evidenceRefs.Count){throw 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND'}
        if($null-ne$stage.PSObject.Properties['evidenceConsumption']){
            if($stage.kind-cin@('DESIGN','USER_DECISION')){throw 'ACCEPTANCE_PLAN_STAGE_CONSUMPTION_KIND'}
            $null=Get-EvConsumption $stage evidenceConsumption
        }
        $map=@{DESIGN_REVIEW='REVIEW_VERDICT';RESULT_REVIEW='REVIEW_VERDICT';SELF_CHECK='SELF_CHECK';RESULT_ACCEPT='RESULT_ACCEPTANCE'}
        if($map.ContainsKey($stage.kind)-and@($stage.evidenceRefs|Where-Object{$_.kind-cne$map[$stage.kind]}).Count){throw 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND'}
        $stages.Add($stage.id,$stage)
    }
    $visiting=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function Visit-Stage([string]$Id){
        if(-not$stages.ContainsKey($Id)){throw 'ACCEPTANCE_PLAN_UNKNOWN_DEPENDENCY'}
        if($done.Contains($Id)){return}
        if(-not$visiting.Add($Id)){throw 'ACCEPTANCE_PLAN_CYCLE'}
        foreach($dep in $stages[$Id].dependsOn){Visit-Stage $dep}
        $null=$visiting.Remove($Id);$null=$done.Add($Id)
    }
    foreach($id in $stages.Keys){Visit-Stage $id}
    if($plan.schemaVersion-eq2){foreach($kind in $plan.qualityBinding.effectiveStages){if(@($plan.stages|Where-Object{$_.kind-ceq$kind}).Count-eq0){throw 'QUALITY_PLAN_STAGE_MISSING'}}}
    return $plan
}
function Get-EvPrerequisites($Plan,[string]$StageId) {
    $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);foreach($s in $Plan.stages){$map.Add($s.id,$s)}
    if(-not$map.ContainsKey($StageId)){throw 'ACCEPTANCE_PLAN_STAGE_NOT_FOUND'}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function Add-StageDeps([string]$Id){foreach($dep in $map[$Id].dependsOn){if($ids.Add($dep)){Add-StageDeps $dep}}}
    Add-StageDeps $StageId
    return @($Plan.stages|Where-Object{$ids.Contains($_.id)})
}
function Assert-AiwAcceptanceStages($Context,$Plan,[string]$TaskId,[string]$BeforeStage='', $UserDecisionRefs=@(),[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@()) {
    $stages=if($BeforeStage){@(Get-EvPrerequisites $Plan $BeforeStage)}else{@($Plan.stages)}
    Assert-EvRefs $UserDecisionRefs
    foreach($stage in $stages){
        $null=Read-EvRef $Context $stage.requiredBy -Section
        if($stage.candidateRef.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
        if($stage.kind-ceq'USER_DECISION'){
            foreach($ref in $stage.candidateRef){
                if(@($UserDecisionRefs|Where-Object{Test-EvSameRef $_ $ref $Context}).Count-ne1){throw ('ACCEPTANCE_USER_DECISION_UNBOUND|'+$stage.id)}
                $null=Read-EvRef $Context $ref
            }
        }elseif($stage.kind-ceq'DESIGN'){
            foreach($ref in $stage.candidateRef){$null=Read-EvRef $Context $ref -Candidate}
        }else{
            if($stage.evidenceRefs.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
            $consumption=Get-EvConsumption $stage evidenceConsumption $EvidencePurpose $OriginalFinalize
            foreach($ref in $stage.evidenceRefs){$null=Read-AiwResultEvidence $Context $ref $TaskId $stage.candidateRef $stage.requiredBy -RequireSuccess -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize}
        }
    }
}
function Assert-AiwAcceptanceBinding($Context,$Package,$Plan,[switch]$Historical,[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@()) {
    # This public admission/acceptance gate always checks the current candidate.
    Assert-EvAcceptanceBinding $Context $Package $Plan -Historical:$Historical -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -PrerequisiteEvidencePurpose $PrerequisiteEvidencePurpose -OriginalFinalize $OriginalFinalize
}
function Assert-EvAcceptanceBinding($Context,$Package,$Plan,[switch]$Historical,[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),[string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE') {
    if($null-eq$Package){throw 'RESULT_ACCEPT_AUTHORIZATION_REQUIRED'}
    $independentRequired=Test-AiwPackageReviewRequired $Package -ExplicitRequirement:$RequireIndependentReview
    $excluded=@($Package.owner,$Package.issuer)+@($ExcludedReviewActors)
    if(@($Package.actions).Count-ne1-or$Package.actions[0]-cne'RESULT_ACCEPT'){throw 'RESULT_ACCEPT_PURE_PACKAGE_REQUIRED'}
    foreach($f in @('continuationPlan','repairReviewPlan','repairReviewBinding','receiverBinding','transitionPlan')){if($null-ne$Package.PSObject.Properties[$f]){throw 'RESULT_ACCEPT_CANNOT_REDELEGATE'}}
    $binding=if($null-ne$Package.PSObject.Properties['acceptanceBinding']){$Package.acceptanceBinding}else{$null}
    if($null-eq$binding){
        if($Package.grantee-cne$Package.owner){throw 'RESULT_ACCEPT_DELEGATION_REQUIRED'}
        if($null-ne$Plan-or$independentRequired){throw 'RESULT_ACCEPT_STAGE_BINDING_REQUIRED'}
        return
    }
    Assert-EvFields $binding @('candidateObjects','requirementsRef','prerequisiteEvidenceRefs','reservedUserDecisionRefs') @('prerequisiteConsumption')
    $consumption=Get-EvConsumption $binding prerequisiteConsumption $PrerequisiteEvidencePurpose $OriginalFinalize
    if($EvidencePurpose-ceq'HISTORICAL_SUCCESS'){
        # The parent has already proved its original successful FINALIZE. Its
        # old declaration cannot turn recursive history into a live recheck.
        $consumption=Get-EvConsumption $null '' HISTORICAL_SUCCESS $OriginalFinalize
    }
    Assert-EvSameCandidates $binding.candidateObjects @(Get-AiwPackageCandidateReferences $Package) $Context
    if($EvidencePurpose-ceq'CURRENT_CANDIDATE'){foreach($candidate in $binding.candidateObjects){$null=Read-EvRef $Context $candidate -Candidate}}
    $null=Read-EvRef $Context $binding.requirementsRef -Section
    Assert-EvRefs $binding.prerequisiteEvidenceRefs -Typed;Assert-EvRefs $binding.reservedUserDecisionRefs
    foreach($ref in $binding.reservedUserDecisionRefs){$null=Read-EvRef $Context $ref}
    $prereqs=@();$stageId=''
    if($null-ne$Plan){
        $stages=@($Plan.stages|Where-Object{$_.kind-ceq'RESULT_ACCEPT'-and(Test-EvSameRef $_.requiredBy $binding.requirementsRef $Context)-and(Test-EvSameCandidates $_.candidateRef $binding.candidateObjects $Context)})
        if($stages.Count-ne1){throw 'RESULT_ACCEPT_STAGE_AMBIGUOUS'}
        $stageId=$stages[0].id;$prereqs=@(Get-EvPrerequisites $Plan $stageId)
        if($Plan.schemaVersion-eq2){
            $required=@($Plan.qualityBinding.effectiveStages|Where-Object{$_-cne'RESULT_ACCEPT'})
            $prereqs=@(@($prereqs)+@($Plan.stages|Where-Object{$_.kind-cin$required})|Group-Object id|ForEach-Object{$_.Group[0]})
        }
    }
    if($Package.grantee-cne$Package.owner-and$Package.issuer-cne$Package.owner){
        # A Controller title is insufficient. The exceptional user route binds
        # the original current user source by identity; origin/meaning is HOST.
        if(@($binding.reservedUserDecisionRefs|Where-Object{$_.identity-ceq$Package.userConfirmation}).Count-ne1){throw 'RESULT_ACCEPT_OWNER_OR_USER_DECISION_REQUIRED'}
    }
    foreach($ref in $binding.prerequisiteEvidenceRefs){
        # Stage-specific design evidence can bind different candidates/requirements.
        $matches=@($prereqs|Where-Object{@($_.evidenceRefs|Where-Object{Test-EvSameRef $_ $ref $Context}).Count})
        $selected=$consumption
        if($matches.Count-eq1){
            $candidate=$matches[0].candidateRef;$requirements=$matches[0].requiredBy
            $selected=Get-EvConsumption $matches[0] evidenceConsumption $consumption.purpose $consumption.originalFinalize
        }else{$candidate=$binding.candidateObjects;$requirements=$binding.requirementsRef}
        if($Historical-or$selected.purpose-ceq'HISTORICAL_SUCCESS'){
            # Historical acceptance retains the original typed evidence bindings;
            # subsequent task progress is not a new permanent hash dependency.
            $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            $candidate=$raw.candidateObjects;$requirements=$raw.requirementsRef
        }
        $null=Read-AiwResultEvidence $Context $ref $Package.taskId $candidate $requirements -RequireSuccess -RequireIndependentReview:$independentRequired -ExcludedReviewActors $excluded -EvidencePurpose $selected.purpose -OriginalFinalize $selected.originalFinalize
    }
    if($independentRequired){
        $reviewed=$false
        foreach($ref in @($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq'REVIEW_VERDICT'})){
            $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            if((Test-EvSameCandidates $raw.candidateObjects $binding.candidateObjects $Context)-and(Test-EvSameRef $raw.requirementsRef $binding.requirementsRef $Context)){$reviewed=$true}
        }
        if(-not$reviewed){throw 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED'}
    }
    if($null-ne$Plan){
        foreach($stage in $prereqs){foreach($ref in $stage.evidenceRefs){if(@($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq$ref.kind-and(Test-EvSameRef $_ $ref $Context)}).Count-ne1){throw 'RESULT_ACCEPT_PREREQUISITE_UNBOUND'}}}
        Assert-AiwAcceptanceStages $Context ([pscustomobject]@{stages=@($prereqs)}) $Package.taskId '' $binding.reservedUserDecisionRefs -RequireIndependentReview:$independentRequired -ExcludedReviewActors $excluded -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize
    }
}
function New-AiwPackageEvidenceContext([string]$ProjectRoot,$Package,[string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@(),[string]$TaskPath='',[object]$TargetState=$null,[string[]]$ProtectedPaths=@()) {
    $repo=$ProjectRoot
    if($null-ne$Package-and$Package.schemaVersion-eq2-and$Package.repositoryId-ceq'REPO_LOCAL'){
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText((Join-Path $ProjectRoot '.ai-workspace/project.json')))
        if($cfg.controlPlaneLayout-cne'repo-local'){throw 'EVIDENCE_REPOSITORY_BINDING'}
    }
    if($null-ne$Package-and$Package.schemaVersion-eq2-and$Package.repositoryId-cnotin@('CONTROL','REPO_LOCAL')){
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText((Join-Path $ProjectRoot '.ai-workspace/project.json')))
        if($null-eq$cfg.PSObject.Properties['frameworkTarget']-or$cfg.frameworkTarget.repositoryId-cne$Package.repositoryId){throw 'EVIDENCE_REPOSITORY_BINDING'}
        $sibling=[string]$cfg.frameworkTarget.siblingDirectory
        if($sibling-cnotmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*$'-or$sibling.EndsWith('.')){throw 'EVIDENCE_REPOSITORY_BINDING'}
        $repo=Join-Path (Split-Path -Parent $ProjectRoot) $sibling
    }
    $target=$null
    if($null-ne$Package-and$Package.schemaVersion-eq4){
        if(-not$TaskPath){throw 'EVIDENCE_EXECUTION_TARGET_TASK_REQUIRED'}
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        $target=Resolve-AiwPackageExecutionTarget $ProjectRoot $Package $TaskPath $ForbiddenPaths $ProtectedPaths $TargetState
        $repo=$target.executionRoot
    }
    $ctx=New-AiwEvidenceContext $ProjectRoot $repo $FrameworkRoot $ForbiddenPaths $ProtectedPaths
    $ctx|Add-Member TaskPath $TaskPath
    $ctx|Add-Member ExecutionContext $target
    return $ctx
}
function Assert-AiwReviewSelfCheck($Context,$References,[string]$TaskId,$Candidates,$Plan=$null) {
    Assert-EvRefs $References -Typed
    $refs=@($References|Where-Object{$_.kind-ceq'SELF_CHECK'})
    if($refs.Count-eq0){throw 'REVIEW_SELF_CHECK_REQUIRED'}
    foreach($ref in $refs){
        $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $requirements=$raw.requirementsRef
        if($null-ne$Plan){
            $matches=@($Plan.stages|Where-Object{$_.kind-ceq'SELF_CHECK'-and(Test-EvSameCandidates $_.candidateRef $Candidates $Context)-and(Test-EvSameRef $_.requiredBy $requirements $Context)})
            if($matches.Count-eq0){throw 'REVIEW_SELF_CHECK_PLAN_DRIFT'}
        }
        $null=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $requirements -RequireSuccess
    }
}
function Get-AiwSelfCheckOutcome($References,$Records) {
    if(@($References).Count-ne@($Records).Count){throw 'SELF_CHECK_OBSERVATION_ALIGNMENT'}
    $outcomes=@(for($i=0;$i-lt@($References).Count;$i++){if($References[$i].kind-ceq'SELF_CHECK'){$Records[$i].outcome}})
    if($outcomes.Count-eq0){return 'NOT_APPLICABLE'}
    if(@($outcomes|Where-Object{$_-cnotin@('PASS','FAIL','INCOMPLETE')}).Count){throw 'SELF_CHECK_OBSERVATION_OUTCOME'}
    if('FAIL'-cin$outcomes){return 'FAIL'}
    if('INCOMPLETE'-cin$outcomes){return 'INCOMPLETE'}
    return 'PASS'
}
function Get-AiwContinuationSelfCheckOutcome($Context,$References,[string]$TaskId,$Candidates,[string]$Actor,[switch]$FrozenCandidateEvidence) {
    Assert-EvRefs $References -Typed
    $refs=@($References|Where-Object{$_.kind-ceq'SELF_CHECK'});$records=@()
    foreach($ref in $refs){
        $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $records+=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $raw.requirementsRef -ExpectedActor $Actor -FrozenCandidateEvidence:$FrozenCandidateEvidence
    }
    return Get-AiwSelfCheckOutcome $refs $records
}
function Get-AiwSelfRepairOriginCycle($Context,$Package) {
    if($null-eq$Package.PSObject.Properties['selfCheckRepairLimit']-or$null-eq$Package.PSObject.Properties['repairReviewBinding']){return 0}
    $binding=$Package.repairReviewBinding
    if($binding.phase-cne'REPAIR'){return 0}
    $parent=Read-EvRef $Context ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity}) -Json
    $null=Assert-AiwFinalizedReviewFinding $Context $parent $binding -FrozenCandidates
    $findingInput=Read-EvRef $Context ([pscustomobject]@{path=$binding.verdictFinalizeInputPath;identity=$binding.verdictFinalizeInputIdentity}) -Json
    $findingSource=Read-EvRef $Context ([pscustomobject]@{path=$findingInput.discoverReceiptPath;identity=$findingInput.expectedDiscoverReceiptIdentity}) -Json
    $review=Read-EvRef $Context ([pscustomobject]@{path=$findingSource.sourceLocators.authorizationPackagePath;identity=$findingSource.binding.authorizationIdentity}) -Json
    $productionInput=Read-EvRef $Context ([pscustomobject]@{path=$review.repairReviewBinding.repairFinalizeInputPath;identity=$review.repairReviewBinding.repairFinalizeInputIdentity}) -Json
    $productionResult=Read-EvRef $Context ([pscustomobject]@{path=$review.repairReviewBinding.repairFinalizeResultPath;identity=$review.repairReviewBinding.repairFinalizeResultIdentity}) -Json
    $productionSource=Read-EvRef $Context ([pscustomobject]@{path=$productionInput.discoverReceiptPath;identity=$productionInput.expectedDiscoverReceiptIdentity}) -Json
    $authority=if($productionSource.schemaVersion-eq1){$productionSource.authorityContext}else{$productionSource.binding}
    $producer=Read-EvRef $Context ([pscustomobject]@{path=$productionSource.sourceLocators.authorizationPackagePath;identity=$authority.authorizationIdentity}) -Json
    if($productionResult.status-cne'PASS'-or$producer.taskIdentity-cne$Package.taskIdentity-or$producer.grantee-cne$Package.grantee-or$producer.selfCheckRepairLimit-ne$Package.selfCheckRepairLimit){throw 'SELF_REPAIR_ORIGIN_AUTHORITY_DRIFT'}
    if($null-ne$producer.PSObject.Properties['repairReviewBinding']){
        if($producer.repairReviewBinding.phase-cne'REPAIR'-or$producer.repairReviewBinding.parentPackageIdentity-cne$binding.parentPackageIdentity-or$producer.repairReviewBinding.cycle-ne($binding.cycle-1)){throw 'SELF_REPAIR_ORIGIN_REVIEW_CYCLE'}
    }elseif($authority.authorizationIdentity-cne$binding.parentPackageIdentity-or$binding.cycle-ne1){throw 'SELF_REPAIR_ORIGIN_PARENT'}
    if($null-ne$productionResult.PSObject.Properties['continuationReceipt']-and$null-ne$productionResult.continuationReceipt){
        return Assert-AiwSelfRepairChain $Context $producer $productionResult.continuationReceipt
    }
    if($authority.continuationReceiptPath-cne'NOT_REQUIRED'){
        $leaf=Read-EvRef $Context ([pscustomobject]@{path=$authority.continuationReceiptPath;identity=$authority.continuationReceiptIdentity}) -Json
        return Assert-AiwSelfRepairChain $Context $producer $leaf
    }
    return Get-AiwSelfRepairOriginCycle $Context $producer
}
Export-ModuleMember -Function Get-AiwSelfRepairOriginCycle
function Assert-AiwSelfRepairChain($Context,$Package,$Leaf) {
    $baseFields=@('schemaVersion','receiptType','status','evidenceGrade','authorityGranted','packageIdentity','taskIdentity','taskId','taskOwner','taskActor','actor','repositoryId','projectConfigIdentity','controllerIdentity','userDecision','protectionState','forbiddenScope','protectedScope','sourceDiscoverReceiptPath','sourceDiscoverReceiptIdentity','sourceSelectionIdentity','sourceContextIdentity','completedStepIndex','completedAction','nextStepIndex','nextAction','exactPaths','postObjectIdentities','evidenceRefs','transitionKind','selfRepairCycle')
    $nodes=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $node=$Leaf;$limit=[int]$Package.selfCheckRepairLimit
    while($true){
        $fields=@($baseFields);if($node.schemaVersion-eq3){$fields+=@('executionTargetRef','observedTargetState','postTargetState')}
        Assert-EvFields $node $fields
        if($node.schemaVersion-notin@(2,3)-or$node.receiptType-cne'AUTHORIZED_ACTION_CONTINUATION'-or$node.status-cne'PASS'-or$node.evidenceGrade-cne'INSTRUCTION_BOUND'-or$node.authorityGranted-isnot[bool]-or$node.authorityGranted){throw 'SELF_REPAIR_RECEIPT_TYPE'}
        foreach($name in @('completedStepIndex','nextStepIndex','selfRepairCycle')){Assert-EvInteger $node.$name}
        if($node.selfRepairCycle-lt0-or$node.selfRepairCycle-gt$limit-or$node.transitionKind-cnotin@('ADVANCE','REPAIR','RETEST')){throw 'SELF_REPAIR_CYCLE'}
        foreach($name in @('packageIdentity','taskIdentity','taskId','taskOwner','taskActor','actor','repositoryId','projectConfigIdentity','controllerIdentity','userDecision','protectionState')){if($node.$name-cne$Leaf.$name){throw ('SELF_REPAIR_AUTHORITY_DRIFT|'+$name)}}
        foreach($name in @('forbiddenScope','protectedScope')){if($node.$name-isnot[Array]-or[string]::Join("`n",@($node.$name))-cne[string]::Join("`n",@($Leaf.$name))){throw 'SELF_REPAIR_SCOPE_DRIFT'}}
        $nextScope=@(Get-AiwActionScopeObjects $Package $node.nextAction $Context)
        if($node.exactPaths-isnot[Array]-or(@($node.exactPaths|Sort-Object)-join'|')-cne(@($nextScope.path|Sort-Object)-join'|')){throw 'SELF_REPAIR_SCOPE_DRIFT'}
        $candidates=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=$node.postObjectIdentities}))
        Assert-EvSameCandidates $candidates $candidates $Context
        if((@($candidates.path|Sort-Object)-join'|')-cne(@($nextScope.path|Sort-Object)-join'|')){throw 'SELF_REPAIR_POSTIMAGE_SET'}
        Assert-EvRefs $node.evidenceRefs -Typed
        $sourceRef=[pscustomobject]@{path=$node.sourceDiscoverReceiptPath;identity=$node.sourceDiscoverReceiptIdentity}
        if(-not$seen.Add($sourceRef.path+'|'+$sourceRef.identity)){throw 'SELF_REPAIR_REFERENCE_CYCLE'}
        $source=Read-EvRef $Context $sourceRef -Json
        $authority=if($source.schemaVersion-eq1){$source.authorityContext}else{$source.binding}
        $action=if($source.schemaVersion-eq1){$source.actionKind}else{$source.intentEnvelope.requestedActionKind}
        if(($Package.schemaVersion-eq4)-ne($node.schemaVersion-eq3)){throw 'SELF_REPAIR_TARGET_SCHEMA'}
        if($node.schemaVersion-eq3){
            Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
            if($source.schemaVersion-ne4-or-not(Test-EvSameRef $node.executionTargetRef $Package.executionTargetRef $Context)-or-not(Test-EvSameRef $node.executionTargetRef $authority.executionContext.executionTargetRef $Context)-or($node.observedTargetState|ConvertTo-Json -Compress)-cne((Get-AiwExecutionTargetState $authority.executionContext)|ConvertTo-Json -Compress)-or($node.postTargetState|ConvertTo-Json -Compress)-cne($node.observedTargetState|ConvertTo-Json -Compress)){throw 'SELF_REPAIR_TARGET_SOURCE_DRIFT'}
        }

        if($source.schemaVersion-notin@(1,2,3,4)-or$source.status-cne'PASS'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or$source.mode-cne'DISCOVER'-or$source.selectionIdentity-cne$node.sourceSelectionIdentity-or$source.contextIdentity-cne$node.sourceContextIdentity-or$action-cne$node.completedAction-or$authority.continuationStepIndex-ne$node.completedStepIndex){throw 'SELF_REPAIR_SOURCE_LINK'}
        $completedScope=@(Get-AiwActionScopeObjects $Package $action $Context)
        if((@($authority.exactScope|Sort-Object)-join'|')-cne(@($completedScope.path|Sort-Object)-join'|')){throw 'SELF_REPAIR_SOURCE_SCOPE_DRIFT'}
        foreach($pair in @(@('authorizationIdentity','packageIdentity'),@('taskIdentity','taskIdentity'),@('taskId','taskId'),@('taskOwner','taskOwner'),@('taskActor','taskActor'),@('actor','actor'),@('projectConfigIdentity','projectConfigIdentity'),@('controllerIdentity','controllerIdentity'),@('userDecision','userDecision'))){if($authority.($pair[0])-cne$node.($pair[1])){throw 'SELF_REPAIR_SOURCE_AUTHORITY_DRIFT'}}
        foreach($scope in @('forbiddenScope','protectedScope')){if([string]::Join("`n",@($authority.$scope))-cne[string]::Join("`n",@($node.$scope))){throw 'SELF_REPAIR_SOURCE_SCOPE_DRIFT'}}
        $nodes.Add($node)
        # A short write/test chain has at most two receipts per granted repair,
        # plus its initial write and final test. This is derived from the grant.
        if([int64]$nodes.Count-gt(2*[int64]$limit+2)){throw 'SELF_REPAIR_CHAIN_EXCEEDS_GRANT'}
        if($authority.continuationReceiptPath-ceq'NOT_REQUIRED'){
            if($authority.continuationReceiptIdentity-cne'NOT_REQUIRED'-or$node.completedStepIndex-ne0){throw 'SELF_REPAIR_CHAIN_ORIGIN'}
            break
        }
        $previousRef=[pscustomobject]@{path=$authority.continuationReceiptPath;identity=$authority.continuationReceiptIdentity}
        if($previousRef.path-ceq$sourceRef.path){throw 'SELF_REPAIR_REFERENCE_CYCLE'}
        $node=Read-EvRef $Context $previousRef -Json
    }
    $previous=$null;$cycle=Get-AiwSelfRepairOriginCycle $Context $Package
    for($i=$nodes.Count-1;$i-ge0;$i--){
        $node=$nodes[$i];$completed=[int]$node.completedStepIndex;$next=[int]$node.nextStepIndex
        if($completed-lt0-or$completed-ge$Package.continuationPlan.Count-or$next-lt0-or$next-ge$Package.continuationPlan.Count-or$node.completedAction-cne$Package.continuationPlan[$completed]-or$node.nextAction-cne$Package.continuationPlan[$next]){throw 'SELF_REPAIR_STEP_DRIFT'}
        if($null-ne$previous-and$previous.nextStepIndex-ne$completed){throw 'SELF_REPAIR_PREDECESSOR_STEP'}
        if($node.transitionKind-ceq'ADVANCE'){
            if($next-ne($completed+1)){throw 'SELF_REPAIR_STEP_DRIFT'}
        }else{
            if($null-eq$previous-or$completed-ne1-or$node.completedAction-cne'TEST_RUN'-or($node.transitionKind-ceq'REPAIR'-and$next-ne0)-or($node.transitionKind-ceq'RETEST'-and$next-ne1)){throw 'SELF_REPAIR_BRANCH_ORDER'}
            $cycle++
        }
        if($node.selfRepairCycle-ne$cycle-or$cycle-gt$limit){throw 'SELF_REPAIR_CYCLE'}
        if($node.completedAction-ceq'TEST_RUN'){
            if($null-eq$previous){throw 'SELF_REPAIR_TEST_PREDECESSOR'}
            $candidates=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@($node.postObjectIdentities|Where-Object{$_.path-cin$Package.exactPaths})}))
            $priorCandidates=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@($previous.postObjectIdentities|Where-Object{$_.path-cin$Package.exactPaths})}))
            Assert-EvSameCandidates $candidates $priorCandidates $Context
            $outcome=Get-AiwContinuationSelfCheckOutcome $Context $node.evidenceRefs $Package.taskId $candidates $Package.grantee -FrozenCandidateEvidence
            if($node.transitionKind-cin@('REPAIR','RETEST')-and$outcome-cne'FAIL'){throw 'SELF_REPAIR_ACTUAL_FAILURE_REQUIRED'}
            if($node.transitionKind-ceq'ADVANCE'-and($outcome-ceq'INCOMPLETE'-or($node.nextAction-ceq'REVIEW_ROUTE'-and$outcome-cne'PASS'))){throw 'SELF_REPAIR_SUCCESSOR_OUTCOME'}
        }
        if($node.nextAction-ceq'REVIEW_ROUTE'){
            if($node.completedAction-cne'TEST_RUN'-or$node.transitionKind-cne'ADVANCE'-or$outcome-cne'PASS'){throw 'SELF_REPAIR_REVIEW_PREDECESSOR'}
            # Source/authority/target, predecessor M and original typed SELF/raw
            # have now been checked. Historical M may have been legally repaired.
            $production=@($node.postObjectIdentities|Where-Object{$_.path-cin$Package.exactPaths})
            $composed=@(Get-EvReviewCandidateMembers @($Package.exactPaths) @(Get-AiwPlannedReviewScope $Package $Context) $production)
            if((@($composed|ForEach-Object{$_.path+'='+$_.identity}|Sort-Object)-join'|')-cne(@($node.postObjectIdentities|ForEach-Object{$_.path+'='+$_.identity}|Sort-Object)-join'|')){throw 'SELF_REPAIR_REVIEW_CANDIDATE_DRIFT'}
            foreach($row in $composed){
                if($row.path-cin$Package.exactPaths){$null=Resolve-EvPath $Context $row.path -Candidate}
                else{$null=Read-EvRef $Context ([pscustomobject]@{path=$row.path;identity=$(if($row.identity-ceq'NEW'){'MISSING'}else{$row.identity})}) -Candidate}
            }
        }
        $previous=$node
    }
    return $cycle
}
function Get-AiwBoundaryEvidence($Receipt,$Boundary,$EvidenceContext=$null) {
    $refs=@()
    if($null-ne$Boundary.PSObject.Properties['evidenceRefs']){$refs=$Boundary.evidenceRefs}
    Assert-EvRefs $refs -Typed
    $closurePaths=@()
    if($Boundary.mode-ceq'FINALIZE_OUTPUT'-and$Receipt.actionKind-ceq'CONTROL_WRITE'){$closurePaths=@($Receipt.exactPaths|Where-Object{$_-cmatch '^\.ai-workspace/tasks/(active|archive)/[^/]+\.md$'})}
    $isClosure=$closurePaths.Count-gt0
    $skipTypedEvidence=$refs.Count-eq0-and$Receipt.actionKind-cnotin@('REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','TEST_RUN')-and-not$isClosure
    $package=$null
    if($Receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
        if($null-ne$EvidenceContext){$package=Read-EvRef $EvidenceContext ([pscustomobject]@{path=$Receipt.sourceLocators.authorizationPackagePath;identity=$Receipt.authorityContext.authorizationIdentity}) -Json}
        else{$package=ConvertFrom-EvJson ([IO.File]::ReadAllText($Receipt.sourceLocators.authorizationPackagePath))}
    }
    $protectedScope=if($null-ne$Receipt.authorityContext.PSObject.Properties['protectedScope']){$Receipt.authorityContext.protectedScope}else{@()}
    $archiveObservation=Get-EvTaskArchiveObservation $Receipt $Boundary
    $actualTaskPath=if($null-ne$archiveObservation){$archiveObservation.TaskRelativePath}else{$Receipt.sourceLocators.taskRelativePath}
    # Nested delivery supplies its already guarded original-root context.
    # Ordinary callers retain their current receipt-derived context.
    $ctx=if($null-ne$EvidenceContext){$EvidenceContext}else{New-AiwPackageEvidenceContext $Receipt.sourceLocators.projectRoot $package $Receipt.sourceLocators.frameworkRoot $Receipt.authorityContext.forbiddenScope -TaskPath $actualTaskPath -ProtectedPaths $protectedScope}
    # Empty typed evidence still hands the last consumer the original full path guard.
    $retentionContext=$ctx|Select-Object *
    $retentionContext.ForbiddenPaths=@(@($ctx.ForbiddenPaths)+@($ctx.CandidateProtectedPaths)|Select-Object -Unique)
    if($skipTypedEvidence){return [pscustomobject]@{references=@();records=@();evidenceCeiling='INSTRUCTION_BOUND';retentionValues=@();retentionContext=$retentionContext}}
    $taskText='';$plan=$null
    if($Receipt.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'){
        Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
        $taskText=(Read-AiwControlTransitionTask $ctx.ProjectRoot $actualTaskPath).Text
        $plan=Get-AiwAcceptancePlan $taskText
    }
    # Reuse the actual plans selected/validated here for last-consumer retention.
    # This is an in-memory handoff, not another closure validator or saved proof.
    $retentionValues=[Collections.Generic.List[object]]::new()
    if($null-ne$plan){$retentionValues.Add($plan)}
    $records=@();$candidateObjects=@()
    if($null-ne$package-and($refs.Count-gt0-or$Receipt.actionKind-ceq'REVIEW_ROUTE')){
        foreach($path in $Receipt.exactPaths){
            $full=Resolve-EvPath $ctx $path -Candidate
            $candidateObjects+=[pscustomobject]@{path=$path;identity=(Get-EvCandidateIdentity $full)}
        }
    }
    $needed=if($Boundary.mode-ceq'ADMIT_ACTION'-and$Receipt.actionKind-ceq'REVIEW_ROUTE'-and(Test-AiwReviewSelfCheckRequired $plan)){'SELF_CHECK'}elseif($Boundary.mode-ceq'FINALIZE_OUTPUT'){
        switch($Receipt.actionKind){'TEST_RUN'{'SELF_CHECK'};'REVIEW_EXECUTE'{'REVIEW_VERDICT'};'RESULT_ACCEPT'{'RESULT_ACCEPTANCE'};default{''}}
    }else{''}
    if($needed-and@($refs|Where-Object{$_.kind-ceq$needed}).Count-eq0){throw ('TYPED_EVIDENCE_REQUIRED|'+$needed)}
    foreach($ref in $refs){
        $raw=Read-EvRef $ctx ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $requirements=$raw.requirementsRef
        if($null-ne$package-and$null-ne$package.PSObject.Properties['acceptanceBinding']){$requirements=$package.acceptanceBinding.requirementsRef}
        $expectedActor=if($Boundary.mode-ceq'FINALIZE_OUTPUT'-and$ref.kind-ceq$needed){[string]$Receipt.actor}else{''}
        $auth=if($ref.kind-cin@('REVIEW_VERDICT','RESULT_ACCEPTANCE')-and$ref.kind-ceq$needed){[string]$Receipt.authorityContext.authorizationIdentity}else{''}
        $records+=Read-AiwResultEvidence $ctx $ref $Receipt.taskId $candidateObjects $requirements -ExpectedActor $expectedActor -AuthorizationIdentity $auth
    }
    if($Receipt.actionKind-ceq'TEST_RUN'-and$Boundary.mode-ceq'FINALIZE_OUTPUT'){
        foreach($record in $records){if(@($record.checks|Where-Object{$_.method-ceq'COMMAND'}).Count-eq0){throw 'TEST_RUN_COMMAND_REQUIRED'}}
    }
    if($null-ne$Boundary.PSObject.Properties['productionFinalizeRef']-and($Receipt.actionKind-cne'REVIEW_ROUTE'-or(Test-AiwReviewSelfCheckRequired $plan))){throw 'QUALITY_PRODUCTION_REF_BOUNDARY'}
    if($Receipt.actionKind-ceq'REVIEW_ROUTE'){
        if($null-ne$plan-and$plan.schemaVersion-eq2){
            $reviewStages=@($plan.stages|Where-Object{$_.kind-ceq'RESULT_REVIEW'})
            if('RESULT_REVIEW'-cin$plan.qualityBinding.effectiveStages-and$reviewStages.Count-eq0){throw 'QUALITY_PLAN_STAGE_MISSING'}
            foreach($stage in $reviewStages){
                if($stage.candidateRef.Count-eq0){throw 'QUALITY_REVIEW_CANDIDATE_REQUIRED'}
                Assert-EvSameCandidates $stage.candidateRef $candidateObjects $ctx
                $null=Read-EvRef $ctx $stage.requiredBy -Section
            }
        }
        if(Test-AiwReviewSelfCheckRequired $plan){if($Boundary.mode-ceq'ADMIT_ACTION'){Assert-AiwReviewSelfCheck $ctx $refs $Receipt.taskId $candidateObjects $plan}}
        else{
            $null=Get-AiwPackageQuality $ctx $package $plan
            if($null-eq$Boundary.PSObject.Properties['productionFinalizeRef']){throw 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'}
            $writer=''
            if($null-ne$package.PSObject.Properties['repairReviewPlan']){$writer=$package.repairReviewPlan.writer}
            if($null-ne$Boundary.PSObject.Properties['deliveryContext']-and$null-ne$Boundary.deliveryContext.PSObject.Properties['reviewPackageRef']){$reviewPackage=Read-EvRef $ctx $Boundary.deliveryContext.reviewPackageRef -Json;$writer=$reviewPackage.candidateWriter}
            if(-not$writer){throw 'QUALITY_PRODUCTION_WRITER_REQUIRED'}
            $null=Assert-AiwProductionFinalize $ctx $Boundary.productionFinalizeRef $package $candidateObjects $writer
        }
    }
    if($Receipt.actionKind-ceq'RESULT_ACCEPT'){
        Assert-AiwAcceptanceBinding $ctx $package $plan
        if($package.grantee-cne$package.owner-and$package.issuer-cne$package.owner-and$Boundary.publicDecisionIdentity-cne$package.userConfirmation){throw 'RESULT_ACCEPT_CURRENT_USER_DECISION_UNBOUND'}
    }
    # Closing SUCCESS checks the entire plan; internal acceptance checked only
    # its dependency closure. Later user gates never become implicit predecessors.
    foreach($closedPath in $closurePaths){
        $closedFull=Resolve-EvPath $ctx $closedPath -Candidate
        if((Get-EvCandidateIdentity $closedFull)-ceq'MISSING'){
            # Deleting an admitted active card transfers its closure check to
            # the same task's real archive; absence alone is never acceptance.
            if($closedPath-cnotmatch'^\.ai-workspace/tasks/active/(?<name>[^/]+)\.md$'){throw 'ACCEPTANCE_ARCHIVE_DELETE_SCOPE'}
            $name=$Matches.name;$archivePath='.ai-workspace/tasks/archive/'+$name+'.md'
            $preimages=@($package.objectIdentities|Where-Object{$_.path-ceq$closedPath})
            if($preimages.Count-ne1-or$preimages[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACCEPTANCE_ARCHIVE_DELETE_PREIMAGE'}
            if(@($Boundary.resultReceipts|Where-Object{$_-ceq('OBJECT_POSTIMAGE|'+$closedPath+'|MISSING')}).Count-ne1){throw 'ACCEPTANCE_ARCHIVE_DELETE_POSTIMAGE'}
            $postimages=@(Get-AiwFinalizedObjectPostimages $Boundary @($Receipt.exactPaths))
            $archivePost=@($postimages|Where-Object{$_.path-ceq$archivePath})
            if($archivePath-cnotin$closurePaths-or$archivePost.Count-ne1-or$archivePost[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'ACCEPTANCE_ARCHIVE_TARGET_REQUIRED'}
            $archiveFull=Read-EvRef $ctx $archivePost[0] -Candidate
            $archiveText=[IO.File]::ReadAllText($archiveFull)
            $archiveIds=[regex]::Matches($archiveText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
            if($archiveIds.Count-ne1){throw 'ACCEPTANCE_ARCHIVE_TASK_ID'}
            if($archiveText-cnotmatch'(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){throw 'ACCEPTANCE_ARCHIVE_NOT_CLOSED'}
            if($closedPath-ceq$Receipt.sourceLocators.taskRelativePath){
                if($null-eq$archiveObservation-or$archiveIds[0].Groups['id'].Value-cne$Receipt.taskId){throw 'ACCEPTANCE_ARCHIVE_TASK_ID'}
            }elseif($archivePost[0].identity-cne$preimages[0].identity){
                # Other closed-card moves preserve original bytes and their real
                # body ID. A filename cannot authenticate a changed task body.
                throw 'ACCEPTANCE_ARCHIVE_PREIMAGE_DRIFT'
            }
            continue # The archive path below still consumes the full acceptance plan.
        }
        $closedText=[IO.File]::ReadAllText($closedFull)
        if($closedText-cnotmatch '(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){continue}
        $closedIds=[regex]::Matches($closedText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
        if($closedIds.Count-ne1){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        Assert-AiwTaskClosure $ctx $closedText $closedIds[0].Groups['id'].Value $Boundary -ExcludedReviewActors @($package.issuer)
        # Cancellation/supersession may legally have no acceptance plan. Keep
        # the real decision reference already consumed by the closure validator.
        foreach($decision in [regex]::Matches($closedText,'(?m)^- Closure decision: (?<path>.+)#(?<identity>\d+\|[A-F0-9]{64})[ \t]*$')){$retentionValues.Add([pscustomobject]@{path=$decision.Groups['path'].Value;identity=$decision.Groups['identity'].Value})}
        $closedPlan=Get-AiwAcceptancePlan $closedText
        if($null-ne$closedPlan){$retentionValues.Add($closedPlan)}
    }
    return [pscustomobject]@{references=@($refs);records=@($records);evidenceCeiling='INSTRUCTION_BOUND';retentionValues=@($retentionValues.ToArray());retentionContext=$retentionContext}
}
function Assert-AiwPushAcceptance($Context,$Reference,[string]$TaskId,$Candidates,[string]$Commit,[switch]$RequireReview,[string[]]$ExcludedReviewActors=@()) {
    $raw=Read-EvRef $Context ([pscustomobject]@{path=$Reference.path;identity=$Reference.identity}) -Json
    $consumption=Get-EvConsumption $null ''
    if($null-ne$Context.PSObject.Properties['TaskPath']-and$Context.TaskPath){
        $task=Resolve-EvPath $Context $Context.TaskPath
        $plan=Get-AiwAcceptancePlan ([IO.File]::ReadAllText($task))
        if($null-ne$plan-and$plan.schemaVersion-eq2){
            $stages=@($plan.stages|Where-Object{$_.kind-ceq'RESULT_ACCEPT'-and(Test-EvSameCandidates $_.candidateRef $Candidates $Context)-and@($_.evidenceRefs|Where-Object{Test-EvSameRef $_ $Reference $Context}).Count-eq1})
            if($stages.Count-ne1){throw 'PUSH_ACCEPTANCE_STAGE_UNBOUND'}
            $consumption=Get-EvConsumption $stages[0] evidenceConsumption
            if($consumption.purpose-cne'HISTORICAL_SUCCESS'){throw 'PUSH_ORIGINAL_ACCEPTANCE_FINALIZE_REQUIRED'}
        }
    }
    $record=Read-AiwResultEvidence $Context $Reference $TaskId $Candidates $raw.requirementsRef -RequireSuccess -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize -PrerequisiteEvidencePurpose $consumption.purpose
    if($null-eq$record.PSObject.Properties['acceptedCommit']-or$record.acceptedCommit-cne$Commit){throw 'PUSH_ACCEPTED_COMMIT_DRIFT'}
    if($RequireReview){
        $package=Read-EvRef $Context $record.authorizationRef -Json
        if($null-eq$package.PSObject.Properties['acceptanceBinding']){throw 'PUSH_REVIEW_UNBOUND'}
        $refs=@($package.acceptanceBinding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq'REVIEW_VERDICT'})
        if($refs.Count-eq0){throw 'PUSH_REVIEW_UNBOUND'}
        foreach($ref in $refs){$null=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $record.requirementsRef -RequireSuccess -RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize}
    }
}
function Resolve-AiwEvidenceObservationPath($Context,[string]$Path) {
    Resolve-EvPath $Context $Path -AllowMissing -AllowDirectory
}
function Read-AiwEvidenceReference($Context,$Reference,[switch]$Json,[switch]$Candidate) {
    Read-EvRef $Context $Reference -Json:$Json -Candidate:$Candidate
}
Export-ModuleMember -Function Resolve-AiwEvidenceObservationPath,New-AiwEvidenceContext,New-AiwPackageEvidenceContext,Get-AiwPackageCandidateReferences,Read-AiwEvidenceReference,Read-AiwResultEvidence,Get-AiwAcceptancePlan,Assert-AiwAcceptanceStages,Assert-AiwAcceptanceBinding,Assert-AiwReviewSelfCheck,Get-AiwBoundaryEvidence,Assert-AiwPushAcceptance,Get-AiwSelfCheckOutcome,Get-AiwContinuationSelfCheckOutcome,Assert-AiwSelfRepairChain,Get-AiwPlannedReviewScope,Get-AiwActionScopeObjects,Get-AiwComposedReviewCandidate,Get-AiwFinalizedObjectPostimages

function Get-AiwPackageQuality($Context,$Package,$Plan=$null,[switch]$Management,[switch]$Historical,[switch]$RequirePlan){
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    $legacy=[pscustomobject]@{mode='LEGACY';effectiveStages=@();qualityBinding=$null}
    $hasBinding=$null-ne$Package-and$null-ne$Package.PSObject.Properties['qualityBinding']
    $special=$null-ne$Package-and$Package.schemaVersion-eq3
    foreach($name in @('transitionPlan','sourcePublicationBinding','externalBinding')){if($null-ne$Package-and$null-ne$Package.PSObject.Properties[$name]){$special=$true}}
    if($special){if($hasBinding){throw 'QUALITY_SPECIAL_BINDING_FORBIDDEN'};return $legacy}
    if($Historical){
        # Only the original-success verifier may call this after verifying its
        # DISCOVER/package/policy linkage. It never reads today's active policy.
        if(-not$hasBinding){return $legacy}
        Assert-AiwQualityBinding $Package.qualityBinding
        return [pscustomobject]@{mode='EXPLICIT';effectiveStages=@($Package.qualityBinding.effectiveStages);qualityBinding=$Package.qualityBinding}
    }
    $policyPath=Resolve-EvPath $Context '.ai-workspace/process-policy.json' -AllowMissing
    if(-not[IO.File]::Exists($policyPath)){if($hasBinding-or($null-ne$Plan-and$Plan.schemaVersion-eq2)){throw 'QUALITY_POLICY_MISSING'};return $legacy}
    $policyRef=[pscustomobject]@{path=$policyPath;identity=(Get-EvCandidateIdentity $policyPath)}
    $policy=Read-EvRef $Context $policyRef -Json
    Assert-AiwQualityPolicy $policy
    if($null-eq$policy.PSObject.Properties['qualityAssurance']){
        if($hasBinding-or($null-ne$Plan-and$Plan.schemaVersion-eq2)){throw 'QUALITY_POLICY_DISABLED_REBIND'}
        return $legacy
    }
    Import-Module (Join-Path $PSScriptRoot 'ObjectFormats.psm1')
    $null=Read-AiwCurrentObject PROCESS_POLICY $policyPath $policyRef.identity ([pscustomobject]@{ForbiddenPaths=@($Context.ForbiddenPaths)})
    $reader=$null-ne$Package-and$Package.actions.Count-eq1-and$Package.actions[0]-ceq'NONE'
    if(($reader-or($Management-and-not$RequirePlan))-and-not$hasBinding-and($null-eq$Plan-or$Plan.schemaVersion-eq1)){return [pscustomobject]@{mode=$(if($reader){'READ_ONLY'}else{'MANAGEMENT'});effectiveStages=@();qualityBinding=$null}}
    if($null-eq$Plan-or$Plan.schemaVersion-ne2){throw 'QUALITY_PLAN_REQUIRED'}
    Assert-AiwQualityBinding $Plan.qualityBinding
    $selection=Get-AiwQualitySelection $policy $policyRef.identity $Package.profile $Plan.qualityBinding.subject
    if((Get-AiwQualityBindingKey $selection.qualityBinding)-cne(Get-AiwQualityBindingKey $Plan.qualityBinding)){throw 'QUALITY_PLAN_DRIFT'}
    if(-not$Management-and-not$hasBinding){throw 'QUALITY_BINDING_REQUIRED'}
    if($hasBinding-and(Get-AiwQualityBindingKey $Package.qualityBinding)-cne(Get-AiwQualityBindingKey $Plan.qualityBinding)){throw 'QUALITY_BINDING_DRIFT'}
    $repo=if($Package.schemaVersion-in@(2,4)){$Package.repositoryId}else{'REPO_LOCAL'}
    if(-not$Management-and$Plan.qualityBinding.subject.repositoryId-cne$repo){throw 'QUALITY_SUBJECT_REPOSITORY_DRIFT'}
    if(-not$Management){
        foreach($path in $Package.exactPaths){if($path-cnotin$Plan.qualityBinding.subject.exactPaths){throw 'QUALITY_SCOPE_OUTSIDE_SUBJECT'}}
        $subjectPaths=@($Plan.qualityBinding.subject.exactPaths|Sort-Object -CaseSensitive)
        foreach($path in $subjectPaths){$null=Resolve-EvPath $Context $path -Candidate -AllowMissing}
        foreach($action in @($Package.actions|Where-Object{$_-cin@('REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','PUSH')})){
            $fullScope=@(Get-AiwActionScopeObjects $Package $action $Context)
            if((@($fullScope.path|Sort-Object -CaseSensitive)-join'|')-cne($subjectPaths-join'|')){throw 'QUALITY_SUBJECT_INCOMPLETE'}
        }
        foreach($stage in @($Plan.stages|Where-Object{$_.kind-cin$selection.effectiveStages-and$_.candidateRef.Count})){
            $paths=@(foreach($ref in $stage.candidateRef){$full=Resolve-EvPath $Context $ref.path -Candidate -AllowMissing;[IO.Path]::GetRelativePath($Context.RepositoryRoot,$full).Replace('\','/')})
            if((@($paths|Sort-Object -CaseSensitive)-join'|')-cne($subjectPaths-join'|')){throw 'QUALITY_STAGE_SUBJECT_INCOMPLETE'}
        }
    }
    return $selection
}
function Test-AiwQualityManagementPackage($Package,[string]$TaskPath){
    if($Package.schemaVersion-notin@(1,2)-or($Package.schemaVersion-eq2-and$Package.repositoryId-cne'CONTROL')-or$Package.actions.Count-ne1-or$Package.actions[0]-cne'CONTROL_WRITE'){return $false}
    foreach($field in @('continuationPlan','repairReviewPlan','repairReviewBinding','acceptanceBinding','externalBinding','gitPushBinding')){if($null-ne$Package.PSObject.Properties[$field]){return $false}}
    if($Package.exactPaths.Count-eq1-and$Package.exactPaths[0]-ceq$TaskPath){return $true}
    if($TaskPath-cmatch'^\.ai-workspace/tasks/active/(?<name>[^/]+)\.md$'-and$Package.exactPaths.Count-eq2-and$TaskPath-cin$Package.exactPaths-and('.ai-workspace/tasks/archive/'+$Matches.name+'.md')-cin$Package.exactPaths){return $true}
    # This is the original bounded source-maintenance carrier set. Original
    # PREPARE/current checker/ADMIT/postimage re-composition still apply.
    $carriers=@('AGENTS.md','.ai-workspace/BOOTSTRAP.md','.ai-workspace/project.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json')
    return $Package.exactPaths.Count-gt0-and@($Package.exactPaths|Where-Object{$_-cnotin$carriers}).Count-eq0
}
function Test-AiwPackageReviewRequired($Package,[switch]$ExplicitRequirement){
    if($ExplicitRequirement){return $true}
    if($null-ne$Package.PSObject.Properties['qualityBinding']){
        if($Package.schemaVersion-eq3-or@(@('transitionPlan','sourcePublicationBinding','externalBinding')|Where-Object{$null-ne$Package.PSObject.Properties[$_]}).Count){throw 'QUALITY_SPECIAL_BINDING_FORBIDDEN'}
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
        Assert-AiwQualityBinding $Package.qualityBinding
        return 'RESULT_REVIEW'-cin$Package.qualityBinding.effectiveStages
    }
    return $Package.profile-ceq'CRITICAL'
}
function Assert-AiwProductionFinalize($Context,$Pair,$Package,$Candidates,[string]$Writer){
    Assert-EvFields $Pair @('inputRef','resultRef');Assert-EvRef $Pair.inputRef;Assert-EvRef $Pair.resultRef
    $input=Read-EvRef $Context $Pair.inputRef -Json;$result=Read-EvRef $Context $Pair.resultRef -Json
    if($input.schemaVersion-ne3-or$input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'}
    $source=Read-EvRef $Context ([pscustomobject]@{path=$input.discoverReceiptPath;identity=$input.expectedDiscoverReceiptIdentity}) -Json
    if($source.schemaVersion-notin@(3,4)-or$source.mode-cne'DISCOVER'-or$source.status-cne'PASS'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'){throw 'QUALITY_PRODUCTION_DISCOVER_REQUIRED'}
    $a=$source.binding;$action=$source.intentEnvelope.requestedActionKind
    $producer=Read-EvRef $Context ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity}) -Json
    if($action-cnotin@('SOURCE_WRITE','TEST_WRITE','CONTROL_WRITE','TEST_RUN')-or$action-cnotin$producer.actions-or$action-cnotin$a.authorizedActions-or$producer.grantee-cne$Writer-or$a.actor-cne$Writer-or$producer.taskId-cne$Package.taskId-or$a.taskId-cne$Package.taskId-or$producer.owner-cne$Package.owner-or$a.taskOwner-cne$Package.owner-or$a.taskIdentity-cne$producer.taskIdentity-or$a.projectConfigIdentity-cne$producer.projectConfigIdentity-or$a.userDecision-cne$producer.userConfirmation){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-ceq'TASK_OWNER'-and$producer.issuer-cne$producer.owner){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-ceq'PROJECT_CONTROLLER'-and($producer.issuer-cne$producer.issuerControllerId-or$a.controllerIdentity-cne$producer.controllerControlIdentity-or$producer.issuerControllerEpoch-lt1)){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-cnotin@('TASK_OWNER','PROJECT_CONTROLLER')){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($result.actionOutcome-cne$(if($action-ceq'TEST_RUN'){'PASS'}else{'OBSERVED'})){throw 'QUALITY_PRODUCTION_NOT_SUCCESSFUL'}
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    if($result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $source $input)-or$result.selectionIdentity-cne$source.selectionIdentity){throw 'QUALITY_PRODUCTION_FINALIZE_DRIFT'}
    if(-not([IO.Path]::GetFullPath($a.projectRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_PRODUCTION_ROOT_DRIFT'}
    $guard=New-AiwPackageEvidenceContext $Context.ProjectRoot $producer $source.sourceLocators.frameworkRoot (@($Context.ForbiddenPaths)+@($a.forbiddenScope)) -TaskPath $source.sourceLocators.taskRelativePath -ProtectedPaths (@($Context.CandidateProtectedPaths)+@($a.protectedScope))
    if(-not$guard.RepositoryRoot.Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_PRODUCTION_REPOSITORY_DRIFT'}
    $scope=@(Get-AiwActionScopeObjects $producer $action $guard)
    if((@($scope.path|Sort-Object)-join'|')-cne(@($a.exactScope|Sort-Object)-join'|')){throw 'QUALITY_PRODUCTION_SCOPE_DRIFT'}
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwFinalizedObjectPostimages $input @($a.exactScope))}))
    if($null-ne$producer.PSObject.Properties['qualityBinding']){
        Assert-AiwQualityBinding $producer.qualityBinding
        if($producer.qualityBinding.policyRef.identity-cne$source.sourceBindings.policyIdentity){throw 'QUALITY_HISTORICAL_POLICY_UNBOUND'}
        $producerRepository=if($producer.schemaVersion-in@(2,4)){$producer.repositoryId}else{'REPO_LOCAL'}
        if($producer.qualityBinding.subject.repositoryId-cne$producerRepository){throw 'QUALITY_HISTORICAL_SUBJECT_DRIFT'}
        $declared=@($producer.qualityBinding.subject.exactPaths|Sort-Object -CaseSensitive)
        if(($declared-join'|')-cne(@($Candidates.path|Sort-Object -CaseSensitive)-join'|')){throw 'QUALITY_SUBJECT_INCOMPLETE'}
        foreach($modified in $post){$member=@($Candidates|Where-Object path -CEQ $modified.path);if($member.Count-ne1-or$member[0].identity-cne$modified.identity){throw 'QUALITY_PRODUCTION_POSTIMAGE_DRIFT'}}
        # The original package binds the complete declared A. Its actual F
        # proves M; the current fresh review package freezes and guards all A.
        # Existing explicit M/A plans retain their stronger unchanged-member
        # bindings. No write authority is inferred for those other members.
        $parent=Get-EvReviewParent $guard $producer
        $complete=if($null-ne$parent.PSObject.Properties['repairReviewPlan']){@(Get-AiwComposedReviewCandidate $guard $producer $post)}else{@($Candidates)}
    }else{$complete=@(Get-AiwComposedReviewCandidate $guard $producer $post)}
    Assert-EvSameCandidates $complete $Candidates $guard
    foreach($ref in $Candidates){$null=Read-EvRef $guard $ref -Candidate}
    $typedPrep=@();$typedResult=@()
    foreach($ref in $input.evidenceRefs){
            $raw=Read-EvRef $guard ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            $purpose=if($ref.kind-ceq'SELF_CHECK'){'HISTORICAL_SUCCESS'}else{'CURRENT_CANDIDATE'}
            $history=if($purpose-ceq'HISTORICAL_SUCCESS'){@($Pair)}else{@()}
            $null=Read-AiwResultEvidence $guard $ref $producer.taskId $raw.candidateObjects $raw.requirementsRef -RequireSuccess -ExpectedActor $(if($ref.kind-ceq'SELF_CHECK'){$Writer}else{''}) -EvidencePurpose $purpose -OriginalFinalize $history
            switch($ref.kind){SELF_CHECK{$typedPrep+='SELF_CHECK_BOUND'};REVIEW_VERDICT{$typedResult+='REVIEW_VERDICT_BOUND'};RESULT_ACCEPTANCE{$typedResult+='RESULT_ACCEPT_RECORDED'}}
    }
    $providedPreparation=@($input.preparationReceipts)+$typedPrep
    $providedResult=@($input.resultReceipts)+$typedResult
    foreach($obligation in $source.selectedObligations){
        if(@($obligation.preparationRequirements|Where-Object{$_-cnotin$providedPreparation}).Count-or@($obligation.resultRequirements|Where-Object{$_-cnotin$providedResult}).Count){throw 'QUALITY_PRODUCTION_FINALIZE_INCOMPLETE'}
    }
    if($action-ceq'TEST_RUN'){
        $self=@($input.evidenceRefs|Where-Object{$_.kind-ceq'SELF_CHECK'})
        if($self.Count-eq0){throw 'QUALITY_PRODUCTION_TEST_SELF_REQUIRED'}
        foreach($ref in $self){
            $record=Read-EvRef $guard ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            Assert-EvSameCandidates $record.candidateObjects $post $guard
            if($record.actor-cne$Writer-or$record.outcome-cne'PASS'-or@($record.checks|Where-Object{$_.method-ceq'COMMAND'}).Count-eq0){throw 'QUALITY_PRODUCTION_TEST_NOT_SUCCESSFUL'}
        }
    }
    [pscustomobject]@{writer=$Writer;source=$source;package=$producer;postimages=$complete;input=$input;result=$result}
}
Export-ModuleMember -Function Get-AiwPackageQuality,Test-AiwQualityManagementPackage,Test-AiwPackageReviewRequired,Assert-AiwProductionFinalize

function Test-AiwReviewSelfCheckRequired($Plan){
    if($null-eq$Plan-or$Plan.schemaVersion-eq1){return $true}
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    Assert-AiwQualityBinding $Plan.qualityBinding
    return 'SELF_CHECK'-cin$Plan.qualityBinding.effectiveStages-or@($Plan.stages|Where-Object{$_.kind-ceq'SELF_CHECK'}).Count-gt0
}
Export-ModuleMember -Function Test-AiwReviewSelfCheckRequired

function Get-AiwCurrentCandidateReferences($Context,[string[]]$Paths){
    foreach($path in $Paths){
        $full=Resolve-EvPath $Context $path -Candidate -AllowMissing
        [pscustomobject]@{path=$path;identity=(Get-EvCandidateIdentity $full)}
    }
}
Export-ModuleMember -Function Get-AiwCurrentCandidateReferences
