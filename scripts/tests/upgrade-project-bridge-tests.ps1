#requires -Version 7.0
[CmdletBinding()]
param([string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$upgradePath = Join-Path $RepositoryRoot 'scripts\upgrade-project.ps1'
$matrixPath = Join-Path $RepositoryRoot 'framework\versions\1.15.0\MIGRATION_MATRIX.md'
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
Confirm $functions.ContainsKey('Invoke-ActorBoundUpgrade') 'legacy-invoke-present'
Confirm $functions.ContainsKey('Resume-ActorBoundUpgrade') 'legacy-resume-present'

$invoke=[string]$functions['Invoke-ActorBoundUpgrade']
$resume=[string]$functions['Resume-ActorBoundUpgrade']
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

$matrix=[IO.File]::ReadAllText($matrixPath)
Confirm ($matrix.Contains('schema3 or schema4 version earlier than 1.14.0 | 1.15.0 | blocked from the direct route')) 'direct-pre-1.14-to-1.15-remains-blocked'

if($failures.Count-gt0){Write-Output ('FAIL|'+[string]::Join(',',$failures));exit 1}
Write-Output ('PASS|upgrade-project-bridge|checks='+$passes)
