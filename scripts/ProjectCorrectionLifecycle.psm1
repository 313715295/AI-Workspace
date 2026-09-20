Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionProjection.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1')

function Assert-AiwLifecycleFields($Value,[string[]]$Fields,[string]$Label) {
    if($Value-isnot[pscustomobject]){throw ($Label+'_OBJECT')}
    $actual=@($Value.PSObject.Properties.Name)
    if($actual.Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin$actual}).Count){throw ($Label+'_FIELDS')}
}
function Get-AiwLifecycleJson($Value) { return ($Value|ConvertTo-Json -Depth 64 -Compress)+"`n" }
function Get-AiwLifecycleIdentity([string]$Text) { return Get-AiwByteIdentity ([Text.UTF8Encoding]::new($false).GetBytes($Text)) }
function Assert-AiwLifecyclePath([string]$Root,[string]$Relative) {
    $full=Get-AiwContainedPath $Root $Relative
    if($Relative-ceq'.git'-or$Relative.StartsWith('.git/',[StringComparison]::OrdinalIgnoreCase)-or
       $Relative-ceq'.ai-workspace/corrections.json'-or$Relative.StartsWith('.ai-workspace/upgrade-recovery/',[StringComparison]::OrdinalIgnoreCase)){
        throw ('CORRECTION_EFFECT_PATH_RESERVED|'+$Relative)
    }
    return $full
}
function Get-AiwLifecycleState($Record) {
    if($null-eq$Record.PSObject.Properties['lifecycle']){return 'LEGACY'}
    return [string]$Record.lifecycle.state
}
function Read-AiwCorrectionInstallation([string]$Root,$Record) {
    $ref=$Record.lifecycle.installation
    Assert-AiwLifecycleFields $ref @('locator','identity') 'CORRECTION_INSTALLATION_REF'
    if(-not([string]$ref.locator).StartsWith('.ai-workspace/upgrade-recovery/corrections/',[StringComparison]::Ordinal)){throw 'CORRECTION_INSTALLATION_LOCATOR'}
    $doc=Read-AiwProjectJson (Get-AiwContainedPath $Root $ref.locator) 'CORRECTION_INSTALLATION'
    if($doc.Identity-cne$ref.identity-or$doc.Value.correctionId-cne$Record.correctionId){throw 'CORRECTION_INSTALLATION_DRIFT'}
    return $doc.Value
}

