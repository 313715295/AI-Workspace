[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED';exit 4}
try{
    $inputFull=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath))
    $input=Get-Content -LiteralPath $inputFull -Raw -Encoding utf8|ConvertFrom-Json -Depth 60
    if($null-eq$input.PSObject.Properties['mode']){throw 'INPUT_FIELD_REQUIRED|mode'}
    if([string]$input.mode-ceq'DISCOVER'){
        foreach($field in @('projectRoot','frameworkRoot','expectedProjectConfigIdentity')){if($null-eq$input.PSObject.Properties[$field]-or[string]::IsNullOrWhiteSpace([string]$input.$field)){throw ('INPUT_FIELD_REQUIRED|'+$field)}}
        $projectRoot=[string]$input.projectRoot;$frameworkRoot=[string]$input.frameworkRoot;$projectConfigIdentity=[string]$input.expectedProjectConfigIdentity
    }elseif([string]$input.mode-in@('ADMIT_ACTION','FINALIZE_OUTPUT')){
        foreach($field in @('discoverReceiptPath','expectedDiscoverReceiptIdentity')){if($null-eq$input.PSObject.Properties[$field]-or[string]::IsNullOrWhiteSpace([string]$input.$field)){throw ('INPUT_FIELD_REQUIRED|'+$field)}}
        $receiptFull=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.discoverReceiptPath)));$receiptBytes=[IO.File]::ReadAllBytes($receiptFull);$receiptIdentity=$receiptBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($receiptBytes))
        if($receiptIdentity-cne[string]$input.expectedDiscoverReceiptIdentity){throw 'DISCOVER_RECEIPT_DRIFT'}
        try{$receipt=Get-Content -LiteralPath $receiptFull -Raw -Encoding utf8|ConvertFrom-Json -Depth 60}catch{throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE'}
        if($null-eq$receipt.sourceLocators-or$null-eq$receipt.sourceBindings){throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE'}
        $projectRoot=[string]$receipt.sourceLocators.projectRoot;$frameworkRoot=[string]$receipt.sourceLocators.frameworkRoot;$projectConfigIdentity=[string]$receipt.sourceBindings.projectConfigIdentity
        if([string]::IsNullOrWhiteSpace($projectRoot)-or[string]::IsNullOrWhiteSpace($frameworkRoot)-or[string]::IsNullOrWhiteSpace($projectConfigIdentity)){throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE'}
    }else{throw 'INPUT_MODE_UNSUPPORTED'}
    $resolver=Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
    $resolvedOutput=@(& $resolver -ControlRepositoryPath $projectRoot -ExpectedProjectConfigIdentity $projectConfigIdentity -AsJson 2>&1|ForEach-Object{[string]$_});$resolvedCode=$LASTEXITCODE
    if($resolvedCode-ne0-or$resolvedOutput.Count-ne1){throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|'+($resolvedOutput-join';'))}
    $resolved=$resolvedOutput[0]|ConvertFrom-Json
    $inputProject=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $projectRoot)))
    $inputFramework=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $frameworkRoot)))
    if($inputProject-cne[string]$resolved.controlRoot-or$inputFramework-cne[string]$resolved.targetRoot){throw 'MAINTENANCE_PROCESS_ROOT_DRIFT'}
    $entry=Join-Path ([string]$resolved.targetRoot) ('framework\versions\'+[string]$resolved.frameworkVersion+'\scripts\resolve-process-requirements.ps1')
    if(-not(Test-Path -LiteralPath $entry -PathType Leaf)){throw 'PROCESS_REQUIREMENTS_RESOLVER_MISSING'}
    $authorizationAdapter=Join-Path $PSScriptRoot 'check-framework-maintenance-authorization.ps1'
    if(-not(Test-Path -LiteralPath $authorizationAdapter -PathType Leaf)){throw 'MAINTENANCE_AUTHORIZATION_ADAPTER_MISSING'}
    $invoke=@('-NoProfile','-NonInteractive','-File',$entry,'-InputPath',$inputFull,'-AuthorizationCheckerPath',$authorizationAdapter)
    if($AsJson){$invoke+='-AsJson'};if($DeleteInputOnExit){$invoke+='-DeleteInputOnExit'}
    & pwsh @invoke
    exit $LASTEXITCODE
}catch{if($AsJson){[ordered]@{status='FAIL';reason=[string]$_.Exception.Message}|ConvertTo-Json -Compress}else{Write-Output ('FAIL|framework-maintenance-process-requirements|'+[string]$_.Exception.Message)};exit 2}
