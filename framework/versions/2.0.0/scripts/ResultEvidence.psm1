# Shared by the structural card checker and semantic result consumers. Only
# line interpretation is normalized; callers retain original bytes/identities.
function Get-AiwTaskClosureFields([string]$Text,[switch]$RequireComplete){
    $lines=$Text.Replace("`r`n","`n").Replace("`r","`n")
    if($lines-cnotmatch'(?m)^- Range summary:[^\n]*lifecycle=CLOSED;'){throw 'ACCEPTANCE_CLOSE_NOT_CLOSED'}
    $canonical=@('Closure basis','Output disposition','Git disposition','Unresolved obligations','Writer','Reviewer','Authorization')
    $legacy=@('Closure evidence','Artifact disposition','Remaining obligations','Writer / reviewer / authorization')
    $values=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($name in @('Closure outcome','Closure decision','Unfinished work')+$canonical+$legacy){
        $entries=[regex]::Matches($lines,('(?m)^- '+[regex]::Escape($name)+':[ \t]*(?<value>[^\n]*)$'))
        if($entries.Count-gt1){throw ('ACCEPTANCE_CLOSE_FIELD|'+$name)}
        if($entries.Count-eq0){continue}
        $value=$entries[0].Groups['value'].Value.Trim()
        if([string]::IsNullOrWhiteSpace($value)-or$value.StartsWith('<')-or$value-cmatch'^(PENDING|WAITING|BLOCKED|NOT_DELIVERED)$'){throw ('ACCEPTANCE_CLOSE_FIELD|'+$name)}
        $values.Add($name,$value)
    }
    $hasCanonical=@($canonical|Where-Object{$values.ContainsKey($_)}).Count-gt0
    $hasLegacy=@($legacy|Where-Object{$values.ContainsKey($_)}).Count-gt0
    if($hasCanonical){foreach($name in @('Closure outcome')+$canonical){if(-not$values.ContainsKey($name)){throw ('ACCEPTANCE_CLOSE_FIELD|'+$name)}}}
    if($hasLegacy){foreach($name in $legacy){if(-not$values.ContainsKey($name)){throw ('ACCEPTANCE_CLOSE_FIELD|'+$name)}}}
    if(-not$hasCanonical-and-not$hasLegacy-and($RequireComplete-or$values.ContainsKey('Closure outcome'))){throw 'ACCEPTANCE_CLOSE_FIELD|Closure basis'}
    $outcome=if($values.ContainsKey('Closure outcome')){$values['Closure outcome']}else{'LEGACY_SUCCESS'}
    if($values.ContainsKey('Closure outcome')-and$outcome-cnotin@('SUCCESS','CANCELLED','SUPERSEDED')){throw 'ACCEPTANCE_CLOSE_OUTCOME'}
    if($hasCanonical){
        if($values['Git disposition']-cnotmatch'^(READY|DEFERRED|EXCLUDED)(?:[; :].+)?$'){throw 'ACCEPTANCE_CLOSE_GIT_DISPOSITION'}
        if($values['Unresolved obligations']-cne'NONE'-and$values['Unresolved obligations']-cnotmatch'^TRANSFERRED: .+'){throw 'ACCEPTANCE_CLOSE_OBLIGATION_TRANSFER'}
        foreach($name in @('Writer','Reviewer','Authorization')){if($values[$name]-cne'RELEASED'){throw 'ACCEPTANCE_CLOSE_LEASE_RELEASE'}}
    }
    if($hasLegacy-and$values['Writer / reviewer / authorization']-cne'NONE / NONE / NONE'){throw 'ACCEPTANCE_CLOSE_LEASE_RELEASE'}
    $basis=[Collections.Generic.List[string]]::new();$outputs=[Collections.Generic.List[string]]::new();$obligations=[Collections.Generic.List[string]]::new()
    if($hasCanonical){$basis.Add($values['Closure basis']);$outputs.Add($values['Output disposition']);$obligations.Add($values['Unresolved obligations'])}
    if($hasLegacy){
        $basis.Add($values['Closure evidence']);$outputs.Add($values['Artifact disposition'])
        $oldObligation=$values['Remaining obligations']
        if($oldObligation-cne'NONE'-and-not$oldObligation.StartsWith('TRANSFERRED: ')){$oldObligation='TRANSFERRED: '+$oldObligation}
        if($hasCanonical-and(($oldObligation-ceq'NONE')-ne($values['Unresolved obligations']-ceq'NONE'))){throw 'ACCEPTANCE_CLOSE_OBLIGATION_CONFLICT'}
        if(-not$obligations.Contains($oldObligation)){$obligations.Add($oldObligation)}
    }
    if($outcome-ceq'SUPERSEDED'-and($obligations.Count-eq0-or$obligations.Contains('NONE'))){throw 'ACCEPTANCE_CLOSE_OBLIGATION_TRANSFER'}
    $decision=$null;$unfinished=$null
    if($outcome-cin@('CANCELLED','SUPERSEDED')){
        if(-not$values.ContainsKey('Closure decision')){throw 'ACCEPTANCE_CLOSE_DECISION_REQUIRED'}
        $match=[regex]::Match($values['Closure decision'],'^(?<path>.+)#(?<identity>\d+\|[A-F0-9]{64})$')
        if(-not$match.Success){throw 'ACCEPTANCE_CLOSE_DECISION_REQUIRED'}
        if(-not$values.ContainsKey('Unfinished work')){throw 'ACCEPTANCE_CLOSE_UNFINISHED_WORK_REQUIRED'}
        $decision=[pscustomobject]@{path=$match.Groups['path'].Value;identity=$match.Groups['identity'].Value};$unfinished=$values['Unfinished work']
    }
    $format=if($hasCanonical-and$hasLegacy){'LEGACY_DUAL'}elseif($hasCanonical){'CANONICAL'}elseif($hasLegacy-and$values.ContainsKey('Closure outcome')){'LEGACY_TEMPLATE'}else{'LEGACY_NO_OUTCOME'}
    [pscustomobject]@{Format=$format;Outcome=$outcome;Basis=@($basis.ToArray());OutputDisposition=@($outputs.ToArray());GitDisposition=$(if($hasCanonical){$values['Git disposition']}else{$null});UnresolvedObligations=@($obligations.ToArray());ClosureDecision=$decision;UnfinishedWork=$unfinished}
}
Export-ModuleMember -Function Get-AiwTaskClosureFields
function Assert-EvArchiveClosedRecord([string]$Text){$null=Get-AiwTaskClosureFields $Text -RequireComplete}
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
    # Location is not a second result-acceptance consumer. The dedicated
    # closure pass below owns the finite outcome graph.
    Assert-EvArchiveClosedRecord $document.Text
    return [pscustomobject]@{TaskRelativePath=$archive;Identity=$document.Identity;Text=$document.Text}
}

