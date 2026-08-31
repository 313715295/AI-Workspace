[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$FrameworkRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')][string]$TargetVersion,
    [Parameter(Mandatory)][string]$ExpectedProjectConfigIdentity,
    [ValidateSet('RECOVER','PRECHECK','POSTCHECK')][string]$Operation='RECOVER',
    [string]$ExpectedCorrectionsIdentity,
    [switch]$AllowMissingCorrections,
    [switch]$AsJson
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -Force
try {
    $result=Invoke-ProcessRequirementComposition -ProjectRoot $ProjectRoot -FrameworkRoot $FrameworkRoot -TargetVersion $TargetVersion -ComposerVersion '1.14.1' -ExpectedProjectConfigIdentity $ExpectedProjectConfigIdentity -ExpectedCorrectionsIdentity $ExpectedCorrectionsIdentity -Profile MICRO -Role CONTROLLER -Phase RECOVER -Actor LEGACY_CORRECTIONS_WRAPPER -TaskIdentity LEGACY_CORRECTIONS_WRAPPER -Objective LEGACY_CORRECTIONS_WRAPPER -ActionKind NONE -ResultKind NONE -AllowProjectPinMismatch:($Operation-ceq'PRECHECK') -UseDeclaredCapabilities
    if([string]$result.correctionsIdentity-ceq'MISSING'-and-not$AllowMissingCorrections){throw 'CORRECTIONS_MISSING'}
    $status=if(@($result.conflicts).Count-ne0){'CONFLICT'}else{'PASS'}
    $legacy=[ordered]@{status=$status;operation=$Operation;projectId=$result.projectId;targetVersion=$TargetVersion;correctionsIdentity=$result.correctionsIdentity;coverageStatus=$result.coverageStatus;incorporated=@($result.incorporated);stillEffective=@($result.stillEffective);conflicts=@($result.conflicts);sourceCompositionIdentity=$result.sourceCompositionIdentity;composer='ProcessRequirementComposition'}
    if($AsJson){$legacy|ConvertTo-Json -Depth 12 -Compress}else{
        Write-Output ('PROJECT_CORRECTIONS|status='+$status+'|target='+$TargetVersion+'|coverage='+$result.coverageStatus+'|incorporated='+@($result.incorporated).Count+'|effective='+@($result.stillEffective).Count+'|conflicts='+@($result.conflicts).Count)
        foreach($item in @($result.incorporated)){Write-Output ('INCORPORATED|'+$item.correctionId)}
        foreach($item in @($result.stillEffective)){Write-Output ('STILL_EFFECTIVE|'+$item.correctionId+'|reason='+$item.requirementReason)}
        foreach($item in @($result.conflicts)){Write-Output ('CONFLICT|'+$item.correctionId+'|reason='+$item.requirementReason)}
    }
    if($status-ceq'CONFLICT'){exit 3}
} catch {
    if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|'+[string]$_.Exception.Message)}
    exit 2
}
