#requires -Version 7.0
[CmdletBinding()]
param([string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$upgradePath = Join-Path $RepositoryRoot 'scripts\upgrade-project.ps1'
$matrixPath = Join-Path $RepositoryRoot 'framework\versions\1.15.1\MIGRATION_MATRIX.md'
$failures = New-Object 'System.Collections.Generic.List[string]'
$passes = 0

function Confirm([bool]$Condition,[string]$Name){
    if($Condition){$script:passes++;return}
    $script:failures.Add($Name)
}

$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($upgradePath,[ref]$tokens,[ref]$errors)
Confirm ($errors.Count-eq0) 'upgrade-script-parses'
$functions=@{}
foreach($functionAst in $ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)){$functions[$functionAst.Name]=[string]$functionAst.Extent.Text}
Confirm $functions.ContainsKey('Assert-ActorBoundUpgradeLegacyMaterial') 'legacy-material-check-present'
Confirm $functions.ContainsKey('Get-ActorRouteMigration') 'actor-route-migration-present'
Confirm $functions.ContainsKey('Invoke-ActorBoundUpgrade115') '1.15-invoke-present'
Confirm $functions.ContainsKey('Resume-ActorBoundUpgrade115') '1.15-resume-present'
Confirm $functions.ContainsKey('Invoke-ActorBoundUpgrade') 'legacy-invoke-present'
Confirm $functions.ContainsKey('Resume-ActorBoundUpgrade') 'legacy-resume-present'
Confirm $functions.ContainsKey('Get-CurrentPinBudgetBridge1151') '1.15.1-current-pin-budget-bridge-present'

$migration=[string]$functions['Get-ActorRouteMigration']
$invoke115=[string]$functions['Invoke-ActorBoundUpgrade115']
$authorize115=[string]$functions['Assert-ActorBoundUpgrade115Authorization']
$resume115=[string]$functions['Resume-ActorBoundUpgrade115']
$invoke=[string]$functions['Invoke-ActorBoundUpgrade']
$resume=[string]$functions['Resume-ActorBoundUpgrade']
$bridge=[string]$functions['Get-CurrentPinBudgetBridge1151']
$upgradeText=[IO.File]::ReadAllText($upgradePath)
$parameterNames=@($ast.ParamBlock.Parameters|ForEach-Object{[string]$_.Name.VariablePath.UserPath})
Confirm ($migration.Contains("Groups['actual']")-and$migration.Contains('ActualPaths=$actualPaths')) 'migration-binds-pre-upgrade-task-actual-pathset'
Confirm $invoke115.Contains('-ObservedActualPath @($Migration.ActualPaths)') '1.15-forward-check-receives-task-actual-pathset'
Confirm $resume115.Contains('-ObservedActualPath @($Migration.ActualPaths)') '1.15-resume-check-receives-task-actual-pathset'
Confirm $invoke.Contains('-ObservedActualPath @($Migration.ActualPaths)') 'legacy-forward-check-receives-task-actual-pathset'
Confirm $resume.Contains('-ObservedActualPath @($Migration.ActualPaths)') 'legacy-resume-check-receives-task-actual-pathset'
Confirm $invoke.Contains(".framework-actor-bound-upgrade-preparation-") 'deterministic-preparation-locator'
Confirm $invoke.Contains(".framework-actor-bound-upgrade-recovery-") 'deterministic-recovery-locator'
Confirm $invoke.Contains('$preparationRelative+''/old/''') 'preview-includes-preparation-old'
Confirm $invoke.Contains('$preparationRelative+''/new/''') 'preview-includes-preparation-new'
Confirm $invoke.Contains('$preparationRelative+''/state.json''') 'preview-includes-preparation-state'

$writeState=$invoke.IndexOf('Write-Utf8NoBom (Join-Path $preparationRoot ''state.json'')',[StringComparison]::Ordinal)
$validatePreparation=$invoke.IndexOf('Assert-ActorBoundUpgradeLegacyMaterial $preparationRoot',[StringComparison]::Ordinal)
$promote=$invoke.IndexOf('[IO.Directory]::Move($preparationRoot,$recoveryRoot)',[StringComparison]::Ordinal)
$validateRecovery=$invoke.IndexOf('Assert-ActorBoundUpgradeLegacyMaterial $recoveryRoot',[StringComparison]::Ordinal)
$firstLiveWrite=$invoke.IndexOf('Set-UpgradeFile ',[StringComparison]::Ordinal)
Confirm ($writeState-ge0) 'state-written-in-preparation'
Confirm ($validatePreparation-gt$writeState) 'preparation-validated-after-state'
Confirm ($promote-gt$validatePreparation) 'promotion-after-preparation-validation'
Confirm ($validateRecovery-gt$promote) 'recovery-validated-after-promotion'
Confirm ($firstLiveWrite-gt$validateRecovery) 'live-write-after-recovery-validation'
if($promote-ge0){
    $beforePromotion=$invoke.Substring(0,$promote)
    Confirm (-not$beforePromotion.Contains('Join-Path $recoveryRoot ''old''')) 'no-recovery-old-write-before-promotion'
    Confirm (-not$beforePromotion.Contains('Join-Path $recoveryRoot ''new''')) 'no-recovery-new-write-before-promotion'
}
Confirm ($resume.Contains('$usesPreparedPathset=')) 'resume-detects-prepared-pathset'
Confirm ($resume.Contains('ACTOR_BOUND_UPGRADE_PREPARATION_REAPPEARED')) 'resume-rejects-preparation-reappearance'
Confirm ($resume.Contains('if($usesPreparedPathset){$reconstructed.Add($preparationRelative+''/state.json'')')) 'resume-reconstructs-preparation-pathset'
Confirm ('CurrentProcessInputPath'-cin$parameterNames-and'ExpectedCurrentProcessInputIdentity'-cin$parameterNames) 'bridge-input-and-identity-parameters-present'
Confirm ($bridge.Contains('-TargetVersion $FromVersion')-and$bridge.Contains('PROCESS_REQUIREMENTS_RESOLVE')-and$bridge.Contains('-InputPath $CurrentProcessInputPath -AsJson')-and$bridge.Contains('$resolverCode-ne2')-and$bridge.Contains('SELECTED_RULE_PACK_BUDGET_EXCEEDED')) 'bridge-runs-current-sealed-resolver-and-accepts-only-exact-budget-failure'
Confirm ($bridge.Contains('Import-Module $modulePath -Force -PassThru')-and$bridge.Contains('Invoke-ProcessRequirementComposition')-and$bridge.Contains('sourceBuildCount-ne1')-and$bridge.Contains('fullText')-and$bridge.Contains('$packBytes-le12288')-and$bridge.Contains('$packBytes-gt65536')) 'bridge-recomposes-complete-pack-once-with-both-byte-ceilings'
Confirm (-not$bridge.Contains('Write-Utf8')-and-not$bridge.Contains('Set-UpgradeFile')-and-not$bridge.Contains('Copy-Item')-and$bridge.Contains('SelectedPackIdentity')-and$bridge.Contains('SourceCompositionIdentity')) 'bridge-evidence-is-in-memory-and-non-authorizing'
Confirm ($authorize115.Contains('CURRENT_PIN_BRIDGE_USER_DECISION_DRIFT')-and$upgradeText.Contains('if($TargetVersion-ceq''1.15.1''){$script:CurrentPinBudgetBridge=Get-CurrentPinBudgetBridge1151')) 'bridge-remains-bound-to-schema3-user-decision-and-exact-target'
Confirm ($upgradeText.Contains('$TargetVersion-in@(''1.15.0'',''1.15.1'')-and$FromVersion-notin@(''1.14.0'',''1.14.1'')')) 'bridge-source-family-is-exact-1.14.x'

$matrix=[IO.File]::ReadAllText($matrixPath)
Confirm ($matrix.Contains('healthy repo-local schema4 1.14.0 or 1.14.1 | 1.15.1')-and$matrix.Contains('schema3 or schema4 version earlier than 1.14.0 | 1.15.1 | blocked from the direct route')) 'matrix-binds-exact-1.14.x-to-1.15.1-and-keeps-earlier-sources-blocked'

if($failures.Count-gt0){Write-Output ('FAIL|'+[string]::Join(',',$failures));exit 1}
Write-Output ('PASS|upgrade-project-bridge|checks='+$passes)
