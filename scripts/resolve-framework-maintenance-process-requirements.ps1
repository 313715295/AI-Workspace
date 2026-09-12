[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,[switch]$AsJson,[switch]$DeleteInputOnExit,[string]$CompactReceiptPath,
    [string]$AdmitInputPath,[string]$ExpectedAdmitInputIdentity,
    [string]$AdmitResultPath,[string]$ExpectedAdmitResultIdentity,
    [string]$AdoptionAuthorizationPackagePath,[string]$ExpectedAdoptionAuthorizationIdentity,
    [string]$ExpectedAdoptionTransactionIdentity
)

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

function Invoke-RuntimeRelocationFinalize($Boundary, $Receipt, $Resolved) {
    # Root adoption recovery only: the original admission is re-proved, never
    # replaced by a new DISCOVER/ADMIT. No live state or retained evidence is written.
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
    Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionTransaction.psm1') -ErrorAction Stop
    $Boundary=(Read-AiwProjectJson $inputFull 'RUNTIME_RELOCATION_INPUT').Value
    $receiptDoc=Read-AiwProjectJson ([string]$Boundary.discoverReceiptPath) 'RUNTIME_RELOCATION_RECEIPT'
    if($receiptDoc.Identity-cne[string]$Boundary.expectedDiscoverReceiptIdentity){throw 'DISCOVER_RECEIPT_DRIFT'}
    $Receipt=$receiptDoc.Value
    Assert-Fields $Receipt @('schemaVersion','receiptType','status','mode','inputContractVersion','sourceCompositionIdentity','selectionIdentity','contextIdentity','binding','intentEnvelope','selectedObligations','pack','sourceLocators','sourceBindings','evidence','counts','authorityGranted','semanticCorrectnessProven') 'RUNTIME_RELOCATION_RECEIPT'
    $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState')
    Assert-Fields $Boundary $fields 'INPUT'
    if($Boundary.schemaVersion-ne2-or$Receipt.schemaVersion-ne2-or$Receipt.inputContractVersion-ne3-or
       [string]$Receipt.status-cne'PASS'-or[string]$Receipt.mode-cne'DISCOVER'-or
       [string]$Receipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or
       $Receipt.authorityGranted-isnot[bool]-or$Receipt.authorityGranted-or
       $Receipt.semanticCorrectnessProven-isnot[bool]-or$Receipt.semanticCorrectnessProven){throw 'RUNTIME_RELOCATION_RECEIPT_CONTRACT'}
    $context=$Receipt.binding;$intent=$Receipt.intentEnvelope;$version=[string]$Resolved.frameworkVersion
    $contextMaterial=(($context|ConvertTo-Json -Depth 30 -Compress)+"`n"+($intent|ConvertTo-Json -Depth 30 -Compress))
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($contextMaterial)))-cne[string]$Receipt.contextIdentity){throw 'RUNTIME_RELOCATION_CONTEXT_IDENTITY'}
    $relative='.ai-workspace/upgrade-recovery/'+$version+'/state.json'
    if($version-cne'1.16.0'-or[string]$context.frameworkVersion-cne$version-or
       [string]$intent.requestedActionKind-cne'CONTROL_WRITE'-or[string]$intent.ambiguityState-cne'CLEAR'-or
       @($context.exactScope).Count-ne1-or[string]$context.exactScope[0]-cne$relative-or
       'CONTROL_WRITE'-cnotin@($context.authorizedActions)-or
       [IO.Path]::GetFullPath([string]$context.repositoryGitTop)-cne[string]$Resolved.controlRoot){throw 'RUNTIME_RELOCATION_EXACT_CONTEXT'}
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $Boundary.$name $name}
    if([string]$Boundary.protectionState-cne'BOUND'-or([string]$Boundary.publicDecisionIdentity-cne'NOT_REQUIRED'-and[string]$Boundary.publicDecisionIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'RUNTIME_RELOCATION_PROTECTION'}
    $documents=@{}
    foreach($proof in @(
        @('admitResult',$AdmitResultPath,$ExpectedAdmitResultIdentity),
        @('adoptionAuthorization',$AdoptionAuthorizationPackagePath,$ExpectedAdoptionAuthorizationIdentity)
    )){
        if([string]::IsNullOrWhiteSpace($proof[1])-or$proof[2]-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('RUNTIME_RELOCATION_ORIGINAL_EVIDENCE_REQUIRED|'+$proof[0])}
        $doc=Read-AiwProjectJson $proof[1] ('RUNTIME_RELOCATION_'+$proof[0])
        if($doc.Identity-cne$proof[2]){throw ('RUNTIME_RELOCATION_EVIDENCE_DRIFT|'+$proof[0])}
        $documents[$proof[0]]=$doc.Value
    }
    $admitted=$documents.admitResult
    if($null-ne$admitted.PSObject.Properties['originalAdmissionInput']){
        $admit=$admitted.originalAdmissionInput
    }else{
        # Compatibility with already retained original inputs. Never reconstruct
        # a deleted historical input from a later FINALIZE or fresh admission.
        if([string]::IsNullOrWhiteSpace($AdmitInputPath)-or$ExpectedAdmitInputIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RUNTIME_RELOCATION_ORIGINAL_EVIDENCE_REQUIRED|admitInput'}
        $admitDoc=Read-AiwProjectJson $AdmitInputPath 'RUNTIME_RELOCATION_admitInput'
        if($admitDoc.Identity-cne$ExpectedAdmitInputIdentity){throw 'RUNTIME_RELOCATION_EVIDENCE_DRIFT|admitInput'}
        $admit=$admitDoc.Value
    }
    Assert-Fields $admit $fields 'RUNTIME_RELOCATION_ADMIT'
    foreach($name in @('preparationReceipts','resultReceipts','deliveryReceipts')){Assert-StringArray $admit.$name ('RUNTIME_RELOCATION_ADMIT_'+$name)}
    if($admit.schemaVersion-ne2-or[string]$admit.mode-cne'ADMIT_ACTION'-or
       [IO.Path]::GetFullPath([string]$admit.discoverReceiptPath)-cne[IO.Path]::GetFullPath([string]$Boundary.discoverReceiptPath)-or
       [string]$admit.expectedDiscoverReceiptIdentity-cne[string]$Boundary.expectedDiscoverReceiptIdentity-or
       [string]$admit.publicDecisionIdentity-cne[string]$Boundary.publicDecisionIdentity-or[string]$admit.protectionState-cne[string]$Boundary.protectionState-or
       [string]$admitted.status-cne'PASS'-or[string]$admitted.mode-cne'ADMIT_ACTION'-or
       [string]$admitted.selectionIdentity-cne[string]$Receipt.selectionIdentity-or
       @($admitted.missingPreparation).Count-ne0-or@($admitted.missingResult).Count-ne0){throw 'RUNTIME_RELOCATION_ORIGINAL_ADMISSION_REQUIRED'}
    $material=@($Receipt.sourceCompositionIdentity,$Receipt.selectionIdentity,$Receipt.contextIdentity,'ADMIT_ACTION',$intent.objective,$intent.requestedActionKind,$intent.requestedResultKind,[string]::Join(',',@($context.exactScope)),$context.authorizationIdentity,[string]::Join(',',@($admit.preparationReceipts)),[string]::Join(',',@($admit.resultReceipts)),[string]::Join(',',@($admit.deliveryReceipts)),$admit.publicDecisionIdentity,$admit.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
    $decision=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($material)))
    if($decision-cne[string]$admitted.decisionIdentity){throw 'RUNTIME_RELOCATION_ORIGINAL_ADMISSION_DECISION'}
    $packageDoc=Read-AiwProjectJson ([string]$Receipt.sourceLocators.authorizationPackagePath) 'RUNTIME_RELOCATION_PROCESS_AUTHORIZATION';$package=$packageDoc.Value
    if($packageDoc.Identity-cne[string]$context.authorizationIdentity-or$package.schemaVersion-ne2-or[string]$package.repositoryId-cne'CONTROL'-or
       [string]$package.grantee-cne[string]$context.actor-or[string]$package.owner-cne[string]$context.taskOwner-or
       [string]$package.taskId-cne[string]$context.taskId-or[string]$package.taskIdentity-cne[string]$context.taskIdentity-or
       [string]$package.projectConfigIdentity-cne[string]$Receipt.sourceBindings.projectConfigIdentity-or
       [string]$package.userConfirmation-cne[string]$context.userDecision-or
       @($package.exactPaths).Count-ne1-or[string]$package.exactPaths[0]-cne$relative-or
       @($package.actions).Count-ne1-or[string]$package.actions[0]-cne'CONTROL_WRITE'-or
       $null-ne$package.PSObject.Properties['continuationPlan']){throw 'RUNTIME_RELOCATION_PROCESS_AUTHORIZATION_BINDING'}
    $transactionPath=Get-AiwContainedPath ([string]$Resolved.controlRoot) '.ai-workspace/runtime/project-adoption/upgrade/state.json'
    $transactionDoc=Read-AiwProjectJson $transactionPath 'RUNTIME_RELOCATION_TRANSACTION';$transaction=$transactionDoc.Value
    if($ExpectedAdoptionTransactionIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or$transactionDoc.Identity-cne$ExpectedAdoptionTransactionIdentity){throw 'RUNTIME_RELOCATION_TRANSACTION_DRIFT'}
    if($transaction.transactionComplete-isnot[bool]-or-not$transaction.transactionComplete-or[string]$transaction.state-cne'COMPLETE'-or
       @($transaction.projection.objects).Count-ne1-or[string]$transaction.projection.objects[0].path-cne$relative-or
       [string]$transaction.metadata.taskPath-cne[string]$Receipt.sourceLocators.taskRelativePath-or
       [string]$transaction.metadata.taskIdentity-cne[string]$context.taskIdentity){throw 'RUNTIME_RELOCATION_TRANSACTION_INCOMPLETE_OR_SCOPE'}
    $recovery=Resume-AiwRuntimeAdoption -RepositoryRoot ([string]$Resolved.controlRoot) -ExpectedTransactionIdentity $ExpectedAdoptionTransactionIdentity -AuthorizationPackagePath $AdoptionAuthorizationPackagePath -ExpectedAuthorizationPackageIdentity $ExpectedAdoptionAuthorizationIdentity -ObservedActor ([string]$context.actor)
    if([string]$recovery.status-cne'COMPLETE'-or$recovery.writes-ne0){throw 'RUNTIME_RELOCATION_TRANSACTION_NOT_COMPLETE'}
    $entry=$transaction.projection.objects[0];$pre=@($package.objectIdentities|Where-Object{[string]$_.path-ceq$relative})
    if(@($package.objectIdentities).Count-ne1-or$pre.Count-ne1-or[string]$pre[0].identity-cne[string]$entry.oldIdentity-or
       [string]$Receipt.sourceBindings.candidatePilotStateIdentity-cne[string]$entry.oldIdentity){throw 'RUNTIME_RELOCATION_PREIMAGE_NOT_AUTHORIZED'}
    $old=$utf8.GetString([Convert]::FromBase64String([string]$entry.oldBase64))|ConvertFrom-Json -Depth 64
    $liveDoc=Read-AiwProjectJson (Get-AiwContainedPath ([string]$Resolved.controlRoot) $relative) 'RUNTIME_RELOCATION_POSTIMAGE';$live=$liveDoc.Value
    if($old.schemaVersion-ne6-or$live.schemaVersion-ne6-or$liveDoc.Identity-cne[string]$entry.newIdentity){throw 'RUNTIME_RELOCATION_ADOPTION_STATE'}
    $oldBinding=Assert-AiwDistributionBinding $old.distributionBinding ([string]$Receipt.sourceLocators.frameworkRoot) $version
    $newBinding=Assert-AiwDistributionBinding $live.distributionBinding ([string]$Resolved.runtimeRoot) $version
    foreach($name in @('distributionId','contentIdentity','manifestIdentity')){
        if([string]$oldBinding.$name-cne[string]$newBinding.$name-or[string]$transaction.metadata.distributionBinding.$name-cne[string]$newBinding.$name){throw ('RUNTIME_RELOCATION_PACKAGE_CHANGED|'+$name)}
    }
    if([string]$transaction.metadata.distributionBinding.runtimeRoot-cne[string]$newBinding.runtimeRoot){throw 'RUNTIME_RELOCATION_TRANSACTION_ROOT'}
    $old.distributionBinding.runtimeRoot=$live.distributionBinding.runtimeRoot
    if(($old|ConvertTo-Json -Depth 64 -Compress)-cne($live|ConvertTo-Json -Depth 64 -Compress)){throw 'RUNTIME_RELOCATION_NON_PATH_STATE_CHANGE'}
    $composer=Join-Path ([string]$Resolved.runtimeRoot) ('framework/versions/'+$version+'/scripts/ProcessRequirementComposition.psm1')
    Import-Module $composer -Force -ErrorAction Stop
    $bindings=Get-AiwProcessBindingSnapshot -ProjectRoot ([string]$Resolved.controlRoot) -FrameworkRoot ([string]$Resolved.runtimeRoot) -TargetVersion $version -TaskRelativePath ([string]$Receipt.sourceLocators.taskRelativePath) -ForbiddenPaths @($context.forbiddenScope)
    Assert-Fields $Receipt.sourceBindings @($bindings.PSObject.Properties.Name) 'RUNTIME_RELOCATION_SOURCE_BINDINGS'
    foreach($name in @($bindings.PSObject.Properties.Name)){
        $expected=if($name-ceq'candidatePilotStateIdentity'){[string]$entry.newIdentity}else{[string]$Receipt.sourceBindings.$name}
        if([string]$bindings.$name-cne$expected){throw ('RUNTIME_RELOCATION_SOURCE_DRIFT|'+$name)}
    }
    $composition=Invoke-ProcessRequirementComposition -ProjectRoot ([string]$Resolved.controlRoot) -FrameworkRoot ([string]$Resolved.runtimeRoot) -TargetVersion $version -ExpectedProjectConfigIdentity ([string]$bindings.projectConfigIdentity) -ExpectedCorrectionsIdentity ([string]$bindings.correctionsIdentity) -Profile ([string]$context.profile) -Role ([string]$context.role) -Phase ([string]$context.phase) -Actor ([string]$context.actor) -TaskIdentity ([string]$bindings.taskIdentity) -Capabilities @($context.observedCapabilities) -Objective (Get-AiwProcessSemanticText -IntentEnvelope $intent) -ActionKind 'CONTROL_WRITE' -ResultKind ([string]$intent.requestedResultKind) -ExactPaths @($context.exactScope) -ForbiddenPaths @($context.forbiddenScope)
    $obligations=@($composition.selectedRequirements|ForEach-Object{[ordered]@{requirementId=[string]$_.requirementId;preparationRequirements=@($_.preparationRequirements);resultRequirements=@($_.resultRequirements)}})
    if(($obligations|ConvertTo-Json -Depth 50 -Compress)-cne($Receipt.selectedObligations|ConvertTo-Json -Depth 50 -Compress)){throw 'RUNTIME_RELOCATION_OBLIGATION_DRIFT'}
    $packBytes=$utf8.GetByteCount((@($composition.selectedRequirements)|ConvertTo-Json -Depth 50 -Compress))
    if($packBytes-ne$Receipt.pack.bytes-or$composition.selectedRulePackBytes-ne$Receipt.pack.ceilingBytes-or$packBytes-gt$composition.selectedRulePackBytes-or$composition.selectedRulePackBytes-gt$composition.absoluteSelectedRulePackBytes){throw 'RUNTIME_RELOCATION_PACK_DRIFT'}
    $requiredPrep=@($obligations|ForEach-Object{$_.preparationRequirements}|Sort-Object -Unique)
    $requiredResult=@($obligations|ForEach-Object{$_.resultRequirements}|Sort-Object -Unique)
    if(@($requiredPrep|Where-Object{$_-cnotin@($admit.preparationReceipts)-or$_-cnotin@($Boundary.preparationReceipts)}).Count-ne0){throw 'RUNTIME_RELOCATION_PREPARATION_INCOMPLETE'}
    if(@($requiredResult|Where-Object{$_-cnotin@($Boundary.resultReceipts)}).Count-ne0){throw 'RUNTIME_RELOCATION_RESULT_INCOMPLETE'}
    $postimages=@($Boundary.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'})
    if($postimages.Count-ne1-or[string]$postimages[0]-cne('OBJECT_POSTIMAGE|'+$relative+'|'+$liveDoc.Identity)){throw 'RUNTIME_RELOCATION_POSTIMAGE_RECEIPT'}
    if([string]$intent.requestedResultKind-cin@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and@($Boundary.deliveryReceipts).Count-eq0){throw 'RUNTIME_RELOCATION_DELIVERY_INCOMPLETE'}
    if((Get-Identity $transactionPath)-cne$transactionDoc.Identity-or(Get-Identity $liveDoc.Path)-cne$liveDoc.Identity-or(Get-Identity $receiptDoc.Path)-cne$receiptDoc.Identity){throw 'RUNTIME_RELOCATION_EVIDENCE_CHANGED_DURING_CHECK'}
    return [ordered]@{status='PASS';mode='FINALIZE_OUTPUT';reason='ORIGINAL_RUNTIME_RELOCATION_FINALIZED';selectionIdentity=[string]$Receipt.selectionIdentity;originalAdmitDecisionIdentity=[string]$admitted.decisionIdentity;originalDiscoverReceiptIdentity=[string]$Boundary.expectedDiscoverReceiptIdentity;adoptionTransactionIdentity=$transactionDoc.Identity;previousSourceCompositionIdentity=[string]$Receipt.sourceCompositionIdentity;currentSourceCompositionIdentity=[string]$composition.sourceCompositionIdentity;changedBindings=@('candidatePilotStateIdentity');previousRuntimeRoot=[string]$oldBinding.runtimeRoot;runtimeRoot=[string]$newBinding.runtimeRoot;missingPreparation=@();missingResult=@();authorityGranted=$false;semanticCorrectnessProven=$false;hostInvocationProven=$false;evidenceGrade='INSTRUCTION_BOUND'}
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
    if ($controlRoot -cne [string]$resolved.controlRoot) { throw 'MAINTENANCE_PROCESS_ROOT_DRIFT' }
    if ($inputFramework -cne [string]$resolved.runtimeRoot) {
        if([string]$input.mode-cne'FINALIZE_OUTPUT'-or$null-eq$receipt){throw 'MAINTENANCE_PROCESS_ROOT_DRIFT'}
        if($DeleteInputOnExit){Assert-SelfUpdateCleanupPath $receipt}
        $customHandled=$true
        $result=Invoke-RuntimeRelocationFinalize $input $receipt $resolved
        if($AsJson){$result|ConvertTo-Json -Depth 50 -Compress}else{Write-Output 'PASS|FINALIZE_OUTPUT|ORIGINAL_RUNTIME_RELOCATION_FINALIZED'}
        exit 0
    }
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
    if ($CompactReceiptPath) { $invoke += @('-CompactReceiptPath',$CompactReceiptPath) }
    if ($AsJson) { $invoke += '-AsJson' }; if ($DeleteInputOnExit) { $invoke += '-DeleteInputOnExit' }
    $retainAdmission=[string]$input.mode-ceq'ADMIT_ACTION'-and$input.schemaVersion-eq2-and$null-ne$receipt-and$receipt.schemaVersion-eq2-and
        [string]$receipt.intentEnvelope.requestedActionKind-ceq'CONTROL_WRITE'-and@($receipt.binding.exactScope).Count-eq1-and
        [string]$receipt.binding.exactScope[0]-ceq('.ai-workspace/upgrade-recovery/'+[string]$resolved.frameworkVersion+'/state.json')
    if($retainAdmission){
        # Capture at the initial boundary, before the real version consumer
        # performs its normal DeleteInputOnExit cleanup. The existing result is
        # the sole evidence carrier; no second file or admission is generated.
        Import-Module (Join-Path $PSScriptRoot 'ProjectAdoptionState.psm1') -ErrorAction Stop
        $originalAdmissionInput=(Read-AiwProjectJson $inputFull 'RUNTIME_RELOCATION_ADMIT_INPUT').Value
        if(-not$AsJson){$invoke+='-AsJson'}
        $admissionOutput=@(& pwsh @invoke);$admissionCode=$LASTEXITCODE
        if($admissionCode-eq0-and$admissionOutput.Count-eq1){
            $admissionResult=$admissionOutput[0]|ConvertFrom-Json -Depth 100
            if([string]$admissionResult.status-ceq'PASS'-and[string]$admissionResult.mode-ceq'ADMIT_ACTION'){
                $admissionResult|Add-Member -NotePropertyName originalAdmissionInput -NotePropertyValue $originalAdmissionInput
            }
            # This state-only admission returns its bound result even without
            # AsJson so normal input cleanup cannot silently discard the proof.
            $admissionResult|ConvertTo-Json -Depth 100 -Compress
        }else{$admissionOutput|Write-Output}
        exit $admissionCode
    }
    & pwsh @invoke
    exit $LASTEXITCODE
} catch {
    if ($AsJson) { [ordered]@{status='FAIL';reason=[string]$_.Exception.Message} | ConvertTo-Json -Compress } else { Write-Output ('FAIL|framework-maintenance-process-requirements|' + [string]$_.Exception.Message) }
    exit 2
} finally {
    if ($customHandled -and $DeleteInputOnExit -and $null -ne $inputFull -and $null -ne $controlRoot) {
        $runtimeRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $controlRoot '.ai-workspace/runtime')))
        if ($inputFull.StartsWith($runtimeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $inputFull -PathType Leaf)) { Remove-Item -LiteralPath $inputFull }
    }
}
