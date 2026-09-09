[CmdletBinding()]
param([Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) { Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'; exit 4 }
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$customHandled = $false
$inputFull = $null
$controlRoot = $null

function Get-Identity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    return $bytes.Length.ToString() + '|' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Read-StrictJson([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Label + '_MISSING') }
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw ($Label + '_BOM') }
    try { return $utf8.GetString($bytes) | ConvertFrom-Json -Depth 100 } catch { throw ($Label + '_JSON') }
}

function Assert-Fields($Value, [string[]]$Names, [string]$Label) {
    $actual = @($Value.PSObject.Properties.Name)
    if ($actual.Count -ne $Names.Count -or @($Names | Where-Object { $_ -cnotin $actual }).Count -ne 0) { throw ($Label + '_FIELDS') }
}

function Assert-StringArray($Value, [string]$Label) {
    if (-not ($Value -is [Array])) { throw ($Label + '_TYPE') }
    foreach ($entry in @($Value)) { if (-not ($entry -is [string]) -or [string]::IsNullOrWhiteSpace([string]$entry)) { throw ($Label + '_TYPE') } }
}

function Get-ControlRootFromReceipt($Receipt) {
    if ([int64]$Receipt.schemaVersion -eq 1) { return [string]$Receipt.sourceLocators.projectRoot }
    if ($null -eq $Receipt.binding) { throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE' }
    # CONTROL is already bound by the compact receipt. Package storage is not a
    # control-root locator; topology and the version consumer still verify it.
    $boundPath = [string]$Receipt.binding.projectRoot
    if (-not [IO.Path]::IsPathRooted($boundPath)) { throw 'MAINTENANCE_RECEIPT_PROJECT_ROOT_DRIFT' }
    $boundRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $boundPath)))
    $frameworkRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$Receipt.sourceLocators.frameworkRoot))))
    if ([StringComparer]::OrdinalIgnoreCase.Equals($boundRoot, $frameworkRoot)) {
        throw 'MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED|USE_SCHEMA2_DISCOVER_SCHEMA1_COMPACT'
    }
    return $boundRoot
}

function Get-TransitionReceipt([string[]]$ResultReceipts) {
    $entries = @($ResultReceipts | Where-Object { $_ -clike 'MAINTENANCE_SELF_UPDATE_TRANSITION|*' })
    if ($entries.Count -eq 0) { return $null }
    if ($entries.Count -ne 1 -or [string]$entries[0] -cnotmatch '^MAINTENANCE_SELF_UPDATE_TRANSITION\|(?<path>[^|]+)\|(?<identity>\d+\|[A-F0-9]{64})$') { throw 'MAINTENANCE_SELF_UPDATE_TRANSITION_RECEIPT' }
    return [pscustomobject]@{ path = [string]$Matches['path']; identity = [string]$Matches['identity']; receipt = [string]$entries[0] }
}

function Invoke-SelfUpdateFinalize($BoundaryInput, $Receipt, $Resolved, $Package, $Transition) {
    Assert-Fields $BoundaryInput @('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState') 'INPUT'
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $BoundaryInput.$name $name}
    if([string]$Package.repositoryId-cne[string]$Resolved.targetRepositoryId){throw 'MAINTENANCE_SELF_UPDATE_REPOSITORY'}
    # The existing transaction validates the original admission, exact transition and
    # the complete current composition. This adapter does not mint a replacement decision.
    $tool=Join-Path $PSScriptRoot 'integrate-framework-source.ps1'
    $output=@(& $tool -Operation COMPLETE -ControlRepositoryPath $Resolved.controlRoot -TransactionPath $Transition.path -ExpectedTransactionIdentity $Transition.identity -FinalizeInputPath $inputFull -AsJson 2>&1|ForEach-Object{[string]$_})
    if($LASTEXITCODE-ne0-or$output.Count-ne1){throw ('MAINTENANCE_SELF_UPDATE_FINALIZE|'+($output-join';'))}
    return $output[0]|ConvertFrom-Json -Depth 100
}

