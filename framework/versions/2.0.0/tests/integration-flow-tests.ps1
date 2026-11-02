[CmdletBinding()]
param([switch]$ConstructionOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
Import-Module (Join-Path $PSScriptRoot 'IntegrationFixture.psm1') -Force
function New-FlowBoundary([string]$Mode,$ReceiptRef,[string[]]$PreparationReceipts,[string[]]$ResultReceipts=@(),[array]$EvidenceRefs=@()) {
 return [ordered]@{schemaVersion=3;mode=$Mode;discoverReceiptPath=$ReceiptRef.path;expectedDiscoverReceiptIdentity=$ReceiptRef.identity;preparationReceipts=@($PreparationReceipts);resultReceipts=@($ResultReceipts);deliveryReceipts=@();publicDecisionIdentity='NOT_REQUIRED';protectionState='BOUND';evidenceRefs=@($EvidenceRefs)}
}
function Test-FlowBoundaryConstructionShape($Boundary) {
 $fields=@('schemaVersion','mode','discoverReceiptPath','expectedDiscoverReceiptIdentity','preparationReceipts','resultReceipts','deliveryReceipts','publicDecisionIdentity','protectionState','evidenceRefs')
 $wire=$Boundary|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 if($wire.schemaVersion-ne3-or$wire.mode-cnotin@('ADMIT_ACTION','FINALIZE_OUTPUT')-or$wire.PSObject.Properties.Name.Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin$wire.PSObject.Properties.Name}).Count){return $false}
 if($wire.mode-ceq'ADMIT_ACTION'){return $wire.evidenceRefs.Count-eq0-and$wire.resultReceipts.Count-eq0}
 return $wire.evidenceRefs.Count-eq1-and$wire.resultReceipts.Count-eq1
}
function Test-FlowConstruction {
 # Symbolic values exercise serialization only, and are never sent to a
 # resolver or represented as actual authorization / typed SELF evidence.
 $symbolicRef=@{path='CONSTRUCTION_ONLY_NOT_A_RECEIPT';identity='CONSTRUCTION_ONLY'}
 $symbolicEvidence=@{kind='SELF_CHECK';path='CONSTRUCTION_ONLY_NOT_EVIDENCE';identity='CONSTRUCTION_ONLY'}
 $admit=New-FlowBoundary 'ADMIT_ACTION' $symbolicRef @('CONSTRUCTION_ONLY')
 $finalize=New-FlowBoundary 'FINALIZE_OUTPUT' $symbolicRef @('CONSTRUCTION_ONLY') @('CONSTRUCTION_ONLY_POSTIMAGE') @($symbolicEvidence)
 Assert-True (Test-FlowBoundaryConstructionShape $admit) 'flow-construction-boundary3-empty-admit'
 Assert-True (Test-FlowBoundaryConstructionShape $finalize) 'flow-construction-boundary3-filled-finalize'
 $bad=$finalize|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.schemaVersion=2
 Assert-True (-not(Test-FlowBoundaryConstructionShape $bad)) 'flow-construction-rejects-boundary2-evidence-combination'
 $bad=$admit|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad.evidenceRefs=@($symbolicEvidence)
 Assert-True (-not(Test-FlowBoundaryConstructionShape $bad)) 'flow-construction-rejects-evidence-at-admit'
 $bad=$finalize|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$bad|Add-Member unknown 'CONSTRUCTION_ONLY'
 Assert-True (-not(Test-FlowBoundaryConstructionShape $bad)) 'flow-construction-rejects-unknown-field'
}
function Preserve-FlowInputs([string]$Stage,[string[]]$Paths) {
 if(-not$env:AIW_TEST_RAW_DIRECTORY){Write-Host 'EVIDENCE_CEILING|FLOW_INPUTS_TEMP_ONLY';return}
 if(-not$script:flowArchiveRoot){$script:flowArchiveRoot=Join-Path ([IO.Path]::GetFullPath($env:AIW_TEST_RAW_DIRECTORY)) ('flow-inputs-'+[guid]::NewGuid().ToString('N'))}
 $destination=Join-Path $script:flowArchiveRoot $Stage
 [IO.Directory]::CreateDirectory($destination)|Out-Null
 $rows=@();$index=0
 foreach($path in $Paths){
  $original=Get-Identity $path;$copy=Join-Path $destination ($index.ToString('D2')+'-'+[IO.Path]::GetFileName($path));$index++
  [IO.File]::Copy($path,$copy,$false)
  if((Get-Identity $copy)-cne$original){throw 'FLOW_ORIGINAL_INPUT_COPY_DRIFT'}
  $rows+=@{originalPath=$path;identity=$original;preservedPath=$copy}
 }
 Write-Utf8 (Join-Path $destination 'originals.json') ($rows|ConvertTo-Json -Depth 100)
}
function New-FlowNativeSelf([string]$Stage,$Native,[string]$CandidatePath,[string]$CandidateIdentity) {
 if($Native.Code-ne0-or$Native.Record.status-cne'PASS'-or$Native.Record.exitCode-ne0-or$Native.Record.cancellation){throw 'FLOW_REAL_NATIVE_SELF_REQUIRED'}
 $selfRoot=Join-Path $controlPlane ('runtime/FIXTURE-001/controller-fixture/flow-self/'+$Stage)
 [IO.Directory]::CreateDirectory($selfRoot)|Out-Null
 $localStdout=Join-Path $selfRoot 'product.stdout.raw';$localStderr=Join-Path $selfRoot 'product.stderr.raw';$localNative=Join-Path $selfRoot 'product.native.json'
 [IO.File]::Copy($Native.Record.stdout.path,$localStdout,$false)
 [IO.File]::Copy($Native.Record.stderr.path,$localStderr,$false)
 [IO.File]::Copy($Native.ResultPath,$localNative,$false)
 if((Get-Identity $localStdout)-cne$Native.Record.stdout.identity-or(Get-Identity $localStderr)-cne$Native.Record.stderr.identity-or(Get-Identity $localNative)-cne(Get-Identity $Native.ResultPath)){throw 'FLOW_REAL_NATIVE_COPY_DRIFT'}
 $requirementsPath=Join-Path $selfRoot 'requirements.md';Write-Utf8 $requirementsPath ('Use the real finite product '+$Stage+' command for the exact authorized docs/public.txt postimage; require native0 and the preserved original output. TEST must leave the product unchanged.')
 $commandPath=Join-Path $selfRoot 'command.json'
 Write-Utf8 $commandPath ([ordered]@{command=($Native.Record.command.executable+' '+($Native.Record.command.arguments-join' '));exitCode=$Native.Code;output=[ordered]@{path=$localStdout;identity=(Get-Identity $localStdout)}}|ConvertTo-Json -Depth 100)
 $commandRef=[ordered]@{path=$commandPath;identity=(Get-Identity $commandPath)}
 $selfPath=Join-Path $selfRoot 'self-check.json'
 Write-Utf8 $selfPath ([ordered]@{schemaVersion=1;taskId='FIXTURE-001';actor='controller-fixture';candidateObjects=@([ordered]@{path=$CandidatePath;identity=$CandidateIdentity});requirementsRef=[ordered]@{path=$requirementsPath;identity=(Get-Identity $requirementsPath)};outcome='PASS';checks=@([ordered]@{id=('flow-real-finite-'+$Stage);method='COMMAND';outcome='PASS';reason='Actual completed native0 consumed the exact authorized product; original full stdout/stderr and native record copied byte-for-byte.';evidenceLocators=@($commandRef)});evidenceLocators=@($commandRef,[ordered]@{path=$localStderr;identity=(Get-Identity $localStderr)},[ordered]@{path=$localNative;identity=(Get-Identity $localNative)})}|ConvertTo-Json -Depth 100)
 Preserve-FlowInputs ($Stage+'-typed-self') @($requirementsPath,$commandPath,$selfPath,$localStdout,$localStderr,$localNative)
 return [ordered]@{kind='SELF_CHECK';path=$selfPath;identity=(Get-Identity $selfPath)}
}
$script:flowArchiveRoot=$null
Test-FlowConstruction
if($ConstructionOnly){Write-Output ('PARTIAL|FLOW_CONSTRUCTION_ONLY|code=0|status=PASS|checks='+(Get-IntegrationCheckCount));return}


