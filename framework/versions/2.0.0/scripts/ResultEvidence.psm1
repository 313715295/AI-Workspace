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
function New-AiwEvidenceContext([string]$ProjectRoot,[string]$RepositoryRoot='', [string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@()) {
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
    return [pscustomobject]@{ProjectRoot=$project;RepositoryRoot=$repo;Roots=@($roots|Select-Object -Unique);ForbiddenPaths=@($excluded|Select-Object -Unique);Reading=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
}
function Resolve-EvPath($Context,[string]$Path,[switch]$Candidate) {
    Assert-EvString $Path
    $value=$Path.Replace('\','/')
    if($value.Contains('//')-or$value-cne$value.Normalize([Text.NormalizationForm]::FormC)-or$value-match '[\x00-\x1f*?]'){throw 'EVIDENCE_PATH_INVALID'}
    foreach($part in $value.Split('/')){if($part-in@('.','..')-or$part.EndsWith('.')-or$part.EndsWith(' ')-or$part-match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'EVIDENCE_PATH_INVALID'}}
    $base=if($Candidate){$Context.RepositoryRoot}else{$Context.ProjectRoot}
    $full=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path $base $Path}))
    $root=@($Context.Roots|Where-Object{$full.StartsWith($_+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}|Sort-Object Length -Descending|Select-Object -First 1)
    if($root.Count-ne1){throw 'EVIDENCE_PATH_OUTSIDE_BOUND_ROOTS'}
    # All exclusions are decided lexically before metadata, hashing or reading.
    foreach($r in $Context.Roots){
        if(-not$full.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){continue}
        $rel=[IO.Path]::GetRelativePath($r,$full).Replace('\','/')
        foreach($forbidden in $Context.ForbiddenPaths){$f=([string]$forbidden).Replace('\','/').TrimEnd('/');if($rel.Equals($f,[StringComparison]::OrdinalIgnoreCase)-or$rel.StartsWith($f+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'EVIDENCE_PATH_FORBIDDEN'}}
    }
    $cursor=[IO.Path]::GetPathRoot($full)
    $parts=$full.Substring($cursor.Length).Split([IO.Path]::DirectorySeparatorChar)
    foreach($part in $parts){if($part.Contains(':')){throw 'EVIDENCE_PATH_INVALID'}}
    foreach($part in $parts){
        $cursor=Join-Path $cursor $part
        $errors=@();$item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue -ErrorVariable errors
        if($null-eq$item){
            if(@($errors|Where-Object{$_.CategoryInfo.Category-cne'ObjectNotFound'}).Count){throw 'EVIDENCE_PATH_UNAVAILABLE'}
            if($Candidate){return $full}
            throw 'EVIDENCE_OBJECT_MISSING'
        }
        if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'EVIDENCE_PATH_REPARSE'}
        if($cursor-cne$full-and-not$item.PSIsContainer){throw 'EVIDENCE_PATH_NOT_DIRECTORY'}
    }
    if($item.PSIsContainer){throw 'EVIDENCE_NOT_FILE'}
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
function Test-EvSameRef($A,$B) {
    if($A.path-cne$B.path-or$A.identity-cne$B.identity){return $false}
    $as=if($null-ne$A.PSObject.Properties['section']){[string]$A.section}else{''}
    $bs=if($null-ne$B.PSObject.Properties['section']){[string]$B.section}else{''}
    return $as-ceq$bs
}
function Assert-EvSameCandidates($Actual,$Expected) {
    Assert-EvRefs $Actual -Nonempty -Candidate;Assert-EvRefs $Expected -Nonempty -Candidate
    if($Actual.Count-ne$Expected.Count){throw 'EVIDENCE_CANDIDATE_SET'}
    foreach($ref in $Expected){if(@($Actual|Where-Object{Test-EvSameRef $_ $ref}).Count-ne1){throw 'EVIDENCE_CANDIDATE_DRIFT'}}
}
function Test-EvSameCandidates($Actual,$Expected) {
    try{Assert-EvSameCandidates $Actual $Expected;return $true}catch{return $false}
}
function Read-AiwResultEvidence($Context,$Reference,[string]$TaskId,$CandidateObjects,$RequirementsRef,[switch]$RequireSuccess,[string]$ExpectedActor='',[string]$AuthorizationIdentity='') {
    Assert-EvRef $Reference -Typed
    $key=$Reference.path+'|'+$Reference.identity
    if($Context.Reading.Count-ge32-or-not$Context.Reading.Add($key)){throw 'EVIDENCE_REFERENCE_CYCLE'}
    try{
        $ref=[pscustomobject]@{path=$Reference.path;identity=$Reference.identity}
        $record=Read-EvRef $Context $ref -Json
        Assert-EvFields $record @('schemaVersion','taskId','actor','candidateObjects','requirementsRef','outcome','checks','evidenceLocators') @('authorizationRef','acceptedCommit')
        Assert-EvInteger $record.schemaVersion;if($record.schemaVersion-ne1){throw 'EVIDENCE_SCHEMA'}
        foreach($s in @('taskId','actor','outcome')){Assert-EvString $record.$s}
        if($record.taskId-cne$TaskId){throw 'EVIDENCE_TASK_DRIFT'}
        if($ExpectedActor-and$record.actor-cne$ExpectedActor){throw 'EVIDENCE_ACTOR_DRIFT'}
        Assert-EvSameCandidates $record.candidateObjects $CandidateObjects
        foreach($candidate in $record.candidateObjects){$null=Read-EvRef $Context $candidate -Candidate}
        Assert-EvRef $record.requirementsRef -Section
        if(-not(Test-EvSameRef $record.requirementsRef $RequirementsRef)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
        $null=Read-EvRef $Context $record.requirementsRef -Section
        $outcomes=@{SELF_CHECK=@('PASS','FAIL','INCOMPLETE');REVIEW_VERDICT=@('APPROVED','CHANGES_REQUESTED','REJECTED','INCOMPLETE');RESULT_ACCEPTANCE=@('ACCEPTED','REJECTED','INCOMPLETE')}
        if($record.outcome-cnotin$outcomes[$Reference.kind]){throw 'EVIDENCE_OUTCOME'}
        $success=$record.outcome-ceq$outcomes[$Reference.kind][0]
        if($RequireSuccess-and-not$success){throw 'EVIDENCE_NOT_SUCCESSFUL'}
        Assert-EvRefs $record.evidenceLocators
        foreach($locator in $record.evidenceLocators){$null=Read-EvRef $Context $locator}
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
            }else{foreach($locator in $check.evidenceLocators){$null=Read-EvRef $Context $locator}}
        }
        if($Reference.kind-ceq'SELF_CHECK'){
            if($null-ne$record.PSObject.Properties['authorizationRef']-or$null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
        }else{
            if($null-eq$record.PSObject.Properties['authorizationRef']){throw 'EVIDENCE_ORIGINAL_PACKAGE_REQUIRED'}
            $package=Read-EvRef $Context $record.authorizationRef -Json
            $action=if($Reference.kind-ceq'REVIEW_VERDICT'){'REVIEW_EXECUTE'}else{'RESULT_ACCEPT'}
            if($package.taskId-cne$TaskId-or$package.grantee-cne$record.actor-or@($package.actions).Count-ne1-or$package.actions[0]-cne$action){throw 'EVIDENCE_ORIGINAL_PACKAGE_DRIFT'}
            if($AuthorizationIdentity-and$record.authorizationRef.identity-cne$AuthorizationIdentity){throw 'EVIDENCE_AUTHORIZATION_DRIFT'}
            Assert-EvSameCandidates @(Get-AiwPackageCandidateReferences $package) $record.candidateObjects
            if($Reference.kind-ceq'REVIEW_VERDICT'){
                if($null-ne$record.PSObject.Properties['acceptedCommit']){throw 'EVIDENCE_KIND_FIELDS'}
                if($package.profile-ceq'CRITICAL'-or$null-ne$package.PSObject.Properties['candidateWriter']-or$null-ne$package.PSObject.Properties['materialContributors']){
                    if($package.reviewIndependence-cne'INDEPENDENT'){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
                    foreach($field in @('candidateWriter','materialContributors')){if($null-eq$package.PSObject.Properties[$field]){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}}
                    if($record.actor-cin(@($package.owner,$package.issuer,$package.candidateWriter)+@($package.materialContributors))){throw 'EVIDENCE_REVIEW_INDEPENDENCE'}
                }
            }else{
                Assert-AiwAcceptanceBinding $Context $package $null -Historical
                if($null-ne$package.PSObject.Properties['acceptanceBinding']-and-not(Test-EvSameRef $package.acceptanceBinding.requirementsRef $record.requirementsRef)){throw 'EVIDENCE_REQUIREMENTS_DRIFT'}
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
    Assert-EvFields $plan @('schemaVersion','stages');Assert-EvInteger $plan.schemaVersion
    if($plan.schemaVersion-ne1){throw 'ACCEPTANCE_PLAN_SCHEMA'}
    Assert-EvArray $plan.stages;if($plan.stages.Count-eq0-or$plan.stages.Count-gt128){throw 'ACCEPTANCE_PLAN_STAGE_COUNT'}
    $stages=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($stage in $plan.stages){
        Assert-EvFields $stage @('id','kind','requiredBy','dependsOn','candidateRef','evidenceRefs')
        Assert-EvString $stage.id
        if($stage.id-cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'-or$stages.ContainsKey($stage.id)){throw 'ACCEPTANCE_PLAN_STAGE_ID'}
        if($stage.kind-cnotin@('DESIGN','DESIGN_REVIEW','SELF_CHECK','RESULT_REVIEW','RESULT_ACCEPT','USER_DECISION')){throw 'ACCEPTANCE_PLAN_STAGE_KIND'}
        Assert-EvRef $stage.requiredBy -Section;Assert-EvArray $stage.dependsOn
        $deps=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($dep in $stage.dependsOn){Assert-EvString $dep;if(-not$deps.Add($dep)){throw 'ACCEPTANCE_PLAN_DUPLICATE_EDGE'}}
        Assert-EvRefs $stage.candidateRef -Candidate:($stage.kind-cne'USER_DECISION');Assert-EvRefs $stage.evidenceRefs -Typed
        if($stage.kind-cin@('DESIGN','USER_DECISION')-and$stage.evidenceRefs.Count){throw 'ACCEPTANCE_PLAN_STAGE_EVIDENCE_KIND'}
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
function Assert-AiwAcceptanceStages($Context,$Plan,[string]$TaskId,[string]$BeforeStage='', $UserDecisionRefs=@()) {
    $stages=if($BeforeStage){@(Get-EvPrerequisites $Plan $BeforeStage)}else{@($Plan.stages)}
    Assert-EvRefs $UserDecisionRefs
    foreach($stage in $stages){
        $null=Read-EvRef $Context $stage.requiredBy -Section
        if($stage.candidateRef.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
        if($stage.kind-ceq'USER_DECISION'){
            foreach($ref in $stage.candidateRef){
                if(@($UserDecisionRefs|Where-Object{Test-EvSameRef $_ $ref}).Count-ne1){throw ('ACCEPTANCE_USER_DECISION_UNBOUND|'+$stage.id)}
                $null=Read-EvRef $Context $ref
            }
        }elseif($stage.kind-ceq'DESIGN'){
            foreach($ref in $stage.candidateRef){$null=Read-EvRef $Context $ref -Candidate}
        }else{
            if($stage.evidenceRefs.Count-eq0){throw ('ACCEPTANCE_STAGE_INCOMPLETE|'+$stage.id)}
            foreach($ref in $stage.evidenceRefs){$null=Read-AiwResultEvidence $Context $ref $TaskId $stage.candidateRef $stage.requiredBy -RequireSuccess}
        }
    }
}
function Assert-AiwAcceptanceBinding($Context,$Package,$Plan,[switch]$Historical) {
    if($null-eq$Package){throw 'RESULT_ACCEPT_AUTHORIZATION_REQUIRED'}
    if(@($Package.actions).Count-ne1-or$Package.actions[0]-cne'RESULT_ACCEPT'){throw 'RESULT_ACCEPT_PURE_PACKAGE_REQUIRED'}
    foreach($f in @('continuationPlan','repairReviewPlan','repairReviewBinding','receiverBinding','transitionPlan')){if($null-ne$Package.PSObject.Properties[$f]){throw 'RESULT_ACCEPT_CANNOT_REDELEGATE'}}
    $binding=if($null-ne$Package.PSObject.Properties['acceptanceBinding']){$Package.acceptanceBinding}else{$null}
    if($null-eq$binding){
        if($Package.grantee-cne$Package.owner){throw 'RESULT_ACCEPT_DELEGATION_REQUIRED'}
        if($null-ne$Plan-or$Package.profile-ceq'CRITICAL'){throw 'RESULT_ACCEPT_STAGE_BINDING_REQUIRED'}
        return
    }
    Assert-EvFields $binding @('candidateObjects','requirementsRef','prerequisiteEvidenceRefs','reservedUserDecisionRefs')
    Assert-EvSameCandidates $binding.candidateObjects @(Get-AiwPackageCandidateReferences $Package)
    foreach($candidate in $binding.candidateObjects){$null=Read-EvRef $Context $candidate -Candidate}
    $null=Read-EvRef $Context $binding.requirementsRef -Section
    Assert-EvRefs $binding.prerequisiteEvidenceRefs -Typed;Assert-EvRefs $binding.reservedUserDecisionRefs
    foreach($ref in $binding.reservedUserDecisionRefs){$null=Read-EvRef $Context $ref}
    $prereqs=@();$stageId=''
    if($null-ne$Plan){
        $stages=@($Plan.stages|Where-Object{$_.kind-ceq'RESULT_ACCEPT'-and(Test-EvSameRef $_.requiredBy $binding.requirementsRef)-and(Test-EvSameCandidates $_.candidateRef $binding.candidateObjects)})
        if($stages.Count-ne1){throw 'RESULT_ACCEPT_STAGE_AMBIGUOUS'}
        $stageId=$stages[0].id;$prereqs=@(Get-EvPrerequisites $Plan $stageId)
    }
    if($Package.grantee-cne$Package.owner-and$Package.issuer-cne$Package.owner){
        # A Controller title is insufficient. The exceptional user route binds
        # the original current user source by identity; origin/meaning is HOST.
        if(@($binding.reservedUserDecisionRefs|Where-Object{$_.identity-ceq$Package.userConfirmation}).Count-ne1){throw 'RESULT_ACCEPT_OWNER_OR_USER_DECISION_REQUIRED'}
    }
    foreach($ref in $binding.prerequisiteEvidenceRefs){
        # Stage-specific design evidence can bind different candidates/requirements.
        $matches=@($prereqs|Where-Object{@($_.evidenceRefs|Where-Object{Test-EvSameRef $_ $ref}).Count})
        if($matches.Count-eq1){$candidate=$matches[0].candidateRef;$requirements=$matches[0].requiredBy}else{$candidate=$binding.candidateObjects;$requirements=$binding.requirementsRef}
        if($Historical){
            # Historical acceptance retains the original typed evidence bindings;
            # subsequent task progress is not a new permanent hash dependency.
            $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            $candidate=$raw.candidateObjects;$requirements=$raw.requirementsRef
        }
        $null=Read-AiwResultEvidence $Context $ref $Package.taskId $candidate $requirements -RequireSuccess
    }
    if($Package.profile-ceq'CRITICAL'){
        $reviewed=$false
        foreach($ref in @($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq'REVIEW_VERDICT'})){
            $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
            if((Test-EvSameCandidates $raw.candidateObjects $binding.candidateObjects)-and(Test-EvSameRef $raw.requirementsRef $binding.requirementsRef)){$reviewed=$true}
        }
        if(-not$reviewed){throw 'RESULT_ACCEPT_CRITICAL_REVIEW_REQUIRED'}
    }
    if($null-ne$Plan){
        foreach($stage in $prereqs){foreach($ref in $stage.evidenceRefs){if(@($binding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq$ref.kind-and(Test-EvSameRef $_ $ref)}).Count-ne1){throw 'RESULT_ACCEPT_PREREQUISITE_UNBOUND'}}}
        Assert-AiwAcceptanceStages $Context $Plan $Package.taskId $stageId $binding.reservedUserDecisionRefs
    }
}
function New-AiwPackageEvidenceContext([string]$ProjectRoot,$Package,[string]$FrameworkRoot='', [string[]]$ForbiddenPaths=@()) {
    $repo=$ProjectRoot
    if($null-ne$Package-and$Package.schemaVersion-eq2-and$Package.repositoryId-cne'CONTROL'){
        $cfg=ConvertFrom-EvJson ([IO.File]::ReadAllText((Join-Path $ProjectRoot '.ai-workspace/project.json')))
        if($null-eq$cfg.PSObject.Properties['frameworkTarget']-or$cfg.frameworkTarget.repositoryId-cne$Package.repositoryId){throw 'EVIDENCE_REPOSITORY_BINDING'}
        $sibling=[string]$cfg.frameworkTarget.siblingDirectory
        if($sibling-cnotmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*$'-or$sibling.EndsWith('.')){throw 'EVIDENCE_REPOSITORY_BINDING'}
        $repo=Join-Path (Split-Path -Parent $ProjectRoot) $sibling
    }
    return New-AiwEvidenceContext $ProjectRoot $repo $FrameworkRoot $ForbiddenPaths
}
function Assert-AiwReviewSelfCheck($Context,$References,[string]$TaskId,$Candidates,$Plan=$null) {
    Assert-EvRefs $References -Typed
    $refs=@($References|Where-Object{$_.kind-ceq'SELF_CHECK'})
    if($refs.Count-eq0){throw 'REVIEW_SELF_CHECK_REQUIRED'}
    foreach($ref in $refs){
        $raw=Read-EvRef $Context ([pscustomobject]@{path=$ref.path;identity=$ref.identity}) -Json
        $requirements=$raw.requirementsRef
        if($null-ne$Plan){
            $matches=@($Plan.stages|Where-Object{$_.kind-ceq'SELF_CHECK'-and(Test-EvSameCandidates $_.candidateRef $Candidates)-and(Test-EvSameRef $_.requiredBy $requirements)})
            if($matches.Count-eq0){throw 'REVIEW_SELF_CHECK_PLAN_DRIFT'}
        }
        $null=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $requirements -RequireSuccess
    }
}
function Get-AiwBoundaryEvidence($Receipt,$Boundary) {
    $refs=@()
    if($null-ne$Boundary.PSObject.Properties['evidenceRefs']){$refs=$Boundary.evidenceRefs}
    Assert-EvRefs $refs -Typed
    $closurePaths=@()
    if($Boundary.mode-ceq'FINALIZE_OUTPUT'-and$Receipt.actionKind-ceq'CONTROL_WRITE'){$closurePaths=@($Receipt.exactPaths|Where-Object{$_-cmatch '^\.ai-workspace/tasks/(active|archive)/[^/]+\.md$'})}
    $isClosure=$closurePaths.Count-gt0
    if($refs.Count-eq0-and$Receipt.actionKind-cnotin@('REVIEW_ROUTE','REVIEW_EXECUTE','RESULT_ACCEPT','TEST_RUN')-and-not$isClosure){return [pscustomobject]@{references=@();records=@();evidenceCeiling='INSTRUCTION_BOUND'}}
    $package=$null
    if($Receipt.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){$package=ConvertFrom-EvJson ([IO.File]::ReadAllText($Receipt.sourceLocators.authorizationPackagePath))}
    $ctx=New-AiwPackageEvidenceContext $Receipt.sourceLocators.projectRoot $package $Receipt.sourceLocators.frameworkRoot $Receipt.authorityContext.forbiddenScope
    $taskText='';$plan=$null
    if($Receipt.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'){
        $taskText=[IO.File]::ReadAllText((Join-Path $ctx.ProjectRoot $Receipt.sourceLocators.taskRelativePath))
        $plan=Get-AiwAcceptancePlan $taskText
    }
    $records=@();$candidateObjects=@()
    if($null-ne$package-and$refs.Count-gt0){
        foreach($path in $package.exactPaths){
            $full=Resolve-EvPath $ctx $path -Candidate
            $candidateObjects+=[pscustomobject]@{path=$path;identity=(Get-EvCandidateIdentity $full)}
        }
    }
    $needed=if($Boundary.mode-ceq'ADMIT_ACTION'-and$Receipt.actionKind-ceq'REVIEW_ROUTE'){'SELF_CHECK'}elseif($Boundary.mode-ceq'FINALIZE_OUTPUT'){
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
    if($Receipt.actionKind-ceq'REVIEW_ROUTE'-and$Boundary.mode-ceq'ADMIT_ACTION'){Assert-AiwReviewSelfCheck $ctx $refs $Receipt.taskId $candidateObjects $plan}
    if($Receipt.actionKind-ceq'RESULT_ACCEPT'){
        Assert-AiwAcceptanceBinding $ctx $package $plan
        if($package.grantee-cne$package.owner-and$package.issuer-cne$package.owner-and$Boundary.publicDecisionIdentity-cne$package.userConfirmation){throw 'RESULT_ACCEPT_CURRENT_USER_DECISION_UNBOUND'}
    }
    # Closing SUCCESS checks the entire plan; internal acceptance checked only
    # its dependency closure. Later user gates never become implicit predecessors.
    foreach($closedPath in $closurePaths){
        $closedText=[IO.File]::ReadAllText((Resolve-EvPath $ctx $closedPath))
        if($closedText-cnotmatch '(?m)^- Range summary:[^\r\n]*lifecycle=CLOSED;'){continue}
        $closedPlan=Get-AiwAcceptancePlan $closedText
        if($null-eq$closedPlan){continue}
        $outcomes=[regex]::Matches($closedText,'(?m)^- Closure outcome:[ \t]*(?<value>[^\r\n]+)$')
        if($outcomes.Count-gt1){throw 'ACCEPTANCE_CLOSURE_OUTCOME'}
        if($outcomes.Count-eq1){
            if($outcomes[0].Groups['value'].Value-cin@('CANCELLED','SUPERSEDED')){continue}
            if($outcomes[0].Groups['value'].Value-cne'SUCCESS'){throw 'ACCEPTANCE_CLOSURE_OUTCOME'}
        }
        # No explicit outcome has the same success obligation as legacy cards;
        # removing the field cannot bypass a plan's required evidence.
        $ids=[regex]::Matches($closedText,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
        if($ids.Count-ne1){throw 'ACCEPTANCE_CLOSURE_TASK_ID'}
        $closedTaskId=$ids[0].Groups['id'].Value
        $userRefs=@()
        foreach($stage in $closedPlan.stages){
            if($stage.kind-ceq'USER_DECISION'){foreach($ref in $stage.candidateRef){if($ref.identity-ceq$Boundary.publicDecisionIdentity){$userRefs+=$ref}}}
            if($stage.kind-ceq'RESULT_ACCEPT'){
                foreach($ref in $stage.evidenceRefs){
                    $record=Read-AiwResultEvidence $ctx $ref $closedTaskId $stage.candidateRef $stage.requiredBy -RequireSuccess
                    $original=Read-EvRef $ctx $record.authorizationRef -Json
                    if($null-ne$original.PSObject.Properties['acceptanceBinding']){$userRefs+=@($original.acceptanceBinding.reservedUserDecisionRefs)}
                }
            }
        }
        $unique=@($userRefs|Group-Object path,identity|ForEach-Object{$_.Group[0]})
        Assert-AiwAcceptanceStages $ctx $closedPlan $closedTaskId '' $unique
    }
    return [pscustomobject]@{references=@($refs);records=@($records);evidenceCeiling='INSTRUCTION_BOUND'}
}
function Assert-AiwPushAcceptance($Context,$Reference,[string]$TaskId,$Candidates,[string]$Commit,[switch]$RequireReview) {
    $raw=Read-EvRef $Context ([pscustomobject]@{path=$Reference.path;identity=$Reference.identity}) -Json
    $record=Read-AiwResultEvidence $Context $Reference $TaskId $Candidates $raw.requirementsRef -RequireSuccess
    if($null-eq$record.PSObject.Properties['acceptedCommit']-or$record.acceptedCommit-cne$Commit){throw 'PUSH_ACCEPTED_COMMIT_DRIFT'}
    if($RequireReview){
        $package=Read-EvRef $Context $record.authorizationRef -Json
        if($null-eq$package.PSObject.Properties['acceptanceBinding']){throw 'PUSH_REVIEW_UNBOUND'}
        $refs=@($package.acceptanceBinding.prerequisiteEvidenceRefs|Where-Object{$_.kind-ceq'REVIEW_VERDICT'})
        if($refs.Count-eq0){throw 'PUSH_REVIEW_UNBOUND'}
        foreach($ref in $refs){$null=Read-AiwResultEvidence $Context $ref $TaskId $Candidates $record.requirementsRef -RequireSuccess}
    }
}
function Read-AiwEvidenceReference($Context,$Reference,[switch]$Json,[switch]$Candidate) {
    Read-EvRef $Context $Reference -Json:$Json -Candidate:$Candidate
}
Export-ModuleMember -Function New-AiwEvidenceContext,New-AiwPackageEvidenceContext,Get-AiwPackageCandidateReferences,Read-AiwEvidenceReference,Read-AiwResultEvidence,Get-AiwAcceptancePlan,Assert-AiwAcceptanceStages,Assert-AiwAcceptanceBinding,Assert-AiwReviewSelfCheck,Get-AiwBoundaryEvidence,Assert-AiwPushAcceptance