function Assert-SelfUpdateCleanupPath($Receipt) {
    $context=if([int]$Receipt.schemaVersion-eq1){$Receipt}else{$Receipt.binding}
    foreach($value in @([string]$context.taskId,[string]$context.actor)){if($value-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'MAINTENANCE_CLEANUP_CONTEXT'}}
    $expectedRoot=[IO.Path]::GetFullPath((Join-Path $controlRoot ('.ai-workspace/runtime/'+$context.taskId+'/'+$context.actor)))
    if(-not$inputFull.StartsWith($expectedRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'MAINTENANCE_CLEANUP_SCOPE'}
    $cursor=$inputFull
    while($cursor.Length-ge$controlRoot.Length){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($null-ne$item-and($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'MAINTENANCE_CLEANUP_REPARSE'}
        if($cursor-ceq$controlRoot){break};$cursor=Split-Path -Parent $cursor
    }
}

try {
    $inputFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputPath))
    $input = Read-StrictJson $inputFull 'INPUT'
    if ($null -eq $input.PSObject.Properties['mode']) { throw 'INPUT_FIELD_REQUIRED|mode' }
    $receipt = $null
    if ([string]$input.mode -ceq 'DISCOVER') {
        foreach ($field in @('projectRoot','frameworkRoot','expectedProjectConfigIdentity')) { if ($null -eq $input.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$input.$field)) { throw ('INPUT_FIELD_REQUIRED|' + $field) } }
        $projectRoot=[string]$input.projectRoot;$frameworkRoot=[string]$input.frameworkRoot;$projectConfigIdentity=[string]$input.expectedProjectConfigIdentity
    } elseif ([string]$input.mode -in @('ADMIT_ACTION','FINALIZE_OUTPUT')) {
        foreach ($field in @('discoverReceiptPath','expectedDiscoverReceiptIdentity')) { if ($null -eq $input.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$input.$field)) { throw ('INPUT_FIELD_REQUIRED|' + $field) } }
        $receiptFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$input.discoverReceiptPath)))
        if ((Get-Identity $receiptFull) -cne [string]$input.expectedDiscoverReceiptIdentity) { throw 'DISCOVER_RECEIPT_DRIFT' }
        $receipt = Read-StrictJson $receiptFull 'DISCOVER_RECEIPT_SELECTION'
        if (-not ($receipt.schemaVersion -is [ValueType]) -or [int64]$receipt.schemaVersion -notin @(1,2) -or $null -eq $receipt.sourceLocators -or $null -eq $receipt.sourceBindings) { throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE' }
        $projectRoot = Get-ControlRootFromReceipt $receipt
        $frameworkRoot=[string]$receipt.sourceLocators.frameworkRoot;$projectConfigIdentity=[string]$receipt.sourceBindings.projectConfigIdentity
        if ([string]::IsNullOrWhiteSpace($projectRoot) -or [string]::IsNullOrWhiteSpace($frameworkRoot) -or [string]::IsNullOrWhiteSpace($projectConfigIdentity)) { throw 'DISCOVER_RECEIPT_SELECTION_UNAVAILABLE' }
    } else { throw 'INPUT_MODE_UNSUPPORTED' }
    $resolver = Join-Path $PSScriptRoot 'resolve-framework-maintenance-target.ps1'
    $resolvedOutput = @(& $resolver -ControlRepositoryPath $projectRoot -ExpectedProjectConfigIdentity $projectConfigIdentity -AsJson 2>&1 | ForEach-Object { [string]$_ });$resolvedCode=$LASTEXITCODE
    if ($resolvedCode -ne 0 -or $resolvedOutput.Count -ne 1) { throw ('MAINTENANCE_TARGET_RESOLUTION_FAILED|' + ($resolvedOutput -join ';')) }
    $resolved = $resolvedOutput[0] | ConvertFrom-Json -Depth 30
    if($null-eq$resolved.PSObject.Properties['runtimeRoot']){
        Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
        if($null-ne(Get-AiwAdoptedDistributionBinding ([string]$resolved.controlRoot) ([string]$resolved.frameworkVersion))){throw 'FIXED_RUNTIME_ADAPTER_REQUIRED'}
        # Old health source has no fixed-runtime carrier; keep its verified target.
        $resolved|Add-Member -NotePropertyName runtimeRoot -NotePropertyValue ([string]$resolved.targetRoot)
    }
    $controlRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $projectRoot)))
    $inputFramework = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $frameworkRoot)))
    if ($controlRoot -cne [string]$resolved.controlRoot -or $inputFramework -cne [string]$resolved.runtimeRoot) { throw 'MAINTENANCE_PROCESS_ROOT_DRIFT' }
    if ($null -ne $receipt -and [int64]$receipt.schemaVersion -eq 2) {
        $boundRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$receipt.binding.projectRoot))))
        if ($boundRoot -cnotin @([string]$resolved.controlRoot,[string]$resolved.targetRoot)) { throw 'MAINTENANCE_RECEIPT_PROJECT_ROOT_DRIFT' }
        # The version boundary consumer cannot recover CONTROL task sources from
        # a schema2 compact whose authority root is TARGET. Do not rewrite it.
        if ($boundRoot -ceq [string]$resolved.targetRoot) { throw 'MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED|USE_SCHEMA2_DISCOVER_SCHEMA1_COMPACT' }
    }
    if ([string]$input.mode -ceq 'DISCOVER' -and [int]$input.schemaVersion -eq 3 -and
        $null -ne $input.PSObject.Properties['authorizationPackagePath'] -and [string]$input.authorizationPackagePath -cne 'NOT_REQUIRED') {
        if ($null -eq $input.PSObject.Properties['expectedAuthorizationIdentity'] -or
            (Get-Identity ([string]$input.authorizationPackagePath)) -cne [string]$input.expectedAuthorizationIdentity) { throw 'MAINTENANCE_AUTHORIZATION_DRIFT' }
        $routePackage = Read-StrictJson ([string]$input.authorizationPackagePath) 'MAINTENANCE_AUTHORIZATION'
        if ($null -ne $routePackage.PSObject.Properties['repositoryId'] -and [string]$routePackage.repositoryId -ceq [string]$resolved.targetRepositoryId) {
            throw 'MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED|USE_SCHEMA2_DISCOVER_SCHEMA1_COMPACT'
        }
    }
    $transition = if ([string]$input.mode -ceq 'FINALIZE_OUTPUT') { Get-TransitionReceipt @($input.resultReceipts) } else { $null }
    if ($null -ne $transition -and [string]$receipt.intentEnvelope.requestedActionKind -ceq 'SOURCE_WRITE') {
        if($DeleteInputOnExit){Assert-SelfUpdateCleanupPath $receipt}
        $customHandled = $true
        $package = Read-StrictJson ([string]$receipt.sourceLocators.authorizationPackagePath) 'MAINTENANCE_AUTHORIZATION'
        $result = Invoke-SelfUpdateFinalize $input $receipt $resolved $package $transition
        if ($AsJson) { $result | ConvertTo-Json -Depth 50 -Compress } else { Write-Output ($result.status + '|FINALIZE_OUTPUT|requirements=' + @($receipt.selectedObligations).Count) }
        if ([string]$result.status -cne 'PASS') { exit 3 }
        exit 0
    }
    $entry = Join-Path ([string]$resolved.runtimeRoot) ('framework\versions\' + [string]$resolved.frameworkVersion + '\scripts\resolve-process-requirements.ps1')
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'PROCESS_REQUIREMENTS_RESOLVER_MISSING' }
    $authorizationAdapter = Join-Path $PSScriptRoot 'check-framework-maintenance-authorization.ps1'
    if (-not (Test-Path -LiteralPath $authorizationAdapter -PathType Leaf)) { throw 'MAINTENANCE_AUTHORIZATION_ADAPTER_MISSING' }
    $invoke = @('-NoProfile','-NonInteractive','-File',$entry,'-InputPath',$inputFull,'-AuthorizationCheckerPath',$authorizationAdapter)
    if ($AsJson) { $invoke += '-AsJson' }; if ($DeleteInputOnExit) { $invoke += '-DeleteInputOnExit' }
    & pwsh @invoke
    exit $LASTEXITCODE
} catch {
    if ($AsJson) { [ordered]@{status='FAIL';reason=[string]$_.Exception.Message} | ConvertTo-Json -Compress } else { Write-Output ('FAIL|framework-maintenance-process-requirements|' + [string]$_.Exception.Message) }
    exit 2
} finally {
    if ($customHandled -and $DeleteInputOnExit -and $null -ne $inputFull -and $null -ne $controlRoot) {
        $runtimeRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $controlRoot '.ai-workspace/runtime')))
        if ($inputFull.StartsWith($runtimeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $inputFull -PathType Leaf)) { Remove-Item -LiteralPath $inputFull -Force }
    }
}