$integrationContext=$null
try {
 $integrationContext=New-IntegrationContext (Join-Path $PSScriptRoot '..') 'flow'
 foreach($key in $integrationContext.Keys){if($key-ceq'script:testJunctions'){$script:testJunctions=$integrationContext[$key]}else{Set-Variable -Name $key -Value $integrationContext[$key]}}
 $closurePath=Join-Path $liveRepositoryRoot 'source-inputs.json'
 $closure=Get-Content -LiteralPath $closurePath -Raw -Encoding utf8|ConvertFrom-Json -Depth 100
 $actualFlowMember=@($closure.inputs|Where-Object{$_.path-ceq'framework/versions/2.0.0/tests/integration-flow-tests.ps1'})
 Assert-True ($closure.kind-ceq'SOURCE_INPUT_CLOSURE'-and$closure.inputView-ceq'SOURCE_PAYLOAD_V1'-and$closure.definitionIdentity-ceq(Get-Identity (Join-Path $candidateRoot 'tests/test-groups.json'))-and$closure.payloadCanonical-ceq$initialPayloadFacts.Canonical-and$actualFlowMember.Count-eq1-and$actualFlowMember[0].identity-ceq(Get-Identity $PSCommandPath)) 'flow-owned-source-view-root-consumed'
 $maintenanceFixture=New-IntegrationMaintenanceFixture -Register
 foreach($key in $maintenanceFixture.Keys){Set-Variable -Name $key -Value $maintenanceFixture[$key]}
 Assert-True ($registeredMaintenance.Code-eq0-and$adoptionState.state-ceq'COMPLETE'-and$adoptionState.transactionComplete) 'flow-cold-real-registration-complete'
 $targetPackage=Join-Path $controlPlane 'flow-target-auth.json'
 New-AuthorizationPackage $targetPackage 2 'ai-workspace-framework' $configIdentity @('SOURCE_WRITE','TEST_RUN') $targetObject (Get-Identity (Join-Path $target $targetObject)) -ContinuationPlan @('SOURCE_WRITE','TEST_RUN')
 $checked=Invoke-FixtureSchema2Authorization $checker $targetPackage $control 'controller-fixture' 'SOURCE_WRITE' $targetObject (Get-Identity (Join-Path $target $targetObject)) 'ai-workspace-framework' $configIdentity
 Assert-True ($checked.Code-eq0) 'flow-real-root-action-checker'
    $maintenanceProcessResolver=Join-Path $fixedRuntime 'scripts\resolve-framework-maintenance-process-requirements.ps1';$maintenanceProcessTask=Join-Path $control '.ai-workspace\tasks\active\FIXTURE-001.md';$maintenanceProcessInputPath=Join-Path $controlPlane 'maintenance-target-process.json'
    $maintenanceProcessIntent=(New-CurrentFixtureIntent ([ordered]@{schemaVersion=1;objective='Modify one bounded Framework target object';requestedActionKind='SOURCE_WRITE';requestedResultKind='IMPLEMENTATION_RESULT';semanticHints=@('implementation');pathHints=@($targetObject);capabilityHints=@();mutationHints=@('source');externalHints=@();ambiguityState='CLEAR'}))
    $maintenanceProcessInput=[ordered]@{schemaVersion=4;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';projectRoot=$control;frameworkRoot=$fixedRuntime;taskPath=$maintenanceProcessTask;expectedProjectConfigIdentity=$configIdentity;expectedCorrectionsIdentity=(Get-Identity (Join-Path $controlPlane 'corrections.json'));expectedTaskIdentity=(Get-Identity $maintenanceProcessTask);observedActor='controller-fixture';capabilities=@();exactPaths=@($targetObject);forbiddenPaths=@();protectedPaths=@();authorizationPackagePath=$targetPackage;expectedAuthorizationIdentity=(Get-Identity $targetPackage);userDecision='NOT_REQUIRED';recoveryState='CURRENT';hostEnforcementGrade='FRAMEWORK_GATED';invocationState='PROVEN_EXPLICIT';intentEnvelope=$maintenanceProcessIntent;evaluationOnly=$false}
    Write-Utf8 $maintenanceProcessInputPath ($maintenanceProcessInput|ConvertTo-Json -Depth 30);Preserve-FlowInputs 'source-discover' @($maintenanceProcessInputPath,$targetPackage,$maintenanceProcessTask);$maintenanceProcessRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceProcessInputPath,'-AsJson');$maintenanceProcessResult=if($maintenanceProcessRun.Code-eq0){$maintenanceProcessRun.Output[-1]|ConvertFrom-Json}else{$null};$maintenanceProcessValue=if($null-ne$maintenanceProcessResult){$maintenanceProcessResult.compactReceipt}else{$null}
    $expectedTargetGitTop=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($target))
    if($maintenanceProcessRun.Code-ne0-or[string]$maintenanceProcessValue.binding.repositoryGitTop-cne$expectedTargetGitTop){Write-Output ('DIAG|process-maintenance-target|code='+$maintenanceProcessRun.Code+'|expected='+$expectedTargetGitTop+'|output='+$maintenanceProcessRun.Text)}
    Assert-True ($maintenanceProcessRun.Code-eq0-and[string]$maintenanceProcessValue.binding.projectRoot-ceq([IO.Path]::GetFullPath($control))-and[string]$maintenanceProcessValue.binding.repositoryGitTop-ceq$expectedTargetGitTop) 'flow-discover-current-task-and-target-root'

    $maintenanceContinuationDiscoverReceiptPath=Join-Path $controlPlane 'maintenance-continuation-discover-receipt.json';$maintenanceTestDiscoverReceiptPath=Join-Path $controlPlane 'maintenance-test-discover-receipt.json';$maintenanceContinuationBoundaryPath=Join-Path $controlPlane 'maintenance-continuation-boundary.json';$maintenanceContinuationReceiptPath=Join-Path $controlPlane 'maintenance-action-continuation-receipt.json'
    Write-Utf8 $maintenanceContinuationDiscoverReceiptPath ($maintenanceProcessValue|ConvertTo-Json -Depth 40)
    $maintenanceContinuationPrep=@($maintenanceProcessValue.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$maintenanceContinuationResults=@($maintenanceProcessValue.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)
    $maintenanceContinuationAdmit=New-FlowBoundary 'ADMIT_ACTION' @{path=$maintenanceContinuationDiscoverReceiptPath;identity=(Get-Identity $maintenanceContinuationDiscoverReceiptPath)} $maintenanceContinuationPrep
    Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceContinuationAdmit|ConvertTo-Json -Depth 30);Preserve-FlowInputs 'source-admit' @($maintenanceContinuationBoundaryPath,$maintenanceContinuationDiscoverReceiptPath);$maintenanceContinuationAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson')
    Assert-True ($maintenanceContinuationAdmitRun.Code-eq0) 'flow-source-admit-before-product'
    $productTool=Join-Path $temp 'finite-product.ps1'
    Write-Utf8 $productTool ((@"
param([string]`$ProductPath,[switch]`$ReadOnly)
__AIW_TEST_NATIVE_OUTPUT__
`$ErrorActionPreference='Stop'
if(-not`$ReadOnly){[IO.File]::WriteAllText(`$ProductPath,'authorized target postimage',[Text.UTF8Encoding]::new(`$false))}
if([IO.File]::ReadAllText(`$ProductPath)-cne'authorized target postimage'){throw 'FINITE_PRODUCT_CONTENT'}
Write-Output 'PASS|finite-product-read'
"@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
    $productRun=Invoke-Ps $productTool @('-ProductPath',(Join-Path $target $targetObject))
    Assert-True ($productRun.Code-eq0-and$productRun.Record.status-ceq'PASS'-and$productRun.Record.exitCode-eq0-and[string]::IsNullOrEmpty([string]$productRun.Record.cancellation)-and$productRun.Text.Trim()-ceq'PASS|finite-product-read') 'flow-real-finite-product-native-complete'
    $sourceSelf=New-FlowNativeSelf 'source' $productRun $targetObject (Get-Identity (Join-Path $target $targetObject));$maintenanceContinuationFinalize=New-FlowBoundary 'FINALIZE_OUTPUT' @{path=$maintenanceContinuationDiscoverReceiptPath;identity=(Get-Identity $maintenanceContinuationDiscoverReceiptPath)} $maintenanceContinuationPrep @($maintenanceContinuationResults+@('OBJECT_POSTIMAGE|'+$targetObject+'|'+(Get-Identity (Join-Path $target $targetObject)))) @($sourceSelf)
    Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceContinuationFinalize|ConvertTo-Json -Depth 30);Preserve-FlowInputs 'source-finalize' @($maintenanceContinuationBoundaryPath);$maintenanceContinuationFinalizeRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson');$maintenanceContinuationFinalizeValue=if($maintenanceContinuationFinalizeRun.Code-eq0){$maintenanceContinuationFinalizeRun.Output[-1]|ConvertFrom-Json}else{$null}
    if($null-ne$maintenanceContinuationFinalizeValue-and$null-ne$maintenanceContinuationFinalizeValue.PSObject.Properties['continuationReceipt']){Write-Utf8 $maintenanceContinuationReceiptPath ($maintenanceContinuationFinalizeValue.continuationReceipt|ConvertTo-Json -Depth 30)}
    $maintenanceTestInput=$maintenanceProcessInput|ConvertTo-Json -Depth 40|ConvertFrom-Json;$maintenanceTestInput.intentEnvelope.requestedActionKind='TEST_RUN';$maintenanceTestInput.intentEnvelope.requestedResultKind='TEST_RESULT';$maintenanceTestInput.intentEnvelope.objective='Test the exact authorized Framework target postimage';$maintenanceTestInput.intentEnvelope.mutationHints=@('test');$maintenanceTestInput|Add-Member -NotePropertyName continuationReceiptPath -NotePropertyValue $maintenanceContinuationReceiptPath;$maintenanceTestInput|Add-Member -NotePropertyName expectedContinuationReceiptIdentity -NotePropertyValue $(if(Test-Path -LiteralPath $maintenanceContinuationReceiptPath){Get-Identity $maintenanceContinuationReceiptPath}else{'MISSING'})
    Write-Utf8 $maintenanceProcessInputPath ($maintenanceTestInput|ConvertTo-Json -Depth 40);Preserve-FlowInputs 'test-discover' @($maintenanceProcessInputPath,$maintenanceContinuationReceiptPath);$maintenanceTestRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceProcessInputPath,'-AsJson');$maintenanceTestResult=if($maintenanceTestRun.Code-eq0){$maintenanceTestRun.Output[-1]|ConvertFrom-Json}else{$null};$maintenanceTestReceipt=if($null-ne$maintenanceTestResult){$maintenanceTestResult.compactReceipt}else{$null}
    if($null-ne$maintenanceTestReceipt){Write-Utf8 $maintenanceTestDiscoverReceiptPath ($maintenanceTestReceipt|ConvertTo-Json -Depth 40);$maintenanceTestPrep=@($maintenanceTestReceipt.selectedObligations|ForEach-Object{@($_.preparationRequirements)}|Sort-Object -Unique);$maintenanceTestAdmit=New-FlowBoundary 'ADMIT_ACTION' @{path=$maintenanceTestDiscoverReceiptPath;identity=(Get-Identity $maintenanceTestDiscoverReceiptPath)} $maintenanceTestPrep;Write-Utf8 $maintenanceContinuationBoundaryPath ($maintenanceTestAdmit|ConvertTo-Json -Depth 30);Preserve-FlowInputs 'test-admit' @($maintenanceContinuationBoundaryPath,$maintenanceTestDiscoverReceiptPath);$maintenanceTestAdmitRun=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson')}else{$maintenanceTestAdmitRun=[pscustomobject]@{Code=2;Text='NO_TEST_RECEIPT'}}
    $maintenanceContinuationEmitted=$null-ne$maintenanceContinuationFinalizeValue-and$null-ne$maintenanceContinuationFinalizeValue.PSObject.Properties['continuationReceipt']
    Assert-True ($maintenanceContinuationAdmitRun.Code-eq0-and$maintenanceContinuationFinalizeRun.Code-eq0-and$maintenanceContinuationEmitted-and$maintenanceTestRun.Code-eq0-and$maintenanceTestAdmitRun.Code-eq0-and[int]$maintenanceTestReceipt.binding.continuationStepIndex-eq1-and[string]$maintenanceTestReceipt.binding.projectRoot-ceq([IO.Path]::GetFullPath($control))) 'flow-real-write-finalize-next-discover-admit'
 Assert-True ($maintenanceContinuationFinalizeRun.Code-eq0) 'flow-source-finalize-real-postimage'
 $testCheckerWrapper=Join-Path $temp 'continuation-checker.ps1'
 Write-Utf8 $testCheckerWrapper ((@"
param([string]`$Package,[string]`$Receipt,[string]`$ReceiptIdentity,[string]`$ObjectIdentity)
__AIW_TEST_NATIVE_OUTPUT__
& '$checker' -ControlRepositoryPath '$control' -PackagePath `$Package -ObservedActor 'controller-fixture' -ObservedTaskId 'FIXTURE-001' -ObservedOwner 'controller-fixture' -ObservedAction TEST_RUN -ObservedPath '$targetObject' -ObservedIdentity ('$targetObject='+`$ObjectIdentity) -ObservedRepositoryId ai-workspace-framework -ExpectedProjectConfigIdentity '$configIdentity' -TaskPath .ai-workspace/tasks/active/FIXTURE-001.md -ExpectedTaskIdentity '$(Get-Identity $maintenanceProcessTask)' -ContinuationReceiptPath `$Receipt -ExpectedContinuationReceiptIdentity `$ReceiptIdentity
exit `$LASTEXITCODE
"@).Replace('__AIW_TEST_NATIVE_OUTPUT__',('Import-Module ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-Path $PSScriptRoot 'TestNativeOutput.psm1')))+''')))' + "`n" + 'Initialize-AiwTestNativeOutput')))
 $testChecked=Invoke-Ps $testCheckerWrapper @('-Package',$targetPackage,'-Receipt',$maintenanceContinuationReceiptPath,'-ReceiptIdentity',(Get-Identity $maintenanceContinuationReceiptPath),'-ObjectIdentity',(Get-Identity (Join-Path $target $targetObject))) $control
 Assert-True ($testChecked.Code-eq0-and$maintenanceTestAdmitRun.Code-eq0) 'flow-next-test-checker-and-admit-consume-source-finalize'
 $beforeRead=Get-Identity (Join-Path $target $targetObject)
 $productRead=Invoke-Ps $productTool @('-ProductPath',(Join-Path $target $targetObject),'-ReadOnly')
 Assert-True ($productRead.Code-eq0-and$productRead.Text.Trim()-ceq'PASS|finite-product-read'-and(Get-Identity (Join-Path $target $targetObject))-ceq$beforeRead) 'flow-real-test-product-reader-preserves-bytes'
 $testSelf=New-FlowNativeSelf 'test' $productRead $targetObject $beforeRead
 $testFinalize=New-FlowBoundary 'FINALIZE_OUTPUT' @{path=$maintenanceTestDiscoverReceiptPath;identity=(Get-Identity $maintenanceTestDiscoverReceiptPath)} $maintenanceTestPrep @(@($maintenanceTestReceipt.selectedObligations|ForEach-Object{@($_.resultRequirements)}|Sort-Object -Unique)+@('OBJECT_POSTIMAGE|'+$targetObject+'|'+$beforeRead)) @($testSelf)
 Write-Utf8 $maintenanceContinuationBoundaryPath ($testFinalize|ConvertTo-Json -Depth 100)
 Preserve-FlowInputs 'test-finalize' @($maintenanceContinuationBoundaryPath)
 $finalTest=Invoke-Ps $maintenanceProcessResolver @('-InputPath',$maintenanceContinuationBoundaryPath,'-AsJson')
 $testValue=if($finalTest.Code-eq0){$finalTest.Text|ConvertFrom-Json -Depth 100}else{$null}
 Assert-True ($finalTest.Code-eq0-and$testValue.status-ceq'PASS'-and$testValue.actionOutcome-ceq'PASS'-and$testValue.successorState-ceq'FINISHED'-and$null-eq$testValue.PSObject.Properties['continuationReceipt']) 'flow-test-finalize-after-real-native-consumer'
 $laterResolver=Invoke-Ps $resolver @('-ControlRepositoryPath',$control,'-ExpectedProjectConfigIdentity',$configIdentity,'-AsJson')
 $laterValue=$laterResolver.Text|ConvertFrom-Json -Depth 100
 Assert-True ($laterResolver.Code-eq0-and$laterValue.status-ceq'PASS'-and(Get-Identity (Join-Path $target $targetObject))-ceq$beforeRead) 'flow-later-root-consumer-current-binding'
} finally { if($integrationContext){Close-IntegrationContext $integrationContext} }
Write-Output ('RESULT|'+(Get-IntegrationCheckCount)+'/'+(Get-IntegrationCheckCount)+' passed|scope=Framework-2.0.0-flow|')
