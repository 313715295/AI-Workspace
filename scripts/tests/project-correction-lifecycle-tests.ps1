[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$scripts=Split-Path -Parent $PSScriptRoot
$framework=Split-Path -Parent $scripts
Import-Module (Join-Path $scripts 'ProjectCorrectionLifecycle.psm1') -Force
Import-Module (Join-Path $scripts 'ProjectAdoptionState.psm1') -Force
Import-Module (Join-Path $scripts 'ProjectAdoptionTransaction.psm1') -Force
Import-Module (Join-Path $framework 'framework/versions/1.16.0/scripts/ProcessRequirementComposition.psm1') -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-correction-lifecycle-'+[guid]::NewGuid().ToString('N'))
$utf8=[Text.UTF8Encoding]::new($false);$script:passed=0;$script:serial=0
function Check([bool]$Condition,[string]$Name){if(-not$Condition){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Text([string]$Relative,[string]$Value){$p=Join-Path $temp $Relative;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$Value.Replace("`r",""),$utf8)}
function Json([string]$Relative,$Value){Text $Relative (($Value|ConvertTo-Json -Depth 64 -Compress)+"`n")}
function Id([string]$Relative){Get-AiwByteIdentity ([IO.File]::ReadAllBytes((Join-Path $temp $Relative)))}
function Read([string]$Relative){[IO.File]::ReadAllText((Join-Path $temp $Relative))}
function Record([string]$Name){
    [pscustomobject]@{correctionId=$Name;introducedAgainstFramework='1.16.0';requirementReason='fixture issue';effectiveRule=('fixture rule '+$Name);applicability='fixture only';decisionLocator='fixture:decision';selectors=[pscustomobject]@{profiles=@();roles=@();phases=@();actionKinds=@();resultKinds=@();pathPrefixes=@();capabilities=@();semanticTerms=@()};preparationRequirements=@();resultRequirements=@();requiredFacts=@();mechanicalCheckRefs=@()}
}
function Plan([string]$Operation,[string]$Name='A',$Changes=@(),$Depends=@()){
    $script:serial++
    $install=$Operation-cin@('INSTALL','REGISTER_HISTORY')
    [pscustomobject]@{schemaVersion=1;operation=$Operation;correctionId=$Name;expectedCorrectionsIdentity=(Id '.ai-workspace/corrections.json');decisionLocator='fixture:decision';forbiddenPaths=@('private/');record=$(if($Operation-ceq'INSTALL'){Record $Name}else{'NOT_APPLICABLE'});installation=$(if($install){[pscustomobject]@{schemaVersion=1;correctionId=$Name;decisionLocator='fixture:original-install-evidence';dependsOn=@($Depends);changes=@($Changes)}}else{'NOT_APPLICABLE'});installationRelativePath=$(if($install){".ai-workspace/upgrade-recovery/corrections/$Name/$serial/installation.json"}else{'NOT_APPLICABLE'});transactionRelativePath=".ai-workspace/upgrade-recovery/corrections/$Name/$serial/state.json";impact=[pscustomobject]@{stoppedObligations=@('fixture owned rule');independentObligations=@('user changes');inFlightEffects=@();recovery='resume from original ownership';semanticAssessment='fixture has explicit dependencies only'}}
}
function ApplyPlan($Plan){
    $preview=New-AiwCorrectionLifecycleProjection $temp $Plan
    if($preview.status-cne'READY'){throw ($preview|ConvertTo-Json -Depth 5 -Compress)}
    $post={param($root,$p) foreach($o in $p.objects){$f=Join-Path $root $o.path;$id=if(Test-Path -LiteralPath $f){Get-AiwByteIdentity ([IO.File]::ReadAllBytes($f))}else{'MISSING'};if($id-cne$o.newIdentity){throw 'POSTCHECK'}};$true}
    $result=Invoke-AiwProjectProjectionTransaction $temp $preview.projection $Plan.transactionRelativePath $post {param($r,$p) $true}
    return $result
}
function Reject([scriptblock]$Action,[string]$Reason,[string]$Name){$message='';try{& $Action|Out-Null}catch{$message=$_.Exception.Message};Check ($message.Contains($Reason)) $Name}
try{
    Json '.ai-workspace/project.json' @{schemaVersion=4;id='fixture';displayName='Fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='1.16.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=@{};processPolicy=@{schemaVersion=1;locator='.ai-workspace/process-policy.json'}}
    Json '.ai-workspace/corrections.json' @{schemaVersion=2;contractVersion='1.16.0';projectId='fixture';corrections=@()}
    Json '.ai-workspace/process-policy.json' @{schemaVersion=1;contractVersion='1.16.0';projectId='fixture';selectedRulePackBytes=65536;rules=@()}
    Text '.ai-workspace/BOOTSTRAP.md' "<!-- PROJECT-CUSTOM:BEGIN -->`n<!-- PROJECT-CUSTOM:END -->`n"
    Text 'AGENTS.md' "# Base`n<!-- scope -->`nUser text`n"
    Text 'settings.json' '{"budget":1,"other":0}'
    $changes=@(
      [pscustomobject]@{kind='TEXT';path='AGENTS.md';before='';after="Owned delegation`n";prefix="# Base`n";suffix="<!-- scope -->`n"},
      [pscustomobject]@{kind='TEXT';path='settings.json';before='1';after='2';prefix='"budget":';suffix=','},
      [pscustomobject]@{kind='FILE';path='helpers/owned.txt';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes('owned helper'))}
    )
    $install=Plan INSTALL A $changes
    $before=Id '.ai-workspace/corrections.json'
    $preview=New-AiwCorrectionLifecycleProjection $temp $install
    Check ($preview.status-ceq'READY'-and$preview.projection.changeCount-eq5-and(Id '.ai-workspace/corrections.json')-ceq$before) 'preview-exact-group-and-no-write'
    $null=ApplyPlan $install
    Check ((Read 'AGENTS.md').Contains('Owned delegation')-and(Test-Path (Join-Path $temp 'helpers/owned.txt'))) 'install-full-group'
    Text 'AGENTS.md' ((Read 'AGENTS.md')+"Later independent user decision`n")
    Text 'settings.json' '{"budget":2,"other":9}'
    $null=ApplyPlan (Plan PAUSE)
    Check (-not(Read 'AGENTS.md').Contains('Owned delegation')-and(Read 'AGENTS.md').Contains('Later independent')-and(Read 'settings.json')-ceq'{"budget":1,"other":9}'-and-not(Test-Path (Join-Path $temp 'helpers/owned.txt'))) 'pause-reverses-all-owned-effects-preserves-independent-edits'
    $composeArgs=@{ProjectRoot=$temp;FrameworkRoot=$framework;TargetVersion='1.16.0';ExpectedProjectConfigIdentity=(Id '.ai-workspace/project.json');ExpectedCorrectionsIdentity=(Id '.ai-workspace/corrections.json');Profile='STANDARD';Role='CONTROLLER';Phase='PLAN';Actor='fixture';TaskIdentity='fixture';EvaluationOnly=$true;Objective='correction';ActionKind='NONE';ResultKind='PLAN'}
    $composed=Invoke-ProcessRequirementComposition @composeArgs
    Check (@($composed.stillEffective).Count-eq0-and$composed.inactive[0].state-ceq'PAUSED') 'paused-rule-not-selected-with-history-retained'
    $null=ApplyPlan (Plan RESUME)
    Check ((Read 'AGENTS.md').Contains('Owned delegation')-and(Read 'settings.json')-ceq'{"budget":2,"other":9}') 'resume-same-installation-over-independent-edits'
    $null=ApplyPlan (Plan INSTALL B @() @('A'))
    Reject {New-AiwCorrectionLifecycleProjection $temp (Plan PAUSE A)} 'CORRECTION_ACTIVE_DEPENDENT' 'direct-dependency-stops-only-affected-operation'
    $null=ApplyPlan (Plan UNINSTALL B)
    $overlap=@([pscustomobject]@{kind='TEXT';path='AGENTS.md';before="Owned delegation`n";after="Second owner`n";prefix="# Base`n";suffix="<!-- scope -->`n"})
    $over=New-AiwCorrectionLifecycleProjection $temp (Plan INSTALL C $overlap)
    Check ($over.status-ceq'CONFLICT'-and$over.conflicts[0].reason.Contains('OVERLAPPING')) 'overlapping-correction-ownership-not-silently-rolled-back'
    $alias=$overlap|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20;$alias.path='agents.md'
    $aliased=New-AiwCorrectionLifecycleProjection $temp (Plan INSTALL C @($alias))
    Check ($aliased.status-ceq'CONFLICT'-and$aliased.conflicts[0].reason.Contains('OVERLAPPING')) 'windows-case-alias-cannot-bypass-text-ownership'
    $fileAlias=@([pscustomobject]@{kind='FILE';path='HELPERS/OWNED.TXT';beforeExists=$true;afterExists=$true;beforeBase64=[Convert]::ToBase64String($utf8.GetBytes('owned helper'));afterBase64=[Convert]::ToBase64String($utf8.GetBytes('other owner'))})
    $aliasedFile=New-AiwCorrectionLifecycleProjection $temp (Plan INSTALL C $fileAlias)
    Check ($aliasedFile.status-ceq'CONFLICT'-and$aliasedFile.conflicts[0].reason.Contains('SHARED_FILE')) 'windows-case-alias-cannot-bypass-file-ownership'
    Text 'helpers/owned.txt' 'later modified owned file'
    $conflict=New-AiwCorrectionLifecycleProjection $temp (Plan UNINSTALL)
    Check ($conflict.status-ceq'CONFLICT'-and$conflict.conflicts[0].path-ceq'helpers/owned.txt'-and(Read 'AGENTS.md').Contains('Owned delegation')) 'mixed-file-conflict-reports-exact-object-and-no-partial-write'
    Text 'helpers/owned.txt' 'owned helper'
    $null=ApplyPlan (Plan UNINSTALL)
    $carrier=Read '.ai-workspace/corrections.json'|ConvertFrom-Json
    Check (-not(Read 'AGENTS.md').Contains('Owned delegation')-and$carrier.corrections[1].lifecycle.state-ceq'UNINSTALLED') 'uninstall-removes-effects-and-keeps-non-effective-history'
    $composeArgs.ExpectedCorrectionsIdentity=Id '.ai-workspace/corrections.json'
    $after=Invoke-ProcessRequirementComposition @composeArgs
    Check (@($after.stillEffective).Count-eq0-and@($after.inactive).Count-eq2) 'uninstalled-records-cannot-revive-through-selector-or-coverage'
    $null=ApplyPlan (Plan INSTALL A $changes)
    $null=ApplyPlan (Plan PAUSE)
    Text 'AGENTS.md' ((Read 'AGENTS.md')+"Independent delegation after pause`n")
    $null=ApplyPlan (Plan UNINSTALL)
    Check ((Read 'AGENTS.md').Contains('Independent delegation after pause')) 'paused-uninstall-preserves-later-independent-decision'
    $bad=Plan INSTALL D @([pscustomobject]@{kind='FILE';path='private/no-read.txt';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=''})
    $blocked=New-AiwCorrectionLifecycleProjection $temp $bad
    Check ($blocked.status-ceq'CONFLICT'-and$blocked.conflicts[0].reason-ceq'CORRECTION_FORBIDDEN_PATH') 'forbidden-effect-path-rejected-before-file-access'
    $rollback=Plan INSTALL R @([pscustomobject]@{kind='FILE';path='rollback.txt';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes('rollback'))})
    $old=Id '.ai-workspace/corrections.json';$rp=New-AiwCorrectionLifecycleProjection $temp $rollback
    Reject {Invoke-AiwProjectProjectionTransaction $temp $rp.projection $rollback.transactionRelativePath {param($r,$p) $true} {param($r,$p) $true} -FailAfterWrite 1} 'INJECTED' 'installation-failure-runs-existing-rollback'
    Check ((Id '.ai-workspace/corrections.json')-ceq$old-and-not(Test-Path (Join-Path $temp 'rollback.txt'))) 'rollback-restores-whole-group'
    $interrupted=Plan INSTALL I @([pscustomobject]@{kind='FILE';path='interrupted.txt';beforeExists=$false;afterExists=$true;beforeBase64='';afterBase64=[Convert]::ToBase64String($utf8.GetBytes('interrupted'))})
    $ip=New-AiwCorrectionLifecycleProjection $temp $interrupted
    $interruption=Invoke-AiwProjectProjectionTransaction $temp $ip.projection $interrupted.transactionRelativePath {param($r,$p) $true} {param($r,$p) $true} -InterruptAfterWrite 1
    Check ($interruption.status-ceq'INTERRUPTED') 'actual-interruption-preserves-existing-transaction'
    $recovered=Resume-AiwProjectProjectionRollback $temp $interrupted.transactionRelativePath (Id $interrupted.transactionRelativePath) {param($r,$p) $true}
    Check ($recovered.status-ceq'ROLLED_BACK'-and(Id '.ai-workspace/corrections.json')-ceq$old-and-not(Test-Path (Join-Path $temp 'interrupted.txt'))) 'existing-recovery-restores-interrupted-full-group'
    $legacy=Record LEGACY;$carrier=Read '.ai-workspace/corrections.json'|ConvertFrom-Json;$carrier.corrections+=@($legacy);Json '.ai-workspace/corrections.json' $carrier
    Reject {New-AiwCorrectionLifecycleProjection $temp (Plan UNINSTALL LEGACY)} 'CORRECTION_TRANSITION' 'legacy-without-provenance-cannot-pretend-complete-uninstall'
    Text 'historical.txt' 'installed'
    $historyChange=@([pscustomobject]@{kind='FILE';path='historical.txt';beforeExists=$true;afterExists=$true;beforeBase64=[Convert]::ToBase64String($utf8.GetBytes('original'));afterBase64=[Convert]::ToBase64String($utf8.GetBytes('installed'))})
    $null=ApplyPlan (Plan REGISTER_HISTORY LEGACY $historyChange)
    $null=ApplyPlan (Plan UNINSTALL LEGACY)
    Check ((Read 'historical.txt')-ceq'original') 'historical-registration-preserves-current-and-enables-proven-reversal'
    $api=Plan INSTALL API @();Json 'plan.json' $api
    $planId=Id 'plan.json'
    $preview=Invoke-AiwCorrectionLifecycle $temp (Join-Path $temp 'plan.json') $planId fixture '1.16.0'
    Check ($preview.status-ceq'READY') 'real-root-helper-preview-validates-target-schema'
    Reject {Invoke-AiwCorrectionLifecycle $temp (Join-Path $temp 'plan.json') $planId fixture '1.16.0' -Apply} 'CORRECTION_ADMIT_INPUT' 'apply-cannot-use-preview-as-authority'
    Write-Output ("RESULT|project-correction-lifecycle|passed=$script:passed")
}finally{
    $full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if(-not$full.StartsWith($parent+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-correction-lifecycle-')){throw 'FIXTURE_CLEANUP_BOUNDARY'}
    if(Test-Path -LiteralPath $full){[IO.Directory]::Delete($full,$true)}
}