# @design-contract framework/versions/1.16.0/PROJECT_CONTROL.md#Project-corrections
# Ownership is an exact reversible edit, never a whole-file rollback over later edits.
function New-AiwCorrectionLifecycleProjection {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Plan)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    Assert-AiwLifecycleFields $Plan @('schemaVersion','operation','correctionId','expectedCorrectionsIdentity','decisionLocator','record','installation','installationRelativePath','transactionRelativePath','impact','forbiddenPaths') 'CORRECTION_PLAN'
    if($Plan.forbiddenPaths-isnot[array]-or@($Plan.forbiddenPaths|Where-Object{$_-isnot[string]}).Count){throw 'CORRECTION_FORBIDDEN_PATHS'}
    foreach($forbidden in $Plan.forbiddenPaths){Assert-AiwRelativePath $forbidden.TrimEnd('/')}
    if($Plan.schemaVersion-ne1-or$Plan.operation-cnotin@('INSTALL','REGISTER_HISTORY','REVISE','PAUSE','RESUME','UNINSTALL')-or$Plan.correctionId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or[string]::IsNullOrWhiteSpace($Plan.decisionLocator)){throw 'CORRECTION_PLAN_VALUES'}
    $transactionPath=Assert-AiwProjectionTransactionPath $root $Plan.transactionRelativePath
    $historyRoot='.ai-workspace/upgrade-recovery/corrections/'+$Plan.correctionId+'/'
    if(-not $Plan.transactionRelativePath.StartsWith($historyRoot,[StringComparison]::Ordinal)){throw 'CORRECTION_TRANSACTION_SCOPE'}
    if(Test-Path -LiteralPath $transactionPath){throw 'CORRECTION_TRANSACTION_EXISTS_USE_RECOVERY'}
    Assert-AiwLifecycleFields $Plan.impact @('stoppedObligations','independentObligations','inFlightEffects','recovery','semanticAssessment') 'CORRECTION_IMPACT'
    foreach($field in @('stoppedObligations','independentObligations','inFlightEffects')){
        if($Plan.impact.$field-isnot[array]-or@($Plan.impact.$field|Where-Object{$_-isnot[string]}).Count){throw 'CORRECTION_IMPACT_ARRAY'}
    }
    if([string]::IsNullOrWhiteSpace($Plan.impact.recovery)-or[string]::IsNullOrWhiteSpace($Plan.impact.semanticAssessment)){throw 'CORRECTION_SEMANTIC_ASSESSMENT_REQUIRED'}
    $carrierPath=Get-AiwContainedPath $root '.ai-workspace/corrections.json'
    $carrierDoc=Read-AiwProjectJson $carrierPath 'CORRECTIONS'
    if($carrierDoc.Identity-cne$Plan.expectedCorrectionsIdentity-or$carrierDoc.Value.schemaVersion-ne2){throw 'CORRECTION_CARRIER_DRIFT_OR_LEGACY'}
    $carrier=$carrierDoc.Value
    $existing=@($carrier.corrections|Where-Object{$_.correctionId-ceq$Plan.correctionId})
    if($existing.Count-gt1){throw 'CORRECTION_DUPLICATE'}
    $state=if($existing.Count){Get-AiwLifecycleState $existing[0]}else{'ABSENT'}
    $allowed=@{INSTALL=@('ABSENT','UNINSTALLED');REGISTER_HISTORY=@('LEGACY');REVISE=@('LEGACY','ACTIVE','PAUSED');PAUSE=@('ACTIVE');RESUME=@('PAUSED');UNINSTALL=@('ACTIVE','PAUSED')}
    if($state-cnotin$allowed[[string]$Plan.operation]){throw ('CORRECTION_TRANSITION|'+$state+'|'+$Plan.operation)}
    $targets=[Collections.Generic.List[object]]::new()
    $priorRecord=if($existing.Count){($existing[0]|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64)}else{$null}
    if($null-ne$priorRecord-and$null-ne$priorRecord.PSObject.Properties['history']){
        Assert-AiwLifecycleFields $priorRecord.history @('locator','identity') 'CORRECTION_HISTORY'
        if(-not$priorRecord.history.locator.StartsWith($historyRoot,[StringComparison]::Ordinal)-or-not$priorRecord.history.locator.EndsWith('/history.json',[StringComparison]::Ordinal)){throw 'CORRECTION_HISTORY_PATH'}
        $previousHistory=Read-AiwProjectJson (Get-AiwContainedPath $root $priorRecord.history.locator) 'CORRECTION_HISTORY'
        if($previousHistory.Identity-cne$priorRecord.history.identity-or$previousHistory.Value.correctionId-cne$Plan.correctionId){throw 'CORRECTION_HISTORY_DRIFT'}
    }
    $historyRelative=$Plan.transactionRelativePath.Substring(0,$Plan.transactionRelativePath.Length-'state.json'.Length)+'history.json'
    $historyPath=Get-AiwContainedPath $root $historyRelative
    if(Test-Path -LiteralPath $historyPath){throw 'CORRECTION_HISTORY_EXISTS'}
    $historyText=Get-AiwLifecycleJson ([ordered]@{schemaVersion=1;correctionId=$Plan.correctionId;operation=$Plan.operation;decisionLocator=$Plan.decisionLocator;priorRecord=$priorRecord})
    $targets.Add([pscustomobject]@{path=$historyRelative;text=$historyText})
    $revisedEffects=$Plan.operation-ceq'REVISE'-and$Plan.installation-is[pscustomobject]
    $previousInstallation=if($revisedEffects-and$state-cne'LEGACY'){Read-AiwCorrectionInstallation $root $existing[0]}else{$null}
    if($revisedEffects-and$state-ceq'LEGACY'){throw 'CORRECTION_REVISE_OWNERSHIP_REQUIRED'}
    if($Plan.operation-cin@('INSTALL','REGISTER_HISTORY')-or$revisedEffects){
        $record=if($Plan.operation-ceq'REGISTER_HISTORY'){
            if($Plan.record-cne'NOT_APPLICABLE'){throw 'CORRECTION_HISTORY_RECORD_UNCHANGED'}
            $existing[0]
        }else{($Plan.record|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64)}
        if($record.correctionId-cne$Plan.correctionId-or$null-ne$record.PSObject.Properties['lifecycle']-or($Plan.operation-cne'REGISTER_HISTORY'-and$null-ne$record.PSObject.Properties['history'])){throw 'CORRECTION_INSTALL_RECORD'}
        $installation=$Plan.installation
        Assert-AiwLifecycleFields $installation @('schemaVersion','correctionId','decisionLocator','dependsOn','changes') 'CORRECTION_INSTALLATION'
        if($installation.schemaVersion-ne1-or$installation.correctionId-cne$Plan.correctionId-or[string]::IsNullOrWhiteSpace($installation.decisionLocator)-or$installation.dependsOn-isnot[array]-or$installation.changes-isnot[array]-or$installation.changes.Count-gt64){throw 'CORRECTION_INSTALLATION_VALUES'}
        if(-not([string]$Plan.installationRelativePath).StartsWith('.ai-workspace/upgrade-recovery/corrections/'+$Plan.correctionId+'/',[StringComparison]::Ordinal)-or-not([string]$Plan.installationRelativePath).EndsWith('/installation.json',[StringComparison]::Ordinal)){throw 'CORRECTION_INSTALLATION_PATH'}
        $evidencePath=Get-AiwContainedPath $root $Plan.installationRelativePath
        if(Test-Path -LiteralPath $evidencePath){throw 'CORRECTION_INSTALLATION_EVIDENCE_EXISTS'}
        $evidenceText=Get-AiwLifecycleJson $installation
        $targets.Add([pscustomobject]@{path=$Plan.installationRelativePath;text=$evidenceText})
        $record|Add-Member lifecycle ([pscustomobject]@{state='ACTIVE';installation=[pscustomobject]@{locator=$Plan.installationRelativePath;identity=(Get-AiwLifecycleIdentity $evidenceText)};decisionLocator=$Plan.decisionLocator})
    }elseif($Plan.operation-ceq'REVISE'){
        if($Plan.installation-cne'NOT_APPLICABLE'-or$Plan.installationRelativePath-cne'NOT_APPLICABLE'-or$Plan.record-isnot[pscustomobject]){throw 'CORRECTION_REVISE_RECORD'}
        $record=($Plan.record|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64)
        if($record.correctionId-cne$Plan.correctionId-or$null-ne$record.PSObject.Properties['lifecycle']-or$null-ne$record.PSObject.Properties['history']){throw 'CORRECTION_REVISE_RECORD'}
        if($state-cne'LEGACY'){$record|Add-Member lifecycle $existing[0].lifecycle;$installation=Read-AiwCorrectionInstallation $root $record}
        else{$installation=[pscustomobject]@{dependsOn=@();changes=@()}}
    }else{
        if($Plan.record-cne'NOT_APPLICABLE'-or$Plan.installation-cne'NOT_APPLICABLE'-or$Plan.installationRelativePath-cne'NOT_APPLICABLE'){throw 'CORRECTION_EXISTING_INSTALLATION_ONLY'}
        $record=$existing[0]
        $installation=Read-AiwCorrectionInstallation $root $record
    }
    $active=@($carrier.corrections|Where-Object{(Get-AiwLifecycleState $_)-cin@('ACTIVE','LEGACY')-and$_.correctionId-cne$Plan.correctionId})
    $forward=$Plan.operation-cin@('INSTALL','RESUME','REGISTER_HISTORY','REVISE')
    $requiresActiveDependencies=$forward-and-not($Plan.operation-ceq'REVISE'-and$state-ceq'PAUSED')
    if($installation.dependsOn-isnot[array]-or@($installation.dependsOn|Select-Object -Unique).Count-ne$installation.dependsOn.Count){throw 'CORRECTION_DEPENDENCY_SHAPE'}
    foreach($dep in $installation.dependsOn){
        if($dep-isnot[string]-or$dep-cnotmatch'^[A-Z][A-Z0-9_]*$'-or$dep-ceq$Plan.correctionId){throw 'CORRECTION_DEPENDENCY_ID'}
        if($requiresActiveDependencies-and@($active|Where-Object correctionId -CEQ $dep).Count-ne1){throw ('CORRECTION_DEPENDENCY_INACTIVE|'+$dep)}
    }
    $otherInstallations=@()
    foreach($other in $active){
        if((Get-AiwLifecycleState $other)-ceq'LEGACY'){continue}
        $otherInstall=Read-AiwCorrectionInstallation $root $other
        $otherInstallations+=@($otherInstall)
        if(-not$forward-and$Plan.correctionId-cin@($otherInstall.dependsOn)){throw ('CORRECTION_ACTIVE_DEPENDENT|'+$other.correctionId)}
    }
    $working=@{};$conflicts=[Collections.Generic.List[object]]::new()
    $changes=@($installation.changes)
    if(-not$forward){[array]::Reverse($changes)}
    # A paused uninstall removes its installation state; effects are already absent.
    if($state-ceq'PAUSED'-and$Plan.operation-ceq'UNINSTALL'){$changes=@()}
    if($Plan.operation-ceq'REVISE'-and(-not$revisedEffects-or$state-ceq'PAUSED')){$changes=@()}
    $operations=@()
    if($revisedEffects-and$state-ceq'ACTIVE'){$reverse=@($previousInstallation.changes);[array]::Reverse($reverse);$operations+=@($reverse|ForEach-Object{[pscustomobject]@{change=$_;forward=$false}})}
    $operations+=@($changes|ForEach-Object{[pscustomobject]@{change=$_;forward=$forward}})
    foreach($operation in $operations){
        $change=$operation.change;$forward=$operation.forward
        try {
            $path=[string]$change.path
            foreach($forbidden in $Plan.forbiddenPaths){if($path.Equals($forbidden.TrimEnd('/'),[StringComparison]::OrdinalIgnoreCase)-or$path.StartsWith($forbidden.TrimEnd('/')+'/',[StringComparison]::OrdinalIgnoreCase)){throw 'CORRECTION_FORBIDDEN_PATH'}}
            $full=Assert-AiwLifecyclePath $root $path
            if(-not$working.ContainsKey($path)){
                $exists=Test-Path -LiteralPath $full -PathType Leaf
                if((Test-Path -LiteralPath $full)-and-not$exists){throw 'CORRECTION_EFFECT_NOT_FILE'}
                $initial=[byte[]]::new(0)
                if($exists){$initial=[IO.File]::ReadAllBytes($full)}
                $working[$path]=[pscustomobject]@{exists=$exists;bytes=$initial}
            }
            $current=$working[$path]
            if($change.kind-ceq'FILE'){
                foreach($otherInstall in $otherInstallations){if(@($otherInstall.changes|Where-Object{([string]$_.path).Equals($path,[StringComparison]::OrdinalIgnoreCase)}).Count){throw ('CORRECTION_SHARED_FILE|'+$otherInstall.correctionId)}}
                Assert-AiwLifecycleFields $change @('kind','path','beforeExists','afterExists','beforeBase64','afterBase64') 'CORRECTION_FILE'
                if($change.beforeExists-isnot[bool]-or$change.afterExists-isnot[bool]){throw 'CORRECTION_FILE_EXISTS'}
                $fromExists=if($forward){$change.beforeExists}else{$change.afterExists}
                $toExists=if($forward){$change.afterExists}else{$change.beforeExists}
                $from=[Convert]::FromBase64String($(if($forward){$change.beforeBase64}else{$change.afterBase64}))
                $to=[Convert]::FromBase64String($(if($forward){$change.afterBase64}else{$change.beforeBase64}))
                if($Plan.operation-ceq'REGISTER_HISTORY'){$fromExists=$toExists;$from=$to}
                if((-not$fromExists-and$from.Length)-or(-not$toExists-and$to.Length)){throw 'CORRECTION_ABSENT_BYTES'}
                if($current.exists-ne$fromExists-or(Get-AiwByteIdentity $current.bytes)-cne(Get-AiwByteIdentity $from)){throw 'CORRECTION_FILE_INDEPENDENT_CHANGE'}
                $current.exists=$toExists;$current.bytes=$to
            }elseif($change.kind-ceq'TEXT'){
                Assert-AiwLifecycleFields $change @('kind','path','before','after','prefix','suffix') 'CORRECTION_TEXT'
                foreach($key in @('before','after','prefix','suffix')){if($change.$key-isnot[string]){throw 'CORRECTION_TEXT_TYPE'}}
                if(-not$current.exists){throw 'CORRECTION_TEXT_MISSING'}
                $from=if($forward){$change.before}else{$change.after};$to=if($forward){$change.after}else{$change.before}
                if($Plan.operation-ceq'REGISTER_HISTORY'){$from=$to}
                $needle=$change.prefix+$from+$change.suffix
                if($needle.Length-eq0){throw 'CORRECTION_TEXT_ANCHOR_REQUIRED'}
                $text=[Text.UTF8Encoding]::new($false,$true).GetString($current.bytes)
                $start=$text.IndexOf($needle,[StringComparison]::Ordinal)
                if($start-lt0-or$text.IndexOf($needle,$start+1,[StringComparison]::Ordinal)-ge0){throw 'CORRECTION_TEXT_MIXED_OR_AMBIGUOUS'}
                foreach($otherInstall in $otherInstallations){foreach($owned in @($otherInstall.changes|Where-Object{([string]$_.path).Equals($path,[StringComparison]::OrdinalIgnoreCase)})){
                    if($owned.kind-cne'TEXT'){throw ('CORRECTION_SHARED_FILE|'+$otherInstall.correctionId)}
                    $otherNeedle=$owned.prefix+$owned.after+$owned.suffix
                    $otherStart=$text.IndexOf($otherNeedle,[StringComparison]::Ordinal)
                    if($otherNeedle.Length-eq0-or$otherStart-lt0-or$text.IndexOf($otherNeedle,$otherStart+1,[StringComparison]::Ordinal)-ge0){throw ('CORRECTION_SHARED_OWNERSHIP_UNPROVEN|'+$otherInstall.correctionId)}
                    $left=$start+$change.prefix.Length;$right=$left+$from.Length
                    $otherLeft=$otherStart+$owned.prefix.Length;$otherRight=$otherLeft+$owned.after.Length
                    if($left-le$otherRight-and$otherLeft-le$right){throw ('CORRECTION_OVERLAPPING_EFFECT|'+$otherInstall.correctionId)}
                }}
                $text=$text.Substring(0,$start)+$change.prefix+$to+$change.suffix+$text.Substring($start+$needle.Length)
                $current.bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
            }else{throw 'CORRECTION_EFFECT_KIND'}
        }catch{$conflicts.Add([pscustomobject]@{path=[string]$change.path;reason=[string]$_.Exception.Message})}
    }
    if($conflicts.Count){return [pscustomobject]@{status='CONFLICT';conflicts=@($conflicts);impact=$Plan.impact;projection=$null}}
    if($null-ne$record.PSObject.Properties['lifecycle']){
        $record.lifecycle.state=switch($Plan.operation){'PAUSE'{'PAUSED'};'UNINSTALL'{'UNINSTALLED'};'REVISE'{$state};default{'ACTIVE'}}
        $record.lifecycle.decisionLocator=$Plan.decisionLocator
    }
    $record|Add-Member -NotePropertyName history -NotePropertyValue ([pscustomobject]@{locator=$historyRelative;identity=(Get-AiwLifecycleIdentity $historyText)}) -Force
    $carrier.corrections=@($carrier.corrections|Where-Object correctionId -CNE $Plan.correctionId)+@($record)
    foreach($path in $working.Keys){
        $value=$working[$path]
        if($value.exists){$targets.Add([pscustomobject]@{path=$path;bytes=$value.bytes})}else{$targets.Add([pscustomobject]@{path=$path;exists=$false})}
    }
    $targets.Add([pscustomobject]@{path='.ai-workspace/corrections.json';text=(Get-AiwLifecycleJson $carrier)})
    $projection=New-AiwProjectProjection $root @($targets)
    return [pscustomobject]@{status='READY';operation=$Plan.operation;correctionId=$Plan.correctionId;projection=$projection;impact=$Plan.impact;conflicts=@();semanticCorrectnessProven=$false}
}