function Resolve-EvRecordTarget($Context,$Record,[switch]$FrozenCandidateEvidence){
    $hasTarget=$null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext
    if($Record.schemaVersion-eq3){
        if($null-ne$Record.PSObject.Properties['executionTargetRef']-or$null-ne$Record.PSObject.Properties['candidateTargetState']-or($hasTarget-and$Context.ExecutionContext.targetKind-cne'SAME_ROOT')){throw 'EVIDENCE_WORK_TARGET_UNSUPPORTED'}
        return $Context
    }
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
        $nested.Roots=@($Context.Roots+$nested.Roots|Select-Object -Unique);Share-EvReadState $nested $Context
        $nested|Add-Member ExecutionContext $target;$nested|Add-Member TaskPath $Context.TaskPath
        $Context=$nested
    }
    if(-not(Test-EvSameRef $Record.executionTargetRef $Context.ExecutionContext.executionTargetRef $Context)){throw 'EVIDENCE_EXECUTION_TARGET_DRIFT'}
    $null=Assert-AiwExecutionTargetState $Context.ExecutionContext $Record.candidateTargetState
    return $Context
}
function Assert-EvTaskClosureCore($Context,[string]$Text,[string]$TaskId,$Boundary,[switch]$RequireExplicitClosure,[string[]]$ExcludedReviewActors=@()) {
    $Text=$Text.Replace("`r`n","`n").Replace("`r","`n")
    $closure=$null
    if($RequireExplicitClosure-or$Text-cmatch'(?m)^- (?:Closure basis|Output disposition|Unresolved obligations|Closure evidence|Artifact disposition|Remaining obligations):'){
        $closure=Get-AiwTaskClosureFields $Text -RequireComplete:$RequireExplicitClosure
        if($closure.Outcome-cin@('CANCELLED','SUPERSEDED')){
            $decision=Read-EvSupersessionDecision $Context $closure.ClosureDecision
            if($closure.Outcome-ceq'SUPERSEDED'-and$null-ne$decision){
                $source=Read-EvProcessOperation $Context $Boundary
                if($source.binding.taskId-cne$TaskId-or$source.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'){throw 'WORK_PREDECESSOR_CLOSE_BINDING'}
                $null=Get-EvSupersessionFacts $Context $decision $source
            }
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
                $candidateContext=New-AiwPackageEvidenceContext $Context.ProjectRoot $candidatePackage '' $Context.ForbiddenPaths -ProtectedPaths $Context.CandidateProtectedPaths
                Share-EvReadState $candidateContext $Context;$Context=$candidateContext
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
        $userRefs=@(foreach($stage in $closedPlan.stages){if($stage.kind-ceq'USER_DECISION'){foreach($ref in $stage.candidateRef){if($ref.identity-ceq$Boundary.publicDecisionIdentity){$ref}}}})
        $criticalClosure=if($closedPlan.schemaVersion-eq2){'RESULT_REVIEW'-cin$closedPlan.qualityBinding.effectiveStages}else{$Text-cmatch '(?m)^- (?:Profile: CRITICAL;|Range summary: profile=CRITICAL;)'}
        $closedOwner=[regex]::Match($Text,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$').Groups['owner'].Value
        if($closedTaskId-cne$TaskId){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        $excluded=@($closedOwner)+@($ExcludedReviewActors)
        $basis=if($null-ne$closure){@($closure.Basis)}else{@()}
        Assert-EvCompletedStages $Context $closedPlan $closedTaskId $userRefs -RequireIndependentReview:$criticalClosure -ExcludedReviewActors $excluded -ClosureBasis $basis -TaskOwner $closedOwner
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
function Get-EvConfiguredRepositoryRoot([string]$ProjectRoot,[string]$RepositoryId,$Config) {
    if($RepositoryId-ceq'REPO_LOCAL'){
        if($Config.controlPlaneLayout-cne'repo-local'){throw 'EVIDENCE_REPOSITORY_BINDING'}
        return $ProjectRoot
    }
    # CONTROL identifies the bound project control root in both supported layouts.
    # The existing schema2 ordinary/non-Git route does not denote a sibling target.
    if($RepositoryId-ceq'CONTROL'){
        if($Config.controlPlaneLayout-cnotin@('repo-local','framework-maintenance-sibling')){throw 'EVIDENCE_REPOSITORY_BINDING'}
        return $ProjectRoot
    }
    if($Config.controlPlaneLayout-cne'framework-maintenance-sibling'){throw 'EVIDENCE_REPOSITORY_BINDING'}
    if($null-eq$Config.PSObject.Properties['frameworkTarget']-or$Config.frameworkTarget.repositoryId-cne$RepositoryId){throw 'EVIDENCE_REPOSITORY_BINDING'}
    $sibling=[string]$Config.frameworkTarget.siblingDirectory
    if($sibling-cnotmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*$'-or$sibling.EndsWith('.')){throw 'EVIDENCE_REPOSITORY_BINDING'}
    return [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ProjectRoot) $sibling)).TrimEnd('\','/')
}
function Get-EvAbsoluteRestrictions($Paths,$Roots) {
    foreach($path in $Paths){
        Assert-EvString $path
        if([IO.Path]::IsPathFullyQualified($path)){[IO.Path]::GetFullPath($path).TrimEnd('\','/')}
        else{foreach($root in $Roots){[IO.Path]::GetFullPath((Join-Path $root $path)).TrimEnd('\','/')}}
    }
}
# One business read owns this private, in-memory handoff. It is neither a
# caller-supplied success flag nor a persisted producer/cleanup registry.
function Get-EvReadState($Context) {
    if($null-eq$Context.PSObject.Properties['RetentionReadState']){
        $Context|Add-Member RetentionReadState ([pscustomobject]@{producers=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase);guards=[Collections.Generic.List[object]]::new();references=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase);observations=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);captureObservations=$false})
    }
    return $Context.RetentionReadState
}
function Share-EvReadState($Nested,$Context) {
    $Nested.Reading=$Context.Reading
    $Nested|Add-Member RetentionReadState (Get-EvReadState $Context) -Force
}
function Add-EvValidatedProducer($Context,$Pair,$Source,$Input,$Result) {
    $state=Get-EvReadState $Context
    $key=[IO.Path]::GetFullPath($Pair.resultRef.path,$Context.ProjectRoot)+'|'+$Pair.resultRef.identity
    if($state.producers.ContainsKey($key)){return}
    $state.producers.Add($key,[pscustomobject]@{pair=$Pair;source=$Source;input=$Input;result=$Result})
    # Keep only the original path guard, without a back-reference to the read
    # state. Isolated-target protection must still run before metadata reads.
    $state.guards.Add(($Context|Select-Object ProjectRoot,RepositoryRoot,Roots,ForbiddenPaths,CandidateProtectedPaths,ExecutionContext))
}
function Get-EvRetentionHandoff($Context) {
    $state=Get-EvReadState $Context
    $guard=$Context|Select-Object * -ExcludeProperty RetentionReadState,HistoricalProducer
    $roots=@($Context.Roots);$denied=@(Get-EvAbsoluteRestrictions (@($Context.ForbiddenPaths)+@($Context.CandidateProtectedPaths)) $Context.Roots)
    foreach($original in $state.guards){$roots+=@($original.Roots);$denied+=@(Get-EvAbsoluteRestrictions (@($original.ForbiddenPaths)+@($original.CandidateProtectedPaths)) $original.Roots)}
    $guard.Roots=@($roots|Select-Object -Unique);$guard.ForbiddenPaths=@($denied|Select-Object -Unique)
    $historicalGuards=@(foreach($original in $state.guards){if($null-ne$original.ExecutionContext){$copy=$original|Select-Object *;$copy.ForbiddenPaths=$guard.ForbiddenPaths;$copy}})
    $guard|Add-Member HistoricalPathGuards $historicalGuards -Force
    return [pscustomobject]@{context=$guard;producers=@($state.producers.Values);references=@($state.references.Values)}
}
function New-AiwEvidenceContext([string]$ProjectRoot,[string]$RepositoryRoot='', [string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()) {
    # An optional empty list may arrive as null through a PowerShell pipeline.
    # It must not become a null member projected onto the entire bound root.
    if($null-eq$ForbiddenPaths){$ForbiddenPaths=@()}
    if($null-eq$ProtectedPaths){$ProtectedPaths=@()}
    $project=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    if(-not$RepositoryRoot){$RepositoryRoot=$project}
    $repo=[IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    $roots=@($project,$repo);if($FrameworkRoot){$roots+=[IO.Path]::GetFullPath($FrameworkRoot).TrimEnd('\','/')}
    $ctx=[pscustomobject]@{ProjectRoot=$project;RepositoryRoot=$repo;Roots=@($roots|Select-Object -Unique);ForbiddenPaths=@($ForbiddenPaths);CandidateProtectedPaths=@($ProtectedPaths);Reading=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    $excluded=@(Get-EvAbsoluteRestrictions $ForbiddenPaths $ctx.Roots)
    $configPath=Resolve-EvPath $ctx '.ai-workspace/project.json' -AllowMissing
    if(Test-Path -LiteralPath $configPath -PathType Leaf){
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText($configPath))
        if($null-ne$cfg.PSObject.Properties['routineExcludedPaths']){$excluded+=@(Get-EvAbsoluteRestrictions $cfg.routineExcludedPaths @($project))}
        if($null-ne$cfg.PSObject.Properties['frameworkTarget']-and$null-ne$cfg.frameworkTarget.PSObject.Properties['routineExcludedPaths']){
            $targetRoot=Get-EvConfiguredRepositoryRoot $project $cfg.frameworkTarget.repositoryId $cfg
            $excluded+=@(Get-EvAbsoluteRestrictions $cfg.frameworkTarget.routineExcludedPaths @($targetRoot))
        }
    }
    $ctx.ForbiddenPaths=@($excluded|Select-Object -Unique)
    return $ctx
}
function Get-EvLogicalPath($Context,[string]$Path,[switch]$Candidate,[switch]$Observation) {
    Assert-EvString $Path
    if([IO.Path]::IsPathRooted($Path)-and-not[IO.Path]::IsPathFullyQualified($Path)){throw 'EVIDENCE_PATH_INVALID'}
    $value=$Path.Replace('\','/')
    if($value.Contains('//')-or$value-cne$value.Normalize([Text.NormalizationForm]::FormC)-or$value-match '[\x00-\x1f*?]'){throw 'EVIDENCE_PATH_INVALID'}
    foreach($part in $value.Split('/')){
        if($Observation-and-not$Candidate-and$part-in@('.','..')){continue}
        if($part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'EVIDENCE_PATH_INVALID'}
    }
    $base=if($Candidate){$Context.RepositoryRoot}else{$Context.ProjectRoot}
    $full=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path $base $Path}))
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
    if($Candidate-and$null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext-and$Context.ExecutionContext.targetKind-ceq'GIT_WORKTREE'){
        $relative=[IO.Path]::GetRelativePath($Context.RepositoryRoot,$full).Replace('\','/')
        if($relative-match'(?i)^(\.ai-workspace|\.git)(/|$)'){throw 'EXECUTION_TARGET_CONTROL_OBJECT_DENIED'}
    }
    return $full
}
function New-EvLogicalContext($Context) {
    $logical=$Context|Select-Object *
    if($null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext){
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        # The original-top projection is obtained once for a logical comparison,
        # never by observing each unselected candidate.
        $projected=@(Get-AiwExecutionTargetDeniedPaths $Context.ExecutionContext $Context.ForbiddenPaths $Context.CandidateProtectedPaths)
        $logical.ForbiddenPaths=@($Context.ForbiddenPaths)+$projected
        $logical.CandidateProtectedPaths=@($Context.CandidateProtectedPaths)+$projected
    }
    return $logical
}
function New-EvCandidateIndex($Context,$Candidates) {
    Assert-EvRefs $Candidates -Candidate -Nonempty
    $index=[Collections.Generic.Dictionary[string,object]]::new($(if($IsWindows){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}))
    foreach($candidate in $Candidates){
        $path=Get-EvLogicalPath $Context $candidate.path -Candidate
        if(-not$index.TryAdd($path,$candidate)){throw 'EVIDENCE_DUPLICATE_REF'}
    }
    return ,$index
}
function Resolve-EvPath($Context,[string]$Path,[switch]$Candidate,[switch]$AllowMissing,[switch]$AllowDirectory,[switch]$Observation) {
    $full=Get-EvLogicalPath $Context $Path -Candidate:$Candidate -Observation:$Observation
    if($null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext-and($Candidate-or$full.StartsWith($Context.RepositoryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        $relative=[IO.Path]::GetRelativePath($Context.RepositoryRoot,$full).Replace('\','/')
        return Resolve-AiwExecutionTargetCandidatePath $Context.ExecutionContext $relative $Context.ForbiddenPaths $Context.CandidateProtectedPaths
    }
    $cursor=[IO.Path]::GetPathRoot($full)
    $parts=$full.Substring($cursor.Length).Split([IO.Path]::DirectorySeparatorChar)
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
function Read-EvRef($Context,$Ref,[switch]$Candidate,[switch]$Section,[switch]$Json,$ReadDocuments=$null) {
    Assert-EvRef $Ref -Section:$Section -Candidate:$Candidate
    $full=Resolve-EvPath $Context $Ref.path -Candidate:$Candidate
    if($Candidate){
        if((Get-EvCandidateIdentity $full)-cne$Ref.identity){throw ('EVIDENCE_IDENTITY_DRIFT|'+$Ref.path)}
        Add-EvReadObservation $Context ([pscustomobject]@{path=$full;identity=$Ref.identity}) $true
        if(-not$Json-and-not$Section){return $full}
        if($Ref.identity-ceq'MISSING'){throw 'EVIDENCE_OBJECT_MISSING'}
    }
    # Bytes belong only to this private acquisition. Every logical reference
    # still resolves its own roots, restrictions, target and section first.
    $document=if($null-ne$ReadDocuments-and$ReadDocuments.ContainsKey($full)){$ReadDocuments[$full]}else{$null}
    if($null-eq$document){
    $bytes=[IO.File]::ReadAllBytes($full)
    $identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $document=[pscustomobject]@{bytes=$bytes;identity=$identity;text=$null;json=$null;jsonRead=$false}
    if($null-ne$ReadDocuments){$ReadDocuments.Add($full,$document)}
    }
    $bytes=$document.bytes;$identity=$document.identity
    if($identity-cne$Ref.identity){throw ('EVIDENCE_IDENTITY_DRIFT|'+$Ref.path)}
    $state=Get-EvReadState $Context
    $state.references[$full+'|'+$identity]=[pscustomobject]@{path=$full;identity=$identity}
    Add-EvReadObservation $Context ([pscustomobject]@{path=$full;identity=$identity})
    if(-not$Json-and-not$Section){return $full}
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'EVIDENCE_UTF8_BOM'}
    if($null-eq$document.text){$document.text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}
    $text=$document.text
    if($text.Contains([char]0)){throw 'EVIDENCE_NUL'}
    if($Section-and$null-ne$Ref.PSObject.Properties['section']){
        $tag=[regex]::Escape($Ref.section)
        if([regex]::Matches($text,'<!-- '+$tag+':BEGIN -->').Count-ne1-or[regex]::Matches($text,'<!-- '+$tag+':END -->').Count-ne1-or-not[regex]::IsMatch($text,'(?s)<!-- '+$tag+':BEGIN -->.+?<!-- '+$tag+':END -->')){throw 'EVIDENCE_SECTION_UNBOUND'}
    }
    if($Json){if(-not$document.jsonRead){$document.json=ConvertFrom-EvJson $text;$document.jsonRead=$true};return $document.json}
    return $full
}
function Test-EvSameRef($A,$B,$Context=$null,[switch]$Candidate) {
    # Equality is root-bound. Resolve both operands before comparing identities,
    # so a mismatching hash cannot hide an unsafe locator.
    if($null-ne$Context){
        $logical=New-EvLogicalContext $Context
        $aPath=Get-EvLogicalPath $logical $A.path -Candidate:$Candidate
        $bPath=Get-EvLogicalPath $logical $B.path -Candidate:$Candidate
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
    # Equality checks syntax, roots and protection without filesystem probing.
    # Actual current-candidate readers still verify every required live member.
    $logical=if($null-ne$Context){New-EvLogicalContext $Context}else{$null}
    $comparer=if($null-ne$Context-and$IsWindows){[StringComparer]::OrdinalIgnoreCase}else{[StringComparer]::Ordinal}
    $indexes=[Collections.Generic.List[object]]::new()
    foreach($set in @(@{refs=$Actual},@{refs=$Expected})){
        $index=[Collections.Generic.Dictionary[string,object]]::new($comparer)
        foreach($ref in $set.refs){
            $path=if($null-ne$logical){Get-EvLogicalPath $logical $ref.path -Candidate}else{$ref.path}
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
function Read-EvObservationLocator($Context,$Reference,$Candidates,[switch]$FrozenCandidateEvidence,[switch]$HistoricalSuccess,$CandidateIndex=$null) {
    if($FrozenCandidateEvidence-or$HistoricalSuccess){
        $full=Resolve-EvPath $Context $Reference.path -AllowMissing
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        if($null-eq$CandidateIndex){$CandidateIndex=New-EvCandidateIndex (New-EvLogicalContext $Context) $Candidates}
        $candidate=$null
        if($CandidateIndex.TryGetValue($full,[ref]$candidate)-and$candidate.identity-ceq$Reference.identity){$null=Resolve-EvPath $Context $candidate.path -Candidate;return}
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
        $fields=@('owner','reviewer','writer','cycle','verdict','exactPaths','objectIdentities','findingPaths','scopeChanged','decisionChanged');$fields+=if($Package.schemaVersion-eq5){'context'}else{'taskId'};Assert-EvFields $value $fields
        $found+=[pscustomobject]@{reference=$ref;value=$value}
    }
    if($found.Count-ne1){throw 'EVIDENCE_PLANNED_FLAT_VERDICT_REQUIRED'}
    $flat=$found[0].value
    Assert-EvInteger $flat.cycle;Assert-EvArray $flat.exactPaths;Assert-EvArray $flat.findingPaths
    if(-not(Test-AiwSameResultContext $(if($Package.schemaVersion-eq5){$flat.context}else{$flat}) $Package)-or$flat.owner-cne$Package.owner-or$flat.reviewer-cne$Record.actor-or$flat.reviewer-cne$Package.grantee-or$flat.writer-cne$plan.writer-or$Package.candidateWriter-cne$plan.writer-or$flat.cycle-ne$binding.cycle-or$flat.verdict-cne$Record.outcome-or$flat.scopeChanged-isnot[bool]-or$flat.decisionChanged-isnot[bool]){throw 'EVIDENCE_FLAT_TYPED_VERDICT_DRIFT'}
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

function Convert-EvOperationCompact($Context,$Raw){
 if($Raw.schemaVersion-ne5){throw 'EVIDENCE_OPERATION_CONTRACT'}
 $codec=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
 return & $codec {param($raw,$ctx)ConvertFrom-AiwOperationCompact $raw -EvidenceContext $ctx} $Raw $Context
}
function Read-EvProcessOperation($Context,$Boundary,$Result=$null,$ReadDocuments=$null){
 if($Boundary.schemaVersion-eq4){
  if($null-ne$Boundary.PSObject.Properties['operationRef']){$ref=$Boundary.operationRef}
  elseif($null-ne$Boundary.PSObject.Properties['currentOperation']-and$null-ne$Result-and$null-ne$Result.PSObject.Properties['operationRef']){$ref=$Result.operationRef}
  else{throw 'EVIDENCE_OPERATION_REF_REQUIRED'}
  $raw=Read-EvRef -ReadDocuments $ReadDocuments $Context $ref -Json
  return Convert-EvOperationCompact $Context $raw
 }
 return Read-EvRef -ReadDocuments $ReadDocuments $Context ([pscustomobject]@{path=$Boundary.discoverReceiptPath;identity=$Boundary.expectedDiscoverReceiptIdentity}) -Json
}


function Assert-AiwFinalizedReviewFinding($Context,$Parent,$Binding,[switch]$FrozenCandidates){
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    if($Parent.schemaVersion-in@(1,2)-and$null-ne$Context.PSObject.Properties['WorkRequest']){
        # Every consumer reads old TASK findings with the same verified
        # predecessor task plan, never the current WORK no-task marker.
        $predecessor=Get-EvWorkReviewRoot $Context $Context.WorkRequest ([pscustomobject]@{path=$Binding.parentPackagePath;identity=$Binding.parentPackageIdentity})
        $originalContext=$Context|Select-Object *
        $originalContext|Add-Member TaskPath (Read-EvRef $Context $predecessor.decision.predecessorTaskRef) -Force
        $Context=$originalContext
    }
    foreach($name in @('verdictFinalizeInputPath','verdictFinalizeInputIdentity','verdictFinalizeResultPath','verdictFinalizeResultIdentity')){if($null-eq$Binding.PSObject.Properties[$name]-or$Binding.$name-isnot[string]-or$Binding.$name-ceq'NOT_APPLICABLE'){throw 'REPAIR_REVIEW_FINALIZED_TYPED_VERDICT_REQUIRED'}}
    $input=Read-EvRef $Context ([pscustomobject]@{path=$Binding.verdictFinalizeInputPath;identity=$Binding.verdictFinalizeInputIdentity}) -Json
    $result=Read-EvRef $Context ([pscustomobject]@{path=$Binding.verdictFinalizeResultPath;identity=$Binding.verdictFinalizeResultIdentity}) -Json
    if($input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count-or$null-ne$result.PSObject.Properties['sourcePostimageTransition']){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_REQUIRED'}
    $source=Read-EvProcessOperation $Context $input $result
    if($source.schemaVersion-notin@(3,4,5)-or$source.status-cne'PASS'-or$source.intentEnvelope.requestedActionKind-cne'REVIEW_EXECUTE'-or$source.intentEnvelope.requestedResultKind-cne'REVIEW_VERDICT'){throw 'REPAIR_REVIEW_VERDICT_SOURCE'}
    $authority=$source.binding
    $review=Read-EvRef $Context ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$authority.authorizationIdentity}) -Json
    if($Parent.schemaVersion-eq5-and$review.schemaVersion-eq5-and(Get-AiwWorkPlanDefinitionKey $review.requestContext)-cne(Get-AiwWorkPlanDefinitionKey $Parent.requestContext)){throw 'REPAIR_REVIEW_PARENT_PLAN_DRIFT'}
    if($authority.actor-cne$review.grantee-or$(if($review.schemaVersion-eq5){-not(Test-AiwSameResultContext $authority $review)}else{$authority.taskId-cne$review.taskId-or$authority.taskOwner-cne$review.owner-or$authority.taskIdentity-cne$review.taskIdentity})-or$authority.userDecision-cne$review.userConfirmation-or@($review.actions).Count-ne1-or$review.actions[0]-cne'REVIEW_EXECUTE'-or(@($authority.exactScope|Sort-Object)-join'|')-cne(@($review.exactPaths|Sort-Object)-join'|')){throw 'REPAIR_REVIEW_VERDICT_AUTHORITY_DRIFT'}
    $crossReview=$Parent.schemaVersion-ne5-and$review.schemaVersion-eq5
    if($crossReview){
        $null=Get-EvWorkReviewRoot $Context $review.requestContext ([pscustomobject]@{path=$Binding.parentPackagePath;identity=$Binding.parentPackageIdentity})
    }
    $parentContextMatches=if($Parent.schemaVersion-eq5){$review.schemaVersion-eq5-and(Test-AiwSameResultContext $review $Parent)}elseif($crossReview){$true}else{$review.taskId-ceq$Parent.taskId-and$review.taskIdentity-ceq$Parent.taskIdentity}
    $parentDecisionMatches=$crossReview-or$review.userConfirmation-ceq$Parent.userConfirmation
    $cycle=[int]$Binding.cycle-1
    if($null-eq$review.PSObject.Properties['repairReviewBinding']-or$review.repairReviewBinding.parentPackageIdentity-cne$Binding.parentPackageIdentity-or$review.repairReviewBinding.cycle-ne$cycle-or$review.repairReviewBinding.phase-cne$(if($cycle-eq0){'INITIAL_REVIEW'}else{'REREVIEW'})-or$review.owner-cne$Parent.owner-or(-not$parentContextMatches)-or(-not$parentDecisionMatches)){throw 'REPAIR_REVIEW_VERDICT_PARENT_CYCLE'}
    if($result.selectionIdentity-cne$source.selectionIdentity-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $source $input)){throw 'REPAIR_REVIEW_VERDICT_FINALIZE_DECISION'}
    $refs=@($input.evidenceRefs|Where-Object kind -CEQ 'REVIEW_VERDICT')
    if($refs.Count-ne1){throw 'REPAIR_REVIEW_FINALIZED_TYPED_VERDICT_REQUIRED'}
    $raw=Read-EvRef $Context ([pscustomobject]@{path=$refs[0].path;identity=$refs[0].identity}) -Json
    $candidates=@(Get-AiwPackageCandidateReferences $review)
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwFinalizedObjectPostimages $input @($review.exactPaths))}))
    Assert-EvSameCandidates $post $candidates $Context
    $record=Read-AiwResultEvidence $Context $refs[0] (Get-EvExpectedResultContext $review) $candidates $raw.requirementsRef -ExpectedActor $review.grantee -AuthorizationIdentity $authority.authorizationIdentity -RequireIndependentReview -ExcludedReviewActors (@($Parent.owner,$Parent.issuer,$Parent.repairReviewPlan.writer)+@($Parent.repairReviewPlan.materialContributors)) -FrozenCandidateEvidence:$FrozenCandidates
    $flat=Get-AiwPlannedReviewFlatVerdict $Context $review $record
    if($record.outcome-cne'CHANGES_REQUESTED'-or$flat.reference.path-cne$Binding.verdictPath-or$flat.reference.identity-cne$Binding.verdictIdentity-or$flat.value.scopeChanged-or$flat.value.decisionChanged){throw 'REPAIR_REVIEW_VERDICT_FLAT_LINK'}
    $allRefs=@($input.evidenceRefs);$allRecords=@()
    foreach($ref in $allRefs){
        if($ref.kind-ceq'REVIEW_VERDICT'){$allRecords+=$record;continue}
        $other=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        if($review.schemaVersion-eq5-and$other.schemaVersion-ne3){
            $origin=Get-EvPredecessorResultBinding $Context $review.requestContext $ref $other $candidates $other.requirementsRef
            $allRecords+=Read-AiwResultEvidence $Context $ref $origin.taskId $candidates $other.requirementsRef -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $origin.originalFinalize
        }else{
            $allRecords+=Read-AiwResultEvidence $Context $ref (Get-EvExpectedResultContext $review) $candidates $other.requirementsRef -FrozenCandidateEvidence:($FrozenCandidates-and$ref.kind-ceq'SELF_CHECK')
        }
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
function Get-EvProducerActions([string]$Kind) {
    switch($Kind){'SELF_CHECK'{@('SOURCE_WRITE','CONTROL_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE')};'REVIEW_VERDICT'{@('REVIEW_EXECUTE')};'RESULT_ACCEPTANCE'{@('RESULT_ACCEPT')}}
}
function Get-EvTypedKey($Context,$Reference) {
    Assert-EvRef $Reference -Typed
    (Get-EvLogicalPath $Context $Reference.path)+'|'+$Reference.identity+'|'+$Reference.kind
}
function Add-EvCompletionFinalizes($Context,$Completion,$Pairs) {
    $readDocuments=if($null-ne$Completion){$Completion.readDocuments}else{$null}
    Assert-EvArray $Pairs
    foreach($pair in $Pairs){
        Assert-EvFields $pair @('inputRef','resultRef');Assert-EvRef $pair.inputRef;Assert-EvRef $pair.resultRef
        $key=(Get-EvLogicalPath $Context $pair.inputRef.path)+'|'+$pair.inputRef.identity+'|'+(Get-EvLogicalPath $Context $pair.resultRef.path)+'|'+$pair.resultRef.identity
        if(-not$Completion.pairs.Add($key)){continue}
        $Completion.originalFinalize.Add($pair)
        $input=Read-EvRef -ReadDocuments $readDocuments $Context $pair.inputRef -Json
        if($null-eq$input.PSObject.Properties['evidenceRefs']){throw 'EVIDENCE_HISTORICAL_FINALIZE_INCOMPLETE'}
        Assert-EvRefs $input.evidenceRefs -Typed
        $operationResult=if($input.schemaVersion-eq4-and$null-ne$input.PSObject.Properties['currentOperation']){Read-EvRef -ReadDocuments $readDocuments $Context $pair.resultRef -Json}else{$null}
        $source=Read-EvProcessOperation $Context $input $operationResult $readDocuments
        if($source.schemaVersion-notin@(3,4,5)-or$source.status-cne'PASS'-or($source.schemaVersion-ne5-and($source.mode-cne'DISCOVER'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'))){throw 'EVIDENCE_HISTORICAL_SOURCE_UNSUPPORTED'}
        $Completion.finalizeFacts.Add($key,[pscustomobject]@{input=$input;source=$source;package=$null;installation=$null})
        foreach($reference in $input.evidenceRefs){
            if($source.intentEnvelope.requestedActionKind-cnotin@(Get-EvProducerActions $reference.kind)){continue}
            $typedKey=Get-EvTypedKey $Context $reference
            if(-not$Completion.producers.ContainsKey($typedKey)){$Completion.producers.Add($typedKey,[Collections.Generic.List[object]]::new())}
            $Completion.producers[$typedKey].Add([pscustomobject]@{input=$input;pair=$pair;source=$source})
        }
    }
}
function Get-EvHistoricalFinalize($Context,$Reference,$Record,$OriginalFinalize,$Completion=$null) {
    $readDocuments=if($null-ne$Completion){$Completion.readDocuments}else{$null}
    # Original inputs/results are supplied by the finite consumer, never found
    # by scanning or written back into a typed record (which would form a cycle).
    Assert-EvArray $OriginalFinalize
    $allowed=@(Get-EvProducerActions $Reference.kind)
    $matches=@()
    if($null-ne$Completion){
        $key=Get-EvTypedKey $Context $Reference
        if($Completion.producers.ContainsKey($key)){$matches=@($Completion.producers[$key].ToArray())}
    }else{
    foreach($pair in $OriginalFinalize){
        Assert-EvFields $pair @('inputRef','resultRef')
        $input=Read-EvRef -ReadDocuments $readDocuments $Context $pair.inputRef -Json
        if($null-eq$input.PSObject.Properties['evidenceRefs']){continue}
        Assert-EvRefs $input.evidenceRefs -Typed
        if(@($input.evidenceRefs|Where-Object{$_.kind-ceq$Reference.kind-and(Test-EvSameRef $_ $Reference $Context)}).Count){
            $operationResult=if($input.schemaVersion-eq4-and$null-ne$input.PSObject.Properties['currentOperation']){Read-EvRef -ReadDocuments $readDocuments $Context $pair.resultRef -Json}else{$null}
        $source=Read-EvProcessOperation $Context $input $operationResult $readDocuments
            if($source.schemaVersion-notin@(3,4,5)-or$source.status-cne'PASS'-or($source.schemaVersion-ne5-and($source.mode-cne'DISCOVER'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'))){throw 'EVIDENCE_HISTORICAL_SOURCE_UNSUPPORTED'}
            # A downstream acceptance can cite the same evidence without
            # producing it. Only producer actions participate in uniqueness.
            if($source.intentEnvelope.requestedActionKind-cin$allowed){$matches+=@([pscustomobject]@{input=$input;pair=$pair;source=$source})}
        }
    }
    }
    if($matches.Count-ne1){throw 'EVIDENCE_HISTORICAL_FINALIZE_UNBOUND'}
    $input=$matches[0].input;$originalPair=$matches[0].pair;$result=Read-EvRef -ReadDocuments $readDocuments $Context $originalPair.resultRef -Json
    if($input.schemaVersion-notin@(3,4)-or$input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'EVIDENCE_HISTORICAL_FINALIZE_INCOMPLETE'}
    $source=$matches[0].source
    $a=$source.binding;$action=$source.intentEnvelope.requestedActionKind
    $packageRef=[pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity}
    $package=Read-EvRef -ReadDocuments $readDocuments $Context $packageRef -Json
    if($null-ne$package.PSObject.Properties['qualityBinding']){
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
        Assert-AiwQualityBinding $package.qualityBinding
        if($null-eq$source.sourceBindings.PSObject.Properties['policyIdentity']-or$package.qualityBinding.policyRef.identity-cne$source.sourceBindings.policyIdentity){throw 'QUALITY_HISTORICAL_POLICY_UNBOUND'}
        $repo=if($package.schemaVersion-in@(2,4,5)){$package.repositoryId}else{'REPO_LOCAL'}
        if($package.qualityBinding.subject.repositoryId-cne$repo-or@($package.exactPaths|Where-Object{$_-cnotin$package.qualityBinding.subject.exactPaths}).Count){throw 'QUALITY_HISTORICAL_SUBJECT_DRIFT'}
    }
    if($action-cnotin$allowed-or$action-cnotin$package.actions-or$action-cnotin$a.authorizedActions-or($action-cne'REVIEW_ROUTE'-and$a.actor-cne$Record.actor)-or$a.actor-cne$package.grantee-or$(if($package.schemaVersion-eq5){$Record.schemaVersion-ne3-or-not(Test-AiwSameResultContext $a $package)-or-not(Test-AiwSameResultContext $Record $package)}else{$a.taskId-cne$Record.taskId-or$a.taskId-cne$package.taskId-or$a.taskOwner-cne$package.owner-or$a.taskIdentity-cne$package.taskIdentity})-or$a.userDecision-cne$package.userConfirmation-or$a.projectConfigIdentity-cne$package.projectConfigIdentity){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-ceq'TASK_OWNER'-and$package.issuer-cne$package.owner){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-ceq'PROJECT_CONTROLLER'-and($package.issuer-cne$package.issuerControllerId-or$package.controllerControlIdentity-cne$a.controllerIdentity-or$package.issuerControllerEpoch-lt1)){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($package.issuerRole-cnotin@('TASK_OWNER','PROJECT_CONTROLLER')){throw 'EVIDENCE_HISTORICAL_AUTHORITY_DRIFT'}
    if($null-ne$Record.PSObject.Properties['authorizationRef']-and-not(Test-EvSameRef $Record.authorizationRef $packageRef $Context)){throw 'EVIDENCE_AUTHORIZATION_DRIFT'}
    if(-not([IO.Path]::GetFullPath($a.projectRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
    # Current topology, not an evidence-supplied absolute root, selects the
    # historical candidate repository. The current consumer context stays intact.
    $currentRestrictions=@(Get-EvAbsoluteRestrictions (@($Context.ForbiddenPaths)+@($Context.CandidateProtectedPaths)) $Context.Roots)
    if($package.schemaVersion-eq4){
        $historical=[pscustomobject]@{ProjectRoot=$Context.ProjectRoot;RepositoryRoot=$Context.RepositoryRoot;Roots=$Context.Roots;ForbiddenPaths=$currentRestrictions;CandidateProtectedPaths=@();Reading=$Context.Reading}
    }else{
        $historical=New-AiwPackageEvidenceContext $Context.ProjectRoot $package '' $currentRestrictions
        $historical.Roots=@(@($historical.Roots)+@($Context.Roots)|Select-Object -Unique)
    }
    Share-EvReadState $historical $Context
    # Original relative restrictions belong to the original control/object
    # roots. Preserve today's already projected restrictions as well.
    $originalRestrictions=@(Get-EvAbsoluteRestrictions (@($a.forbiddenScope)+@($a.protectedScope)) @($historical.ProjectRoot,$historical.RepositoryRoot))
    $historical.ForbiddenPaths=@(@($historical.ForbiddenPaths)+$originalRestrictions|Select-Object -Unique)
    $historical.CandidateProtectedPaths=@($historical.ForbiddenPaths)
    if($source.schemaVersion-in@(4,5)){
        $repositoryId=if($package.schemaVersion-in@(2,4,5)){$package.repositoryId}else{'PROJECT'}
        if(-not[IO.Path]::IsPathFullyQualified($a.controlRoot)-or-not([IO.Path]::GetFullPath($a.controlRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)-or$a.repositoryId-cne$repositoryId-or-not[IO.Path]::IsPathFullyQualified($a.objectRoot)-or-not([IO.Path]::GetFullPath($a.objectRoot)).Equals($historical.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
        if($a.executionContext.targetKind-ceq'GIT_WORKTREE'){
            if($Record.schemaVersion-ne2){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
            $descriptor=Read-EvRef -ReadDocuments $readDocuments $historical $a.executionContext.executionTargetRef -Json
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
        }elseif($a.executionContext.targetKind-cne'SAME_ROOT'-or$package.schemaVersion-eq4-or$Record.schemaVersion-notin@(1,3)){throw 'EVIDENCE_HISTORICAL_TARGET_UNBOUND'}
    }else{
        if($Record.schemaVersion-ne1-or$package.schemaVersion-eq4){throw 'EVIDENCE_HISTORICAL_TARGET_UNBOUND'}
        $originalRoot=if($package.schemaVersion-eq2){$a.repositoryGitTop}else{$a.projectRoot}
        if(-not[IO.Path]::IsPathFullyQualified($originalRoot)-or-not([IO.Path]::GetFullPath($originalRoot)).Equals($historical.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_HISTORICAL_ROOT_DRIFT'}
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
    Assert-EvOriginalFinalizeDecision $source $input $result
    if($null-eq$result.PSObject.Properties['actionOutcome']-or$result.actionOutcome-cne$(if($action-ceq'TEST_RUN'){'PASS'}else{'OBSERVED'})){throw 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL'}
    $prep=@($input.preparationReceipts|Where-Object{$_-cne'SELF_CHECK_BOUND'})
    $results=@($input.resultReceipts|Where-Object{$_-cnotin@('REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED','DELIVERY_RECEIPT')})
    foreach($ref in $input.evidenceRefs){
        $raw=Read-EvRef -ReadDocuments $readDocuments $historical ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        # The matching record is validated by our caller; other original typed
        # records are still immutable and must have a successful outcome.
        $ok=@{SELF_CHECK='PASS';REVIEW_VERDICT='APPROVED';RESULT_ACCEPTANCE='ACCEPTED'}
        if($raw.outcome-cne$ok[$ref.kind]){throw 'EVIDENCE_HISTORICAL_ACTION_NOT_SUCCESSFUL'}
        if($action-ceq'REVIEW_ROUTE'-and$ref.kind-ceq'SELF_CHECK'){
            if($raw.actor-cne$routeQualification.writer-or-not(Test-AiwSameResultContext $raw $Record)){throw 'EVIDENCE_HISTORICAL_AUTHOR_DRIFT'}
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
                $null=Read-EvRef -ReadDocuments $readDocuments $historical $input.deliveryContext.userDecisionRef
                $routeRecipient=[string]$input.deliveryContext.expectedRecipient
                if([string]::IsNullOrWhiteSpace($routeRecipient)-or$routeRecipient-cne$routeRecipient.Trim()-or$routeRecipient-cin@('USER','NOT_APPLICABLE','NOT_REQUIRED','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')){throw 'DELIVERY_EXPLICIT_TASK_RECIPIENT_REQUIRED'}
            }
            if($input.deliveryContext.channel-cne'TASK_MESSAGE'-or$input.deliveryContext.expectedRecipient-cne$routeRecipient-or$null-eq$result.PSObject.Properties['consumer']-or$result.consumer.recipient-cne$routeRecipient-or$result.consumer.channel-cne'TASK_MESSAGE'-or$result.consumer.authorizationIdentity-cne$packageRef.identity){throw 'EVIDENCE_HISTORICAL_DELIVERY_DRIFT'}
        }
        if($input.deliveryContext.channel-ceq'TASK_MESSAGE'){
            if(-not$observation.delivered-or$input.deliveryContext.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'EVIDENCE_HISTORICAL_DELIVERY_UNPROVEN'}
            $hostResult=Read-EvRef -ReadDocuments $readDocuments $historical ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
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
    $historical|Add-Member HistoricalProducer ([pscustomobject]@{pair=$originalPair;source=$source;input=$input;result=$result;package=$package})
    return $historical
}
function Read-AiwResultEvidence($Context,$Reference,$TaskId,$CandidateObjects,$RequirementsRef,[switch]$RequireSuccess,[string]$ExpectedActor='',[string]$AuthorizationIdentity='',[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[switch]$FrozenCandidateEvidence,[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE',$AcceptancePlan=$null) {
    Read-EvResultEvidenceCore @PSBoundParameters
}
function Read-EvResultEvidenceCore($Context,$Reference,$TaskId,$CandidateObjects,$RequirementsRef,[switch]$RequireSuccess,[string]$ExpectedActor='',[string]$AuthorizationIdentity='',[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[switch]$FrozenCandidateEvidence,[string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),[string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE',$AcceptancePlan=$null,$Completion=$null,$ObservedRecord=$null) {
    $readDocuments=if($null-ne$Completion){$Completion.readDocuments}else{$null}
    Assert-EvRef $Reference -Typed
    # Continuation history cannot satisfy a success gate. Historical success
    # separately requires the original completed action and its exact postimage.
    if($FrozenCandidateEvidence-and($Reference.kind-cnotin@('SELF_CHECK','REVIEW_VERDICT')-or$RequireSuccess-or$EvidencePurpose-ceq'HISTORICAL_SUCCESS')){throw 'EVIDENCE_FROZEN_SUCCESS_GATE_DENIED'}
    $historical=$EvidencePurpose-ceq'HISTORICAL_SUCCESS'
    $ref=[pscustomobject]@{path=$Reference.path;identity=$Reference.identity}
    if($null-ne$ObservedRecord-and$null-eq$Completion){throw 'EVIDENCE_OBSERVED_RECORD_CONTEXT'}
    $record=if($null-ne$ObservedRecord){$ObservedRecord}else{Read-EvRef -ReadDocuments $readDocuments $Context $ref -Json}
    Assert-EvInteger $record.schemaVersion;if($record.schemaVersion-notin@(1,2,3)){throw 'EVIDENCE_SCHEMA'}
    if($record.schemaVersion-eq3){
        Assert-EvFields $record @('schemaVersion','context','actor','candidateObjects','requirementsRef','outcome','checks','evidenceLocators') @('authorizationRef','acceptedCommit')
    }else{Assert-EvFields $record @('schemaVersion','taskId','actor','candidateObjects','requirementsRef','outcome','checks','evidenceLocators') @('authorizationRef','acceptedCommit','executionTargetRef','candidateTargetState')}
    $request=Get-EvWorkRequest $TaskId
    if($record.schemaVersion-ne3-and$null-ne$request-and$null-ne$request.PSObject.Properties['predecessorRef']){
        if($ExpectedActor-or$AuthorizationIdentity-or$FrozenCandidateEvidence){throw 'WORK_PREDECESSOR_NEW_OUTPUT_REQUIRES_SCHEMA3'}
        $predecessor=Get-EvPredecessorResultBinding $Context $request $Reference $record $CandidateObjects $RequirementsRef
        $TaskId=$predecessor.taskId;$AcceptancePlan=$predecessor.plan;$OriginalFinalize=$predecessor.originalFinalize
        $historical=$true;$EvidencePurpose='HISTORICAL_SUCCESS'
    }
    # Resolve the original task edge before guarding this typed validation.
    # Its finite predecessor graph validates the same record in its own context.
    $key=(Resolve-EvPath $Context $Reference.path)+'|'+$Reference.identity
    if($Context.Reading.Count-ge32-or-not$Context.Reading.Add($key)){throw 'EVIDENCE_REFERENCE_CYCLE'}
    try{
        Assert-EvResultContext $record $TaskId
        if($historical){$Context=Get-EvHistoricalFinalize $Context $Reference $record $OriginalFinalize $Completion;if($record.schemaVersion-eq3){Assert-EvResultContext $Context.HistoricalProducer.package $TaskId}}
        else{$Context=Resolve-EvRecordTarget $Context $record -FrozenCandidateEvidence:$FrozenCandidateEvidence}
        foreach($s in @('actor','outcome')){Assert-EvString $record.$s}
        if($record.schemaVersion-ne3){Assert-EvString $record.taskId}
        if($ExpectedActor-and$record.actor-cne$ExpectedActor){throw 'EVIDENCE_ACTOR_DRIFT'}
        Assert-EvSameCandidates $record.candidateObjects $CandidateObjects $Context
        if(-not($FrozenCandidateEvidence-or$historical)){foreach($candidate in $record.candidateObjects){$null=Read-EvRef -ReadDocuments $readDocuments $Context $candidate -Candidate}}
        Assert-EvRef $record.requirementsRef -Section
        if(-not(Test-EvSameRef $record.requirementsRef $RequirementsRef $Context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
        $null=Read-EvRef -ReadDocuments $readDocuments $Context $record.requirementsRef -Section
        $outcomes=@{SELF_CHECK=@('PASS','FAIL','INCOMPLETE');REVIEW_VERDICT=@('APPROVED','CHANGES_REQUESTED','REJECTED','INCOMPLETE');RESULT_ACCEPTANCE=@('ACCEPTED','REJECTED','INCOMPLETE')}
        if($record.outcome-cnotin$outcomes[$Reference.kind]){throw 'EVIDENCE_OUTCOME'}
        $success=$record.outcome-ceq$outcomes[$Reference.kind][0]
        if(($RequireSuccess-or$historical)-and-not$success){throw 'EVIDENCE_NOT_SUCCESSFUL'}
        Assert-EvRefs $record.evidenceLocators
        $candidateIndex=if($null-eq$Completion-and($FrozenCandidateEvidence-or$historical)){New-EvCandidateIndex (New-EvLogicalContext $Context) $CandidateObjects}else{$null}
        if($null-eq$Completion){foreach($locator in $record.evidenceLocators){Read-EvObservationLocator $Context $locator $CandidateObjects -FrozenCandidateEvidence:$FrozenCandidateEvidence -HistoricalSuccess:$historical -CandidateIndex $candidateIndex}}
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
                if($null-eq$Completion){
                    $command=Read-EvRef -ReadDocuments $readDocuments $Context $check.evidenceLocators[0] -Json
                    Assert-EvFields $command @('command','exitCode','output')
                    Assert-EvString $command.command;Assert-EvInteger $command.exitCode
                    $null=Read-EvRef -ReadDocuments $readDocuments $Context $command.output
                    if($check.outcome-ceq'PASS'-and$command.exitCode-ne0){throw 'EVIDENCE_COMMAND_FAILURE'}
                }
            }elseif($null-eq$Completion){foreach($locator in $check.evidenceLocators){Read-EvObservationLocator $Context $locator $CandidateObjects -FrozenCandidateEvidence:$FrozenCandidateEvidence -HistoricalSuccess:$historical -CandidateIndex $candidateIndex}}
        }
        if($Reference.kind-ceq'SELF_CHECK'){
            if($null-ne$record.PSObject.Properties['authorizationRef']-or$null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
        }else{
            if($null-eq$record.PSObject.Properties['authorizationRef']){throw 'EVIDENCE_ORIGINAL_PACKAGE_REQUIRED'}
            $package=Read-EvRef -ReadDocuments $readDocuments $Context $record.authorizationRef -Json
            if($package.schemaVersion-eq4-and$record.schemaVersion-ne2){throw 'EVIDENCE_ISOLATED_TARGET_REQUIRES_SCHEMA2'}
            $action=if($Reference.kind-ceq'REVIEW_VERDICT'){'REVIEW_EXECUTE'}else{'RESULT_ACCEPT'}
            if(-not(Test-AiwSameResultContext $package $TaskId)-or$package.grantee-cne$record.actor-or@($package.actions).Count-ne1-or$package.actions[0]-cne$action){throw 'EVIDENCE_ORIGINAL_PACKAGE_DRIFT'}
            if($AuthorizationIdentity-and$record.authorizationRef.identity-cne$AuthorizationIdentity){throw 'EVIDENCE_AUTHORIZATION_DRIFT'}
            if($package.schemaVersion-eq5){
                if($record.schemaVersion-ne3){throw 'EVIDENCE_WORK_REQUIRES_SCHEMA3'}
                $null=Get-EvWorkRecordRequirements $Context $package.requestContext $Reference.kind $record.candidateObjects $record.requirementsRef
                if(-not$historical){$null=Get-AiwPackageQuality $Context $package (Get-AiwProjectWorkPlan $package.requestContext)}
            }elseif($record.schemaVersion-eq3){throw 'EVIDENCE_WORK_PACKAGE5_REQUIRED'}
            if($package.schemaVersion-ne5-and-not$historical-and$null-ne$package.PSObject.Properties['qualityBinding']){
                $taskLocator=if($null-ne$Context.PSObject.Properties['TaskPath']-and$Context.TaskPath){$Context.TaskPath}else{'.ai-workspace/tasks/active/'+$package.taskId+'.md'}
                $taskFull=Resolve-EvPath $Context $taskLocator
                $activePlan=Get-AiwAcceptancePlan ([IO.File]::ReadAllText($taskFull))
                $null=Get-AiwPackageQuality $Context $package $activePlan
            }
            Assert-EvSameCandidates @(Get-AiwPackageCandidateReferences $package) $record.candidateObjects $Context
            if($Reference.kind-ceq'REVIEW_VERDICT'){
                $null=Get-AiwPlannedReviewFlatVerdict $Context $package $record
                if($null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
                Assert-EvReviewIndependence $package $record -Required:$RequireIndependentReview -Excluded $ExcludedReviewActors
            }else{
                $prerequisitePurpose=if($historical){'HISTORICAL_SUCCESS'}else{$PrerequisiteEvidencePurpose}
                Assert-EvAcceptanceBinding $Context $package $AcceptancePlan -Historical -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -EvidencePurpose $EvidencePurpose -OriginalFinalize $OriginalFinalize -PrerequisiteEvidencePurpose $prerequisitePurpose -Completion $Completion
                if($null-ne$package.PSObject.Properties['acceptanceBinding']-and-not(Test-EvSameRef $package.acceptanceBinding.requirementsRef $record.requirementsRef $Context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
                if($null-ne$record.PSObject.Properties['acceptedCommit']-and$record.acceptedCommit-cnotmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw 'EVIDENCE_ACCEPTED_COMMIT'}
            }
        }
        if($historical){
            $producer=$Context.HistoricalProducer;Add-EvValidatedProducer $Context $producer.pair $producer.source $producer.input $producer.result
            if($null-ne$Completion){
                $node=$Completion.nodes[(Get-EvTypedKey $Context $Reference)];$node.context=$Context
                # All typed flags used by the original frozen obligations refer
                # to real nodes; merely citing a successful outcome is insufficient.
                foreach($other in $producer.input.evidenceRefs){
                    if((Get-EvTypedKey $Context $other)-ceq(Get-EvTypedKey $Context $Reference)){continue}
                    $raw=Read-EvRef -ReadDocuments $readDocuments $Context ([pscustomobject]@{path=$other.path;identity=$other.identity}) -Json
                    Add-EvCompletionNode $Context $Completion $other $TaskId $raw.candidateObjects $raw.requirementsRef -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -ObservedRecord $raw
                }
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
function Add-EvCompletionNode($Context,$Completion,$Reference,$TaskId,$Candidates,$Requirements,[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),$ObservedRecord=$null) {
    $key=Get-EvTypedKey $Context $Reference
    if(-not$Completion.nodes.ContainsKey($key)){
        $Completion.nodes.Add($key,[pscustomobject]@{reference=$Reference;constraints=[Collections.Generic.List[object]]::new();dependencies=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);record=$null;context=$null;observedRecord=$ObservedRecord})
        $Completion.pending.Enqueue($key)
    }
    $Completion.nodes[$key].constraints.Add([pscustomobject]@{taskId=$TaskId;candidates=$Candidates;requirements=$Requirements;independent=[bool]$RequireIndependentReview;excluded=@($ExcludedReviewActors)})
}
function Assert-EvReviewIndependence($Package,$Record,[switch]$Required,[string[]]$Excluded=@()) {
    if($Package.reviewIndependence-ceq'INDEPENDENT'-or$Required-or$Package.profile-ceq'CRITICAL'-or$null-ne$Package.PSObject.Properties['candidateWriter']-or$null-ne$Package.PSObject.Properties['materialContributors']){
        if($Package.reviewIndependence-cne'INDEPENDENT'){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
        foreach($field in @('candidateWriter','materialContributors')){if($null-eq$Package.PSObject.Properties[$field]){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}}
        if($Package.materialContributors-isnot[Array]){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
        $actors=@(Get-AiwReviewExcludedActors $Package.owner $Package.issuer $Package.candidateWriter $Package.materialContributors)
        if($Record.actor-cin($actors+@($Excluded))){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
    }
}
function New-EvCompletionGraph($ReadDocuments=$null) {
    # Only actual consumers create this private, invocation-local graph. It is
    # neither public input nor a reusable PASS; live targets belong to callers.
    [pscustomobject]@{
        nodes=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        producers=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        pairs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        originalFinalize=[Collections.Generic.List[object]]::new()
        pending=[Collections.Generic.Queue[string]]::new()
        userDecisions=[Collections.Generic.List[object]]::new()
        installedStages=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        finalizeFacts=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        publicationInstallations=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        readDocuments=$ReadDocuments
        currentKey=''
    }
}
function Complete-EvCompletionGraph($Context,$Completion,$Plan=$null) {
    $readDocuments=if($null-ne$Completion){$Completion.readDocuments}else{$null}
    while($Completion.pending.Count){
        $key=$Completion.pending.Dequeue();$node=$Completion.nodes[$key];$constraint=$node.constraints[0]
        $Completion.currentKey=$key
        $node.record=Read-EvResultEvidenceCore $Context $node.reference $constraint.taskId $constraint.candidates $constraint.requirements -RequireSuccess -RequireIndependentReview:$constraint.independent -ExcludedReviewActors $constraint.excluded -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $Completion.originalFinalize.ToArray() -AcceptancePlan $Plan -Completion $Completion -ObservedRecord $node.observedRecord
        $node.observedRecord=$null
    }
    # Constraints can arrive after a shared ancestor was read. Validate their
    # union without re-expanding that ancestor's production or acceptance.
    foreach($node in $Completion.nodes.Values){
        foreach($constraint in $node.constraints){
            Assert-EvResultContext $node.record $constraint.taskId
            Assert-EvSameCandidates $node.record.candidateObjects $constraint.candidates $node.context
            if(-not(Test-EvSameRef $node.record.requirementsRef $constraint.requirements $node.context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
            if($node.reference.kind-ceq'REVIEW_VERDICT'){
                $package=Read-EvRef -ReadDocuments $readDocuments $node.context $node.record.authorizationRef -Json
                Assert-EvReviewIndependence $package $node.record -Required:$constraint.independent -Excluded $constraint.excluded
            }
        }
    }
    $incoming=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $Completion.nodes.GetEnumerator()){$incoming.Add($entry.Key,$entry.Value.dependencies.Count)}
    $ready=[Collections.Generic.Queue[string]]::new();foreach($key in $incoming.Keys){if($incoming[$key]-eq0){$ready.Enqueue($key)}}
    $visited=0
    while($ready.Count){$key=$ready.Dequeue();$visited++;foreach($entry in $Completion.nodes.GetEnumerator()){if($entry.Value.dependencies.Contains($key)){$incoming[$entry.Key]--;if($incoming[$entry.Key]-eq0){$ready.Enqueue($entry.Key)}}}}
    if($visited-ne$Completion.nodes.Count){throw 'EVIDENCE_REFERENCE_CYCLE'}
}
function Assert-EvCurrentCompletedObjects($Context,$Plan,$Completion,[string[]]$ClosureBasis=@()) {
    # A version is the entire original candidate mapping, never a bag of
    # independently replaceable files. Equal path sets identify comparison
    # families; partial overlap does not discard either delivery obligation.
    $families=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($stage in @($Plan.stages|Where-Object kind -CNE USER_DECISION)){
        $stageContext=$Context
        if($Completion.installedStages.ContainsKey($stage.id)){$stageContext=$Completion.installedStages[$stage.id].context}
        elseif($stage.evidenceRefs.Count){$stageContext=$Completion.nodes[(Get-EvTypedKey $Context $stage.evidenceRefs[0])].context}
        $logical=New-EvLogicalContext $stageContext
        $memberMap=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($candidate in $stage.candidateRef){$path=Get-EvLogicalPath $logical $candidate.path -Candidate;$memberMap.Add($path,[pscustomobject]@{path=$path;reference=$candidate})}
        $keys=[string[]]@($memberMap.Keys);[Array]::Sort($keys,[StringComparer]::OrdinalIgnoreCase)
        $members=@(foreach($key in $keys){$memberMap[$key]})
        $familyKey=(@($members.path|ForEach-Object{$_.ToUpperInvariant()})-join"`n")
        $versionKey=(@($members|ForEach-Object{$_.path.ToUpperInvariant()+'|'+$_.reference.identity})-join"`n")
        if(-not$families.ContainsKey($familyKey)){$families.Add($familyKey,[Collections.Generic.List[object]]::new())}
        $bound=$false
        $basisRefs=@($stage.evidenceRefs)
        if($Completion.installedStages.ContainsKey($stage.id)){$basisRefs+=@($Completion.installedStages[$stage.id].originalRefs)}
        foreach($reference in $basisRefs){
            # Only known, already validated original refs are matched. Prose
            # cannot introduce a new path to read or manufacture a candidate.
            $locator=[regex]::Escape($reference.path+'#'+$reference.identity)
            foreach($basis in $ClosureBasis){if([regex]::IsMatch($basis,'(?<![A-Za-z0-9_./\\:-])'+$locator+'(?![A-Za-z0-9_|])',[Text.RegularExpressions.RegexOptions]::IgnoreCase)){$bound=$true}}
        }
        $families[$familyKey].Add([pscustomobject]@{stage=$stage;context=$stageContext;members=$members;version=$versionKey;bound=$bound})
    }
    $current=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($rows in $families.Values){
        $versions=@($rows.version|Select-Object -Unique)
        $selected=@($rows|Where-Object bound)
        if($versions.Count-gt1){
            if($selected.Count-eq0){throw 'ACCEPTANCE_CURRENT_DELIVERABLE_BINDING_REQUIRED'}
            if(@($selected.version|Select-Object -Unique).Count-ne1){throw 'ACCEPTANCE_CURRENT_DELIVERABLE_BINDING_AMBIGUOUS'}
        }else{$selected=@($rows[0])}
        foreach($member in $selected[0].members){
            if($current.ContainsKey($member.path)){
                if($current[$member.path].reference.identity-cne$member.reference.identity){throw 'ACCEPTANCE_CURRENT_OBJECT_CONFLICT'}
            }else{$current.Add($member.path,[pscustomobject]@{reference=$member.reference;context=$selected[0].context})}
        }
    }
    foreach($member in $current.Values){$null=Read-EvRef $member.context $member.reference -Candidate}
}
function Assert-EvCompletedStages($Context,$Plan,[string]$TaskId,$UserDecisionRefs=@(),[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[string[]]$ClosureBasis=@(),[string]$TaskOwner='') {
    $completion=New-EvCompletionGraph
    foreach($ref in $UserDecisionRefs){$completion.userDecisions.Add($ref)}
    foreach($stage in $Plan.stages){
        $null=Read-EvRef $Context $stage.requiredBy -Section
        if($stage.candidateRef.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
        if($stage.kind-cin@('DESIGN','USER_DECISION')){continue}
        $consumption=Get-EvConsumption $stage evidenceConsumption
        Add-EvCompletionFinalizes $Context $completion $consumption.originalFinalize
        $installed=Get-EvCompletedInstallationStage $Context $completion $stage $TaskId $TaskOwner -RequireIndependentReview:$RequireIndependentReview
        if($null-ne$installed){$completion.installedStages.Add($stage.id,$installed);continue}
        if($stage.evidenceRefs.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
        foreach($ref in $stage.evidenceRefs){Add-EvCompletionNode $Context $completion $ref $TaskId $stage.candidateRef $stage.requiredBy -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors}
    }
    Complete-EvCompletionGraph $Context $completion $Plan
    # Only a bound original acceptance or the current explicit decision can
    # satisfy user-reserved stages, including stages after final acceptance.
    foreach($stage in @($Plan.stages|Where-Object kind -CEQ USER_DECISION)){
        foreach($ref in $stage.candidateRef){
            if(@($completion.userDecisions|Where-Object{Test-EvSameRef $_ $ref $Context}).Count-eq0){throw ('ACCEPTANCE_USER_DECISION_UNBOUND|'+$stage.id)}
            $null=Read-EvRef $Context $ref
        }
    }
    Assert-EvCurrentCompletedObjects $Context $Plan $completion $ClosureBasis
}
function Assert-AiwAcceptanceStages($Context,$Plan,$TaskId,[string]$BeforeStage='', $UserDecisionRefs=@(),[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),$AcceptancePlan=$null) {
    if($null-eq$AcceptancePlan){$AcceptancePlan=$Plan}
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
            foreach($ref in $stage.evidenceRefs){$null=Read-AiwResultEvidence $Context $ref $TaskId $stage.candidateRef $stage.requiredBy -RequireSuccess -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize -AcceptancePlan $AcceptancePlan}
        }
    }
}
function Assert-AiwAcceptanceBinding($Context,$Package,$Plan,[switch]$Historical,[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[ValidateSet('CURRENT_CANDIDATE','HISTORICAL_SUCCESS')][string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@()) {
    # This public admission/acceptance gate always checks the current candidate.
    Assert-EvAcceptanceBinding $Context $Package $Plan -Historical:$Historical -RequireIndependentReview:$RequireIndependentReview -ExcludedReviewActors $ExcludedReviewActors -PrerequisiteEvidencePurpose $PrerequisiteEvidencePurpose -OriginalFinalize $OriginalFinalize
}
function Assert-EvAcceptanceBinding($Context,$Package,$Plan,[switch]$Historical,[switch]$RequireIndependentReview,[string[]]$ExcludedReviewActors=@(),[string]$EvidencePurpose='CURRENT_CANDIDATE',[object[]]$OriginalFinalize=@(),[string]$PrerequisiteEvidencePurpose='CURRENT_CANDIDATE',$Completion=$null) {
    $readDocuments=if($null-ne$Completion){$Completion.readDocuments}else{$null}
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
    if($null-ne$Completion){Add-EvCompletionFinalizes $Context $Completion $consumption.originalFinalize}
    if($EvidencePurpose-ceq'HISTORICAL_SUCCESS'){
        # The parent has already proved its original successful FINALIZE. Its
        # old declaration cannot turn recursive history into a live recheck.
        $consumption=Get-EvConsumption $null '' HISTORICAL_SUCCESS $OriginalFinalize
    }
    Assert-EvSameCandidates $binding.candidateObjects @(Get-AiwPackageCandidateReferences $Package) $Context
    if($EvidencePurpose-ceq'CURRENT_CANDIDATE'){foreach($candidate in $binding.candidateObjects){$null=Read-EvRef -ReadDocuments $readDocuments $Context $candidate -Candidate}}
    $null=Read-EvRef -ReadDocuments $readDocuments $Context $binding.requirementsRef -Section
    Assert-EvRefs $binding.prerequisiteEvidenceRefs -Typed;Assert-EvRefs $binding.reservedUserDecisionRefs
    foreach($ref in $binding.reservedUserDecisionRefs){$null=Read-EvRef -ReadDocuments $readDocuments $Context $ref}
    if($null-ne$Completion){foreach($ref in $binding.reservedUserDecisionRefs){$Completion.userDecisions.Add($ref)}}
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
        $observedPrerequisite=$null
        if($Historical-or$selected.purpose-ceq'HISTORICAL_SUCCESS'){
            # Historical acceptance retains the original typed evidence bindings;
            # subsequent task progress is not a new permanent hash dependency.
            $raw=Read-EvRef -ReadDocuments $readDocuments $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            $candidate=$raw.candidateObjects;$requirements=$raw.requirementsRef;$observedPrerequisite=$raw
        }
        if($null-ne$Completion){
            Add-EvCompletionFinalizes $Context $Completion $selected.originalFinalize
            Add-EvCompletionNode $Context $Completion $ref (Get-EvExpectedResultContext $Package) $candidate $requirements -RequireIndependentReview:$independentRequired -ExcludedReviewActors $excluded -ObservedRecord $observedPrerequisite
            $parent=$Completion.nodes[$Completion.currentKey]
            $null=$parent.dependencies.Add((Get-EvTypedKey $Context $ref))
        }else{
            $null=Read-AiwResultEvidence $Context $ref (Get-EvExpectedResultContext $Package) $candidate $requirements -RequireSuccess -RequireIndependentReview:$independentRequired -ExcludedReviewActors $excluded -EvidencePurpose $selected.purpose -OriginalFinalize $selected.originalFinalize -AcceptancePlan $Plan
        }
    }
    if($independentRequired){
        $reviewed=$false
        foreach($ref in @($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq'REVIEW_VERDICT'})){
            $raw=Read-EvRef -ReadDocuments $readDocuments $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            if((Test-EvSameCandidates $raw.candidateObjects $binding.candidateObjects $Context)-and(Test-EvSameRef $raw.requirementsRef $binding.requirementsRef $Context)){$reviewed=$true}
        }
        if(-not$reviewed){throw 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED'}
    }
    if($null-ne$Plan){
        foreach($stage in $prereqs){foreach($ref in $stage.evidenceRefs){if(@($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq$ref.kind-and(Test-EvSameRef $_ $ref $Context)}).Count-ne1){throw 'RESULT_ACCEPT_PREREQUISITE_UNBOUND'}}}
        if($null-eq$Completion){Assert-AiwAcceptanceStages $Context ([pscustomobject]@{stages=@($prereqs)}) (Get-EvExpectedResultContext $Package) '' $binding.reservedUserDecisionRefs -RequireIndependentReview:$independentRequired -ExcludedReviewActors $excluded -EvidencePurpose $consumption.purpose -OriginalFinalize $consumption.originalFinalize -AcceptancePlan $Plan}
    }
}
function New-AiwPackageEvidenceContext([string]$ProjectRoot,$Package,[string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@(),[string]$TaskPath='',[object]$TargetState=$null,[string[]]$ProtectedPaths=@()) {
    $ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    $repo=$ProjectRoot
    if($null-ne$Package-and$Package.schemaVersion-eq2){
        $guard=New-AiwEvidenceContext $ProjectRoot '' $FrameworkRoot $ForbiddenPaths $ProtectedPaths
        $configPath=Resolve-EvPath $guard '.ai-workspace/project.json'
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText($configPath))
        $repo=Get-EvConfiguredRepositoryRoot $ProjectRoot $Package.repositoryId $cfg
    }
    $target=$null
    if($null-ne$Package-and$Package.schemaVersion-eq4){
        if(-not$TaskPath){throw 'EVIDENCE_EXECUTION_TARGET_TASK_REQUIRED'}
        Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
        $target=Resolve-AiwPackageExecutionTarget $ProjectRoot $Package $TaskPath $ForbiddenPaths $ProtectedPaths $TargetState
        $repo=$target.executionRoot
    }
    $ctx=New-AiwEvidenceContext $ProjectRoot $repo $FrameworkRoot $ForbiddenPaths $ProtectedPaths
    if($null-ne$Package-and$Package.schemaVersion-eq5-and$null-ne$Package.requestContext.PSObject.Properties['predecessorRef']){
        # Private source data only; the finding reader validates its edge/root.
        $ctx|Add-Member WorkRequest $Package.requestContext
    }
    $ctx|Add-Member TaskPath $TaskPath
    $ctx|Add-Member ExecutionContext $target
    return $ctx
}
function Assert-AiwReviewSelfCheck($Context,$References,$TaskId,$Candidates,$Plan=$null) {
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
function Get-AiwContinuationSelfCheckOutcome($Context,$References,$TaskId,$Candidates,[string]$Actor,[switch]$FrozenCandidateEvidence) {
    Assert-EvRefs $References -Typed
    $refs=@($References|Where-Object{$_.kind-ceq'SELF_CHECK'});$records=@()
    foreach($ref in $refs){
        $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $records+=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $raw.requirementsRef -ExpectedActor $Actor -FrozenCandidateEvidence:$FrozenCandidateEvidence
    }
    return Get-AiwSelfCheckOutcome $refs $records
}
function Get-AiwSelfRepairOriginCycle($Context,$Package) {
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    if($Package.schemaVersion-eq5-and$null-ne$Package.requestContext.PSObject.Properties['predecessorRef']-and$null-ne$Package.PSObject.Properties['selfCheckRepairLimit']-and$null-eq$Package.PSObject.Properties['repairReviewBinding']){
        $predecessor=Get-EvWorkPredecessor $Context $Package.requestContext
        if($null-ne$predecessor.selfRoot){
            if($Package.selfCheckRepairLimit-ne$predecessor.selfLimit){throw 'WORK_PREDECESSOR_SELF_LIMIT_DRIFT'}
            return [int]$predecessor.selfCycle
        }
    }
    if($null-eq$Package.PSObject.Properties['selfCheckRepairLimit']-or$null-eq$Package.PSObject.Properties['repairReviewBinding']){return 0}
    $binding=$Package.repairReviewBinding
    if($binding.phase-cne'REPAIR'){return 0}
    $parent=Read-EvRef $Context ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity}) -Json
    $null=Assert-AiwFinalizedReviewFinding $Context $parent $binding -FrozenCandidates
    $findingInput=Read-EvRef $Context ([pscustomobject]@{path=$binding.verdictFinalizeInputPath;identity=$binding.verdictFinalizeInputIdentity}) -Json
    $findingResult=Read-EvRef $Context ([pscustomobject]@{path=$binding.verdictFinalizeResultPath;identity=$binding.verdictFinalizeResultIdentity}) -Json
    $findingSource=Read-EvProcessOperation $Context $findingInput $findingResult
    $review=Read-EvRef $Context ([pscustomobject]@{path=$findingSource.sourceLocators.authorizationPackagePath;identity=$findingSource.binding.authorizationIdentity}) -Json
    $productionInput=Read-EvRef $Context ([pscustomobject]@{path=$review.repairReviewBinding.repairFinalizeInputPath;identity=$review.repairReviewBinding.repairFinalizeInputIdentity}) -Json
    $productionResult=Read-EvRef $Context ([pscustomobject]@{path=$review.repairReviewBinding.repairFinalizeResultPath;identity=$review.repairReviewBinding.repairFinalizeResultIdentity}) -Json
    $productionSource=Read-EvProcessOperation $Context $productionInput $productionResult
    $authority=if($productionSource.schemaVersion-eq1){$productionSource.authorityContext}else{$productionSource.binding}
    $producer=Read-EvRef $Context ([pscustomobject]@{path=$productionSource.sourceLocators.authorizationPackagePath;identity=$authority.authorizationIdentity}) -Json
    Assert-EvReviewProducerRelation $Context $Package $producer ([pscustomobject]@{path=$productionSource.sourceLocators.authorizationPackagePath;identity=$authority.authorizationIdentity})
    if($Package.schemaVersion-ne5-and$producer.taskIdentity-cne$Package.taskIdentity){throw 'SELF_REPAIR_ORIGIN_AUTHORITY_DRIFT'}
    if($Package.schemaVersion-eq5-and$producer.schemaVersion-eq5-and(Get-AiwWorkPlanDefinitionKey $producer.requestContext)-cne(Get-AiwWorkPlanDefinitionKey $Package.requestContext)){throw 'SELF_REPAIR_ORIGIN_PLAN_DRIFT'}
    if($productionResult.status-cne'PASS'-or$(if($producer.schemaVersion-eq5){-not(Test-AiwSameResultContext $authority $producer)}else{$authority.taskId-cne$producer.taskId-or$authority.taskIdentity-cne$producer.taskIdentity})-or$producer.grantee-cne$Package.grantee-or$producer.selfCheckRepairLimit-ne$Package.selfCheckRepairLimit){throw 'SELF_REPAIR_ORIGIN_AUTHORITY_DRIFT'}
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
    $work=$Package.schemaVersion-eq5
    if($work){Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')}
    if($work){$baseFields=@($baseFields|Where-Object{$_-cnotin@('taskIdentity','taskId','taskOwner','taskActor')})+@('requestContext')}
    $nodes=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $node=$Leaf;$limit=[int]$Package.selfCheckRepairLimit
    while($true){
        $fields=@($baseFields);if($node.schemaVersion-eq3){$fields+=@('executionTargetRef','observedTargetState','postTargetState')}
        Assert-EvFields $node $fields
        if($node.schemaVersion-notin@(2,3,4)-or$node.receiptType-cne'AUTHORIZED_ACTION_CONTINUATION'-or$node.status-cne'PASS'-or$node.evidenceGrade-cne'INSTRUCTION_BOUND'-or$node.authorityGranted-isnot[bool]-or$node.authorityGranted){throw 'SELF_REPAIR_RECEIPT_TYPE'}
        foreach($name in @('completedStepIndex','nextStepIndex','selfRepairCycle')){Assert-EvInteger $node.$name}
        if($node.selfRepairCycle-lt0-or$node.selfRepairCycle-gt$limit-or$node.transitionKind-cnotin@('ADVANCE','REPAIR','RETEST')){throw 'SELF_REPAIR_CYCLE'}
        if($work-ne($node.schemaVersion-eq4)){throw 'SELF_REPAIR_CONTEXT_SCHEMA'}
        if($work){Assert-AiwWorkPackageContext $node.requestContext $Package $node.completedAction;Assert-EvResultContext $node $Leaf}
        $authorityNames=@('packageIdentity','actor','repositoryId','projectConfigIdentity','controllerIdentity','userDecision','protectionState')
        if(-not$work){$authorityNames+=@('taskIdentity','taskId','taskOwner','taskActor')}
        foreach($name in $authorityNames){if($node.$name-cne$Leaf.$name){throw ('SELF_REPAIR_AUTHORITY_DRIFT|'+$name)}}
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
        if($source.schemaVersion-eq5){$source=Convert-EvOperationCompact $Context $source}
        $authority=if($source.schemaVersion-eq1){$source.authorityContext}else{$source.binding}
        $action=if($source.schemaVersion-eq1){$source.actionKind}else{$source.intentEnvelope.requestedActionKind}
        if(($Package.schemaVersion-eq4)-ne($node.schemaVersion-eq3)){throw 'SELF_REPAIR_TARGET_SCHEMA'}
        if($node.schemaVersion-eq3){
            Import-Module (Join-Path $PSScriptRoot 'ExecutionTargetContext.psm1')
            if($source.schemaVersion-notin@(4,5)-or-not(Test-EvSameRef $node.executionTargetRef $Package.executionTargetRef $Context)-or-not(Test-EvSameRef $node.executionTargetRef $authority.executionContext.executionTargetRef $Context)-or($node.observedTargetState|ConvertTo-Json -Compress)-cne((Get-AiwExecutionTargetState $authority.executionContext)|ConvertTo-Json -Compress)-or($node.postTargetState|ConvertTo-Json -Compress)-cne($node.observedTargetState|ConvertTo-Json -Compress)){throw 'SELF_REPAIR_TARGET_SOURCE_DRIFT'}
        }

        $sourceFormat=if($source.schemaVersion-eq5){$source.receiptType-ceq'PROCESS_REQUIREMENTS_OPERATION'}else{$source.schemaVersion-in@(1,2,3,4)-and$source.receiptType-ceq'PROCESS_REQUIREMENTS_DISCOVER'-and$source.mode-ceq'DISCOVER'}
        if(-not$sourceFormat-or$source.status-cne'PASS'-or$source.selectionIdentity-cne$node.sourceSelectionIdentity-or$source.contextIdentity-cne$node.sourceContextIdentity-or$action-cne$node.completedAction-or$authority.continuationStepIndex-ne$node.completedStepIndex){throw 'SELF_REPAIR_SOURCE_LINK'}
        $completedScope=@(Get-AiwActionScopeObjects $Package $action $Context)
        if((@($authority.exactScope|Sort-Object)-join'|')-cne(@($completedScope.path|Sort-Object)-join'|')){throw 'SELF_REPAIR_SOURCE_SCOPE_DRIFT'}
        if($work-and($source.schemaVersion-ne5-or$authority.contextType-cne'PROJECT_WORK'-or(Get-AiwContentDescriptorIdentity $authority.context.requestContext)-cne(Get-AiwContentDescriptorIdentity $node.requestContext))){throw 'SELF_REPAIR_SOURCE_CONTEXT_DRIFT'}
        $authorityPairs=@(@('authorizationIdentity','packageIdentity'),@('actor','actor'),@('projectConfigIdentity','projectConfigIdentity'),@('controllerIdentity','controllerIdentity'),@('userDecision','userDecision'))
        if(-not$work){$authorityPairs+=@(@('taskIdentity','taskIdentity'),@('taskId','taskId'),@('taskOwner','taskOwner'),@('taskActor','taskActor'))}
        foreach($pair in $authorityPairs){if($authority.($pair[0])-cne$node.($pair[1])){throw 'SELF_REPAIR_SOURCE_AUTHORITY_DRIFT'}}
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
            $outcome=Get-AiwContinuationSelfCheckOutcome $Context $node.evidenceRefs (Get-EvExpectedResultContext $Package) $candidates $Package.grantee -FrozenCandidateEvidence
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
function Test-EvOriginalClosedCardMove($Context,$Receipt,$Boundary,$Package,[string]$Path,[string]$Text){
    if($Path-cnotmatch'^\.ai-workspace/tasks/archive/(?<name>[^/]+)\.md$'){return $false}
    $active='.ai-workspace/tasks/active/'+$Matches.name+'.md'
    if($active-ceq$Receipt.sourceLocators.taskRelativePath-or$active-cnotin@($Receipt.exactPaths)){return $false}
    $ordinary=$Package.schemaVersion-eq1-or($Package.schemaVersion-eq2-and$Package.repositoryId-ceq'CONTROL')
    if(-not$ordinary-or@($Package.actions).Count-ne1-or$Package.actions[0]-cne'CONTROL_WRITE'-or$active-cnotin@($Package.exactPaths)-or$Path-cnotin@($Package.exactPaths)){throw 'ACCEPTANCE_ARCHIVE_CURRENT_SCOPE'}
    foreach($field in @('transitionPlan','continuationPlan','repairReviewPlan','sourcePublicationBinding','acceptanceBinding','externalBinding','gitPushBinding')){if($null-ne$Package.PSObject.Properties[$field]){throw 'ACCEPTANCE_ARCHIVE_CURRENT_SCOPE'}}
    $pre=@($Package.objectIdentities|Where-Object path -CEQ $active)
    $posts=@(Get-AiwFinalizedObjectPostimages $Boundary @($Receipt.exactPaths))
    $post=@($posts|Where-Object path -CEQ $Path)
    if($pre.Count-ne1-or$pre[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$post.Count-ne1-or$post[0].identity-cne$pre[0].identity){throw 'ACCEPTANCE_ARCHIVE_PREIMAGE_DRIFT'}
    if(@($Boundary.resultReceipts|Where-Object{$_-ceq('OBJECT_POSTIMAGE|'+$active+'|MISSING')}).Count-ne1-or(Get-EvCandidateIdentity (Resolve-EvPath $Context $active -Candidate))-cne'MISSING'){throw 'ACCEPTANCE_ARCHIVE_DELETE_POSTIMAGE'}
    $null=Read-EvRef $Context $post[0] -Candidate
    $ids=[regex]::Matches($Text,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
    if($ids.Count-ne1-or[regex]::Matches($Text,'(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;').Count-ne1){throw 'ACCEPTANCE_ARCHIVE_NOT_CLOSED'}
    if($Text-cmatch'(?m)^- Writer / reviewer / authorization:'){
        # Preserve the established legacy release form; do not add modern fields.
        if([regex]::Matches($Text,'(?m)^- Writer / reviewer / authorization:[ \t]*NONE / NONE / NONE[ \t]*$').Count-ne1){throw 'ACCEPTANCE_CLOSE_LEASE_RELEASE'}
    }else{Assert-EvArchiveClosedRecord $Text}
    # The original closed bytes moved. This says nothing new about the validity
    # of their old success proofs or today's mutable product candidates.
    return $true
}
function Get-AiwBoundaryEvidence($Receipt,$Boundary,$EvidenceContext=$null) {
    Get-EvBoundaryEvidenceCore @PSBoundParameters
}
function Get-EvBoundaryEvidenceCore($Receipt,$Boundary,$EvidenceContext=$null,$PublicationMember=$null) {
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
    $workRequest=Get-EvWorkRequest $Receipt
    if($null-ne$workRequest){Assert-AiwProjectWorkSources $ctx $workRequest}
    $acceptedFacts=$null
    if($null-ne$package-and$null-ne$package.PSObject.Properties['acceptedOutcomeBinding']){
        $currentTask=Read-EvRef $ctx ([pscustomobject]@{path=$actualTaskPath;identity=(Get-EvCandidateIdentity (Resolve-EvPath $ctx $actualTaskPath))})
        $currentPlan=Get-AiwAcceptancePlan ([IO.File]::ReadAllText($currentTask))
        $stage=if($Boundary.mode-ceq'FINALIZE_OUTPUT'){'FINALIZE'}else{'ADMIT'}
        $acceptedFacts=Get-EvOrdinaryAcceptedOutcome $ctx $package $stage $currentPlan
    }elseif($null-ne$package-and$null-ne$package.PSObject.Properties['sourcePublicationBinding']){
        $publication=@(Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -PassThru)[0]
        $eligibility=$null
        $publicationPlan=if($null-ne$PublicationMember){
            $eligibility=& $publication {param($member,$root,$package,$denied) Get-PubMemberEligibility $member $root $package $denied} $PublicationMember $ctx.ProjectRoot $package @(@($ctx.ForbiddenPaths)+@($ctx.CandidateProtectedPaths))
            $null=Get-EvLogicalPath $ctx $package.sourcePublicationBinding.planRef.path
            $eligibility.plan
        }else{Read-EvRef $ctx $package.sourcePublicationBinding.planRef -Json}
        if($publicationPlan.schemaVersion-eq2){
            if($null-ne$PublicationMember){
                $acceptedFacts=$eligibility.acceptedOutcome
                $state=Get-EvReadState $ctx;$observed=$acceptedFacts.readState
                foreach($reference in $observed.references.Values){$state.references[$reference.path+'|'+$reference.identity]=$reference}
                foreach($producer in $observed.producers.Values){Add-EvValidatedProducer $ctx $producer.pair $producer.source $producer.input $producer.result}
                foreach($guard in $observed.guards){$state.guards.Add($guard)}
            }else{
                $acceptedFacts=& $publication {param($root,$plan,$package,$denied,$context) Get-PubAcceptedOutcomeFacts $root $plan $package $denied $context} $ctx.ProjectRoot $publicationPlan $package @($ctx.ForbiddenPaths) $ctx
            }
        }
    }
    $acceptedCoverage=if($null-ne$acceptedFacts){@($acceptedFacts.coveredKinds)}else{@()}
    # Empty typed evidence still hands the last consumer the original full path guard.
    if($skipTypedEvidence){$handoff=Get-EvRetentionHandoff $ctx;$values=if($null-ne$workRequest){@($package,$workRequest)+@($handoff.references)}elseif($null-ne$acceptedFacts){@($package)+@($acceptedFacts.retentionValues)+@($handoff.references)}else{@()};return [pscustomobject]@{references=@();records=@();acceptedCoverage=$acceptedCoverage;evidenceCeiling='INSTRUCTION_BOUND';retentionValues=$values;retentionContext=$handoff.context;retentionProducers=$handoff.producers}}
    $taskText='';$plan=$null
    if($null-ne$Receipt.authorityContext.PSObject.Properties['contextType']-and$Receipt.authorityContext.contextType-ceq'PROJECT_WORK'){$plan=Get-AiwProjectWorkPlan $Receipt.authorityContext.context.requestContext}
    if($Receipt.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'){
        Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
        $taskText=(Read-AiwControlTransitionTask $ctx.ProjectRoot $actualTaskPath).Text
        $plan=Get-AiwAcceptancePlan $taskText
    }
    # Reuse the actual plans selected/validated here for last-consumer retention.
    # This is an in-memory handoff, not another closure validator or saved proof.
    $retentionValues=[Collections.Generic.List[object]]::new()
    if($null-ne$plan){$retentionValues.Add($plan)}
    if($null-ne$package){$retentionValues.Add($package)}
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
        if($null-ne$Receipt.authorityContext.PSObject.Properties['contextType']-and$Receipt.authorityContext.contextType-ceq'PROJECT_WORK'){$requirements=Get-EvWorkRecordRequirements $ctx $Receipt.authorityContext.context.requestContext $ref.kind $candidateObjects $requirements}
        if($null-ne$package-and$null-ne$package.PSObject.Properties['acceptanceBinding']){$requirements=$package.acceptanceBinding.requirementsRef}
        $expectedActor=if($Boundary.mode-ceq'FINALIZE_OUTPUT'-and$ref.kind-ceq$needed){[string]$Receipt.actor}else{''}
        $auth=if($ref.kind-cin@('REVIEW_VERDICT','RESULT_ACCEPTANCE')-and$ref.kind-ceq$needed){[string]$Receipt.authorityContext.authorizationIdentity}else{''}
        $records+=Read-AiwResultEvidence $ctx $ref (Get-EvExpectedResultContext $Receipt) $candidateObjects $requirements -ExpectedActor $expectedActor -AuthorizationIdentity $auth
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
        if(Test-AiwReviewSelfCheckRequired $plan){if($Boundary.mode-ceq'ADMIT_ACTION'){Assert-AiwReviewSelfCheck $ctx $refs (Get-EvExpectedResultContext $Receipt) $candidateObjects $plan}}
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
            continue # The archive row distinguishes an original move from new closure.
        }
        $closedText=[IO.File]::ReadAllText($closedFull)
        if($closedText-cnotmatch '(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){continue}
        $closedIds=[regex]::Matches($closedText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
        if($closedIds.Count-ne1){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        $originalMove=$taskText-cmatch'(?m)^- Range summary:[^\r\n]*lifecycle=ACTIVE;'-and(Test-EvOriginalClosedCardMove $ctx $Receipt $Boundary $package $closedPath $closedText)
        if(-not$originalMove){Assert-AiwTaskClosure $ctx $closedText $closedIds[0].Groups['id'].Value $Boundary -ExcludedReviewActors @($package.issuer)}
        # Cancellation/supersession may legally have no acceptance plan. Keep
        # the real decision reference already consumed by the closure validator.
        foreach($decision in [regex]::Matches($closedText,'(?m)^- Closure decision: (?<path>.+)#(?<identity>\d+\|[A-F0-9]{64})[ \t]*$')){$retentionValues.Add([pscustomobject]@{path=$decision.Groups['path'].Value;identity=$decision.Groups['identity'].Value})}
        $closedPlan=Get-AiwAcceptancePlan $closedText
        if($null-ne$closedPlan){$retentionValues.Add($closedPlan)}
    }
    $handoff=Get-EvRetentionHandoff $ctx
    return [pscustomobject]@{references=@($refs);records=@($records);acceptedCoverage=$acceptedCoverage;evidenceCeiling='INSTRUCTION_BOUND';retentionValues=@($retentionValues.ToArray())+@($handoff.references)+$(if($null-ne$acceptedFacts){@($acceptedFacts.retentionValues)}else{@()});retentionContext=$handoff.context;retentionProducers=$handoff.producers}
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
    if($null-ne$Context.PSObject.Properties['HistoricalPathGuards']){
        $full=[IO.Path]::GetFullPath($Path,$Context.ProjectRoot)
        foreach($guard in $Context.HistoricalPathGuards){
            if($full.Equals($guard.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)-or$full.StartsWith($guard.RepositoryRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$null=Resolve-EvPath $guard $Path -AllowMissing -AllowDirectory -Observation}
        }
    }
    Resolve-EvPath $Context $Path -AllowMissing -AllowDirectory -Observation
}
function Read-AiwEvidenceReference($Context,$Reference,[switch]$Json,[switch]$Candidate,[switch]$Section) {
    Read-EvRef $Context $Reference -Json:$Json -Candidate:$Candidate -Section:$Section
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
    $repo=if($Package.schemaVersion-in@(2,4,5)){$Package.repositoryId}else{'REPO_LOCAL'}
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
    foreach($field in @('continuationPlan','repairReviewPlan','repairReviewBinding','acceptanceBinding','externalBinding','gitPushBinding','acceptedOutcomeBinding')){if($null-ne$Package.PSObject.Properties[$field]){return $false}}
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
    if($input.schemaVersion-notin@(3,4)-or$input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'}
    $source=Read-EvProcessOperation $Context $input $result
    if($source.schemaVersion-notin@(3,4,5)-or$source.status-cne'PASS'-or($source.schemaVersion-ne5-and($source.mode-cne'DISCOVER'-or$source.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'))){throw 'QUALITY_PRODUCTION_DISCOVER_REQUIRED'}
    $a=$source.binding;$action=$source.intentEnvelope.requestedActionKind
    $producer=Read-EvRef $Context ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity}) -Json
    Assert-EvReviewProducerRelation $Context $Package $producer ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity})
    if($action-cnotin@('SOURCE_WRITE','TEST_WRITE','CONTROL_WRITE','TEST_RUN')-or$action-cnotin$producer.actions-or$action-cnotin$a.authorizedActions-or$producer.grantee-cne$Writer-or$a.actor-cne$Writer-or$(if($producer.schemaVersion-eq5){-not(Test-AiwSameResultContext $a $producer)}else{$a.taskId-cne$producer.taskId-or$producer.owner-cne$Package.owner-or$a.taskOwner-cne$producer.owner-or$a.taskIdentity-cne$producer.taskIdentity})-or$a.projectConfigIdentity-cne$producer.projectConfigIdentity-or$a.userDecision-cne$producer.userConfirmation){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-ceq'TASK_OWNER'-and$producer.issuer-cne$producer.owner){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-ceq'PROJECT_CONTROLLER'-and($producer.issuer-cne$producer.issuerControllerId-or$a.controllerIdentity-cne$producer.controllerControlIdentity-or$producer.issuerControllerEpoch-lt1)){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($producer.issuerRole-cnotin@('TASK_OWNER','PROJECT_CONTROLLER')){throw 'QUALITY_PRODUCTION_AUTHORITY_DRIFT'}
    if($result.actionOutcome-cne$(if($action-ceq'TEST_RUN'){'PASS'}else{'OBSERVED'})){throw 'QUALITY_PRODUCTION_NOT_SUCCESSFUL'}
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    Assert-EvOriginalFinalizeDecision $source $input $result -Failure QUALITY_PRODUCTION_FINALIZE_DRIFT
    if(-not([IO.Path]::GetFullPath($a.projectRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_PRODUCTION_ROOT_DRIFT'}
    $guard=New-AiwPackageEvidenceContext $Context.ProjectRoot $producer $source.sourceLocators.frameworkRoot (@($Context.ForbiddenPaths)+@($a.forbiddenScope)) -TaskPath $source.sourceLocators.taskRelativePath -ProtectedPaths (@($Context.CandidateProtectedPaths)+@($a.protectedScope))
    Share-EvReadState $guard $Context
    if(-not$guard.RepositoryRoot.Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'QUALITY_PRODUCTION_REPOSITORY_DRIFT'}
    $scope=@(Get-AiwActionScopeObjects $producer $action $guard)
    if((@($scope.path|Sort-Object)-join'|')-cne(@($a.exactScope|Sort-Object)-join'|')){throw 'QUALITY_PRODUCTION_SCOPE_DRIFT'}
    # Scope composition retains its original NEW sentinel. Normalize to the
    # evidence MISSING state only after the strict production composition.
    $productionPostimages=@(Get-AiwFinalizedObjectPostimages $input @($a.exactScope))
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=$productionPostimages}))
    if($null-ne$producer.PSObject.Properties['qualityBinding']){
        Assert-AiwQualityBinding $producer.qualityBinding
        if($producer.qualityBinding.policyRef.identity-cne$source.sourceBindings.policyIdentity){throw 'QUALITY_HISTORICAL_POLICY_UNBOUND'}
        $producerRepository=if($producer.schemaVersion-in@(2,4,5)){$producer.repositoryId}else{'REPO_LOCAL'}
        if($producer.qualityBinding.subject.repositoryId-cne$producerRepository){throw 'QUALITY_HISTORICAL_SUBJECT_DRIFT'}
        $declared=@($producer.qualityBinding.subject.exactPaths|Sort-Object -CaseSensitive)
        if(($declared-join'|')-cne(@($Candidates.path|Sort-Object -CaseSensitive)-join'|')){throw 'QUALITY_SUBJECT_INCOMPLETE'}
        foreach($modified in $post){$member=@($Candidates|Where-Object path -CEQ $modified.path);if($member.Count-ne1-or$member[0].identity-cne$modified.identity){throw 'QUALITY_PRODUCTION_POSTIMAGE_DRIFT'}}
        # The original package binds the complete declared A. Its actual F
        # proves M; the current fresh review package freezes and guards all A.
        # Existing explicit M/A plans retain their stronger unchanged-member
        # bindings. No write authority is inferred for those other members.
        $parent=Get-EvReviewParent $guard $producer
        $complete=@(if($null-ne$parent.PSObject.Properties['repairReviewPlan']){Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwComposedReviewCandidate $guard $producer $productionPostimages)})}else{$Candidates})
    }else{$complete=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwComposedReviewCandidate $guard $producer $productionPostimages)}))}
    $acceptedOutcome=$null
    if($null-ne$producer.PSObject.Properties['acceptedOutcomeBinding']){
        # Only after original source/package/decision/root/scope and frozen
        # quality-policy linkage are bound; today's policy is not substituted.
        $acceptedOutcome=Get-EvOrdinaryAcceptedOutcome $guard $producer FINALIZE -Historical
    }
    Assert-EvSameCandidates $complete $Candidates $guard
    foreach($ref in $Candidates){$null=Read-EvRef $guard $ref -Candidate}
    $typedPrep=@();$typedResult=@()
    foreach($ref in $input.evidenceRefs){
            $raw=Read-EvRef $guard ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            $purpose=if($ref.kind-ceq'SELF_CHECK'){'HISTORICAL_SUCCESS'}else{'CURRENT_CANDIDATE'}
            $history=if($purpose-ceq'HISTORICAL_SUCCESS'){@($Pair)}else{@()}
            $null=Read-AiwResultEvidence $guard $ref (Get-EvExpectedResultContext $producer) $raw.candidateObjects $raw.requirementsRef -RequireSuccess -ExpectedActor $(if($ref.kind-ceq'SELF_CHECK'){$Writer}else{''}) -EvidencePurpose $purpose -OriginalFinalize $history
            switch($ref.kind){SELF_CHECK{$typedPrep+='SELF_CHECK_BOUND'};REVIEW_VERDICT{$typedResult+='REVIEW_VERDICT_BOUND'};RESULT_ACCEPTANCE{$typedResult+='RESULT_ACCEPT_RECORDED'}}
    }
    if($null-ne$acceptedOutcome){
        if('SELF_CHECK'-cin$acceptedOutcome.coveredKinds){$typedPrep+='SELF_CHECK_BOUND'}
        if('REVIEW_VERDICT'-cin$acceptedOutcome.coveredKinds){$typedResult+='REVIEW_VERDICT_BOUND'}
        if('RESULT_ACCEPTANCE'-cin$acceptedOutcome.coveredKinds){$typedResult+='RESULT_ACCEPT_RECORDED'}
    }
    $providedPreparation=@($input.preparationReceipts|Where-Object{$_-cne'SELF_CHECK_BOUND'})+$typedPrep
    $providedResult=@($input.resultReceipts|Where-Object{$_-cnotin@('REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED','DELIVERY_RECEIPT')})+$typedResult
    if($null-ne$input.PSObject.Properties['deliveryContext']){
        Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
        $observation=Get-AiwDeliveryObservation $input.deliveryContext
        if($null-eq$result.PSObject.Properties['delivery']-or($result.delivery|ConvertTo-Json -Compress)-cne($observation|ConvertTo-Json -Compress)){throw 'QUALITY_PRODUCTION_DELIVERY_DRIFT'}
        if($input.deliveryContext.channel-ceq'TASK_MESSAGE'){
            if(-not$observation.delivered-or$input.deliveryContext.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'QUALITY_PRODUCTION_DELIVERY_UNPROVEN'}
            $hostResult=Read-EvRef $guard ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
            if((Get-AiwCodexSendOutcome $hostResult $input.deliveryContext.expectedRecipient).outcome-cne'SUCCESS'){throw 'QUALITY_PRODUCTION_DELIVERY_UNPROVEN'}
        }
        $providedResult+='DELIVERY_RECEIPT'
    }elseif(@($input.deliveryReceipts).Count){$providedResult+='DELIVERY_RECEIPT'}
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
    Add-EvValidatedProducer $guard $Pair $source $input $result
    [pscustomobject]@{writer=$Writer;source=$source;package=$producer;postimages=$complete;modifiedObjects=$post;acceptedOutcome=$acceptedOutcome;input=$input;result=$result}
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

# Invocation-owned parsing reuse. Callers provide original references, never
# a verified graph. Every use observes the necessary original bytes again.
$script:CompletedEvidenceObservations=$null
function Invoke-EvCompletedEvidenceScope([scriptblock]$Body,[object[]]$Arguments=@()){
    $previous=$script:CompletedEvidenceObservations
    if($null-eq$previous){$script:CompletedEvidenceObservations=@{}}
    try{& $Body @Arguments}finally{$script:CompletedEvidenceObservations=$previous}
}
function Add-EvReadObservation($Context,$Reference,[bool]$Candidate=$false){
    $state=Get-EvReadState $Context
    if(-not$state.captureObservations){return}
    $guard=$Context|Select-Object ProjectRoot,RepositoryRoot,Roots,ForbiddenPaths,CandidateProtectedPaths,ExecutionContext
    $key=(@($Reference.path,$Reference.identity,$Candidate,$guard)|ConvertTo-Json -Depth 40 -Compress)
    if(-not$state.observations.ContainsKey($key)){
        $state.observations.Add($key,[pscustomobject]@{guard=$guard;reference=$Reference;candidate=$Candidate})
    }
}
function Assert-EvAcceptedOutcomeBinding($Binding){
    Assert-EvFields $Binding @('schemaVersion','useRef','additionalEvidence','additionalConsumption')
    Assert-EvInteger $Binding.schemaVersion
    if($Binding.schemaVersion-ne1){throw 'ACCEPTED_USE_BINDING_SCHEMA'}
    Assert-EvRef $Binding.useRef
    Assert-EvRefs $Binding.additionalEvidence -Typed
    $consumption=Get-EvConsumption $Binding additionalConsumption
    if($Binding.additionalEvidence.Count){
        if($consumption.purpose-cne'HISTORICAL_SUCCESS'){throw 'ACCEPTED_USE_ADDITIONAL_NOT_COMPLETE'}
    }elseif($consumption.purpose-cne'CURRENT_CANDIDATE'-or$consumption.originalFinalize.Count){
        throw 'ACCEPTED_USE_EMPTY_ADDITIONAL_CONSUMPTION'
    }
}
function Assert-EvUniqueEvidencePaths($Context,$References){
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($reference in $References){
        if(-not$paths.Add((Get-EvLogicalPath $Context $reference.path))){throw 'EVIDENCE_DUPLICATE_REF'}
    }
}
function Read-EvAcceptedUse($Context,$Reference,$ReadDocuments=$null){
    $use=Read-EvRef -ReadDocuments $ReadDocuments $Context $Reference -Json
    Assert-EvFields $use @('schemaVersion','kind','requirementsRef','assuranceEvidence','assuranceConsumption','basisRefs','mappings')
    Assert-EvInteger $use.schemaVersion
    if($use.schemaVersion-ne1-or$use.kind-cne'ACCEPTED_OUTCOME_USE'){throw 'ACCEPTED_USE_SCHEMA'}
    Assert-EvRef $use.requirementsRef -Section
    Assert-EvRefs $use.assuranceEvidence -Typed -Nonempty
    Assert-EvUniqueEvidencePaths $Context $use.assuranceEvidence
    if(@($use.assuranceEvidence|Where-Object kind -CEQ RESULT_ACCEPTANCE).Count-ne1){throw 'ACCEPTED_USE_UNIQUE_ACCEPTANCE_REQUIRED'}
    $consumption=Get-EvConsumption $use assuranceConsumption
    if($consumption.purpose-cne'HISTORICAL_SUCCESS'){throw 'ACCEPTED_USE_ORIGINAL_SUCCESS_REQUIRED'}
    Assert-EvArray $use.basisRefs
    if($use.basisRefs.Count-eq0){throw 'EVIDENCE_REFS_EMPTY'}
    $basisPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($basis in $use.basisRefs){
        Assert-EvRef $basis -Section
        if(-not$basisPaths.Add($basis.path)){throw 'EVIDENCE_DUPLICATE_REF'}
    }
    Assert-EvArray $use.mappings
    if($use.mappings.Count-eq0){throw 'ACCEPTED_USE_MAPPING_EMPTY'}
    $targets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $sources=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($mapping in $use.mappings){
        $fields=@('operation','sourcePath','targetPath','basisIndexes')
        if($null-ne$mapping.PSObject.Properties['operation']-and$mapping.operation-ceq'WRITE'){$fields+='preparedRef'}
        Assert-EvFields $mapping $fields
        if($mapping.operation-cnotin@('WRITE','DELETE')){throw 'ACCEPTED_USE_MAPPING_OPERATION'}
        foreach($name in @('sourcePath','targetPath')){
            Assert-EvString $mapping.$name
            if($name-ceq'targetPath'-and([IO.Path]::IsPathRooted($mapping.$name)-or$mapping.$name.Contains('\'))){throw 'ACCEPTED_USE_MAPPING_RELATIVE_PATH'}
        }
        $target=Get-EvLogicalPath $Context $mapping.targetPath -Candidate
        if(-not$targets.Add($target)-or-not$sources.Add($mapping.sourcePath)){throw 'ACCEPTED_USE_MAPPING_DUPLICATE'}
        if($mapping.operation-ceq'WRITE'){Assert-EvRef $mapping.preparedRef}
        Assert-EvArray $mapping.basisIndexes
        if($mapping.basisIndexes.Count-eq0){throw 'ACCEPTED_USE_MAPPING_BASIS'}
        $indexes=[Collections.Generic.HashSet[int]]::new()
        foreach($index in $mapping.basisIndexes){
            Assert-EvInteger $index
            if($index-lt0-or$index-ge$use.basisRefs.Count-or-not$indexes.Add([int]$index)){throw 'ACCEPTED_USE_MAPPING_BASIS'}
        }
    }
    return $use
}


function Get-EvAcceptedGraph($Context,$Use,$UseRef,$ReadDocuments=$null){
    $roots=@($Context.Roots|ForEach-Object{[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($_)).ToUpperInvariant()}|Sort-Object -Unique)
    $forbidden=@(Get-EvAbsoluteRestrictions @($Context.ForbiddenPaths) $Context.Roots|ForEach-Object{$_.ToUpperInvariant()}|Sort-Object -Unique)
    $protected=@(Get-EvAbsoluteRestrictions @($Context.CandidateProtectedPaths) $Context.Roots|ForEach-Object{$_.ToUpperInvariant()}|Sort-Object -Unique)
    $execution=if($null-ne$Context.PSObject.Properties['ExecutionContext']){$Context.ExecutionContext}else{$null}
    $key=(@($Context.ProjectRoot.ToUpperInvariant(),$Context.RepositoryRoot.ToUpperInvariant(),(Get-EvLogicalPath $Context $UseRef.path).ToUpperInvariant(),$UseRef.identity,$roots,$forbidden,$protected,$execution)|ConvertTo-Json -Depth 20 -Compress)
    if($null-ne$script:CompletedEvidenceObservations-and$script:CompletedEvidenceObservations.ContainsKey($key)){
        $saved=$script:CompletedEvidenceObservations[$key]
        foreach($observation in $saved.observations){
            # Guards are those of the actual original read, including original
            # producer restrictions. The key independently binds today's guard.
            $guard=$observation.guard|Select-Object *
            $guard|Add-Member Reading $Context.Reading
            Share-EvReadState $guard $Context
            $null=Read-EvRef -ReadDocuments $ReadDocuments $guard $observation.reference -Candidate:$observation.candidate
        }
        foreach($producer in $saved.producers){Add-EvValidatedProducer $Context $producer.pair $producer.source $producer.input $producer.result}
        foreach($guard in $saved.guards){(Get-EvReadState $Context).guards.Add($guard)}
        return $saved
    }
    $graphContext=$Context|Select-Object * -ExcludeProperty RetentionReadState
    (Get-EvReadState $graphContext).captureObservations=$true
    $graph=New-EvCompletionGraph $ReadDocuments
    $consumption=Get-EvConsumption $Use assuranceConsumption
    Add-EvCompletionFinalizes $graphContext $graph $consumption.originalFinalize
    $anchor=@($Use.assuranceEvidence|Where-Object kind -CEQ RESULT_ACCEPTANCE)[0]
    $anchorRecord=Read-EvRef -ReadDocuments $ReadDocuments $graphContext ([pscustomobject]@{path=$anchor.path;identity=$anchor.identity}) -Json
    foreach($reference in $Use.assuranceEvidence){
        $record=if(Test-EvSameRef $reference $anchor $graphContext){$anchorRecord}else{Read-EvRef -ReadDocuments $ReadDocuments $graphContext ([pscustomobject]@{path=$reference.path;identity=$reference.identity}) -Json}
        if($record.taskId-cne$anchorRecord.taskId){throw 'ACCEPTED_USE_ORIGINAL_TASK_DRIFT'}
        Add-EvCompletionNode $graphContext $graph $reference $record.taskId $record.candidateObjects $record.requirementsRef -ObservedRecord $record
    }
    Complete-EvCompletionGraph $graphContext $graph
    $graph.readDocuments=$null
    (Get-EvReadState $graphContext).captureObservations=$false
    $anchorNode=$graph.nodes[(Get-EvTypedKey $graphContext $anchor)]
    if(-not$anchorNode.context.RepositoryRoot.Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){
        throw 'ACCEPTED_USE_SAME_REPOSITORY_REQUIRED'
    }
    foreach($node in $graph.nodes.Values){
        if($null-ne$node.context.PSObject.Properties['ExecutionContext']-and$null-ne$node.context.ExecutionContext-and$node.context.ExecutionContext.targetKind-cne'SAME_ROOT'){
            throw 'ACCEPTED_USE_SAME_ROOT_REQUIRED'
        }
    }
    $index=New-EvCandidateIndex (New-EvLogicalContext $anchorNode.context) $anchorNode.record.candidateObjects
    $trace=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($node in $graph.nodes.Values){
        $null=$trace.Add((Get-EvLogicalPath $node.context $node.reference.path)+'|'+$node.reference.identity)
        $null=$trace.Add((Get-EvLogicalPath $node.context $node.record.requirementsRef.path)+'|'+$node.record.requirementsRef.identity)
        foreach($candidate in $node.record.candidateObjects){
            $null=$trace.Add((Get-EvLogicalPath $node.context $candidate.path -Candidate)+'|'+$candidate.identity)
        }
    }
    $state=Get-EvReadState $graphContext
    foreach($reference in $state.references.Values){$null=$trace.Add($reference.path+'|'+$reference.identity)}
    $observations=@($state.observations.Values)
    $saved=[pscustomobject]@{graph=$graph;anchor=$anchorNode;index=$index;trace=$trace;observations=$observations;producers=@($state.producers.Values);guards=$state.guards.ToArray()}
    if($null-ne$script:CompletedEvidenceObservations){$script:CompletedEvidenceObservations[$key]=$saved}
    foreach($observation in $observations){
        $targetState=Get-EvReadState $Context
        $targetState.references[$observation.reference.path+'|'+$observation.reference.identity]=$observation.reference
    }
    foreach($producer in $saved.producers){Add-EvValidatedProducer $Context $producer.pair $producer.source $producer.input $producer.result}
    foreach($guard in $saved.guards){(Get-EvReadState $Context).guards.Add($guard)}
    return $saved
}
function Get-EvAcceptedOutcomeCore($Context,$Binding,$Objects,[string[]]$RequiredKinds=@(),[string]$TaskId='',$RequirementsRef=$null,$CoverageObjects=@()){
    $readDocuments=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    try{
    Assert-EvAcceptedOutcomeBinding $Binding
    Assert-EvUniqueEvidencePaths $Context $Binding.additionalEvidence
    $use=Read-EvAcceptedUse $Context $Binding.useRef $readDocuments
    return Get-EvAcceptedOutcomeFromUse $Context $Binding $Objects $RequiredKinds $TaskId $RequirementsRef $CoverageObjects $use $readDocuments
    }finally{$readDocuments.Clear()}
}

# Only the strict readers above and the publication module's same-stack U
# reader enter here. This private continuation is not exported and accepts
# neither a PASS nor a graph; current requirements/objects and all originals
# still pass through the ordinary consumers below.
function Get-EvAcceptedOutcomeFromUse($Context,$Binding,$Objects,[string[]]$RequiredKinds,[string]$TaskId,$RequirementsRef,$CoverageObjects,$use,$ReadDocuments=$null){
    $null=Read-EvRef -ReadDocuments $ReadDocuments $Context $use.requirementsRef -Section
    if($null-ne$RequirementsRef-and-not(Test-EvSameRef $RequirementsRef $use.requirementsRef $Context)){throw 'ACCEPTED_USE_CURRENT_REQUIREMENTS_DRIFT'}
    $original=Get-EvAcceptedGraph $Context $use $Binding.useRef $ReadDocuments
    if($TaskId-and$original.anchor.record.taskId-ceq$TaskId){throw 'ACCEPTED_USE_DISTINCT_TASK_REQUIRED'}
    $sourceContext=$original.anchor.context
    $basisPaths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($basis in $use.basisRefs){
        $path=Get-EvLogicalPath $sourceContext $basis.path -Observation
        $candidatePath=Get-EvLogicalPath $sourceContext $basis.path -Candidate
        $candidate=$original.index.ContainsKey($candidatePath)-and$original.index[$candidatePath].identity-ceq$basis.identity
        if(-not$candidate-and-not$original.trace.Contains($path+'|'+$basis.identity)){throw ('ACCEPTED_USE_ORIGINAL_BASIS_UNBOUND|'+$basis.path)}
        $basisPath=if($candidate){$candidatePath}else{$path}
        if(-not$basisPaths.Add($basisPath)){throw 'EVIDENCE_DUPLICATE_REF'}
        $null=Read-EvRef -ReadDocuments $ReadDocuments $sourceContext $basis -Candidate:$candidate -Section
    }
    $maps=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($mapping in $use.mappings){
        $source=Get-EvLogicalPath $sourceContext $mapping.sourcePath -Candidate
        if(-not$original.index.ContainsKey($source)){throw ('ACCEPTED_USE_SOURCE_NOT_IN_Q|'+$mapping.sourcePath)}
        if($mapping.sourcePath-cne$original.index[$source].path){throw 'ACCEPTED_USE_SOURCE_KEY_DRIFT'}
        $expected=if($mapping.operation-ceq'DELETE'){'MISSING'}else{$mapping.preparedRef.identity}
        if($original.index[$source].identity-cne$expected){throw ('ACCEPTED_USE_FROZEN_BYTES_DRIFT|'+$mapping.sourcePath)}
        $maps.Add((Get-EvLogicalPath $Context $mapping.targetPath -Candidate),[pscustomobject]@{mapping=$mapping;source=$original.index[$source]})
    }
    $additional=$null
    if($Binding.additionalEvidence.Count){
        $additional=New-EvCompletionGraph $ReadDocuments
        $consumption=Get-EvConsumption $Binding additionalConsumption
        Add-EvCompletionFinalizes $Context $additional $consumption.originalFinalize
        foreach($ref in $Binding.additionalEvidence){
            $record=Read-EvRef -ReadDocuments $ReadDocuments $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            if($record.taskId-cne$TaskId-or-not(Test-EvSameRef $record.requirementsRef $use.requirementsRef $Context)){
                throw 'ACCEPTED_USE_ADDITIONAL_PURPOSE_DRIFT'
            }
            $members=New-EvCandidateIndex (New-EvLogicalContext $Context) $record.candidateObjects
            $usePath=Get-EvLogicalPath $Context $Binding.useRef.path
            if(-not$members.ContainsKey($usePath)-or$members[$usePath].identity-cne$Binding.useRef.identity){throw 'ACCEPTED_USE_ADDITIONAL_U_UNBOUND'}
            $prepared=@($use.mappings|Where-Object operation -CEQ WRITE|Where-Object{
                $p=Get-EvLogicalPath $Context $_.preparedRef.path
                $members.ContainsKey($p)-and$members[$p].identity-ceq$_.preparedRef.identity
            })
            if($prepared.Count-eq0){throw 'ACCEPTED_USE_ADDITIONAL_PREPARED_UNBOUND'}
            Add-EvCompletionNode $Context $additional $ref $record.taskId $record.candidateObjects $record.requirementsRef
        }
        Complete-EvCompletionGraph $Context $additional
        $additional.readDocuments=$null
    }
    $guaranteed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $additionalIndexes=[Collections.Generic.List[object]]::new()
    foreach($node in $original.graph.nodes.Values){
        if(-not$node.context.RepositoryRoot.Equals($sourceContext.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-EvSameCandidates $node.record.candidateObjects $original.anchor.record.candidateObjects $sourceContext)){continue}
        if($node.reference.kind-ceq'REVIEW_VERDICT'){
            $producer=Read-EvRef -ReadDocuments $ReadDocuments $node.context $node.record.authorizationRef -Json
            try{Assert-EvReviewIndependence $producer $node.record -Required}catch{if($_.Exception.Message-ceq'EVIDENCE_REVIEW_INDEPENDENCE'){continue};throw}
        }
        $null=$guaranteed.Add($node.reference.kind)
    }
    if($null-ne$additional){foreach($node in $additional.nodes.Values){
        if($node.record.taskId-cne$TaskId-or-not(Test-EvSameRef $node.record.requirementsRef $use.requirementsRef $Context)){continue}
        if($node.reference.kind-ceq'REVIEW_VERDICT'){
            $producer=Read-EvRef -ReadDocuments $ReadDocuments $node.context $node.record.authorizationRef -Json
            try{Assert-EvReviewIndependence $producer $node.record -Required}catch{if($_.Exception.Message-ceq'EVIDENCE_REVIEW_INDEPENDENCE'){continue};throw}
        }
        $members=New-EvCandidateIndex (New-EvLogicalContext $node.context) $node.record.candidateObjects
        $usePath=Get-EvLogicalPath $Context $Binding.useRef.path
        if($members.ContainsKey($usePath)-and$members[$usePath].identity-ceq$Binding.useRef.identity){
            $additionalIndexes.Add([pscustomobject]@{kind=$node.reference.kind;members=$members})
        }
    }}
    $selected=[Collections.Generic.List[object]]::new()
    $covered=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($kind in @('SELF_CHECK','REVIEW_VERDICT','RESULT_ACCEPTANCE')){$null=$covered.Add($kind)}
    $currentTargets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $coverage=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($object in $Objects){$null=$currentTargets.Add((Get-EvLogicalPath $Context $object.path -Candidate))}
    # The actual consumer derives this logical assurance subject from current
    # quality selection. It does not expand this action's physical write/read A.
    foreach($object in @($Objects)+@($CoverageObjects)){
        Assert-EvRef $object -Candidate
        $path=Get-EvLogicalPath $Context $object.path -Candidate
        if($coverage.ContainsKey($path)){if($coverage[$path].identity-cne$object.identity){throw 'ACCEPTED_USE_TARGET_POSTIMAGE_DRIFT'}}
        else{$coverage.Add($path,$object)}
    }
    foreach($object in $coverage.Values){
        Assert-EvRef $object -Candidate
        $target=Get-EvLogicalPath $Context $object.path -Candidate
        if(-not$maps.ContainsKey($target)){throw ('ACCEPTED_USE_TARGET_UNMAPPED|'+$object.path)}
        $entry=$maps[$target];$mapping=$entry.mapping;$source=$entry.source
        $expected=if($mapping.operation-ceq'DELETE'){'MISSING'}else{$mapping.preparedRef.identity}
        if($object.identity-cne$expected){throw ('ACCEPTED_USE_TARGET_POSTIMAGE_DRIFT|'+$object.path)}
        # Original Q is historical. Only selected prepared bytes are observed;
        # the old production directory is not a second current-candidate gate.
        if($currentTargets.Contains($target)-and$mapping.operation-ceq'WRITE'){$null=Read-EvRef -ReadDocuments $ReadDocuments $Context $mapping.preparedRef}
        foreach($kind in @('SELF_CHECK','REVIEW_VERDICT','RESULT_ACCEPTANCE')){
            $has=$guaranteed.Contains($kind)
            if(-not$has-and$mapping.operation-ceq'WRITE'){
                $p=Get-EvLogicalPath $Context $mapping.preparedRef.path
                foreach($index in $additionalIndexes){if($index.kind-ceq$kind-and$index.members.ContainsKey($p)-and$index.members[$p].identity-ceq$mapping.preparedRef.identity){$has=$true;break}}
            }
            if(-not$has){
                if($kind-cin$RequiredKinds){throw ('ACCEPTED_USE_REQUIRED_STAGE_UNCOVERED|'+$kind+'|'+$object.path)}
                $null=$covered.Remove($kind)
            }
        }
        if($currentTargets.Contains($target)){$selected.Add([pscustomobject]@{targetPath=$object.path;identity=$expected;mapping=$mapping;sourceRef=$source})}
    }
    $handoff=Get-EvRetentionHandoff $Context
    [pscustomobject]@{use=$use;binding=$Binding;original=$original;additional=$additional;objects=$selected.ToArray();coveredKinds=@($covered);retentionValues=@($use,$Binding)+@($handoff.references)}
}

function Assert-EvAcceptedDeleteUnused($Context,$Package,$Objects){
    $deletes=@($Objects|Where-Object{$_.mapping.operation-ceq'DELETE'})
    if(-not$deletes.Count){return}
    if($Package.schemaVersion-ne1-or$Package.actions.Count-ne1-or$Package.actions[0]-cne'SOURCE_WRITE'){
        throw 'ACCEPTED_USE_DELETE_REPO_LOCAL_SOURCE_ONLY'
    }
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    $configPath=Resolve-EvPath $Context '.ai-workspace/project.json'
    $config=Read-EvRef $Context ([pscustomobject]@{path=$configPath;identity=$Package.projectConfigIdentity}) -Json
    $policyPath=Resolve-EvPath $Context '.ai-workspace/process-policy.json'
    $policyRef=[pscustomobject]@{path=$policyPath;identity=(Get-EvCandidateIdentity $policyPath)}
    $policy=Read-EvRef $Context $policyRef -Json
    $denied=@(Get-EvAbsoluteRestrictions (@($Context.ForbiddenPaths)+@($Context.CandidateProtectedPaths)) $Context.Roots)
    $key='ADOPTED|'+$Context.ProjectRoot+'|'+$Context.RepositoryRoot+'|'+$Package.projectConfigIdentity+'|'+$policyRef.identity+'|'+($denied-join'|')
    $saved=if($null-ne$script:CompletedEvidenceObservations-and$script:CompletedEvidenceObservations.ContainsKey($key)){$script:CompletedEvidenceObservations[$key]}else{$null}
    if($null-ne$saved){
        Assert-AiwProjectPolicySourceClosure $saved.closure
        # Knowledge indexes are actual adopted references. Reopen them through
        # their owner so permissions and current index bytes remain fresh.
    }else{
        $closure=Get-AiwProjectPolicySourceClosure -ProjectRoot $Context.ProjectRoot -Rules @($policy.rules) -ForbiddenPaths $denied
        $saved=[pscustomobject]@{closure=$closure}
        if($null-ne$script:CompletedEvidenceObservations){$script:CompletedEvidenceObservations[$key]=$saved}
    }
    $adopted=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($document in $saved.closure.Documents){$adopted[$document.sourcePath]='PROCESS_POLICY_SOURCE'}
    if($null-ne$config.frameworkCapabilities.PSObject.Properties['KNOWLEDGE_REFERENCE']-and$config.frameworkCapabilities.KNOWLEDGE_REFERENCE.enabled){
        $knowledge=@(Import-Module (Join-Path $PSScriptRoot 'KnowledgeSources.psm1') -PassThru)[0]
        $references=& $knowledge {
            param($root,$identity,$forbidden)
            $context=New-KsContext $root $identity $forbidden
            foreach($source in $context.sources){
                $opened=Open-KsSource $context $source
                if($opened.status-cne'CURRENT'){throw ('ACCEPTED_USE_KNOWLEDGE_UNPROVEN|'+$source.id+'|'+$opened.reason)}
                if($source.root.kind-cnotin@('PROJECT','LOCAL_DIRECTORY')){continue}
                $base=$source.root.locator
                [pscustomobject]@{path=[IO.Path]::GetFullPath($source.indexLocator,$base);kind='KNOWLEDGE_INDEX'}
                foreach($entry in $opened.entries){
                    if($entry.state-cne'CURRENT'){continue}
                    [pscustomobject]@{path=[IO.Path]::GetFullPath($entry.locator,$base);kind='KNOWLEDGE_REFERENCE'}
                    if($null-ne$entry.PSObject.Properties['authorityDependencies']){
                        foreach($dependency in $entry.authorityDependencies){
                            [pscustomobject]@{path=[IO.Path]::GetFullPath($dependency.locator,$base);kind='KNOWLEDGE_AUTHORITY_DEPENDENCY'}
                        }
                    }
                }
            }
        } $Context.ProjectRoot $Package.projectConfigIdentity $denied
        foreach($reference in $references){$adopted[$reference.path]=$reference.kind}
    }
    foreach($object in $deletes){
        $path=Get-EvLogicalPath $Context $object.targetPath -Candidate
        if($adopted.ContainsKey($path)){throw ('ACCEPTED_USE_DELETE_STILL_ADOPTED|'+$object.targetPath+'|'+$adopted[$path])}
    }
}
function Get-EvOrdinaryAcceptedOutcome($Context,$Package,[string]$Stage,$Plan=$null,[switch]$Historical){
    if($null-eq$Package.PSObject.Properties['acceptedOutcomeBinding']){return $null}
    if($Package.schemaVersion-notin@(1,2)-or($Package.schemaVersion-eq2-and$Package.repositoryId-cne'CONTROL')-or$Package.actions.Count-ne1-or$Package.actions[0]-cnotin@('SOURCE_WRITE','CONTROL_WRITE')){
        throw 'ACCEPTED_USE_ORDINARY_SCOPE_UNSUPPORTED'
    }
    foreach($field in @('sourcePublicationBinding','continuationPlan','selfCheckRepairLimit','repairReviewPlan','repairReviewBinding','transitionPlan','acceptanceBinding','externalBinding','gitPushBinding','executionTargetRef')){
        if($null-ne$Package.PSObject.Properties[$field]){throw 'ACCEPTED_USE_MIXED_PACKAGE'}
    }
    if($Package.schemaVersion-eq2-and$Package.actions[0]-cne'CONTROL_WRITE'){throw 'ACCEPTED_USE_CONTROL_SOURCE_DENIED'}
    if($null-ne$Context.PSObject.Properties['ExecutionContext']-and$null-ne$Context.ExecutionContext-and$Context.ExecutionContext.targetKind-cne'SAME_ROOT'){throw 'ACCEPTED_USE_SAME_ROOT_REQUIRED'}
    if($Stage-cnotin@('DISCOVER','ADMIT','FINALIZE','RESUME')){throw 'ACCEPTED_USE_CONSUMER_STAGE'}
    $quality=Get-AiwPackageQuality $Context $Package $Plan -Historical:$Historical
    $kinds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null=$kinds.Add('RESULT_ACCEPTANCE')
    if(Test-AiwPackageReviewRequired $Package){$null=$kinds.Add('REVIEW_VERDICT')}
    $stageKinds=@{SELF_CHECK='SELF_CHECK';RESULT_REVIEW='REVIEW_VERDICT';RESULT_ACCEPT='RESULT_ACCEPTANCE'}
    foreach($stageKind in $quality.effectiveStages){$null=$kinds.Add($stageKinds[$stageKind])}
    $use=Read-EvAcceptedUse $Context $Package.acceptedOutcomeBinding.useRef
    $paths=if($quality.mode-ceq'EXPLICIT'){@($quality.qualityBinding.subject.exactPaths)}else{@($Package.exactPaths)}
    $coverageObjects=@(foreach($path in $paths){
        $mapping=@($use.mappings|Where-Object targetPath -CEQ $path)
        if($mapping.Count-ne1){throw ('ACCEPTED_USE_TARGET_UNMAPPED|'+$path)}
        [pscustomobject]@{path=$path;identity=$(if($mapping[0].operation-ceq'DELETE'){'MISSING'}else{$mapping[0].preparedRef.identity})}
    })
    $objects=@($coverageObjects|Where-Object{$_.path-cin$Package.exactPaths})
    if($objects.Count-ne$Package.exactPaths.Count){throw 'ACCEPTED_USE_CURRENT_SCOPE_INCOMPLETE'}
    $facts=Get-EvAcceptedOutcomeCore $Context $Package.acceptedOutcomeBinding $objects @($kinds) $Package.taskId -CoverageObjects $coverageObjects
    if($null-ne$Plan){
        foreach($planStage in @($Plan.stages|Where-Object{$_.kind-cin$quality.effectiveStages})){
            if(-not(Test-EvSameRef $planStage.requiredBy $use.requirementsRef $Context)){throw 'ACCEPTED_USE_CURRENT_REQUIREMENTS_DRIFT'}
        }
    }
    Assert-EvAcceptedDeleteUnused $Context $Package $facts.objects
    foreach($object in $facts.objects){
        # M is independently checked against the original action preimages.
        # Unchanged A and final current A must already equal the selected image.
        if($Stage-ceq'FINALIZE'-or$object.targetPath-cnotin$Package.exactPaths){
            $null=Read-EvRef $Context ([pscustomobject]@{path=$object.targetPath;identity=$object.identity}) -Candidate
        }elseif($Stage-ceq'RESUME'){
            $pre=@($Package.objectIdentities|Where-Object path -CEQ $object.targetPath)
            if($pre.Count-ne1){throw 'ACCEPTED_USE_ORIGINAL_PREIMAGE_UNBOUND'}
            $live=Get-EvCandidateIdentity (Resolve-EvPath $Context $object.targetPath -Candidate -AllowMissing)
            $old=if($pre[0].identity-ceq'NEW'){'MISSING'}else{$pre[0].identity}
            if($live-cne$old-and$live-cne$object.identity){throw ('ACCEPTED_USE_RESUME_THIRD_PARTY_BYTES|'+$object.targetPath)}
        }
    }
    return $facts
}

function Assert-EvOriginalFinalizeDecision($source,$finalInput,$result,[string]$Failure='EVIDENCE_HISTORICAL_FINALIZE_DECISION'){
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    $a=$source.binding
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
    if($result.selectionIdentity-cne$source.selectionIdentity-or$result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $source $finalInput $postSource $changed)){throw $Failure}
}

function Get-EvCompletedInstallationStage($Context,$Completion,$Stage,[string]$TaskId,[string]$TaskOwner,[switch]$RequireIndependentReview){
    $consumption=Get-EvConsumption $Stage evidenceConsumption
    $proofs=[Collections.Generic.List[object]]::new()
    $originalRefs=[Collections.Generic.List[object]]::new()
    $covered=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $publications=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $useRef=$null
    foreach($pair in $consumption.originalFinalize){
        $key=(Get-EvLogicalPath $Context $pair.inputRef.path)+'|'+$pair.inputRef.identity+'|'+(Get-EvLogicalPath $Context $pair.resultRef.path)+'|'+$pair.resultRef.identity
        $entry=$Completion.finalizeFacts[$key];$source=$entry.source
        if($source.schemaVersion-notin@(3,4,5)-or$source.binding.taskId-cne$TaskId-or$source.intentEnvelope.requestedActionKind-cnotin@('SOURCE_WRITE','CONTROL_WRITE')){continue}
        if($null-eq$entry.package){$entry.package=Read-EvRef $Context ([pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$source.binding.authorizationIdentity}) -Json}
        $package=$entry.package
        if($null-ne$package.PSObject.Properties['acceptedOutcomeBinding']){
            if(-not$TaskOwner){throw 'ACCEPTANCE_INSTALLATION_OWNER_REQUIRED'}
            $use=Read-EvAcceptedUse $Context $package.acceptedOutcomeBinding.useRef
            $paths=if($null-ne$package.PSObject.Properties['qualityBinding']){@($package.qualityBinding.subject.exactPaths)}else{@($package.exactPaths)}
            $candidates=@(foreach($path in $paths){
                $mapping=@($use.mappings|Where-Object targetPath -CEQ $path)
                if($mapping.Count-ne1){throw ('ACCEPTED_USE_TARGET_UNMAPPED|'+$path)}
                [pscustomobject]@{path=$path;identity=$(if($mapping[0].operation-ceq'DELETE'){'MISSING'}else{$mapping[0].preparedRef.identity})}
            })
            $expected=[pscustomobject]@{schemaVersion=$package.schemaVersion;taskId=$TaskId;owner=$TaskOwner}
            if($null-eq$entry.installation){$entry.installation=Assert-AiwProductionFinalize $Context $pair $expected $candidates $package.grantee}
            $proof=$entry.installation
            $refs=@($pair.inputRef,$pair.resultRef)
        }elseif($null-ne$package.PSObject.Properties['sourcePublicationBinding']){
            $planRef=$package.sourcePublicationBinding.planRef
            $plan=Read-EvRef $Context $planRef -Json
            if($plan.schemaVersion-ne2){continue}
            if(-not$TaskOwner){throw 'ACCEPTANCE_INSTALLATION_OWNER_REQUIRED'}
            $publicationKey=(Get-EvLogicalPath $Context $planRef.path)+'|'+$planRef.identity
            if(-not$publications.Add($publicationKey)){continue}
            if(-not$Completion.publicationInstallations.ContainsKey($publicationKey)){
                $publication=@(Import-Module (Join-Path $PSScriptRoot 'ProjectSourcePublication.psm1') -PassThru)[0]
                $verified=& $publication {param($c,$p,$pairs,$task,$owner) Get-PubCompletedAcceptedInstallation $c $p $pairs $task $owner} $Context $pair $consumption.originalFinalize $TaskId $TaskOwner
                foreach($doc in $verified.history.documents){$null=Read-EvRef $Context ([pscustomobject]@{path=$doc.Path;identity=$doc.Identity})}
                foreach($member in @('SOURCE','CONTROL')){
                    $final=$verified.history.finals[$member]
                    $producer=[pscustomobject]@{inputRef=[pscustomobject]@{path=$final.input.Path;identity=$final.input.Identity};resultRef=[pscustomobject]@{path=$final.result.Path;identity=$final.result.Identity}}
                    Add-EvValidatedProducer $Context $producer $verified.original.receipts[$member] $final.input.Value $final.result.Value
                }
                $Completion.publicationInstallations.Add($publicationKey,$verified)
            }
            $proof=$Completion.publicationInstallations[$publicationKey]
            $refs=@($proof.originalRefs)
        }else{continue}
        $facts=$proof.acceptedOutcome
        if($null-eq$facts){throw 'ACCEPTANCE_INSTALLATION_FINALIZE_REQUIRED'}
        if($null-ne$useRef-and-not(Test-EvSameRef $useRef $facts.binding.useRef $Context)){throw 'ACCEPTANCE_INSTALLATION_USE_CONFLICT'}
        $useRef=$facts.binding.useRef
        if(-not(Test-EvSameRef $Stage.requiredBy $facts.use.requirementsRef $Context)){throw 'ACCEPTED_USE_CURRENT_REQUIREMENTS_DRIFT'}
        $kind=@{SELF_CHECK='SELF_CHECK';RESULT_REVIEW='REVIEW_VERDICT';RESULT_ACCEPT='RESULT_ACCEPTANCE'}[$Stage.kind]
        if($kind-cnotin$facts.coveredKinds-or($RequireIndependentReview-and'REVIEW_VERDICT'-cnotin$facts.coveredKinds)){throw ('ACCEPTED_USE_REQUIRED_STAGE_UNCOVERED|'+$Stage.kind)}
        foreach($node in $facts.original.graph.nodes.Values){$null=$known.Add((Get-EvTypedKey $Context $node.reference))}
        if($null-ne$facts.additional){foreach($node in $facts.additional.nodes.Values){$null=$known.Add((Get-EvTypedKey $Context $node.reference))}}
        # Full A is covered by the frozen U and this actual completion proof;
        # M remains separately recorded and never expands write authority.
        foreach($object in $proof.postimages){
            $path=Get-EvLogicalPath $Context $object.path -Candidate
            if($covered.ContainsKey($path)-and$covered[$path].identity-cne$object.identity){throw 'ACCEPTANCE_INSTALLATION_POSTIMAGE_CONFLICT'}
            $covered[$path]=$object
        }
        $proofs.Add($proof);foreach($reference in $refs){$originalRefs.Add($reference)}
    }
    if($proofs.Count-eq0){return $null}
    foreach($reference in $Stage.evidenceRefs){if(-not$known.Contains((Get-EvTypedKey $Context $reference))){throw 'ACCEPTANCE_INSTALLATION_ASSURANCE_UNBOUND'}}
    foreach($candidate in $Stage.candidateRef){
        $path=Get-EvLogicalPath $Context $candidate.path -Candidate
        if(-not$covered.ContainsKey($path)-or$covered[$path].identity-cne$candidate.identity){throw ('ACCEPTANCE_INSTALLATION_STAGE_INCOMPLETE|'+$Stage.id+'|'+$candidate.path)}
        $null=Read-EvRef $Context $candidate -Candidate
    }
    [pscustomobject]@{context=$Context;proofs=$proofs.ToArray();originalRefs=$originalRefs.ToArray()}
}

function Assert-AiwTaskClosure($Context,[string]$Text,[string]$TaskId,$Boundary,[switch]$RequireExplicitClosure,[string[]]$ExcludedReviewActors=@()){
    Invoke-EvCompletedEvidenceScope -Body {
        param($parameters)
        Assert-EvTaskClosureCore @parameters
    } -Arguments @($PSBoundParameters)
}
Export-ModuleMember -Function Assert-AiwTaskClosure
function Get-EvWorkRequest($Value){
    if($null-eq$Value){return $null}
    if($null-ne$Value.PSObject.Properties['requestRef']-and$null-ne$Value.PSObject.Properties['subject']-and$null-ne$Value.PSObject.Properties['requirementsRef']){return $Value}
    if($null-ne$Value.PSObject.Properties['requestContext']-and$null-ne$Value.PSObject.Properties['schemaVersion']-and$Value.schemaVersion-eq5){return $Value.requestContext}
    if($null-ne$Value.PSObject.Properties['requestContext']-and$null-ne$Value.PSObject.Properties['receiptType']-and$Value.receiptType-ceq'AUTHORIZED_ACTION_CONTINUATION'-and$Value.schemaVersion-eq4){return $Value.requestContext}
    if($null-ne$Value.PSObject.Properties['authorityContext']){return Get-EvWorkRequest $Value.authorityContext}
    if($null-ne$Value.PSObject.Properties['contextType']-and$Value.contextType-ceq'PROJECT_WORK'){return $Value.context.requestContext}
    return $null
}
function Get-EvExpectedResultContext($Value){
    $request=Get-EvWorkRequest $Value
    if($null-ne$request){return $request}
    return Get-AiwEvidenceSubject $Value
}
function Get-AiwEvidenceSubject($Value){
    $request=Get-EvWorkRequest $Value
    if($null-ne$request){
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
        return Get-AiwWorkEvidenceBinding $request
    }
    if($Value-is[string]){Assert-EvString $Value;return $Value}
    if($null-ne$Value.PSObject.Properties['schemaVersion']-and$Value.schemaVersion-eq3-and$null-ne$Value.PSObject.Properties['context']){return $Value.context}
    if($null-ne$Value.PSObject.Properties['kind']-and$Value.kind-ceq'PROJECT_WORK'){return $Value}
    if($null-eq$Value.PSObject.Properties['taskId']){throw 'EVIDENCE_RESULT_CONTEXT_REQUIRED'}
    Assert-EvString $Value.taskId
    return $Value.taskId
}
function Assert-EvResultContext($Value,$Expected){
    $actual=Get-AiwEvidenceSubject $Value;$expectedSubject=Get-AiwEvidenceSubject $Expected
    if($actual-is[string]-or$expectedSubject-is[string]){
        if($actual-isnot[string]-or$expectedSubject-isnot[string]-or$actual-cne$expectedSubject){throw 'EVIDENCE_TASK_DRIFT'}
        return
    }
    Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    foreach($context in @($actual,$expectedSubject)){
        Assert-EvFields $context @('kind','requestRef','owner')
        Assert-AiwRequestReference $context.requestRef;Assert-EvString $context.owner
        if($context.kind-cne'PROJECT_WORK'-or$context.owner-cin@('UNKNOWN','NOT_REQUIRED','NOT_APPLICABLE','USER','UNBOUND_RECEIVER')){throw 'EVIDENCE_WORK_CONTEXT'}
    }
    if((Get-AiwContentDescriptorIdentity $actual)-cne(Get-AiwContentDescriptorIdentity $expectedSubject)){throw 'EVIDENCE_WORK_CONTEXT_DRIFT'}
    $left=Get-EvWorkRequest $Value;$right=Get-EvWorkRequest $Expected
    if($null-ne$left-and$null-ne$right-and(Get-AiwWorkRequestKey $left)-cne(Get-AiwWorkRequestKey $right)){throw 'EVIDENCE_WORK_SUBJECT_DRIFT'}
}
function Test-AiwSameResultContext($Left,$Right){
    try{Assert-EvResultContext $Left $Right;return $true}catch{return $false}
}
function Get-EvWorkRecordRequirements($Context,$Request,[string]$Kind,$Candidates,$Requirements){
    if(Test-EvSameRef $Request.requirementsRef $Requirements $Context){return $Request.requirementsRef}
    $plan=Get-AiwProjectWorkPlan $Request
    $stageKind=@{SELF_CHECK='SELF_CHECK';REVIEW_VERDICT='RESULT_REVIEW';RESULT_ACCEPTANCE='RESULT_ACCEPT'}[$Kind]
    if($null-ne$plan){
        foreach($stage in $plan.stages){
            if($stage.kind-ceq$stageKind-and(Test-EvSameRef $stage.requiredBy $Requirements $Context)-and(Test-EvSameCandidates $stage.candidateRef $Candidates $Context)){return $stage.requiredBy}
        }
    }
    throw 'EVIDENCE_WORK_REQUIREMENTS_UNBOUND'
}
Export-ModuleMember -Function Get-AiwEvidenceSubject,Test-AiwSameResultContext


# @design-contract UNIFIED-INTENT-LOADING-PLAN.md sections 4.1-4.3.
# These are finite original-action readers. No current TASK permission is
# inferred from a historical action, nor is a failed result a success stage.
function Get-EvFinalizeKey($Context,$Pair){
    Assert-EvFields $Pair @('inputRef','resultRef')
    foreach($name in @('inputRef','resultRef')){Assert-EvRef $Pair.$name}
    return (Get-EvLogicalPath $Context $Pair.inputRef.path)+'|'+$Pair.inputRef.identity+'|'+(Get-EvLogicalPath $Context $Pair.resultRef.path)+'|'+$Pair.resultRef.identity
}
function Assert-EvCompletedTaskFinalizeDecision($Context,$Source,$FinalBoundary,$Result,$Package,$Postimages){
    $a=$Source.binding;$relative=$Source.sourceLocators.taskRelativePath
    if($Source.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'-or$relative-cnotin$a.exactScope){
        Assert-EvOriginalFinalizeDecision $Source $FinalBoundary $Result
        return
    }
    # Ordinary own-card FINALIZE hashes the observed taskIdentity change too.
    # Derive it from the exact original scope and real closed postimage; no
    # caller-supplied changed-binding set or exception to decision equality.
    $archive=$relative.Replace('/active/','/archive/')
    if($Source.schemaVersion-ne5-or$relative-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or$Package.schemaVersion-ne1-or@($Package.actions).Count-ne1-or$Package.actions[0]-cne'CONTROL_WRITE'-or@($Package.exactPaths|Where-Object{$_-cnotin@($relative,$archive)}).Count-or$a.actor-cne$a.taskActor-or$a.actor-cne$a.taskOwner){throw 'WORK_PREDECESSOR_CLOSE_SCOPE'}
    if($null-ne$Result.PSObject.Properties['sourcePostimageTransition']-or$null-ne$Result.PSObject.Properties['controlTransitionCompletion']){throw 'WORK_PREDECESSOR_CLOSE_SCOPE'}
    $posts=@($Postimages|Where-Object path -CEQ $relative)
    if($posts.Count-ne1-or$posts[0].identity-ceq$a.taskIdentity){throw 'WORK_PREDECESSOR_CLOSE_POSTIMAGE'}
    $post=$posts[0]
    if($post.identity-ceq'MISSING'){
        $posts=@($Postimages|Where-Object path -CEQ $archive)
        if($posts.Count-ne1-or$posts[0].identity-ceq'MISSING'){throw 'WORK_PREDECESSOR_CLOSE_ARCHIVE'}
        $post=$posts[0]
    }elseif(-not[IO.File]::Exists((Resolve-EvPath $Context $relative -Candidate -AllowMissing))){$post=[pscustomobject]@{path=$archive;identity=$post.identity}}
    $path=Read-EvRef $Context $post -Candidate
    $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($path))
    $closure=Get-AiwTaskClosureFields $text -RequireComplete
    $module=@(Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1') -PassThru)[0]
    $task=& $module {param($text)Get-TransitionTaskFacts $text} $text
    if($closure.Outcome-cne'SUPERSEDED'-or$task.TaskId-cne$a.taskId-or$task.Owner-cne$a.taskOwner-or$task.TaskActor-cne$a.taskActor-or$task.Role-cne$a.context.workRoute.role-or$task.Phase-cne$a.context.workRoute.phase-or$task.Profile-cne$a.profile){throw 'WORK_PREDECESSOR_CLOSE_POSTIMAGE_BINDING'}
    if($Result.selectionIdentity-cne$Source.selectionIdentity-or$Result.decisionIdentity-cne(Get-AiwProcessDecisionIdentity $Source $FinalBoundary 'NO_SOURCE_POSTIMAGE_TRANSITION' @('taskIdentity'))){throw 'EVIDENCE_HISTORICAL_FINALIZE_DECISION'}
}
function Read-EvCompletedTaskAction($Context,$Pair,[string]$TaskId,[string]$Owner,[object[]]$OriginalFinalize=@(),$OriginalTaskRef=$null){
    $null=Get-EvFinalizeKey $Context $Pair
    $input=Read-EvRef $Context $Pair.inputRef -Json
    $result=Read-EvRef $Context $Pair.resultRef -Json
    if($input.schemaVersion-notin@(3,4)-or$input.mode-cne'FINALIZE_OUTPUT'-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'PASS'-or@($result.missingPreparation).Count-or@($result.missingResult).Count){throw 'WORK_PREDECESSOR_ACTION_NOT_FINALIZED'}
    $source=Read-EvProcessOperation $Context $input $result
    if($source.schemaVersion-notin@(3,4,5)-or$source.status-cne'PASS'){throw 'WORK_PREDECESSOR_ACTION_SOURCE'}
    $a=$source.binding;$action=$source.intentEnvelope.requestedActionKind
    $packageRef=[pscustomobject]@{path=$source.sourceLocators.authorizationPackagePath;identity=$a.authorizationIdentity}
    $package=Read-EvRef $Context $packageRef -Json
    if($package.schemaVersion-notin@(1,2)-or$a.taskId-cne$TaskId-or$package.taskId-cne$TaskId-or$a.taskOwner-cne$Owner-or$package.owner-cne$Owner-or$a.taskIdentity-cne$package.taskIdentity-or$a.actor-cne$package.grantee-or$a.projectConfigIdentity-cne$package.projectConfigIdentity-or$a.userDecision-cne$package.userConfirmation-or$action-cnotin$package.actions-or$action-cnotin$a.authorizedActions){throw 'WORK_PREDECESSOR_ACTION_AUTHORITY'}
    if($package.issuerRole-ceq'TASK_OWNER'){
        if($package.issuer-cne$Owner){throw 'WORK_PREDECESSOR_ACTION_ISSUER'}
    }elseif($package.issuerRole-ceq'PROJECT_CONTROLLER'){
        if($package.issuer-cne$package.issuerControllerId-or$package.issuerControllerEpoch-lt1-or$package.controllerControlIdentity-cne$a.controllerIdentity){throw 'WORK_PREDECESSOR_ACTION_ISSUER'}
    }else{throw 'WORK_PREDECESSOR_ACTION_ISSUER'}
    if(-not([IO.Path]::GetFullPath($a.projectRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)-or($source.schemaVersion-in@(4,5)-and($a.executionContext.targetKind-cne'SAME_ROOT'-or-not([IO.Path]::GetFullPath($a.controlRoot)).Equals($Context.ProjectRoot,[StringComparison]::OrdinalIgnoreCase)))){throw 'WORK_PREDECESSOR_SAME_ROOT_REQUIRED'}
    # The supersession graph supplies its strictly bound original task plan.
    # Historical findings must not depend on today's active/archive location.
    $originalTaskPath=if($null-ne$OriginalTaskRef){Read-EvRef $Context $OriginalTaskRef}else{''}
    $guard=New-AiwPackageEvidenceContext $Context.ProjectRoot $package $source.sourceLocators.frameworkRoot (@($Context.ForbiddenPaths)+@($a.forbiddenScope)) -TaskPath $originalTaskPath -ProtectedPaths (@($Context.CandidateProtectedPaths)+@($a.protectedScope))
    Share-EvReadState $guard $Context
    if(-not$guard.RepositoryRoot.Equals($Context.RepositoryRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'WORK_PREDECESSOR_REPOSITORY_DRIFT'}
    $scope=@(Get-AiwActionScopeObjects $package $action $guard)
    if((@($scope.path|Sort-Object -CaseSensitive)-join'|')-cne(@($a.exactScope|Sort-Object -CaseSensitive)-join'|')){throw 'WORK_PREDECESSOR_ACTION_SCOPE'}
    $post=@(Get-AiwPackageCandidateReferences ([pscustomobject]@{objectIdentities=@(Get-AiwFinalizedObjectPostimages $input @($a.exactScope))}))
    Assert-EvCompletedTaskFinalizeDecision $guard $source $input $result $package $post
    # A review can consume a successful SELF without producing it. Keep the
    # finite consumer-declared pairs and the review's actual production edge;
    # the historical reader still selects and validates the unique producer.
    $history=@($Pair)+@($OriginalFinalize)
    if($null-ne$package.PSObject.Properties['repairReviewBinding']){
        $binding=$package.repairReviewBinding
        if($binding.phase-cin@('INITIAL_REVIEW','REREVIEW')){
            $history+=,[pscustomobject]@{inputRef=[pscustomobject]@{path=$binding.repairFinalizeInputPath;identity=$binding.repairFinalizeInputIdentity};resultRef=[pscustomobject]@{path=$binding.repairFinalizeResultPath;identity=$binding.repairFinalizeResultIdentity}}
        }
    }
    $historicalPairs=@();$historyKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($original in $history){if($historyKeys.Add((Get-EvFinalizeKey $guard $original))){$historicalPairs+=,$original}}
    $records=@();$typedPrep=@();$typedResult=@()
    Assert-EvRefs $input.evidenceRefs -Typed
    foreach($ref in $input.evidenceRefs){
        $raw=Read-EvRef $guard ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        if($raw.schemaVersion-notin@(1,2)-or$raw.taskId-cne$TaskId){throw 'WORK_PREDECESSOR_TYPED_TASK_DRIFT'}
        if($action-cin@(Get-EvProducerActions $ref.kind)){Assert-EvSameCandidates $raw.candidateObjects $post $guard}
        $success=$raw.outcome-ceq@{SELF_CHECK='PASS';REVIEW_VERDICT='APPROVED';RESULT_ACCEPTANCE='ACCEPTED'}[$ref.kind]
        if($success){
            $records+=Read-EvResultEvidenceCore $guard $ref $TaskId $raw.candidateObjects $raw.requirementsRef -EvidencePurpose HISTORICAL_SUCCESS -OriginalFinalize $historicalPairs
        }else{
            if($ref.kind-ceq'RESULT_ACCEPTANCE'){throw 'WORK_PREDECESSOR_UNFINISHED_ACCEPTANCE'}
            $records+=Read-EvResultEvidenceCore $guard $ref $TaskId $raw.candidateObjects $raw.requirementsRef -FrozenCandidateEvidence
        }
        switch($ref.kind){SELF_CHECK{$typedPrep+='SELF_CHECK_BOUND'};REVIEW_VERDICT{$typedResult+='REVIEW_VERDICT_BOUND'};RESULT_ACCEPTANCE{$typedResult+='RESULT_ACCEPT_RECORDED'}}
    }
    $self=Get-AiwSelfCheckOutcome $input.evidenceRefs $records
    $expectedOutcome=if($action-ceq'TEST_RUN'){
        if($self-ceq'NOT_APPLICABLE'-or@($records|Where-Object{@($_.checks|Where-Object method -CEQ 'COMMAND').Count-eq0}).Count){throw 'WORK_PREDECESSOR_TEST_COMMAND_REQUIRED'}
        $self
    }elseif($null-ne$input.PSObject.Properties['continuationDisposition']-and$input.continuationDisposition-ceq'STOP'-and$self-cin@('FAIL','INCOMPLETE')){$self}else{'OBSERVED'}
    if($result.actionOutcome-cne$expectedOutcome){throw 'WORK_PREDECESSOR_ACTION_OUTCOME'}
    $prep=@($input.preparationReceipts|Where-Object{$_-cne'SELF_CHECK_BOUND'})+$typedPrep
    $results=@($input.resultReceipts|Where-Object{$_-cnotin@('REVIEW_VERDICT_BOUND','RESULT_ACCEPT_RECORDED','DELIVERY_RECEIPT')})+$typedResult
    if($null-ne$input.PSObject.Properties['deliveryContext']){
        Import-Module (Join-Path $PSScriptRoot 'WorkflowDelivery.psm1')
        $observation=Get-AiwDeliveryObservation $input.deliveryContext
        if($null-eq$result.PSObject.Properties['delivery']-or($result.delivery|ConvertTo-Json -Compress)-cne($observation|ConvertTo-Json -Compress)){throw 'WORK_PREDECESSOR_DELIVERY_DRIFT'}
        if($input.deliveryContext.channel-ceq'TASK_MESSAGE'){
            if(-not$observation.delivered-or$input.deliveryContext.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'WORK_PREDECESSOR_OBSERVE_REQUIRED'}
            $hostResult=Read-EvRef $guard ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
            if((Get-AiwCodexSendOutcome $hostResult $input.deliveryContext.expectedRecipient).outcome-cne'SUCCESS'){throw 'WORK_PREDECESSOR_OBSERVE_REQUIRED'}
            if($input.schemaVersion-eq4){
                if($null-eq$result.PSObject.Properties['consumer']-or$result.consumer.recipient-cne$input.deliveryContext.expectedRecipient-or$result.consumer.channel-cne'TASK_MESSAGE'-or$result.consumer.authorizationIdentity-cne$packageRef.identity){throw 'WORK_PREDECESSOR_CONSUMER_DRIFT'}
                $deliveryModule=(Get-Command Get-AiwBoundDelivery).Module
                & $deliveryModule {param($s,$b,$ctx,$consumer)Assert-AiwPreparedOperationDelivery $s $b $ctx $consumer} $source $input $guard $result.consumer
            }
        }
        $results+='DELIVERY_RECEIPT'
    }elseif(@($input.deliveryReceipts).Count){$results+='DELIVERY_RECEIPT'}
    foreach($obligation in $source.selectedObligations){if(@($obligation.preparationRequirements|Where-Object{$_-cnotin$prep}).Count-or@($obligation.resultRequirements|Where-Object{$_-cnotin$results}).Count){throw 'WORK_PREDECESSOR_ACTION_INCOMPLETE'}}
    Add-EvValidatedProducer $guard $Pair $source $input $result
    return [pscustomobject]@{pair=$Pair;source=$source;input=$input;result=$result;package=$package;packageRef=$packageRef;context=$guard;postimages=$post;records=$records}
}
function Read-EvSupersessionDecision($Context,$Reference){
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
    $path=Read-EvRef $Context $Reference
    $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($path))
    # Old free-text decisions still close old tasks. Only this complete shape
    # establishes the finite migration edge.
    if(-not$text.TrimStart().StartsWith('{',[StringComparison]::Ordinal)){return $null}
    $value=ConvertFrom-EvJson $text
    $fields=@('userDecisionRef','predecessorTaskRef','successorRequest','completedActionRefs','repairHeads')
    if(@($fields|Where-Object{$null-ne$value.PSObject.Properties[$_]}).Count-eq0){return $null}
    Assert-EvFields $value $fields
    Assert-AiwRequestReference $value.userDecisionRef;Assert-EvRef $value.predecessorTaskRef
    Assert-EvFields $value.successorRequest @('requestRef','owner','subject','requirementsRef')
    Assert-AiwRequestReference $value.successorRequest.requestRef;Assert-EvString $value.successorRequest.owner
    Assert-AiwQualitySubject $value.successorRequest.subject 2;Assert-EvRef $value.successorRequest.requirementsRef -Section
    Assert-EvArray $value.completedActionRefs
    Assert-EvFields $value.repairHeads @('selfCheck','review')
    $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($pair in $value.completedActionRefs){if(-not$keys.Add((Get-EvFinalizeKey $Context $pair))){throw 'WORK_PREDECESSOR_DUPLICATE_TAIL'}}
    foreach($name in @('selfCheck','review')){
        $head=$value.repairHeads.$name
        if($head-is[string]){if($head-cne'NOT_APPLICABLE'){throw 'WORK_PREDECESSOR_REPAIR_HEAD'};continue}
        if(-not$keys.Contains((Get-EvFinalizeKey $Context $head))){throw 'WORK_PREDECESSOR_HEAD_NOT_TAIL'}
    }
    return $value
}
function Get-EvSelfHeadSourceKeys($Head){
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $source=$Head.source;$result=$Head.result;$node=$null
    $null=$seen.Add($source.contextIdentity+'|'+$source.selectionIdentity)
    if($null-ne$result.PSObject.Properties['continuationReceipt']-and$null-ne$result.continuationReceipt){$node=$result.continuationReceipt}
    elseif($null-ne$source.binding.PSObject.Properties['continuationReceiptPath']-and$source.binding.continuationReceiptPath-cne'NOT_REQUIRED'){
        $node=Read-EvRef $Head.context ([pscustomobject]@{path=$source.binding.continuationReceiptPath;identity=$source.binding.continuationReceiptIdentity}) -Json
    }
    $references=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while($null-ne$node){
        $reference=[pscustomobject]@{path=$node.sourceDiscoverReceiptPath;identity=$node.sourceDiscoverReceiptIdentity}
        if(-not$references.Add((Get-EvLogicalPath $Head.context $reference.path)+'|'+$reference.identity)){throw 'WORK_PREDECESSOR_SELF_REFERENCE_CYCLE'}
        $source=Read-EvRef $Head.context $reference -Json
        if($source.schemaVersion-eq5){$source=Convert-EvOperationCompact $Head.context $source}
        $null=$seen.Add($source.contextIdentity+'|'+$source.selectionIdentity)
        if($source.binding.continuationReceiptPath-ceq'NOT_REQUIRED'){break}
        $node=Read-EvRef $Head.context ([pscustomobject]@{path=$source.binding.continuationReceiptPath;identity=$source.binding.continuationReceiptIdentity}) -Json
    }
    return ,$seen
}
function Get-EvSupersessionReviewFacts($Context,$Authority,$Tails,$Head,$SelfRoot,$OriginalTaskRef){
    $relevant=@($Tails|Where-Object{$null-ne$_.package.PSObject.Properties['repairReviewPlan']-or$null-ne$_.package.PSObject.Properties['repairReviewBinding']})
    if($relevant.Count-eq0){if($null-ne$Head){throw 'WORK_PREDECESSOR_REVIEW_HEAD_INVALID'};return $null}
    if($null-eq$Head){throw 'WORK_PREDECESSOR_REVIEW_HEAD_REQUIRED'}
    $rootRef=$null
    foreach($tail in $relevant){
        $ref=$tail.packageRef
        if($null-ne$tail.package.PSObject.Properties['repairReviewBinding']){$ref=[pscustomobject]@{path=$tail.package.repairReviewBinding.parentPackagePath;identity=$tail.package.repairReviewBinding.parentPackageIdentity}}
        if($null-ne$rootRef-and-not(Test-EvSameRef $rootRef $ref $Context)){throw 'WORK_PREDECESSOR_REVIEW_ROOT_AMBIGUOUS'}
        $rootRef=$ref
    }
    $parent=Read-EvRef $Context $rootRef -Json
    if($parent.schemaVersion-notin@(1,2)-or$parent.taskId-cne$Authority.taskId-or$parent.owner-cne$Authority.taskOwner-or$parent.profile-cne$Authority.profile-or$null-eq$parent.PSObject.Properties['repairReviewPlan']-or$null-ne$parent.PSObject.Properties['repairReviewBinding']){throw 'WORK_PREDECESSOR_REVIEW_ROOT_INVALID'}
    $plan=$parent.repairReviewPlan
    Assert-EvFields $plan @('writer','reviewer','maxCycles','materialContributors') @('reviewScope')
    Assert-EvString $plan.writer;Assert-EvString $plan.reviewer;Assert-EvInteger $plan.maxCycles
    if($plan.maxCycles-lt1-or$plan.maxCycles-gt[int]::MaxValue-or$plan.writer-cne$parent.grantee-or'REVIEW_ROUTE'-cnotin$parent.actions-or$null-eq$parent.PSObject.Properties['continuationPlan']-or$parent.continuationPlan[-1]-cne'REVIEW_ROUTE'){throw 'WORK_PREDECESSOR_REVIEW_PLAN_INVALID'}
    $excluded=@(Get-AiwReviewExcludedActors $parent.owner $parent.issuer $plan.writer $plan.materialContributors)
    if($plan.reviewer-cin$excluded){throw 'REPAIR_REVIEW_INDEPENDENCE'}
    $null=@(Get-AiwPlannedReviewScope $parent)
    if($null-ne$SelfRoot-and-not(Test-EvSameRef $SelfRoot $rootRef $Context)){throw 'WORK_PREDECESSOR_SELF_REVIEW_ROOT_DRIFT'}
    # Only this call's explicit original pairs form the graph. The head must
    # account for every declared tail; no history discovery or new authority.
    $known=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($tail in $Tails){$known.Add((Get-EvFinalizeKey $Context $tail.pair),$tail)}
    $visiting=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $done=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sources=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function Visit-EvOriginalReviewPair($Pair){
        $key=Get-EvFinalizeKey $Context $Pair
        if($done.Contains($key)){return}
        if(-not$visiting.Add($key)){throw 'WORK_PREDECESSOR_REVIEW_REFERENCE_CYCLE'}
        try{
            $tail=$null
            if(-not$known.TryGetValue($key,[ref]$tail)){$tail=Read-EvCompletedTaskAction $Context $Pair $Authority.taskId $Authority.taskOwner -OriginalTaskRef $OriginalTaskRef;$known.Add($key,$tail)}
            foreach($sourceKey in (Get-EvSelfHeadSourceKeys $tail)){$null=$sources.Add($sourceKey)}
            $package=$tail.package
            if($null-ne$package.PSObject.Properties['repairReviewBinding']){
                $binding=$package.repairReviewBinding
                if(-not(Test-EvSameRef ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity}) $rootRef $Context)){throw 'WORK_PREDECESSOR_REVIEW_ROOT_AMBIGUOUS'}
                Assert-EvInteger $binding.cycle
                if($binding.phase-ceq'INITIAL_REVIEW'){
                    if($binding.cycle-ne0-or$tail.source.intentEnvelope.requestedActionKind-cne'REVIEW_EXECUTE'){throw 'WORK_PREDECESSOR_REVIEW_CYCLE'}
                }elseif($binding.phase-cin@('REPAIR','REREVIEW')){
                    if($binding.cycle-lt1-or$binding.cycle-gt$plan.maxCycles){throw 'WORK_PREDECESSOR_REVIEW_CYCLE'}
                    $null=Assert-AiwFinalizedReviewFinding $tail.context $parent $binding -FrozenCandidates
                    Visit-EvOriginalReviewPair ([pscustomobject]@{inputRef=[pscustomobject]@{path=$binding.verdictFinalizeInputPath;identity=$binding.verdictFinalizeInputIdentity};resultRef=[pscustomobject]@{path=$binding.verdictFinalizeResultPath;identity=$binding.verdictFinalizeResultIdentity}})
                }else{throw 'WORK_PREDECESSOR_REVIEW_PHASE'}
                if($binding.phase-cin@('INITIAL_REVIEW','REREVIEW')){
                    if($tail.source.intentEnvelope.requestedActionKind-cne'REVIEW_EXECUTE'){throw 'WORK_PREDECESSOR_REVIEW_PHASE'}
                    Visit-EvOriginalReviewPair ([pscustomobject]@{inputRef=[pscustomobject]@{path=$binding.repairFinalizeInputPath;identity=$binding.repairFinalizeInputIdentity};resultRef=[pscustomobject]@{path=$binding.repairFinalizeResultPath;identity=$binding.repairFinalizeResultIdentity}})
                    $reviews=@($tail.records|Where-Object outcome -CIN @('APPROVED','CHANGES_REQUESTED'))
                    if($reviews.Count-ne1){throw 'WORK_PREDECESSOR_REVIEW_TYPED_REQUIRED'}
                    Assert-EvReviewIndependence $package $reviews[0] -Required -Excluded $excluded
                    $null=Get-AiwPlannedReviewFlatVerdict $tail.context $package $reviews[0]
                }
            }elseif(-not(Test-EvSameRef $tail.packageRef $rootRef $Context)){throw 'WORK_PREDECESSOR_REVIEW_PRODUCER_ROOT_DRIFT'}
            $null=$done.Add($key)
        }finally{$null=$visiting.Remove($key)}
    }
    Visit-EvOriginalReviewPair $Head.pair
    foreach($tail in $relevant){if(-not$sources.Contains($tail.source.contextIdentity+'|'+$tail.source.selectionIdentity)){throw 'WORK_PREDECESSOR_REVIEW_HEAD_FORK'}}
    $state='INITIAL_READY';$cycle=0
    if($null-ne$Head.package.PSObject.Properties['repairReviewBinding']){
        $binding=$Head.package.repairReviewBinding;$cycle=[int]$binding.cycle
        if($binding.phase-ceq'REPAIR'){$state='REREVIEW_READY'}
        else{$state=[string]@($Head.records|Where-Object outcome -CIN @('APPROVED','CHANGES_REQUESTED'))[0].outcome}
    }
    if($state-cin@('INITIAL_READY','REREVIEW_READY')-and$Head.result.actionOutcome-cnotin@('PASS','OBSERVED')){throw 'WORK_PREDECESSOR_REVIEW_PRODUCTION_NOT_SUCCESSFUL'}
    return [pscustomobject]@{rootRef=$rootRef;parent=$parent;head=$Head;cycle=$cycle;state=$state}
}
function Get-EvWorkReviewRoot($Context,$Request,$ParentRef){
    $facts=Get-EvWorkPredecessor $Context $Request
    if($null-eq$facts-or$null-eq$facts.review-or-not(Test-EvSameRef $facts.review.rootRef $ParentRef $Context)){throw 'WORK_PREDECESSOR_REVIEW_ROOT_DRIFT'}
    return $facts
}
function Assert-EvReviewProducerRelation($Context,$Current,$Producer,$ProducerRef){
    if($Current.schemaVersion-ne5-or$Producer.schemaVersion-eq5){
        if($Current.schemaVersion-eq5){
            if(-not(Test-AiwSameResultContext $Producer $Current)){throw 'REPAIR_REVIEW_PARENT_CONTEXT_DRIFT'}
        }elseif($Producer.taskId-cne$Current.taskId-or$Producer.owner-cne$Current.owner){throw 'REPAIR_REVIEW_PARENT_CONTEXT_DRIFT'}
        return
    }
    if($null-eq$Current.PSObject.Properties['repairReviewBinding']){throw 'WORK_PREDECESSOR_REVIEW_BINDING_REQUIRED'}
    $parentRef=[pscustomobject]@{path=$Current.repairReviewBinding.parentPackagePath;identity=$Current.repairReviewBinding.parentPackageIdentity}
    $facts=Get-EvWorkReviewRoot $Context $Current.requestContext $parentRef
    if($Producer.schemaVersion-notin@(1,2)-or$Producer.taskId-cne$facts.taskId-or$Producer.owner-cne$facts.owner){throw 'WORK_PREDECESSOR_REVIEW_PRODUCER_DRIFT'}
    $root=$ProducerRef
    if($null-ne$Producer.PSObject.Properties['repairReviewBinding']){$root=[pscustomobject]@{path=$Producer.repairReviewBinding.parentPackagePath;identity=$Producer.repairReviewBinding.parentPackageIdentity}}
    if(-not(Test-EvSameRef $root $parentRef $Context)){throw 'WORK_PREDECESSOR_REVIEW_PRODUCER_ROOT_DRIFT'}
}

function Get-EvSupersessionFacts($Context,$Decision,$Source){
    $a=$Source.binding
    foreach($reference in @($Decision.userDecisionRef,$Decision.successorRequest.requestRef)){
        if($reference.kind-ceq'FILE'){
            $original=Read-EvRef $Context ([pscustomobject]@{path=$reference.path;identity=$reference.identity})
            if([string]::IsNullOrWhiteSpace([Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($original)))){throw 'WORK_PREDECESSOR_ORIGINAL_EMPTY'}
        }
    }
    $taskPath=Read-EvRef $Context $Decision.predecessorTaskRef
    $taskText=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($taskPath))
    Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
    $module=(Get-Command Read-AiwControlTransitionTask).Module
    $task=& $module {param($text)Get-TransitionTaskFacts $text} $taskText
    if($Decision.predecessorTaskRef.identity-cne$a.taskIdentity-or$task.TaskId-cne$a.taskId-or$task.Owner-cne$a.taskOwner-or$task.TaskActor-cne$a.taskActor-or$task.Profile-cne$a.profile-or$taskText-cnotmatch'(?m)^- Range summary:[^\r\n]*lifecycle=ACTIVE;'-or$Decision.successorRequest.owner-cne$a.taskOwner-or$Decision.successorRequest.subject.repositoryId-cne'REPO_LOCAL'-or$taskText-cmatch'(?m)^(?:- )?Execution target:'){throw 'WORK_PREDECESSOR_TASK_PREIMAGE'}
    $plan=Get-AiwAcceptancePlan $taskText
    if($null-eq$plan-or$plan.schemaVersion-ne2){throw 'WORK_PREDECESSOR_STABLE_SUBJECT_UNPROVEN'}
    $subject=$Decision.successorRequest.subject
    Assert-AiwQualitySubject $subject 2
    $subjectVersion=[int]$plan.qualityBinding.schemaVersion
    $projected=$subject
    if($subjectVersion-eq1){
        # QA1 keeps its original binding and two-axis key. The Owner must have
        # read actual original human/requirements material at the safe point;
        # these byte/section relations cannot certify its semantic workType.
        $projected=[pscustomobject]@{repositoryId=$subject.repositoryId;exactPaths=@($subject.exactPaths);facets=[pscustomobject]@{domain=$subject.facets.domain;deliverableType=$subject.facets.deliverableType}}
    }
    $subjectBinding=[pscustomobject]@{schemaVersion=$subjectVersion;policyRef=$plan.qualityBinding.policyRef;subject=$projected;effectiveStages=$plan.qualityBinding.effectiveStages}
    if((Get-AiwQualityBindingKey $subjectBinding)-cne(Get-AiwQualityBindingKey $plan.qualityBinding)-or@($plan.stages|Where-Object{Test-EvSameRef $_.requiredBy $Decision.successorRequest.requirementsRef $Context}).Count-eq0){throw 'WORK_PREDECESSOR_SUBJECT_REQUIREMENTS_DRIFT'}
    if($subjectVersion-eq1){
        $originPath=Read-EvRef $Context $Decision.successorRequest.requirementsRef -Section
        $originText=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($originPath))
        if($null-ne$Decision.successorRequest.requirementsRef.PSObject.Properties['section']){
            $tag=[regex]::Escape($Decision.successorRequest.requirementsRef.section)
            $originText=[regex]::Match($originText,'(?s)<!-- '+$tag+':BEGIN -->(.*?)<!-- '+$tag+':END -->').Groups[1].Value
        }
        if([string]::IsNullOrWhiteSpace($originText)){throw 'WORK_PREDECESSOR_ORIGINAL_WORK_TYPE_UNPROVEN'}
        $policyPath=Resolve-EvPath $Context '.ai-workspace/process-policy.json'
        $policyRef=[pscustomobject]@{path=$policyPath;identity=(Get-EvCandidateIdentity $policyPath)}
        $policy=Read-EvRef $Context $policyRef -Json
        # Validate the complete current vocabulary without reclassifying old
        # success or replacing its frozen QA1 policy/stages with today's ones.
        $null=Get-AiwQualitySelection $policy $policyRef.identity $a.profile $subject
    }
    $originalFinalize=@($Decision.completedActionRefs)
    foreach($stage in $plan.stages){
        $consumption=Get-EvConsumption $stage evidenceConsumption
        if($consumption.purpose-ceq'HISTORICAL_SUCCESS'){$originalFinalize+=@($consumption.originalFinalize)}
    }
    $tails=@();$operations=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($pair in $Decision.completedActionRefs){
        $tail=Read-EvCompletedTaskAction $Context $pair $a.taskId $a.taskOwner -OriginalFinalize $originalFinalize -OriginalTaskRef $Decision.predecessorTaskRef
        if($tail.source.binding.profile-cne$a.profile-or-not$operations.Add($tail.source.contextIdentity+'|'+$tail.source.selectionIdentity)){throw 'WORK_PREDECESSOR_CONFLICTING_TAIL'}
        $tails+=,$tail
    }
    $heads=[ordered]@{selfCheck=$null;review=$null}
    foreach($name in @('selfCheck','review')){
        if($Decision.repairHeads.$name-is[string]){continue}
        $key=Get-EvFinalizeKey $Context $Decision.repairHeads.$name
        $heads[$name]=@($tails|Where-Object{(Get-EvFinalizeKey $Context $_.pair)-ceq$key})[0]
    }
    $selfTails=@($tails|Where-Object{$null-ne$_.package.PSObject.Properties['selfCheckRepairLimit']})
    if($selfTails.Count-and$null-eq$heads.selfCheck){throw 'WORK_PREDECESSOR_SELF_HEAD_REQUIRED'}
    $selfRoot=$null;$cycle=0;$limit=0
    foreach($tail in $selfTails){
        $root=$tail.packageRef
        if($null-ne$tail.package.PSObject.Properties['repairReviewBinding']){$root=[pscustomobject]@{path=$tail.package.repairReviewBinding.parentPackagePath;identity=$tail.package.repairReviewBinding.parentPackageIdentity}}
        if($null-ne$selfRoot-and-not(Test-EvSameRef $selfRoot $root $Context)){throw 'WORK_PREDECESSOR_SELF_ROOT_AMBIGUOUS'}
        $selfRoot=$root
    }
    if($null-ne$heads.selfCheck){
        $head=$heads.selfCheck;$producer=$head.package;$authority=$head.source.binding
        if($null-eq$producer.PSObject.Properties['selfCheckRepairLimit']){throw 'WORK_PREDECESSOR_SELF_HEAD_INVALID'}
        $limit=[int]$producer.selfCheckRepairLimit
        if($null-ne$head.result.PSObject.Properties['continuationReceipt']-and$null-ne$head.result.continuationReceipt){$cycle=Assert-AiwSelfRepairChain $head.context $producer $head.result.continuationReceipt}
        elseif($null-ne$authority.PSObject.Properties['continuationReceiptPath']-and$authority.continuationReceiptPath-cne'NOT_REQUIRED'){
            $leaf=Read-EvRef $head.context ([pscustomobject]@{path=$authority.continuationReceiptPath;identity=$authority.continuationReceiptIdentity}) -Json
            $cycle=Assert-AiwSelfRepairChain $head.context $producer $leaf
        }else{$cycle=Get-AiwSelfRepairOriginCycle $head.context $producer}
        if($cycle-lt0-or$cycle-gt$limit){throw 'WORK_PREDECESSOR_SELF_CYCLE'}
        $sources=Get-EvSelfHeadSourceKeys $head
        foreach($tail in $selfTails){if(-not$sources.Contains($tail.source.contextIdentity+'|'+$tail.source.selectionIdentity)){throw 'WORK_PREDECESSOR_SELF_HEAD_FORK'}}
    }
    $review=Get-EvSupersessionReviewFacts $Context $a $tails $heads.review $selfRoot $Decision.predecessorTaskRef
    return [pscustomobject]@{decision=$Decision;taskId=$a.taskId;owner=$a.taskOwner;plan=$plan;tails=$tails;selfRoot=$selfRoot;selfCycle=$cycle;selfLimit=$limit;review=$review}
}
function Assert-EvPredecessorStages($Context,$OldPlan,$Request){
    $current=Get-AiwProjectWorkPlan $Request
    if($null-eq$current){throw 'WORK_PREDECESSOR_PLAN_REQUIRED'}
    foreach($old in $OldPlan.stages){
        $matches=@($current.stages|Where-Object id -CEQ $old.id)
        if($matches.Count-ne1){throw 'WORK_PREDECESSOR_STAGE_REMOVED'}
        $stage=$matches[0]
        if($stage.kind-cne$old.kind-or-not(Test-EvSameRef $stage.requiredBy $old.requiredBy $Context)-or(@($stage.dependsOn|Sort-Object -CaseSensitive)-join'|')-cne(@($old.dependsOn|Sort-Object -CaseSensitive)-join'|')){throw 'WORK_PREDECESSOR_STAGE_DEFINITION_DRIFT'}
        if($old.evidenceRefs.Count){
            Assert-EvSameCandidates $stage.candidateRef $old.candidateRef $Context
            foreach($ref in $old.evidenceRefs){if(@($stage.evidenceRefs|Where-Object{$_.kind-ceq$ref.kind-and(Test-EvSameRef $_ $ref $Context)}).Count-ne1){throw 'WORK_PREDECESSOR_STAGE_EVIDENCE_REMOVED'}}
            if($null-ne$old.PSObject.Properties['evidenceConsumption']-and(Get-AiwContentDescriptorIdentity $stage.evidenceConsumption)-cne(Get-AiwContentDescriptorIdentity $old.evidenceConsumption)){throw 'WORK_PREDECESSOR_ORIGINAL_FINALIZE_DRIFT'}
        }
    }
}
function Get-EvWorkPredecessor($Context,$Request){
    if($null-eq$Request.PSObject.Properties['predecessorRef']){return $null}
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')
    Import-Module (Join-Path $PSScriptRoot 'ContentSources.psm1')
    Assert-AiwProjectWorkContext $Request
    $state=Get-EvReadState $Context
    if($null-eq$state.PSObject.Properties['predecessors']){
        $state|Add-Member predecessors ([Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal))
        $state|Add-Member predecessorReading ([Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal))
    }
    $key=Get-AiwContentDescriptorIdentity $Request
    if($state.predecessors.ContainsKey($key)){return $state.predecessors[$key]}
    if(-not$state.predecessorReading.Add($key)){throw 'WORK_PREDECESSOR_REFERENCE_CYCLE'}
    try{
        $pair=$Request.predecessorRef.closureFinalize
        $input=Read-EvRef $Context $pair.inputRef -Json;$result=Read-EvRef $Context $pair.resultRef -Json
        $source=Read-EvProcessOperation $Context $input $result
        if($source.schemaVersion-ne5-or$source.construction.entry-cne'ADMIT_ACTION'-or$source.binding.contextType-cne'TASK'-or$source.intentEnvelope.requestedActionKind-cne'CONTROL_WRITE'){throw 'WORK_PREDECESSOR_ORIGINAL_ADMIT_REQUIRED'}
        $admit=Read-EvRef $Context $source.construction.boundaryRef -Json
        if($admit.mode-cne'ADMIT_ACTION'-or$admit.schemaVersion-ne4-or$null-eq$admit.PSObject.Properties['currentOperation']){throw 'WORK_PREDECESSOR_ORIGINAL_ADMIT_REQUIRED'}
        if($admit.currentOperation.expectedTaskIdentity-cne$source.binding.taskIdentity-or$admit.currentOperation.authorizationRef.identity-cne$source.binding.authorizationIdentity-or$admit.currentOperation.observedActor-cne$source.binding.actor){throw 'WORK_PREDECESSOR_ADMIT_BINDING_DRIFT'}
        $closed=Read-EvCompletedTaskAction $Context $pair $source.binding.taskId $Request.owner
        $package=$closed.package;$relative=$source.sourceLocators.taskRelativePath
        if($relative-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'-or$package.schemaVersion-ne1-or@($package.actions).Count-ne1-or$package.actions[0]-cne'CONTROL_WRITE'-or$source.binding.actor-cne$Request.owner){throw 'WORK_PREDECESSOR_CLOSE_SCOPE'}
        $archive=$relative.Replace('/active/','/archive/')
        if(@($package.exactPaths|Where-Object{$_-cnotin@($relative,$archive)}).Count-or$relative-cnotin$package.exactPaths){throw 'WORK_PREDECESSOR_CLOSE_SCOPE'}
        $preimages=@($package.objectIdentities|Where-Object path -CEQ $relative)
        if($preimages.Count-ne1-or$preimages[0].identity-cne$source.binding.taskIdentity){throw 'WORK_PREDECESSOR_CLOSE_PREIMAGE'}
        foreach($name in @('transitionPlan','continuationPlan','sourcePublicationBinding','repairReviewPlan','repairReviewBinding')){if($null-ne$package.PSObject.Properties[$name]){throw 'WORK_PREDECESSOR_CLOSE_SCOPE'}}
        $posts=@($closed.postimages|Where-Object{$_.path-ceq$relative})
        if($posts.Count-ne1){throw 'WORK_PREDECESSOR_CLOSE_POSTIMAGE'}
        $post=$posts[0]
        if($post.identity-ceq'MISSING'){
            $archive=$relative.Replace('/active/','/archive/');$posts=@($closed.postimages|Where-Object path -CEQ $archive)
            if($posts.Count-ne1-or$posts[0].identity-ceq'MISSING'){throw 'WORK_PREDECESSOR_CLOSE_ARCHIVE'}
            $post=$posts[0]
        }elseif(-not[IO.File]::Exists((Resolve-EvPath $Context $relative -Candidate -AllowMissing))){$post=[pscustomobject]@{path=$relative.Replace('/active/','/archive/');identity=$post.identity}}
        $closedPath=Read-EvRef $Context $post -Candidate
        $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($closedPath))
        $closure=Get-AiwTaskClosureFields $text -RequireComplete
        if($closure.Outcome-cne'SUPERSEDED'-or$text-cnotmatch('(?m)^# '+[regex]::Escape($source.binding.taskId)+' (?:—|-)')-or[regex]::Match($text,'(?m)^- Owner:\s*(\S+)\s*$').Groups[1].Value-cne$Request.owner){throw 'WORK_PREDECESSOR_NOT_SUPERSEDED'}
        $decision=Read-EvSupersessionDecision $Context $closure.ClosureDecision
        if($null-eq$decision){throw 'WORK_PREDECESSOR_STRICT_DECISION_REQUIRED'}
        $facts=Get-EvSupersessionFacts $Context $decision $source
        if($Request.profile-cne$source.binding.profile){throw 'WORK_PREDECESSOR_PROFILE_DRIFT'}
        if($source.binding.context.workRoute.role-cne([regex]::Match($text,'(?m)^- Work route: actor=[^;]+; role=([^;]+);').Groups[1].Value)-or$source.binding.context.workRoute.phase-cne([regex]::Match($text,'(?m)^- Work route: actor=[^;]+; role=[^;]+; phase=(\S+)').Groups[1].Value)){throw 'WORK_PREDECESSOR_CLOSE_ROUTE_DRIFT'}
        if((Get-AiwContentDescriptorIdentity $decision.userDecisionRef)-cne(Get-AiwContentDescriptorIdentity $Request.userDecisionRef)){throw 'WORK_PREDECESSOR_USER_DECISION_DRIFT'}
        $successor=[pscustomobject]@{requestRef=$Request.requestRef;owner=$Request.owner;subject=$Request.subject;requirementsRef=$Request.requirementsRef}
        if((Get-AiwContentDescriptorIdentity $decision.successorRequest)-cne(Get-AiwContentDescriptorIdentity $successor)){throw 'WORK_PREDECESSOR_SUCCESSOR_DRIFT'}
        Assert-EvPredecessorStages $Context $facts.plan $Request
        $state.predecessors.Add($key,$facts)
        return $facts
    }finally{$null=$state.predecessorReading.Remove($key)}
}
function Assert-AiwWorkPredecessor($Context,$Request){$null=Get-EvWorkPredecessor $Context $Request}
function Assert-AiwWorkPredecessorPackage($Context,$Request,$Package){
    $facts=Get-EvWorkPredecessor $Context $Request
    if($null-eq$facts){return}
    $production=@($Package.actions|Where-Object{$_-cin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN')}).Count-gt0
    if($production-and$null-ne$facts.selfRoot-and($null-eq$Package.PSObject.Properties['selfCheckRepairLimit']-or$Package.selfCheckRepairLimit-ne$facts.selfLimit)){throw 'WORK_PREDECESSOR_SELF_LIMIT_DRIFT'}
    $plannedAction=@($Package.actions|Where-Object{$_-cin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE')}).Count-gt0
    if($plannedAction-and$null-ne$facts.review){
        if($null-ne$Package.PSObject.Properties['repairReviewPlan']-or$null-eq$Package.PSObject.Properties['repairReviewBinding']){throw 'WORK_PREDECESSOR_REVIEW_BINDING_REQUIRED'}
        $binding=$Package.repairReviewBinding
        $null=Get-EvWorkReviewRoot $Context $Request ([pscustomobject]@{path=$binding.parentPackagePath;identity=$binding.parentPackageIdentity})
        if($facts.review.state-ceq'APPROVED'){throw 'WORK_PREDECESSOR_REVIEW_ALREADY_APPROVED'}
        if($binding.phase-ceq'INITIAL_REVIEW'){
            if($facts.review.state-cne'INITIAL_READY'-or$binding.cycle-ne0){throw 'WORK_PREDECESSOR_REVIEW_CYCLE_RESET'}
        }elseif($binding.phase-cin@('REPAIR','REREVIEW')){
            $minimum=[int]$facts.review.cycle+$(if($facts.review.state-ceq'CHANGES_REQUESTED'){1}else{0})
            if($binding.cycle-lt$minimum-or$binding.cycle-lt1-or$binding.cycle-gt$facts.review.parent.repairReviewPlan.maxCycles){throw 'WORK_PREDECESSOR_REVIEW_CYCLE_RESET'}
        }else{throw 'WORK_PREDECESSOR_REVIEW_PHASE'}
    }
}
function Get-EvPredecessorResultBinding($Context,$Request,$Reference,$Record,$Candidates,$Requirements){
    $facts=Get-EvWorkPredecessor $Context $Request
    if($null-eq$facts-or$Record.taskId-cne$facts.taskId){throw 'EVIDENCE_TASK_DRIFT'}
    $matches=@($facts.plan.stages|Where-Object{@($_.evidenceRefs|Where-Object{$_.kind-ceq$Reference.kind-and(Test-EvSameRef $_ $Reference $Context)}).Count})
    if($matches.Count-ne1){throw 'WORK_PREDECESSOR_STAGE_UNBOUND'}
    $stage=$matches[0]
    Assert-EvSameCandidates $stage.candidateRef $Candidates $Context
    if(-not(Test-EvSameRef $stage.requiredBy $Requirements $Context)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
    $pairs=@($facts.tails|ForEach-Object{$_.pair})
    $consumption=Get-EvConsumption $stage evidenceConsumption HISTORICAL_SUCCESS $pairs
    if($consumption.purpose-cne'HISTORICAL_SUCCESS'){throw 'WORK_PREDECESSOR_STAGE_ORIGINAL_FINALIZE_REQUIRED'}
    return [pscustomobject]@{taskId=$facts.taskId;plan=$facts.plan;originalFinalize=$consumption.originalFinalize}
}
Export-ModuleMember -Function Assert-AiwWorkPredecessor,Assert-AiwWorkPredecessorPackage