function Invoke-AiwCorrectionLifecycle {
    param([string]$RepositoryRoot,[string]$PlanPath,[string]$ExpectedPlanIdentity,
          [string]$ProjectId,[string]$Version,[switch]$Apply,
          [string]$AdmitInputPath,[string]$ExpectedAdmitInputIdentity,[int]$InterruptAfterWrite=-1)
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    $doc=Read-AiwProjectJson $PlanPath 'CORRECTION_PLAN'
    if($doc.Identity-cne$ExpectedPlanIdentity){throw 'CORRECTION_PLAN_DRIFT'}
    $config=Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/project.json') 'CORRECTION_PROJECT'
    if($config.Value.id-cne$ProjectId-or$config.Value.frameworkVersion-cne$Version){throw 'CORRECTION_PROJECT_BINDING'}
    $prepared=New-AiwCorrectionLifecycleProjection $root $doc.Value
    $binding=Get-AiwAdoptedDistributionBinding $root $Version
    $runtime=if($null-ne$binding){$null=Assert-AiwDistributionBinding $binding $binding.runtimeRoot $Version;[string]$binding.runtimeRoot}else{Split-Path -Parent $PSScriptRoot}
    if($prepared.status-ceq'READY'){
        $carrier=@($prepared.projection.objects|Where-Object path -CEQ '.ai-workspace/corrections.json')[0]
        $json=[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($carrier.newBase64))
        if(-not(Test-Json -Json $json -SchemaFile (Join-Path $runtime "framework/versions/$Version/PROJECT_CORRECTIONS_SCHEMA.json"))){throw 'CORRECTION_TARGET_SCHEMA'}
    }
    if(-not$Apply-or$prepared.status-cne'READY'){return $prepared}
    # Re-run the actual pinned boundary with its current package and source receipt.
    if([string]::IsNullOrWhiteSpace($AdmitInputPath)-or[string]::IsNullOrWhiteSpace($ExpectedAdmitInputIdentity)){throw 'CORRECTION_ADMIT_INPUT_REQUIRED'}
    $admit=Read-AiwProjectJson $AdmitInputPath 'CORRECTION_ADMIT_INPUT'
    if($admit.Identity-cne$ExpectedAdmitInputIdentity-or$admit.Value.mode-cne'ADMIT_ACTION'){throw 'CORRECTION_ADMIT_BINDING'}
    $receipt=Read-AiwProjectJson $admit.Value.discoverReceiptPath 'CORRECTION_DISCOVER'
    if($receipt.Identity-cne$admit.Value.expectedDiscoverReceiptIdentity){throw 'CORRECTION_DISCOVER_DRIFT'}
    $r=$receipt.Value;$ctx=if($r.schemaVersion-eq2){$r.binding}else{$r.authorityContext}
    $action=if($r.schemaVersion-eq2){$r.intentEnvelope.requestedActionKind}else{$r.actionKind}
    if($action-cne'CONTROL_WRITE'-or$ctx.projectRoot-cne$root){throw 'CORRECTION_ACTION_SCOPE'}
    $paths=@($prepared.projection.objects.path|Sort-Object)
    $exact=if($r.schemaVersion-eq2){@($ctx.exactScope)}else{@($r.exactPaths)}
    if(($paths-join"`n")-cne(@($exact|Sort-Object)-join"`n")){throw 'CORRECTION_EXACT_PATHSET'}
    $forbidden=@($ctx.forbiddenScope)
    if(($forbidden-join"`n")-cne(@($doc.Value.forbiddenPaths)-join"`n")){throw 'CORRECTION_FORBIDDEN_SCOPE_DRIFT'}
    if([string]$r.sourceLocators.frameworkRoot-cne$runtime){throw 'CORRECTION_RUNTIME_DRIFT'}
    $resolver=if($config.Value.PSObject.Properties.Name-ccontains'frameworkTarget'){Join-Path $runtime 'scripts/resolve-framework-maintenance-process-requirements.ps1'}else{Join-Path $runtime "framework/versions/$Version/scripts/resolve-process-requirements.ps1"}
    $result=@(& $resolver -InputPath $AdmitInputPath -AsJson);$code=$LASTEXITCODE
    if($code-ne0-or(($result-join"`n")|ConvertFrom-Json).status-cne'PASS'){throw 'CORRECTION_ADMIT_REJECTED'}
    if((Read-AiwProjectJson $PlanPath 'CORRECTION_PLAN').Identity-cne$ExpectedPlanIdentity){throw 'CORRECTION_PLAN_DRIFT'}
    $check={
        param($checkRoot,$projection)
        foreach($entry in $projection.objects){$path=Get-AiwContainedPath $checkRoot $entry.path;$id=if(Test-Path -LiteralPath $path -PathType Leaf){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($path))}else{'MISSING'};if($id-cne$entry.newIdentity){throw ('CORRECTION_POSTIMAGE|'+$entry.path)}}
        Import-Module (Join-Path $runtime "framework/versions/$Version/scripts/ProcessRequirementComposition.psm1") -Force
        $facts=if($r.schemaVersion-eq2){$r.binding}else{$r}
        $intent=$r.intentEnvelope
        $semantic=Get-AiwProcessSemanticText -IntentEnvelope $intent
        $composed=Invoke-ProcessRequirementComposition -ProjectRoot $checkRoot -FrameworkRoot $runtime -TargetVersion $Version -ExpectedProjectConfigIdentity $config.Identity -ExpectedCorrectionsIdentity (Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $checkRoot '.ai-workspace/corrections.json')))) -Profile $facts.profile -Role $facts.role -Phase $facts.phase -Actor $facts.actor -TaskIdentity $facts.taskIdentity -Objective $semantic -ActionKind CONTROL_WRITE -ResultKind $intent.requestedResultKind -ExactPaths $exact -ForbiddenPaths $forbidden -Capabilities @($ctx.observedCapabilities) -SemanticApplicabilityUnknown:($intent.ambiguityState-cne'CLEAR')
        if($composed.status-cne'PASS'-or'PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD'-cin@($composed.evidenceCeilings)){throw 'CORRECTION_COMPOSITION_POSTCHECK'}
        $packBytes=[Text.Encoding]::UTF8.GetByteCount((@($composed.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress))
        # Whole-rule validity, not a historical byte quota, determines rollback.
        $true
    }
    Invoke-AiwProjectProjectionTransaction $root $prepared.projection $doc.Value.transactionRelativePath $check {param($r,$p) $true} -InterruptAfterWrite $InterruptAfterWrite -Metadata @{operation='PROJECT_CORRECTION_LIFECYCLE';planIdentity=$ExpectedPlanIdentity;impact=$doc.Value.impact}
}
function New-AiwCorrectionAdoptionProjection {
    param([string]$RepositoryRoot,$Plan,[string[]]$RequiredDispositionIds=@())
    $root=Resolve-AiwRepositoryRoot $RepositoryRoot
    Assert-AiwLifecycleFields $Plan @('schemaVersion','expectedCorrectionsIdentity','changes') 'CORRECTION_ADOPTION_PLAN'
    if($Plan.schemaVersion-ne1-or$Plan.changes-isnot[array]){throw 'CORRECTION_ADOPTION_PLAN_VALUES'}
    $doc=Read-AiwProjectJson (Get-AiwContainedPath $root '.ai-workspace/corrections.json') 'CORRECTIONS'
    if($doc.Identity-cne$Plan.expectedCorrectionsIdentity-or$doc.Value.schemaVersion-ne2){throw 'CORRECTION_ADOPTION_SOURCE_DRIFT'}
    $carrier=$doc.Value;$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $targets=[Collections.Generic.List[object]]::new()
    foreach($change in $Plan.changes){
        Assert-AiwLifecycleFields $change @('correctionId','decisionLocator','record','historyRelativePath') 'CORRECTION_ADOPTION_CHANGE'
        if($change.correctionId-cnotmatch'^[A-Z][A-Z0-9_]*$'-or-not$seen.Add($change.correctionId)-or[string]::IsNullOrWhiteSpace($change.decisionLocator)){throw 'CORRECTION_ADOPTION_CHANGE_VALUES'}
        $matches=@($carrier.corrections|Where-Object correctionId -CEQ $change.correctionId)
        if($matches.Count-ne1){throw 'CORRECTION_ADOPTION_RECORD_SET'}
        $prior=$matches[0];$prefix='.ai-workspace/upgrade-recovery/corrections/'+$change.correctionId+'/'
        $historyPath=Get-AiwContainedPath $root $change.historyRelativePath
        if(-not$change.historyRelativePath.StartsWith($prefix,[StringComparison]::Ordinal)-or$change.historyRelativePath-cnotmatch'^\.ai-workspace/upgrade-recovery/corrections/[A-Z][A-Z0-9_]*/[A-Za-z0-9._-]+/history\.json$'-or(Test-Path -LiteralPath $historyPath)){throw 'CORRECTION_ADOPTION_HISTORY_PATH'}
        if($null-ne$prior.PSObject.Properties['history']){
            $previous=Read-AiwProjectJson (Get-AiwContainedPath $root $prior.history.locator) 'CORRECTION_HISTORY'
            if($previous.Identity-cne$prior.history.identity-or$previous.Value.correctionId-cne$change.correctionId){throw 'CORRECTION_HISTORY_DRIFT'}
        }
        $retire=$change.record-is[string]-and$change.record-ceq'NOT_APPLICABLE'
        if($retire-and(Get-AiwLifecycleState $prior)-cin@('ACTIVE','PAUSED')){throw 'CORRECTION_ADOPTION_OWNED_EFFECTS_REQUIRE_UNINSTALL'}
        $historyText=Get-AiwLifecycleJson ([ordered]@{schemaVersion=1;correctionId=$change.correctionId;operation=$(if($retire){'ADOPTION_RETIRE'}else{'ADOPTION_REVISE'});decisionLocator=$change.decisionLocator;priorRecord=$prior})
        $targets.Add([pscustomobject]@{path=$change.historyRelativePath;text=$historyText})
        if($retire){$carrier.corrections=@($carrier.corrections|Where-Object correctionId -CNE $change.correctionId)}
        else{
            if($change.record-isnot[pscustomobject]-or$change.record.correctionId-cne$change.correctionId-or$null-ne$change.record.PSObject.Properties['history']-or$null-ne$change.record.PSObject.Properties['lifecycle']){throw 'CORRECTION_ADOPTION_REVISED_RECORD'}
            $record=$change.record|ConvertTo-Json -Depth 64|ConvertFrom-Json -Depth 64
            if($null-ne$prior.PSObject.Properties['lifecycle']){$record|Add-Member lifecycle $prior.lifecycle}
            $record|Add-Member history ([pscustomobject]@{locator=$change.historyRelativePath;identity=(Get-AiwLifecycleIdentity $historyText)})
            $carrier.corrections=@($carrier.corrections|ForEach-Object{if($_.correctionId-ceq$change.correctionId){$record}else{$_}})
        }
    }
    if(@($RequiredDispositionIds|Where-Object{-not$seen.Contains($_)}).Count){throw 'ADOPTION_CORRECTIONS_DISPOSITION_REQUIRED'}
    $targets.Add([pscustomobject]@{path='.ai-workspace/corrections.json';text=(Get-AiwLifecycleJson $carrier)})
    return New-AiwProjectProjection $root @($targets)
}
Export-ModuleMember -Function New-AiwCorrectionLifecycleProjection,Invoke-AiwCorrectionLifecycle,New-AiwCorrectionAdoptionProjection
