[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$ObservedActor,

    [Parameter(Mandatory = $true)]
    [string]$ObservedTaskId,

    [Parameter(Mandatory = $true)]
    [string]$ObservedOwner,

    [Parameter(Mandatory = $true)]
    [ValidateSet('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')]
    [string[]]$ObservedAction,

    [Parameter(Mandatory = $true)]
    [string[]]$ObservedPath,

    [string[]]$ObservedIdentity = @(),

    [string]$ControllerControlPath,

    [string]$ObservedRepositoryId,

    [string]$ProjectConfigPath,

    [string]$ExpectedProjectConfigIdentity,

    [string]$TaskPath,

    [string]$ExpectedTaskIdentity,

    [string]$ContinuationReceiptPath,

    [string]$ExpectedContinuationReceiptIdentity,

    [switch]$RootRepositoryBindingValidated
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -cne 'Core' -or $PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'FAIL|tool-runtime|POWERSHELL7_REQUIRED'
    exit 4
}

function Add-Reason([System.Collections.Generic.List[string]]$Reasons, [string]$Reason) {
    if (-not $Reasons.Contains($Reason)) { $Reasons.Add($Reason) }
}

function Test-JsonInteger($Value) {
    return $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Assert-NoDuplicateJsonMembers($Element) {
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add([string]$property.Name)) { throw ('PACKAGE_DUPLICATE_MEMBER|' + [string]$property.Name) }
            Assert-NoDuplicateJsonMembers $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-NoDuplicateJsonMembers $item }
    }
}

function Assert-StrictJsonMembers([string]$Text) {
    $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
    try { $document=[Text.Json.JsonDocument]::Parse($Text,$options) } catch { throw 'PACKAGE_JSON' }
    try { Assert-NoDuplicateJsonMembers $document.RootElement } finally { $document.Dispose() }
}

function Get-FileIdentity([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return $bytes.Length.ToString() + '|' + ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Read-StrictUtf8([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'CONTROLLER_BOM' }
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $encoding.GetString($bytes) } catch { throw 'CONTROLLER_UTF8' }
    if ($text.Contains([char]0) -or $text.Contains([char]0xFFFD)) { throw 'CONTROLLER_TEXT_FORMAT' }
    return $text
}

function Normalize-RelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'PATH_EMPTY' }
    if ($Path -cne $Path.Trim()) { throw "PATH_OUTER_WHITESPACE|$Path" }
    $value = $Path.Replace('\','/')
    if (-not [string]::Equals($value, $value.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw "PATH_NOT_NFC|$Path" }
    if ([IO.Path]::IsPathRooted($value) -or $value.Contains(':') -or $value.StartsWith('/')) {
        throw "PATH_INVALID|$Path"
    }
    $parts = $value.Split('/')
    if ($parts.Count -eq 0) { throw "PATH_EMPTY|$Path" }
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw "PATH_COMPONENT_INVALID|$Path" }
        if ($part.EndsWith('.') -or $part.EndsWith(' ')) { throw "PATH_TRAILING_DOT_OR_SPACE|$Path" }
        if ([regex]::IsMatch($part, '[\x00-\x1F]')) { throw "PATH_CONTROL_CHAR|$Path" }
        $baseName = $part.Split('.')[0]
        if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw "PATH_RESERVED_NAME|$Path" }
    }
    return [string]::Join('/', $parts)
}

function ConvertTo-RoutinePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -cne $Value.Trim()) { throw 'ROUTINE_PATH_EMPTY_OR_WHITESPACE' }
    $path = $Value.Replace('\','/')
    if ([regex]::IsMatch($path,'[<>"|?*]')) { throw 'ROUTINE_PATH_LITERAL_METACHAR' }
    if ([IO.Path]::IsPathRooted($path) -or $path.StartsWith('/') -or $path.Contains(':')) { throw 'ROUTINE_PATH_ROOTED' }
    if (-not [string]::Equals($path,$path.Normalize([Text.NormalizationForm]::FormC),[StringComparison]::Ordinal)) { throw 'ROUTINE_PATH_NOT_NFC' }
    $parts = $path.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.','..')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.EndsWith('.') -or $part.EndsWith(' ') -or [regex]::IsMatch($part,'[\x00-\x1F]')) { throw 'ROUTINE_PATH_COMPONENT' }
        if ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { throw 'ROUTINE_PATH_RESERVED' }
    }
    return [string]::Join('/',$parts)
}

function Assert-FrameworkCapabilities($Capabilities,[string]$Raw) {
    if (-not ($Capabilities -is [pscustomobject])) { throw 'FRAMEWORK_CAPABILITIES_TYPE' }
    $names = @($Capabilities.PSObject.Properties | ForEach-Object { $_.Name })
    if ($names.Count -eq 0) { return }
    if ($names.Count -ne 1 -or $names[0] -cne 'KNOWLEDGE_REFERENCE' -or [regex]::Matches($Raw,'"KNOWLEDGE_REFERENCE"\s*:').Count -ne 1) { throw 'FRAMEWORK_CAPABILITIES_UNKNOWN_OR_DUPLICATE' }
    $knowledge = $Capabilities.KNOWLEDGE_REFERENCE
    if (-not ($knowledge -is [pscustomobject])) { throw 'KNOWLEDGE_CAPABILITY_TYPE' }
    $fields = @($knowledge.PSObject.Properties | ForEach-Object { $_.Name })
    if ($fields.Count -eq 1 -and $fields[0] -ceq 'enabled' -and $knowledge.enabled -is [bool] -and -not [bool]$knowledge.enabled) {
        if ([regex]::Matches($Raw,'"enabled"\s*:').Count -ne 1) { throw 'KNOWLEDGE_CAPABILITY_DUPLICATE_FIELD' }
        return
    }
    if ($fields.Count -ne 2 -or $fields -cnotcontains 'enabled' -or $fields -cnotcontains 'indexLocator' -or
        -not ($knowledge.enabled -is [bool]) -or -not [bool]$knowledge.enabled -or
        -not ($knowledge.indexLocator -is [string]) -or
        [regex]::Matches($Raw,'"enabled"\s*:').Count -ne 1 -or [regex]::Matches($Raw,'"indexLocator"\s*:').Count -ne 1) { throw 'KNOWLEDGE_CAPABILITY_FIELDS' }
    $null = ConvertTo-RoutinePath ([string]$knowledge.indexLocator)
}

function Get-FullDirectoryPath([string]$Path) {
    return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
}

function Assert-DirectoryChainWithoutReparse([string]$Root,[string]$Child) {
    $rootPath = Get-FullDirectoryPath $Root
    $childPath = Get-FullDirectoryPath $Child
    $relative = [IO.Path]::GetRelativePath($rootPath,$childPath).Replace('\','/')
    if ($relative -ceq '..' -or $relative.StartsWith('../') -or [IO.Path]::IsPathRooted($relative)) { throw 'GIT_TOP_DOES_NOT_CONTAIN_CWD' }
    $cursor = $rootPath
    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) { throw 'GIT_TOP_MISSING' }
    if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'GIT_TOP_REPARSE' }
    if ($relative -ceq '.') { return }
    foreach ($component in $relative.Split('/')) {
        $cursor = Join-Path $cursor $component
        if (-not (Test-Path -LiteralPath $cursor -PathType Container)) { throw 'CWD_COMPONENT_MISSING' }
        if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CWD_COMPONENT_REPARSE' }
    }
}

$reasons = New-Object 'System.Collections.Generic.List[string]'
$packageText = Get-Content -LiteralPath $PackagePath -Raw -Encoding utf8
if ([IO.Path]::GetExtension($PackagePath) -ieq '.md') {
    $matches = [regex]::Matches($packageText, '(?ms)^```authorization-package[ \t]*\n(?<json>.*?)\n```[ \t]*$')
    if ($matches.Count -ne 1) {
        Write-Output ('FAIL|AUTHORIZATION_PACKAGE_BLOCK_COUNT_' + $matches.Count)
        exit 2
    }
    $packageText = $matches[0].Groups['json'].Value
}
$taskRouteActor=$null
$actualTaskIdentity=$null
try {
    Assert-StrictJsonMembers $packageText
    $package = $packageText | ConvertFrom-Json
} catch {
    Write-Output ('FAIL|' + [string]$_.Exception.Message)
    exit 2
}
if ($null -eq $package) {
    Write-Output 'FAIL|PACKAGE_JSON'
    exit 2
}

$requiredFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','taskIdentity','actions','exactPaths','objectIdentities','invalidatesOn','projectConfigIdentity')
foreach ($field in $requiredFields) {
    if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
}
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

$baseFields = @('schemaVersion','frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','delegatedGitCloser','taskIdentity','actions','exactPaths','objectIdentities','invalidatesOn')
$controllerFields = @('issuerControllerId','issuerControllerEpoch','controllerControlIdentity')
$repositoryFields = @('repositoryId')
$continuationPlanFields = @('continuationPlan')
$upgradePostimageFields = @('postObjectIdentities')
$upgradeSnapshotFields = @('targetFrameworkSnapshot')
$criticalReviewFields = @('candidateWriter','materialContributors')
$boundedRereview=$null-ne$package.PSObject.Properties['repairReviewBinding']-and[string]$package.repairReviewBinding.phase-cin@('INITIAL_REVIEW','REREVIEW')
$criticalReviewPackage = ([string]$package.profile -ceq 'CRITICAL' -and 'REVIEW_EXECUTE' -in @($package.actions)) -or $boundedRereview
$domainExternalPackage = [string]$package.issuerRole -ceq 'DOMAIN_OWNER' -and 'EXTERNAL' -in @($package.actions)
$domainPushPackage = [string]$package.issuerRole -ceq 'DOMAIN_OWNER' -and 'PUSH' -in @($package.actions)
$actualFields = @($package.PSObject.Properties.Name)
$expectedFields = @($baseFields) + @('projectConfigIdentity')
if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { $expectedFields += $controllerFields }
if ((Test-JsonInteger $package.schemaVersion) -and [int]$package.schemaVersion -eq 2) { $expectedFields += $repositoryFields }
if ($null -ne $package.PSObject.Properties['continuationPlan']) { $expectedFields += $continuationPlanFields }
if ($null -ne $package.PSObject.Properties['repairReviewPlan']) { $expectedFields += 'repairReviewPlan' }
if ($null -ne $package.PSObject.Properties['repairReviewBinding']) { $expectedFields += 'repairReviewBinding' }
if ($null -ne $package.PSObject.Properties['receiverBinding']) { $expectedFields += 'receiverBinding' }
if ((Test-JsonInteger $package.schemaVersion) -and [int]$package.schemaVersion -eq 3) {
    $expectedFields += $upgradePostimageFields
    if ($null -ne $package.PSObject.Properties['targetFrameworkSnapshot']) { $expectedFields += $upgradeSnapshotFields }
}
if ($criticalReviewPackage) { $expectedFields += $criticalReviewFields }
if ($domainExternalPackage) { $expectedFields += @('externalBinding') }
if ($domainPushPackage) { $expectedFields += @('gitPushBinding') }
if ($actualFields.Count -ne $expectedFields.Count -or @($expectedFields | Where-Object { $_ -cnotin $actualFields }).Count -ne 0) {
    Add-Reason $reasons 'PACKAGE_FIELD_SET'
}

function Assert-RepairFields($Value,[string[]]$Fields) {
    if($Value-isnot[pscustomobject]-or@($Value.PSObject.Properties).Count-ne$Fields.Count-or@($Fields|Where-Object{$_-cnotin@($Value.PSObject.Properties.Name)}).Count){throw 'REPAIR_REVIEW_FIELDS'}
}
function Read-RepairEvidence([string]$Path,[string]$Identity) {
    if($Identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or(Get-FileIdentity $Path)-cne$Identity){throw 'REPAIR_REVIEW_EVIDENCE_DRIFT'}
    $text=Read-StrictUtf8 $Path;Assert-StrictJsonMembers $text;return $text|ConvertFrom-Json -Depth 64
}
function Assert-RepairPlan($Parent) {
    $plan=$Parent.repairReviewPlan
    Assert-RepairFields $plan @('writer','reviewer','maxCycles','materialContributors')
    if($plan.writer-isnot[string]-or$plan.reviewer-isnot[string]-or[string]::IsNullOrWhiteSpace($plan.writer)-or[string]::IsNullOrWhiteSpace($plan.reviewer)-or
       -not(Test-JsonInteger $plan.maxCycles)-or$plan.maxCycles-lt1-or$plan.materialContributors-isnot[array]){throw 'REPAIR_REVIEW_PLAN_VALUES'}
    if($plan.writer-cne$Parent.grantee-or$plan.reviewer-cin@($Parent.owner,$Parent.issuer,$plan.writer)-or$plan.reviewer-cin@($plan.materialContributors)){throw 'REPAIR_REVIEW_INDEPENDENCE'}
    if(@($Parent.actions|Where-Object{$_-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','CONTROL_WRITE','REVIEW_ROUTE')}).Count){throw 'REPAIR_REVIEW_PARENT_ACTION'}
}
function Get-RepairReviewer($Parent,$Binding,[string]$ParentIdentity) {
    $plan=$Parent.repairReviewPlan
    if([string]$plan.reviewer-cne'DEFERRED_VISIBLE_REVIEWER'){
        if($null-ne$Binding.PSObject.Properties['reviewerAssignment']){throw 'REVIEWER_ASSIGNMENT_UNEXPECTED'}
        return [string]$plan.reviewer
    }
    if($null-eq$Binding.PSObject.Properties['reviewerAssignment']){throw 'REVIEWER_ASSIGNMENT_REQUIRED'}
    $assignment=$Binding.reviewerAssignment
    Assert-RepairFields $assignment @('source','createdBy','threadId','hostId','taskId','parentPackageIdentity')
    foreach($name in @('source','createdBy','threadId','hostId','taskId','parentPackageIdentity')){if($assignment.$name-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$assignment.$name)){throw 'REVIEWER_ASSIGNMENT_TYPE'}}
    $hostAssigned=[string]$assignment.source-ceq'HOST_CREATE_THREAD_RESULT'
    $initialDelegation=[string]$assignment.source-ceq'HOST_INITIAL_DELEGATION'-and(($Binding.phase-ceq'INITIAL_REVIEW'-and$null-ne$package.PSObject.Properties['receiverBinding']-and[string]$assignment.threadId-ceq[string]$package.grantee)-or($Binding.phase-cin@('REPAIR','REREVIEW')-and$null-eq$package.PSObject.Properties['receiverBinding']-and[string]$assignment.threadId-cne'UNBOUND_RECEIVER'))
    if(-not($hostAssigned-or$initialDelegation)-or[string]$assignment.createdBy-cne[string]$plan.writer-or[string]$assignment.taskId-cne[string]$Parent.taskId-or[string]$assignment.parentPackageIdentity-cne$ParentIdentity-or[string]$assignment.threadId-cin@($Parent.owner,$Parent.issuer,$plan.writer)-or[string]$assignment.threadId-cin@($plan.materialContributors)){throw 'REVIEWER_ASSIGNMENT_BINDING'}
    return [string]$assignment.threadId
}
try {
    if($null-ne$package.PSObject.Properties['repairReviewPlan']){Assert-RepairPlan $package}
    if($null-ne$package.PSObject.Properties['repairReviewBinding']){
        if($null-ne$package.PSObject.Properties['repairReviewPlan']){throw 'REPAIR_REVIEW_NESTED_PLAN'}
        $b=$package.repairReviewBinding
        $bindingFields=@('parentPackagePath','parentPackageIdentity','phase','cycle','verdictPath','verdictIdentity','repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')
        if($null-ne$b.PSObject.Properties['reviewerAssignment']){$bindingFields+='reviewerAssignment'}
        Assert-RepairFields $b $bindingFields
        $parent=Read-RepairEvidence $b.parentPackagePath $b.parentPackageIdentity
        if($null-ne$parent.PSObject.Properties['repairReviewBinding']){throw 'REPAIR_REVIEW_NESTED_PARENT'}
        Assert-RepairPlan $parent
        $plan=$parent.repairReviewPlan
        $reviewerActor=Get-RepairReviewer $parent $b ([string]$b.parentPackageIdentity)
        $initialReview=$b.phase-ceq'INITIAL_REVIEW'
        if($b.phase-cnotin@('INITIAL_REVIEW','REPAIR','REREVIEW')-or-not(Test-JsonInteger $b.cycle)-or
           ($initialReview-and$b.cycle-ne0)-or(-not$initialReview-and($b.cycle-lt1-or$b.cycle-gt$plan.maxCycles))){throw 'REPAIR_REVIEW_CYCLE'}
        foreach($name in @('schemaVersion','frameworkVersion','taskId','taskIdentity','owner','issuer','issuerRole','profile','projectConfigIdentity','userConfirmation')){
            if($package.$name-cne$parent.$name){throw ('REPAIR_REVIEW_PARENT_DRIFT|'+$name)}
        }
        foreach($name in @('repositoryId','issuerControllerId','issuerControllerEpoch','controllerControlIdentity')){
            if($null-ne$parent.PSObject.Properties[$name]-and($null-eq$package.PSObject.Properties[$name]-or$package.$name-cne$parent.$name)){throw ('REPAIR_REVIEW_PARENT_DRIFT|'+$name)}
        }
        if((@($package.exactPaths|Sort-Object)-join"`n")-cne(@($parent.exactPaths|Sort-Object)-join"`n")){throw 'REPAIR_REVIEW_SCOPE_CHANGED'}
        if($initialReview){
            if($b.verdictPath-cne'NOT_APPLICABLE'-or$b.verdictIdentity-cne'NOT_APPLICABLE'){throw 'INITIAL_REVIEW_NO_VERDICT'}
        }else{
        $verdict=Read-RepairEvidence $b.verdictPath $b.verdictIdentity
        Assert-RepairFields $verdict @('taskId','owner','reviewer','writer','cycle','verdict','exactPaths','objectIdentities','findingPaths','scopeChanged','decisionChanged')
        if($verdict.taskId-cne$parent.taskId-or$verdict.owner-cne$parent.owner-or$verdict.reviewer-cne$reviewerActor-or$verdict.writer-cne$plan.writer-or
           $verdict.cycle-ne($b.cycle-1)-or$verdict.verdict-cne'CHANGES_REQUESTED'-or$verdict.scopeChanged-isnot[bool]-or$verdict.scopeChanged-or$verdict.decisionChanged-isnot[bool]-or$verdict.decisionChanged){throw 'REPAIR_REVIEW_VERDICT_BOUNDARY'}
        if($verdict.findingPaths-isnot[array]-or$verdict.findingPaths.Count-eq0-or@($verdict.findingPaths|Where-Object{$_-cnotin$parent.exactPaths}).Count-or
           (@($verdict.exactPaths|Sort-Object)-join"`n")-cne(@($parent.exactPaths|Sort-Object)-join"`n")){throw 'REPAIR_REVIEW_FINDING_SCOPE'}
        }
        if($b.phase-ceq'REPAIR'){
            if($package.grantee-cne$plan.writer-or@($package.actions|Where-Object{$_-cnotin$parent.actions}).Count){throw 'REPAIR_REVIEW_WRITER_ACTION'}
            foreach($name in @('repairFinalizeInputPath','repairFinalizeInputIdentity','repairFinalizeResultPath','repairFinalizeResultIdentity')){if($b.$name-cne'NOT_APPLICABLE'){throw 'REPAIR_REVIEW_FUTURE_RESULT'}}
            $candidateRows=@($verdict.objectIdentities|ForEach-Object{$_.path+'='+$_.identity}|Sort-Object)
            if(($candidateRows-join"`n")-cne(@($package.objectIdentities|ForEach-Object{$_.path+'='+$_.identity}|Sort-Object)-join"`n")){throw 'REPAIR_REVIEW_CANDIDATE_DRIFT'}
        }else{
            if($package.grantee-cne$reviewerActor-or@($package.actions).Count-ne1-or$package.actions[0]-cne'REVIEW_EXECUTE'-or$package.candidateWriter-cne$plan.writer-or
               (@($package.materialContributors|Sort-Object)-join"`n")-cne(@($plan.materialContributors|Sort-Object)-join"`n")){throw 'REPAIR_REVIEW_REVIEWER_ACTION'}
            $finalInput=Read-RepairEvidence $b.repairFinalizeInputPath $b.repairFinalizeInputIdentity
            $finalResult=Read-RepairEvidence $b.repairFinalizeResultPath $b.repairFinalizeResultIdentity
            if($finalInput.mode-cne'FINALIZE_OUTPUT'-or$finalResult.mode-cne'FINALIZE_OUTPUT'-or$finalResult.status-cne'PASS'-or$finalResult.decisionIdentity-cnotmatch'^[A-F0-9]{64}$'){throw 'REPAIR_REVIEW_FINALIZE_REQUIRED'}
            $discover=Read-RepairEvidence $finalInput.discoverReceiptPath $finalInput.expectedDiscoverReceiptIdentity
            if($null-ne$finalResult.PSObject.Properties['sourcePostimageTransition']){throw 'REPAIR_REVIEW_AUTHORITY_CHANGE_REQUIRES_OWNER'}
            $context=if($discover.schemaVersion-eq2){$discover.binding}else{$discover.authorityContext}
            $intent=if($discover.schemaVersion-eq2){$discover.intentEnvelope}else{[pscustomobject]@{objective=$discover.objective;requestedActionKind=$discover.actionKind;requestedResultKind=$discover.resultKind}}
            $exact=if($discover.schemaVersion-eq2){$context.exactScope}else{$discover.exactPaths}
            $finalDelivery=$null
            if($null-ne$finalInput.PSObject.Properties['deliveryContext']){
                Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -Force
                $finalDelivery=Get-AiwDeliveryObservation $finalInput.deliveryContext
                if($finalInput.deliveryContext.stage-ceq'PREPARE'-and@($finalInput.deliveryReceipts).Count){throw 'DELIVERY_FUTURE_EVIDENCE'}
                if($null-eq$finalResult.PSObject.Properties['delivery']-or($finalResult.delivery|ConvertTo-Json -Compress)-cne($finalDelivery|ConvertTo-Json -Compress)){throw 'REPAIR_REVIEW_DELIVERY_RESULT_DRIFT'}
            }elseif($null-ne$finalResult.PSObject.Properties['delivery']){throw 'REPAIR_REVIEW_DELIVERY_RESULT_DRIFT'}
            $material=@($discover.sourceCompositionIdentity,$discover.selectionIdentity,$discover.contextIdentity,'FINALIZE_OUTPUT',$intent.objective,$intent.requestedActionKind,$intent.requestedResultKind,[string]::Join(',',@($exact)),$context.authorizationIdentity,[string]::Join(',',@($finalInput.preparationReceipts)),[string]::Join(',',@($finalInput.resultReceipts)),[string]::Join(',',@($finalInput.deliveryReceipts)),$finalInput.publicDecisionIdentity,$finalInput.protectionState,'NO_SOURCE_POSTIMAGE_TRANSITION','')-join"`n"
            if($null-ne$finalDelivery){$material+=($finalInput.deliveryContext|ConvertTo-Json -Compress)}
            $expectedDecision=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($material)))
            if($expectedDecision-cne$finalResult.decisionIdentity-or$finalResult.selectionIdentity-cne$discover.selectionIdentity-or@($finalResult.missingPreparation).Count-or@($finalResult.missingResult).Count){throw 'REPAIR_REVIEW_FINALIZE_DECISION_DRIFT'}
            foreach($obligation in $discover.selectedObligations){
                $requiredResults=@($obligation.resultRequirements|Where-Object{$null-eq$finalDelivery-or$_-cne'DELIVERY_RECEIPT'})
                if(@($obligation.preparationRequirements|Where-Object{$_-cnotin$finalInput.preparationReceipts}).Count-or@($requiredResults|Where-Object{$_-cnotin$finalInput.resultReceipts}).Count){throw 'REPAIR_REVIEW_FINALIZE_INCOMPLETE'}
            }
            if($null-eq$finalDelivery-and$intent.requestedResultKind-cin@('USER_RESPONSE','TERMINAL','HANDOFF','REVIEW_VERDICT','OWNER_ACCEPTANCE')-and@($finalInput.deliveryReceipts).Count-eq0){throw 'REPAIR_REVIEW_FINALIZE_INCOMPLETE'}
            $repairPackage=Read-RepairEvidence $discover.sourceLocators.authorizationPackagePath $context.authorizationIdentity
            if($repairPackage.grantee-cne$plan.writer-or$repairPackage.taskIdentity-cne$package.taskIdentity){throw 'REPAIR_REVIEW_REPAIR_SOURCE'}
            if([string]$intent.requestedActionKind-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','CONTROL_WRITE')){throw 'REPAIR_REVIEW_PRODUCTION_FINALIZE_REQUIRED'}
            if($initialReview){
                if($context.authorizationIdentity-cne$b.parentPackageIdentity-or
                   $null-ne$repairPackage.PSObject.Properties['repairReviewBinding']-or
                   $intent.requestedActionKind-cnotin$parent.actions){throw 'INITIAL_REVIEW_PRODUCER_SOURCE'}
            }elseif($repairPackage.repairReviewBinding.phase-cne'REPAIR'-or$repairPackage.repairReviewBinding.parentPackageIdentity-cne$b.parentPackageIdentity-or
                     $repairPackage.repairReviewBinding.verdictIdentity-cne$b.verdictIdentity-or$repairPackage.repairReviewBinding.cycle-ne$b.cycle){throw 'REPAIR_REVIEW_REPAIR_SOURCE'}
            $rows=@($finalInput.resultReceipts|Where-Object{$_-clike'OBJECT_POSTIMAGE|*'}|Sort-Object)
            $expected=@($package.objectIdentities|ForEach-Object{'OBJECT_POSTIMAGE|'+$_.path+'|'+$_.identity}|Sort-Object)
            if(($rows-join"`n")-cne($expected-join"`n")){throw 'REPAIR_REVIEW_POSTIMAGE_DRIFT'}
        }
    }
}catch{Add-Reason $reasons ([string]$_.Exception.Message)}
$stringFields = @('frameworkVersion','taskId','profile','lifecycle','owner','issuer','issuerRole','grantee','bundle','decisionClass','userConfirmation','reviewIndependence','taskIdentity','projectConfigIdentity')
foreach ($field in $stringFields) {
    if (-not ($package.$field -is [string])) { Add-Reason $reasons "FIELD_TYPE_${field}_STRING" }
}
if (-not (Test-JsonInteger $package.schemaVersion)) { Add-Reason $reasons 'FIELD_TYPE_schemaVersion_INTEGER' }
if (-not ($package.delegatedGitCloser -is [bool])) { Add-Reason $reasons 'FIELD_TYPE_delegatedGitCloser_BOOLEAN' }
foreach ($field in @('actions','exactPaths','objectIdentities','invalidatesOn') + $(if ((Test-JsonInteger $package.schemaVersion) -and [int]$package.schemaVersion -eq 3) { @('postObjectIdentities') } else { @() })) {
    if (-not ($package.$field -is [System.Array])) { Add-Reason $reasons "FIELD_TYPE_${field}_ARRAY" }
}
if ($null -ne $package.PSObject.Properties['continuationPlan'] -and -not ($package.continuationPlan -is [System.Array])) { Add-Reason $reasons 'FIELD_TYPE_continuationPlan_ARRAY' }
if ($criticalReviewPackage) {
    if (-not ($package.candidateWriter -is [string]) -or [string]::IsNullOrWhiteSpace([string]$package.candidateWriter)) { Add-Reason $reasons 'FIELD_TYPE_candidateWriter_STRING' }
    if (-not ($package.materialContributors -is [System.Array])) { Add-Reason $reasons 'FIELD_TYPE_materialContributors_ARRAY' }
}
if ($domainExternalPackage -and -not ($package.externalBinding -is [pscustomobject])) { Add-Reason $reasons 'FIELD_TYPE_externalBinding_OBJECT' }
if ($domainPushPackage -and -not ($package.gitPushBinding -is [pscustomobject])) { Add-Reason $reasons 'FIELD_TYPE_gitPushBinding_OBJECT' }
if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

if ([int]$package.schemaVersion -notin @(1,2,3)) { Add-Reason $reasons 'SCHEMA_VERSION' }
if ([string]$package.frameworkVersion -cne '1.16.0') { Add-Reason $reasons 'FRAMEWORK_VERSION' }
if ([string]$package.projectConfigIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'PROJECT_CONFIG_IDENTITY_FORMAT' }
if ([string]$package.taskIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'TASK_IDENTITY_FORMAT' }
if ([string]$package.lifecycle -cne 'ACTIVE') { Add-Reason $reasons 'LIFECYCLE_NOT_ACTIVE' }
if ([string]$package.profile -cnotin @('MICRO','STANDARD','CRITICAL')) { Add-Reason $reasons 'PROFILE' }
if ([string]$package.issuerRole -cnotin @('PROJECT_CONTROLLER','DOMAIN_OWNER')) { Add-Reason $reasons 'ISSUER_ROLE' }
if ([string]$package.decisionClass -cnotin @('ROUTINE_LOCAL','PRODUCT_RESULT','MAJOR_ARCHITECTURE','EXTERNAL_ACTION')) { Add-Reason $reasons 'DECISION_CLASS' }
if ([string]$package.grantee -cne $ObservedActor) { Add-Reason $reasons 'GRANTEE_DRIFT' }
if ([string]$package.grantee -ceq 'UNBOUND_RECEIVER') { Add-Reason $reasons 'PENDING_RECEIVER_NOT_ACTIONABLE' }
if ([string]$package.taskId -cne $ObservedTaskId) { Add-Reason $reasons 'TASK_DRIFT' }
if ([string]$package.owner -cne $ObservedOwner) { Add-Reason $reasons 'OWNER_DRIFT' }
if ([string]::IsNullOrWhiteSpace([string]$package.taskId) -or [string]::IsNullOrWhiteSpace([string]$package.owner)) { Add-Reason $reasons 'TASK_OR_OWNER_EMPTY' }
if ([string]::IsNullOrWhiteSpace([string]$package.issuer)) { Add-Reason $reasons 'ISSUER_EMPTY' }
if ([string]::IsNullOrWhiteSpace([string]$package.grantee)) { Add-Reason $reasons 'GRANTEE_EMPTY' }

if($null-ne$package.PSObject.Properties['receiverBinding']){
    try{
        $binding=$package.receiverBinding;$fields=@('pendingPath','pendingIdentity','delegationId','hostActor','receiverRole')
        if($binding-isnot[pscustomobject]-or@($binding.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin@($binding.PSObject.Properties.Name)}).Count){throw 'RECEIVER_BINDING_FIELDS'}
        if([string]$binding.pendingIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or[string]$binding.delegationId-cnotmatch'^[A-Za-z0-9._-]{8,128}$'-or[string]$binding.hostActor-cne[string]$package.grantee-or[string]$binding.hostActor-cne$ObservedActor-or[string]$binding.hostActor-cne[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')){throw 'RECEIVER_HOST_IDENTITY'}
        $controlRoot=[IO.Path]::GetFullPath((Get-Location).Path);$runtimeRoot=[IO.Path]::GetFullPath((Join-Path $controlRoot '.ai-workspace/runtime'))
        $pendingFull=[IO.Path]::GetFullPath([string]$binding.pendingPath)
        if(-not$pendingFull.StartsWith($runtimeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $pendingFull -PathType Leaf)-or(Get-FileIdentity $pendingFull)-cne[string]$binding.pendingIdentity){throw 'RECEIVER_PENDING_DRIFT'}
        $cursor=$pendingFull;while($cursor.StartsWith($runtimeRoot,[StringComparison]::OrdinalIgnoreCase)){
            if(((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'RECEIVER_PENDING_REPARSE'}
            if($cursor-ceq$runtimeRoot){break};$cursor=Split-Path -Parent $cursor
        }
        $pendingRaw=Read-StrictUtf8 $pendingFull;Assert-StrictJsonMembers $pendingRaw;$pending=$pendingRaw|ConvertFrom-Json -Depth 100
        $pendingFields=@('schemaVersion','delegationId','receiverRole','authorizationTemplate')
        if($pending-isnot[pscustomobject]-or@($pending.PSObject.Properties).Count-ne$pendingFields.Count-or@($pendingFields|Where-Object{$_-cnotin@($pending.PSObject.Properties.Name)}).Count-or[int]$pending.schemaVersion-ne1-or[string]$pending.delegationId-cne[string]$binding.delegationId-or[string]$pending.receiverRole-cne[string]$binding.receiverRole-or[string]$pending.authorizationTemplate.grantee-cne'UNBOUND_RECEIVER'-or$null-ne$pending.authorizationTemplate.PSObject.Properties['receiverBinding']){throw 'RECEIVER_PENDING_CONTRACT'}
        $derived=$package|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$derived.PSObject.Properties.Remove('receiverBinding');$derived.grantee='UNBOUND_RECEIVER'
        if($null-ne$pending.authorizationTemplate.PSObject.Properties['repairReviewPlan']){
            $pendingPlan=$pending.authorizationTemplate.repairReviewPlan
            if([string]$binding.receiverRole-cne'IMPLEMENTER'-or$pendingPlan-isnot[pscustomobject]-or$null-eq$pendingPlan.PSObject.Properties['writer']-or[string]$pendingPlan.writer-cne'UNBOUND_RECEIVER'-or$null-eq$derived.PSObject.Properties['repairReviewPlan']){throw 'RECEIVER_REPAIR_WRITER_TEMPLATE'}
            $derived.repairReviewPlan.writer='UNBOUND_RECEIVER'
        }
        if($null-ne$derived.PSObject.Properties['repairReviewBinding']-and$null-ne$derived.repairReviewBinding.PSObject.Properties['reviewerAssignment']-and[string]$derived.repairReviewBinding.reviewerAssignment.source-ceq'HOST_INITIAL_DELEGATION'){$derived.repairReviewBinding.reviewerAssignment.threadId='UNBOUND_RECEIVER'}
        if(($derived|ConvertTo-Json -Depth 100 -Compress)-cne($pending.authorizationTemplate|ConvertTo-Json -Depth 100 -Compress)){throw 'RECEIVER_AUTHORITY_EXPANDED'}
    }catch{Add-Reason $reasons ([string]$_.Exception.Message)}
}

try {
    if ([string]::IsNullOrWhiteSpace($TaskPath) -or [string]::IsNullOrWhiteSpace($ExpectedTaskIdentity)) { throw 'TASK_BINDING_REQUIRED' }
    $normalizedTaskPath = Normalize-RelativePath $TaskPath
    if (-not $normalizedTaskPath.StartsWith('.ai-workspace/tasks/',[StringComparison]::OrdinalIgnoreCase) -or -not $normalizedTaskPath.EndsWith('.md',[StringComparison]::OrdinalIgnoreCase)) { throw 'TASK_PATH_NOT_CANONICAL' }
    if (-not (Test-Path -LiteralPath $TaskPath -PathType Leaf)) { throw 'TASK_OBJECT_MISSING' }
    if (((Get-Item -LiteralPath $TaskPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'TASK_OBJECT_REPARSE' }
    $actualTaskIdentity = Get-FileIdentity $TaskPath
    if ($actualTaskIdentity -cne $ExpectedTaskIdentity -or [string]$package.taskIdentity -cne $ExpectedTaskIdentity) { throw 'TASK_OBJECT_DRIFT' }
    $taskRaw = Read-StrictUtf8 $TaskPath
    $taskIdMatches=[regex]::Matches($taskRaw,'(?m)^#\s+(?<id>[A-Za-z0-9][A-Za-z0-9._-]*)\s+(?:\u2014|-)')
    $taskOwnerMatches=[regex]::Matches($taskRaw,'(?m)^- Owner:\s*(?<owner>[^\s]+)\s*$')
    $taskRouteMatches=[regex]::Matches($taskRaw,'(?m)^- Work route:\s*actor=(?<actor>[^;\s]+);\s*role=(?<role>CONTROLLER|DOMAIN_OWNER|EXECUTOR|REVIEWER|FRAMEWORK_MAINTAINER);\s*phase=(?<phase>DISCOVER|PLAN|IMPLEMENT|VERIFY|REVIEW|GIT|EXTERNAL|RECOVER)\s*$')
    $taskProfileMatches=[regex]::Matches($taskRaw,'(?m)^- Range summary:\s*profile=(?<profile>MICRO|STANDARD|CRITICAL);')
    if($taskIdMatches.Count-ne1-or$taskOwnerMatches.Count-ne1-or$taskRouteMatches.Count-ne1-or$taskProfileMatches.Count-ne1){throw 'TASK_BINDING_FIELDS'}
    if([string]$taskProfileMatches[0].Groups['profile'].Value-cne[string]$package.profile){throw 'TASK_PROFILE_DRIFT'}
    $taskRouteActor=[string]$taskRouteMatches[0].Groups['actor'].Value
    $temporaryActionKinds=@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','GIT_STAGE','GIT_COMMIT','PUSH','BROWSER_RUN','DEVICE_RUN','EXTERNAL')
    $temporaryActionGrantee=@($package.actions).Count-gt0-and@($package.actions|Where-Object{[string]$_-cnotin$temporaryActionKinds}).Count-eq0
    if([string]$taskIdMatches[0].Groups['id'].Value-cne$ObservedTaskId-or[string]$taskOwnerMatches[0].Groups['owner'].Value-cne$ObservedOwner-or(-not$temporaryActionGrantee-and[string]$taskRouteMatches[0].Groups['actor'].Value-cne$ObservedActor)){throw 'TASK_BINDING_DRIFT'}
    if([string]$package.actions[0]-ceq'REVIEW_EXECUTE'-and[string]$taskRouteMatches[0].Groups['actor'].Value-ceq$ObservedActor){throw 'REVIEW_GRANTEE_NOT_TEMPORARY'}
} catch { Add-Reason $reasons ([string]$_.Exception.Message) }

$schema2ProjectId = $null
if ([int]$package.schemaVersion -eq 1 -or ([int]$package.schemaVersion -eq 3 -and -not $RootRepositoryBindingValidated)) {
    try {
        foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')) {
            $value = [Environment]::GetEnvironmentVariable($name,'Process')
            if (-not [string]::IsNullOrEmpty($value)) { throw ('GIT_ENVIRONMENT_OVERRIDE_' + $name) }
        }
        $workingDirectory = Get-FullDirectoryPath (Get-Location).Path
        $gitTopOutput = @(& git -C $workingDirectory rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $gitTopOutput.Count -ne 1) { throw 'GIT_TOP_UNAVAILABLE' }
        $schema1GitTop = Get-FullDirectoryPath ([string]$gitTopOutput[0])
        Assert-DirectoryChainWithoutReparse $schema1GitTop $workingDirectory
        $schema1ControlPlane = Join-Path $schema1GitTop '.ai-workspace'
        if (-not (Test-Path -LiteralPath $schema1ControlPlane -PathType Container)) { throw 'PROJECT_CONTROL_PLANE_MISSING' }
        if (((Get-Item -LiteralPath $schema1ControlPlane -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONTROL_PLANE_REPARSE' }
        $schema1ConfigPath = Join-Path $schema1ControlPlane 'project.json'
        if (-not (Test-Path -LiteralPath $schema1ConfigPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
        if (((Get-Item -LiteralPath $schema1ConfigPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONFIG_REPARSE' }
        if ([string]$package.projectConfigIdentity -cne (Get-FileIdentity $schema1ConfigPath)) { throw 'PROJECT_CONFIG_DRIFT' }
        $schema1ConfigRaw = Read-StrictUtf8 $schema1ConfigPath
        try { $schema1Config = $schema1ConfigRaw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
        $schema1HasPolicy=$null-ne$schema1Config.PSObject.Properties['processPolicy']
        $schema1Fields = @('schemaVersion','id','displayName','controlPlaneLayout','repositoryRoot','frameworkVersion','frameworkToolBackend','routineExcludedPaths','frameworkCapabilities')+$(if($schema1HasPolicy){@('processPolicy')}else{@()})
        $schema1Names = @($schema1Config.PSObject.Properties.Name)
        if (-not ($schema1Config -is [pscustomobject]) -or $schema1Names.Count -ne $schema1Fields.Count -or @($schema1Fields | Where-Object { $_ -cnotin $schema1Names }).Count -ne 0) { throw 'PROJECT_CONFIG_FIELDS' }
        foreach ($name in $schema1Fields) {
            $expectedCount=if($name-ceq'schemaVersion'-and$schema1HasPolicy){2}else{1}
            if ([regex]::Matches($schema1ConfigRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne $expectedCount) { throw 'PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD' }
        }
        if($schema1HasPolicy-and[regex]::Matches($schema1ConfigRaw,'"locator"\s*:').Count-ne1){throw 'PROJECT_CONFIG_DUPLICATE_OR_MISSING_FIELD'}
        if (-not (Test-JsonInteger $schema1Config.schemaVersion) -or [int]$schema1Config.schemaVersion -notin @(3,4) -or
            -not ($schema1Config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema1Config.id) -or
            -not ($schema1Config.displayName -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema1Config.displayName) -or
            -not ($schema1Config.controlPlaneLayout -is [string]) -or [string]$schema1Config.controlPlaneLayout -cne 'repo-local' -or
            -not ($schema1Config.repositoryRoot -is [string]) -or [string]$schema1Config.repositoryRoot -cne '..' -or
            -not ($schema1Config.frameworkVersion -is [string]) -or
            ([int]$package.schemaVersion -eq 1 -and [string]$schema1Config.frameworkVersion -cne '1.16.0') -or
            ([int]$package.schemaVersion -eq 3 -and ([int]$schema1Config.schemaVersion -ne 4 -or [string]$schema1Config.frameworkVersion -cnotmatch '^\d+\.\d+\.\d+$')) -or
            -not ($schema1Config.frameworkToolBackend -is [string]) -or [string]$schema1Config.frameworkToolBackend -cne 'powershell7' -or
            -not ($schema1Config.routineExcludedPaths -is [System.Array])) { throw 'PROJECT_CONFIG_VALUES' }
        if(([int]$schema1Config.schemaVersion-eq4)-ne$schema1HasPolicy){throw 'PROJECT_CONFIG_PROCESS_POLICY_MODE'}
        if($schema1HasPolicy){
            $policyNames=@($schema1Config.processPolicy.PSObject.Properties.Name)
            if(-not($schema1Config.processPolicy-is[pscustomobject])-or$policyNames.Count-ne2-or'schemaVersion'-cnotin$policyNames-or'locator'-cnotin$policyNames-or[int]$schema1Config.processPolicy.schemaVersion-ne1-or[string]$schema1Config.processPolicy.locator-cne'.ai-workspace/process-policy.json'){throw 'PROJECT_CONFIG_PROCESS_POLICY'}
        }
        $schema1Exclusions = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($pathValue in @($schema1Config.routineExcludedPaths)) {
            if (-not ($pathValue -is [string])) { throw 'ROUTINE_EXCLUSION_TYPE' }
            if (-not $schema1Exclusions.Add((ConvertTo-RoutinePath ([string]$pathValue)))) { throw 'ROUTINE_EXCLUSION_DUPLICATE' }
        }
        Assert-FrameworkCapabilities $schema1Config.frameworkCapabilities $schema1ConfigRaw
    } catch {
        Add-Reason $reasons ('SCHEMA1_REQUIRES_REPO_LOCAL_SCHEMA3|' + [string]$_.Exception.Message)
    }
}
if ([int]$package.schemaVersion -in @(2,3) -and $RootRepositoryBindingValidated) {
    try {
        if ([string]::IsNullOrWhiteSpace($ProjectConfigPath) -or [string]::IsNullOrWhiteSpace($ExpectedProjectConfigIdentity)) { throw 'PROJECT_CONFIG_BINDING_REQUIRED' }
        $normalizedConfigPath = Normalize-RelativePath $ProjectConfigPath
        if ($normalizedConfigPath -cne '.ai-workspace/project.json') { throw 'PROJECT_CONFIG_PATH_NOT_CANONICAL' }
        if (-not (Test-Path -LiteralPath $ProjectConfigPath -PathType Leaf)) { throw 'PROJECT_CONFIG_MISSING' }
        if (((Get-Item -LiteralPath $ProjectConfigPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROJECT_CONFIG_REPARSE' }
        $actualConfigIdentity = Get-FileIdentity $ProjectConfigPath
        if ([string]$package.projectConfigIdentity -cne $ExpectedProjectConfigIdentity -or $actualConfigIdentity -cne $ExpectedProjectConfigIdentity) { throw 'PROJECT_CONFIG_DRIFT' }
        $configRaw = Read-StrictUtf8 $ProjectConfigPath
        try { $config = $configRaw | ConvertFrom-Json } catch { throw 'PROJECT_CONFIG_JSON' }
        if (-not ($config -is [pscustomobject]) -or -not ($config.id -is [string]) -or [string]::IsNullOrWhiteSpace([string]$config.id)) { throw 'PROJECT_CONFIG_ID' }
        $schema2ProjectId = [string]$config.id
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
    }
}
if ([int]$package.schemaVersion -eq 2) {
    foreach ($field in $repositoryFields) {
        if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
        elseif (-not ($package.$field -is [string])) { Add-Reason $reasons "FIELD_TYPE_${field}_STRING" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$package.repositoryId)) { Add-Reason $reasons 'REPOSITORY_ID_EMPTY' }
    if ([string]$package.repositoryId -cne $ObservedRepositoryId) { Add-Reason $reasons 'REPOSITORY_DRIFT' }
    if (-not $RootRepositoryBindingValidated) { Add-Reason $reasons 'ROOT_REPOSITORY_BINDING_REQUIRED' }
}

$allowedActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','BROWSER_RUN','DEVICE_RUN','REVIEW_ROUTE','REVIEW_EXECUTE','OWNER_ACCEPT','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
$actions = @($package.actions)
$hasContinuationPlan=$null-ne$package.PSObject.Properties['continuationPlan']
$continuationPlan=@()
if ('OWNER_ACCEPT' -cin $actions -and [string]$package.grantee -cne [string]$package.owner) {
    Add-Reason $reasons 'OWNER_ACCEPT_REQUIRES_CURRENT_TASK_OWNER'
}
foreach ($actionValue in $actions) {
    if (-not ($actionValue -is [string])) { Add-Reason $reasons 'ACTION_TYPE'; continue }
    $action = [string]$actionValue
    if ($action -cnotin $allowedActions) { Add-Reason $reasons 'ACTION_UNKNOWN' }
}
$observedActions = @($ObservedAction)
if ($observedActions.Count -eq 0) { Add-Reason $reasons 'OBSERVED_ACTION_EMPTY' }
foreach ($action in $observedActions) {
    if ($action -cnotin $allowedActions) { Add-Reason $reasons 'OBSERVED_ACTION_UNKNOWN' }
    elseif ($action -cnotin $actions) { Add-Reason $reasons 'ACTION_NOT_GRANTED' }
}
if ($observedActions.Count -ne @($observedActions | Select-Object -Unique).Count) { Add-Reason $reasons 'OBSERVED_ACTION_DUPLICATE' }
if ($actions.Count -ne @($actions | Select-Object -Unique).Count) { Add-Reason $reasons 'ACTION_DUPLICATE' }
if($hasContinuationPlan){
    $continuationPlan=@($package.continuationPlan)
    $continuableActions=@('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE')
    if([int]$package.schemaVersion-eq3-or$continuationPlan.Count-lt2){Add-Reason $reasons 'CONTINUATION_PLAN_SHAPE'}
    foreach($action in $continuationPlan){
        if(-not($action-is[string])-or[string]$action-cnotin$continuableActions-or[string]$action-cnotin$actions){Add-Reason $reasons 'CONTINUATION_PLAN_ACTION'}
    }
    $planActions=@($continuationPlan|Select-Object -Unique)
    if($planActions.Count-ne$actions.Count-or@($actions|Where-Object{$_-cnotin$planActions}).Count-ne0){Add-Reason $reasons 'CONTINUATION_PLAN_ACTION_SET'}
    if('REVIEW_ROUTE'-cin$continuationPlan){
        if(@($continuationPlan|Where-Object{$_-ceq'REVIEW_ROUTE'}).Count-ne1-or[string]$continuationPlan[-1]-cne'REVIEW_ROUTE'-or[string]$continuationPlan[-2]-cne'TEST_RUN'-or@($continuationPlan|Where-Object{$_-cin@('SOURCE_WRITE','TEST_WRITE')}).Count-eq0){Add-Reason $reasons 'CONTINUATION_REVIEW_ROUTE_ORDER'}
    }
}
if ([int]$package.schemaVersion -eq 3) {
    if ([string]$package.bundle -cne 'ACTOR_BOUND_PROJECT_UPGRADE' -or $actions.Count -ne 1 -or [string]$actions[0] -cne 'CONTROL_WRITE') { Add-Reason $reasons 'SCHEMA3_UPGRADE_BUNDLE_ACTION' }
    if ([string]$package.issuerRole -cne 'PROJECT_CONTROLLER' -or [string]$package.profile -cne 'CRITICAL' -or [string]$package.decisionClass -cne 'MAJOR_ARCHITECTURE') { Add-Reason $reasons 'SCHEMA3_UPGRADE_AUTHORITY_PROFILE' }
}
if ([int]$package.schemaVersion -eq 2) {
    if ([string]$package.repositoryId -ceq 'CONTROL' -and @($actions | Where-Object { $_ -in @('SOURCE_WRITE','TEST_WRITE','BROWSER_RUN','DEVICE_RUN') }).Count -gt 0) {
        Add-Reason $reasons 'CONTROL_REPOSITORY_ACTION_DENIED'
    }
    if ([string]$package.repositoryId -cne 'CONTROL' -and 'CONTROL_WRITE' -in $actions) {
        Add-Reason $reasons 'TARGET_REPOSITORY_CONTROL_WRITE_DENIED'
    }
}

$externalActions = @('PUSH','EXTERNAL','DEVICE_RUN')
$requiresUser = [string]$package.decisionClass -ne 'ROUTINE_LOCAL' -or @($actions | Where-Object { $_ -in $externalActions }).Count -gt 0
if ($requiresUser -and ([string]::IsNullOrWhiteSpace([string]$package.userConfirmation) -or [string]$package.userConfirmation -ceq 'NOT_REQUIRED')) {
    Add-Reason $reasons 'USER_CONFIRMATION_REQUIRED'
}
if (-not $requiresUser -and [string]$package.userConfirmation -cne 'NOT_REQUIRED') {
    Add-Reason $reasons 'ROUTINE_USER_CONFIRMATION_SHOULD_NOT_BE_REQUIRED'
}

if ([string]$package.issuerRole -ceq 'DOMAIN_OWNER') {
    if ([string]$package.issuer -cne [string]$package.owner) { Add-Reason $reasons 'DOMAIN_OWNER_MUST_OWN_TASK' }
    if ('PUSH' -in $actions -and -not $domainPushPackage) { Add-Reason $reasons 'DOMAIN_OWNER_EXTERNAL_DENIED' }
    if ('EXTERNAL' -in $actions -and -not $domainExternalPackage) { Add-Reason $reasons 'DOMAIN_OWNER_EXTERNAL_DENIED' }
    if (@($actions | Where-Object { $_ -in @('GIT_STAGE','GIT_COMMIT','PUSH') }).Count -gt 0 -and -not [bool]$package.delegatedGitCloser) {
        Add-Reason $reasons 'DOMAIN_OWNER_GIT_NOT_DELEGATED'
    }
}

if ($domainPushPackage) {
    try {
        if ([int]$package.schemaVersion -ne 2) { throw 'DOMAIN_PUSH_SCHEMA2_REQUIRED' }
        if ($actions.Count -ne 1 -or [string]$actions[0] -cne 'PUSH' -or -not [bool]$package.delegatedGitCloser) { throw 'DOMAIN_PUSH_PURE_CLOSER_REQUIRED' }
        if ($taskRouteMatches.Count -ne 1 -or [string]$taskRouteMatches[0].Groups['role'].Value -cne 'DOMAIN_OWNER' -or [string]$taskRouteMatches[0].Groups['phase'].Value -cne 'GIT') { throw 'DOMAIN_PUSH_TASK_ROUTE' }
        $binding=$package.gitPushBinding
        $fields=@('remote','branch','remoteUrlIdentity','expectedRemoteCommit','localCommit','acceptanceEvidencePath','acceptanceEvidenceIdentity')
        if ($binding -isnot [pscustomobject] -or @($binding.PSObject.Properties).Count -ne $fields.Count -or @($fields|Where-Object{$_-cnotin@($binding.PSObject.Properties.Name)}).Count) { throw 'DOMAIN_PUSH_BINDING_FIELDS' }
        foreach($field in $fields){if($binding.$field -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$binding.$field)){throw 'DOMAIN_PUSH_BINDING_TYPE'}}
        $remote=[string]$binding.remote;$branch=[string]$binding.branch
        if($remote-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $branch-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $branch.Contains('..') -or $branch.Contains('//') -or $branch.EndsWith('.lock') -or $branch.EndsWith('/') -or $branch.Contains('@{')){throw 'DOMAIN_PUSH_TARGET_INVALID'}
        foreach($field in @('expectedRemoteCommit','localCommit')){if([string]$binding.$field -cnotmatch '^(?:[A-F0-9]{40}|[A-F0-9]{64})$'){throw 'DOMAIN_PUSH_COMMIT_IDENTITY'}}
        if([string]$binding.remoteUrlIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$' -or [string]$binding.acceptanceEvidenceIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$'){throw 'DOMAIN_PUSH_EVIDENCE_IDENTITY'}
        $evidenceRelative=Normalize-RelativePath ([string]$binding.acceptanceEvidencePath)
        if(-not($evidenceRelative.StartsWith('.ai-workspace/reports/',[StringComparison]::Ordinal) -or $evidenceRelative.StartsWith('.ai-workspace/tasks/',[StringComparison]::Ordinal))){throw 'DOMAIN_PUSH_ACCEPTANCE_LOCATOR'}
        $evidencePath=Join-Path (Get-Location).Path $evidenceRelative
        if(-not(Test-Path -LiteralPath $evidencePath -PathType Leaf) -or (Get-FileIdentity $evidencePath) -cne [string]$binding.acceptanceEvidenceIdentity){throw 'DOMAIN_PUSH_ACCEPTANCE_DRIFT'}
        $evidenceText=Read-StrictUtf8 $evidencePath
        $reviewReady=$evidenceText.Contains('Review=APPROVED') -or ([string]$package.profile -cne 'CRITICAL' -and $evidenceText.Contains('Review=NOT_REQUIRED'))
        if(-not $reviewReady -or -not $evidenceText.Contains('OwnerAccept=ACCEPTED')){throw 'DOMAIN_PUSH_ACCEPTANCE_UNPROVEN'}
        $acceptedCommitLines=@($evidenceText -split '\r?\n' | Where-Object { $_ -clike 'AcceptedCommit=*' })
        if($acceptedCommitLines.Count -ne 1 -or [string]$acceptedCommitLines[0] -cne ('AcceptedCommit='+[string]$binding.localCommit)){throw 'DOMAIN_PUSH_ACCEPTED_COMMIT_DRIFT'}
        $decisionLine='Push authorization: repositoryId='+[string]$package.repositoryId+'; remote='+$remote+'; branch='+$branch+'; decision='+[string]$package.userConfirmation
        if(-not $taskRaw.Contains($decisionLine)){throw 'DOMAIN_PUSH_USER_SCOPE_UNPROVEN'}
        $controlRoot=Get-FullDirectoryPath (Get-Location).Path
        $repositoryRoot=$controlRoot
        if([string]$package.repositoryId -cne 'CONTROL'){
            if($null-eq$config.frameworkTarget -or [string]$config.frameworkTarget.repositoryId -cne [string]$package.repositoryId){throw 'DOMAIN_PUSH_REPOSITORY_BINDING'}
            $repositoryRoot=Get-FullDirectoryPath (Join-Path (Split-Path -Parent $controlRoot) ([string]$config.frameworkTarget.siblingDirectory))
        }
        foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')){if(-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name,'Process'))){throw 'DOMAIN_PUSH_GIT_ENVIRONMENT_OVERRIDE'}}
        $gitTop=@(& git -C $repositoryRoot rev-parse --show-toplevel 2>$null);if($LASTEXITCODE -ne 0 -or $gitTop.Count -ne 1 -or (Get-FullDirectoryPath ([string]$gitTop[0])) -cne $repositoryRoot){throw 'DOMAIN_PUSH_GIT_TOP'}
        $head=@(& git -C $repositoryRoot rev-parse HEAD 2>$null);if($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or ([string]$head[0]).ToUpperInvariant() -cne [string]$binding.localCommit){throw 'DOMAIN_PUSH_LOCAL_COMMIT_DRIFT'}
        $activeBranch=@(& git -C $repositoryRoot symbolic-ref --quiet --short HEAD 2>$null);if($LASTEXITCODE -ne 0 -or $activeBranch.Count -ne 1 -or [string]$activeBranch[0] -cne $branch){throw 'DOMAIN_PUSH_BRANCH_DRIFT'}
        $parent=@(& git -C $repositoryRoot rev-parse HEAD^ 2>$null);if($LASTEXITCODE -ne 0 -or $parent.Count -ne 1 -or ([string]$parent[0]).ToUpperInvariant() -cne [string]$binding.expectedRemoteCommit){throw 'DOMAIN_PUSH_COMMIT_PARENT'}
        $staged=@(& git -C $repositoryRoot diff --cached --name-only 2>$null);if($LASTEXITCODE -ne 0 -or $staged.Count -gt 0){throw 'DOMAIN_PUSH_SHARED_INDEX_NOT_CLEAR'}
        $commitPaths=@(& git -C $repositoryRoot diff-tree --no-commit-id --name-only -r HEAD 2>$null);if($LASTEXITCODE -ne 0){throw 'DOMAIN_PUSH_COMMIT_PATHS'}
        $commitSorted=@($commitPaths|Sort-Object -CaseSensitive);$exactSorted=@($package.exactPaths|Sort-Object -CaseSensitive)
        if([string]::Join("`n",$commitSorted) -cne [string]::Join("`n",$exactSorted)){throw 'DOMAIN_PUSH_COMMIT_PATHSET_DRIFT'}
        $urls=@(& git -C $repositoryRoot remote get-url --push $remote 2>$null);if($LASTEXITCODE -ne 0 -or $urls.Count -ne 1){throw 'DOMAIN_PUSH_REMOTE_UNAVAILABLE'}
        $urlBytes=[Text.UTF8Encoding]::new($false).GetBytes([string]$urls[0]);$urlIdentity=$urlBytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($urlBytes))
        if($urlIdentity -cne [string]$binding.remoteUrlIdentity){throw 'DOMAIN_PUSH_REMOTE_DRIFT'}
        $oldPrompt=[Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT','Process');[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT','0','Process')
        try{$remoteRef=@(& git -C $repositoryRoot ls-remote --exit-code --heads $remote ('refs/heads/'+$branch) 2>$null);$remoteCode=$LASTEXITCODE}finally{[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT',$oldPrompt,'Process')}
        if($remoteCode -ne 0 -or $remoteRef.Count -ne 1 -or ([string]$remoteRef[0]).Split([char]9)[0].ToUpperInvariant() -cne [string]$binding.expectedRemoteCommit){throw 'DOMAIN_PUSH_REMOTE_REF_DRIFT'}
    } catch { Add-Reason $reasons ([string]$_.Exception.Message) }
}

if ($domainExternalPackage) {
    try {
        if ($actions.Count -ne 1 -or [string]$actions[0] -cne 'EXTERNAL') { throw 'DOMAIN_EXTERNAL_ACTION_MUST_BE_PURE' }
        if ([string]$package.issuer -cne [string]$package.owner -or [string]$package.grantee -cne [string]$package.owner) { throw 'DOMAIN_EXTERNAL_OWNER_ACTOR_MISMATCH' }
        if ($taskRouteMatches.Count -ne 1 -or [string]$taskRouteMatches[0].Groups['role'].Value -cne 'DOMAIN_OWNER' -or [string]$taskRouteMatches[0].Groups['phase'].Value -cne 'EXTERNAL') { throw 'DOMAIN_EXTERNAL_TASK_ROUTE' }
        $binding = $package.externalBinding
        $bindingFields = @('schemaVersion','route','provider','orderedOperations','outputUse','totalQuantity','perOperationRetryCeiling','totalRetryCeiling','costClass','costCeiling','stopConditions','batchExecutionMode','reissuable','ambiguousConsumptionPolicy','escalationFlags')
        $bindingNames = @($binding.PSObject.Properties.Name)
        if ($bindingNames.Count -ne $bindingFields.Count -or @($bindingFields | Where-Object { $_ -cnotin $bindingNames }).Count -ne 0) { throw 'DOMAIN_EXTERNAL_BINDING_FIELDS' }
        if (-not (Test-JsonInteger $binding.schemaVersion) -or [int]$binding.schemaVersion -ne 1 -or
            [string]$binding.route -cne 'DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL' -or
            -not ($binding.provider -is [string]) -or [string]::IsNullOrWhiteSpace([string]$binding.provider) -or
            -not ($binding.orderedOperations -is [Array]) -or @($binding.orderedOperations).Count -eq 0 -or
            -not ($binding.outputUse -is [string]) -or [string]::IsNullOrWhiteSpace([string]$binding.outputUse) -or
            -not (Test-JsonInteger $binding.totalQuantity) -or [int]$binding.totalQuantity -lt 1 -or [int]$binding.totalQuantity -ne @($binding.orderedOperations).Count -or
            -not (Test-JsonInteger $binding.perOperationRetryCeiling) -or [int]$binding.perOperationRetryCeiling -lt 0 -or
            -not (Test-JsonInteger $binding.totalRetryCeiling) -or [int]$binding.totalRetryCeiling -lt 0 -or [int]$binding.totalRetryCeiling -gt ([int]$binding.totalQuantity * [int]$binding.perOperationRetryCeiling) -or
            [string]$binding.costClass -cne 'FREE' -or -not (Test-JsonInteger $binding.costCeiling) -or [int]$binding.costCeiling -ne 0 -or
            -not ($binding.stopConditions -is [Array]) -or @($binding.stopConditions).Count -eq 0 -or
            [string]$binding.batchExecutionMode -cne 'ONE_LOGICAL_ATOMIC_EXECUTION' -or -not ($binding.reissuable -is [bool]) -or [bool]$binding.reissuable -or
            [string]$binding.ambiguousConsumptionPolicy -cne 'BLOCK') { throw 'DOMAIN_EXTERNAL_BINDING_VALUES' }
        $operationIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($operation in @($binding.orderedOperations)) {
            $operationFields=@('operationId','operationKind','declaredInputClass','payloads');$operationNames=@($operation.PSObject.Properties.Name)
            if(-not($operation-is[pscustomobject])-or$operationNames.Count-ne$operationFields.Count-or@($operationFields|Where-Object{$_-cnotin$operationNames}).Count-ne0){throw 'DOMAIN_EXTERNAL_OPERATION_FIELDS'}
            if(-not($operation.operationId-is[string])-or[string]$operation.operationId-cnotmatch'^[A-Z0-9][A-Z0-9._-]*$'-or-not$operationIds.Add([string]$operation.operationId)-or-not($operation.operationKind-is[string])-or[string]::IsNullOrWhiteSpace([string]$operation.operationKind)-or-not($operation.payloads-is[Array])){throw 'DOMAIN_EXTERNAL_OPERATION_VALUES'}
            if([string]$operation.declaredInputClass-ceq'ZERO_PROJECT_DATA'){
                if(@($operation.payloads).Count-ne0){throw 'DOMAIN_EXTERNAL_ZERO_DATA_HAS_PAYLOAD'}
                if([string]$operation.operationKind-cnotin@('PROVIDER_PUBLIC_METADATA_READ','PROVIDER_PUBLIC_STATUS_READ','PROVIDER_CAPABILITY_DISCOVERY')){throw 'DOMAIN_EXTERNAL_ZERO_DATA_OPERATION_NOT_CLOSED'}
            }elseif([string]$operation.declaredInputClass-ceq'EXACT_PAYLOADS'){
                if(@($operation.payloads).Count-eq0){throw 'DOMAIN_EXTERNAL_EXACT_PAYLOAD_MISSING'}
                foreach($payload in @($operation.payloads)){
                    $payloadFields=@('payloadKind','normalizedIdentity','canonicalizationVersion');$payloadNames=@($payload.PSObject.Properties.Name)
                    if(-not($payload-is[pscustomobject])-or$payloadNames.Count-ne$payloadFields.Count-or@($payloadFields|Where-Object{$_-cnotin$payloadNames}).Count-ne0-or-not($payload.payloadKind-is[string])-or[string]::IsNullOrWhiteSpace([string]$payload.payloadKind)-or[string]$payload.normalizedIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not($payload.canonicalizationVersion-is[string])-or[string]::IsNullOrWhiteSpace([string]$payload.canonicalizationVersion)){throw 'DOMAIN_EXTERNAL_PAYLOAD_VALUES'}
                }
            }else{throw 'DOMAIN_EXTERNAL_INPUT_CLASS'}
        }
        foreach($condition in @($binding.stopConditions)){if(-not($condition-is[string])-or[string]::IsNullOrWhiteSpace([string]$condition)){throw 'DOMAIN_EXTERNAL_STOP_CONDITION'}}
        $flagFields=@('paymentOrSubscription','commercialLicensing','accountOrCredentialChange','publicPublication','installation','protectedOrSecretUpload','crossDomain','formalAssetActivation','projectPhaseChange','gitOrPush','sharedQuotaOrResource','unknownScope')
        $flagNames=@($binding.escalationFlags.PSObject.Properties.Name)
        if(-not($binding.escalationFlags-is[pscustomobject])-or$flagNames.Count-ne$flagFields.Count-or@($flagFields|Where-Object{$_-cnotin$flagNames}).Count-ne0){throw 'DOMAIN_EXTERNAL_ESCALATION_FIELDS'}
        foreach($flag in $flagFields){if(-not($binding.escalationFlags.$flag-is[bool])-or[bool]$binding.escalationFlags.$flag){throw ('DOMAIN_EXTERNAL_ESCALATION_REQUIRED|'+$flag)}}
    } catch { Add-Reason $reasons ([string]$_.Exception.Message) }
}

if ([int]$package.schemaVersion -eq 2) {
    try {
        if ([string]::IsNullOrWhiteSpace($ControllerControlPath)) { throw 'CONTROLLER_PATH_REQUIRED' }
        $normalizedSchema2ControllerPath = Normalize-RelativePath $ControllerControlPath
        if ($normalizedSchema2ControllerPath -cne '.ai-workspace/controller.json') { throw 'CONTROLLER_PATH_NOT_CANONICAL' }
        if (-not (Test-Path -LiteralPath $ControllerControlPath -PathType Leaf)) { throw 'CONTROLLER_MISSING' }
        if (((Get-Item -LiteralPath $ControllerControlPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CONTROLLER_REPARSE' }
        $schema2ControllerRaw = Read-StrictUtf8 $ControllerControlPath
        try { $schema2Controller = $schema2ControllerRaw | ConvertFrom-Json } catch { throw 'CONTROLLER_JSON' }
        $schema2ControllerExpected = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
        $schema2ControllerNames = @($schema2Controller.PSObject.Properties.Name)
        if (-not ($schema2Controller -is [pscustomobject]) -or $schema2ControllerNames.Count -ne $schema2ControllerExpected.Count -or @($schema2ControllerExpected | Where-Object { $_ -cnotin $schema2ControllerNames }).Count -ne 0) { throw 'CONTROLLER_FIELDS' }
        foreach ($name in $schema2ControllerExpected) { if ([regex]::Matches($schema2ControllerRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'CONTROLLER_DUPLICATE_FIELD' } }
        if (-not (Test-JsonInteger $schema2Controller.schemaVersion) -or [int]$schema2Controller.schemaVersion -ne 1 -or
            -not ($schema2Controller.projectId -is [string]) -or [string]$schema2Controller.projectId -cne [string]$schema2ProjectId -or
            -not ($schema2Controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$schema2Controller.controllerId) -or
            -not (Test-JsonInteger $schema2Controller.controllerEpoch) -or [int64]$schema2Controller.controllerEpoch -lt 1 -or
            -not ($schema2Controller.state -is [string]) -or [string]$schema2Controller.state -cne 'CURRENT') { throw 'CONTROLLER_VALUES' }
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
    }
}

if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') {
    foreach ($field in $controllerFields) {
        if ($null -eq $package.PSObject.Properties[$field]) { Add-Reason $reasons "FIELD_MISSING_$field" }
    }
    if ($null -ne $package.PSObject.Properties['issuerControllerId'] -and -not ($package.issuerControllerId -is [string])) { Add-Reason $reasons 'FIELD_TYPE_issuerControllerId_STRING' }
    if ($null -ne $package.PSObject.Properties['issuerControllerEpoch'] -and -not (Test-JsonInteger $package.issuerControllerEpoch)) { Add-Reason $reasons 'FIELD_TYPE_issuerControllerEpoch_INTEGER' }
    if ($null -ne $package.PSObject.Properties['controllerControlIdentity'] -and -not ($package.controllerControlIdentity -is [string])) { Add-Reason $reasons 'FIELD_TYPE_controllerControlIdentity_STRING' }
    try {
        if ([string]::IsNullOrWhiteSpace($ControllerControlPath)) { throw 'CONTROLLER_PATH_REQUIRED' }
        $normalizedControllerPath = Normalize-RelativePath $ControllerControlPath
        if ($normalizedControllerPath -cne '.ai-workspace/controller.json') { throw 'CONTROLLER_PATH_NOT_CANONICAL' }
        if (-not (Test-Path -LiteralPath $ControllerControlPath -PathType Leaf)) { throw 'CONTROLLER_MISSING' }
        if (((Get-Item -LiteralPath $ControllerControlPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CONTROLLER_REPARSE' }
        $controllerIdentity = Get-FileIdentity $ControllerControlPath
        if ([string]$package.controllerControlIdentity -cne $controllerIdentity) { throw 'CONTROLLER_OBJECT_DRIFT' }
        $controllerRaw = Read-StrictUtf8 $ControllerControlPath
        try { $controller = $controllerRaw | ConvertFrom-Json } catch { throw 'CONTROLLER_JSON' }
        $controllerExpected = @('schemaVersion','projectId','controllerId','controllerEpoch','state')
        $controllerNames = @($controller.PSObject.Properties.Name)
        if (-not ($controller -is [pscustomobject]) -or $controllerNames.Count -ne $controllerExpected.Count -or @($controllerExpected | Where-Object { $_ -cnotin $controllerNames }).Count -ne 0) { throw 'CONTROLLER_FIELDS' }
        foreach ($name in $controllerExpected) { if ([regex]::Matches($controllerRaw,'"'+[regex]::Escape($name)+'"\s*:').Count -ne 1) { throw 'CONTROLLER_DUPLICATE_FIELD' } }
        if (-not (Test-JsonInteger $controller.schemaVersion) -or [int]$controller.schemaVersion -ne 1 -or
            -not ($controller.projectId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.projectId) -or
            -not ($controller.controllerId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$controller.controllerId) -or
            -not (Test-JsonInteger $controller.controllerEpoch) -or [int64]$controller.controllerEpoch -lt 1 -or
            -not ($controller.state -is [string]) -or [string]$controller.state -cne 'CURRENT') { throw 'CONTROLLER_VALUES' }
        if ([string]$package.issuer -cne [string]$controller.controllerId -or
            [string]$package.issuerControllerId -cne [string]$controller.controllerId -or
            [int64]$package.issuerControllerEpoch -ne [int64]$controller.controllerEpoch) { throw 'STALE_CONTROLLER_AUTHORIZATION' }
    } catch {
        Add-Reason $reasons ([string]$_.Exception.Message)
    }
}

if ('REVIEW_EXECUTE' -in $actions -and [string]$package.profile -ceq 'CRITICAL') {
    $disqualified = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $null = $disqualified.Add([string]$package.owner)
    $null = $disqualified.Add([string]$package.issuer)
    $null = $disqualified.Add([string]$package.candidateWriter)
    $contributorsValid = $true
    foreach ($contributor in @($package.materialContributors)) {
        if (-not ($contributor -is [string]) -or [string]::IsNullOrWhiteSpace([string]$contributor) -or -not $disqualified.Add([string]$contributor)) {
            Add-Reason $reasons 'MATERIAL_CONTRIBUTOR_SET'
            $contributorsValid = $false
        }
    }
    if ([string]$package.reviewIndependence -cne 'INDEPENDENT' -or -not $contributorsValid -or $disqualified.Contains([string]$package.grantee)) {
        Add-Reason $reasons 'CRITICAL_REVIEW_NOT_INDEPENDENT'
    }
}

$candidateMutationActions = @('CONTROL_WRITE','SOURCE_WRITE','TEST_WRITE','GIT_STAGE','GIT_COMMIT','PUSH','EXTERNAL')
if ('REVIEW_EXECUTE' -in $actions -and @($actions | Where-Object { $_ -in $candidateMutationActions }).Count -gt 0) {
    Add-Reason $reasons 'REVIEW_WRITE_ACTION_CONFLICT'
}

$requiredInvalidators = @('TASK_CHANGE','OWNER_CHANGE','GRANTEE_CHANGE','ACTION_CHANGE','PATHSET_CHANGE','OBJECT_DRIFT','USER_DECISION_CHANGE','PROJECT_CONFIG_DRIFT')
if ([string]$package.issuerRole -ceq 'PROJECT_CONTROLLER') { $requiredInvalidators += 'CONTROLLER_EPOCH_CHANGE' }
if ([int]$package.schemaVersion -eq 2) { $requiredInvalidators += 'REPOSITORY_CHANGE' }
if ([int]$package.schemaVersion -eq 3) { $requiredInvalidators += 'POST_OBJECT_DRIFT' }
if ($hasContinuationPlan) { $requiredInvalidators += 'CONTINUATION_RESULT_DRIFT' }
if ($criticalReviewPackage) { $requiredInvalidators += 'CONTRIBUTOR_SET_CHANGE' }
$invalidators = @($package.invalidatesOn)
foreach ($item in $invalidators) {
    if (-not ($item -is [string])) { Add-Reason $reasons 'INVALIDATOR_TYPE' }
}
foreach ($item in $requiredInvalidators) {
    if ($item -cnotin $invalidators) { Add-Reason $reasons "INVALIDATOR_MISSING_$item" }
}

$exact = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($package.exactPaths)) {
    if (-not ($path -is [string])) { Add-Reason $reasons 'EXACT_PATH_TYPE'; continue }
    try { $normalized = Normalize-RelativePath ([string]$path) } catch { Add-Reason $reasons 'EXACT_PATH_INVALID'; continue }
    if (-not $exact.Add($normalized)) { Add-Reason $reasons 'EXACT_PATH_DUPLICATE' }
}
if($hasContinuationPlan-and$exact.Count-eq0){Add-Reason $reasons 'CONTINUATION_EXACT_SCOPE_REQUIRED'}

$identityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($package.objectIdentities)) {
    if (-not ($entry -is [pscustomobject]) -or $null -eq $entry.PSObject.Properties['path'] -or $null -eq $entry.PSObject.Properties['identity']) {
        Add-Reason $reasons 'IDENTITY_ENTRY_FIELD_MISSING'
        continue
    }
    if (-not ($entry.path -is [string]) -or -not ($entry.identity -is [string])) {
        Add-Reason $reasons 'IDENTITY_ENTRY_TYPE'
        continue
    }
    try { $path = Normalize-RelativePath ([string]$entry.path) } catch { Add-Reason $reasons 'IDENTITY_PATH_INVALID'; continue }
    $identity = [string]$entry.identity
    if ($identityMap.ContainsKey($path)) { Add-Reason $reasons 'IDENTITY_PATH_DUPLICATE'; continue }
    if ($identity -cne 'NEW' -and $identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'IDENTITY_FORMAT' }
    $identityMap[$path] = $identity
}
foreach ($path in $exact) {
    if (-not $identityMap.ContainsKey($path)) { Add-Reason $reasons 'IDENTITY_MISSING' }
}
foreach ($path in $identityMap.Keys) {
    if (-not $exact.Contains($path)) { Add-Reason $reasons 'IDENTITY_OUTSIDE_EXACT' }
}

$continuationExpectedIdentityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach($path in $identityMap.Keys){$continuationExpectedIdentityMap[$path]=[string]$identityMap[$path]}
$hasContinuationPath=-not[string]::IsNullOrWhiteSpace($ContinuationReceiptPath)
$hasContinuationIdentity=-not[string]::IsNullOrWhiteSpace($ExpectedContinuationReceiptIdentity)
$continuationReceipt=$null
if($hasContinuationPath-ne$hasContinuationIdentity){Add-Reason $reasons 'CONTINUATION_RECEIPT_BINDING_INCOMPLETE'}
elseif($hasContinuationPath){
    try{
        if(-not$hasContinuationPlan){throw 'CONTINUATION_PLAN_REQUIRED'}
        if($ExpectedContinuationReceiptIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'CONTINUATION_RECEIPT_IDENTITY_FORMAT'}
        if(-not(Test-Path -LiteralPath $ContinuationReceiptPath -PathType Leaf)){throw 'CONTINUATION_RECEIPT_MISSING'}
        if(((Get-Item -LiteralPath $ContinuationReceiptPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'CONTINUATION_RECEIPT_REPARSE'}
        if((Get-FileIdentity $ContinuationReceiptPath)-cne$ExpectedContinuationReceiptIdentity){throw 'CONTINUATION_RECEIPT_DRIFT'}
        $continuationText=Read-StrictUtf8 $ContinuationReceiptPath
        Assert-StrictJsonMembers $continuationText
        try{$continuationReceipt=$continuationText|ConvertFrom-Json}catch{throw 'CONTINUATION_RECEIPT_JSON'}
        $continuationFields=@('schemaVersion','receiptType','status','evidenceGrade','authorityGranted','packageIdentity','taskIdentity','taskId','taskOwner','taskActor','actor','repositoryId','projectConfigIdentity','controllerIdentity','userDecision','protectionState','forbiddenScope','protectedScope','sourceDiscoverReceiptPath','sourceDiscoverReceiptIdentity','sourceSelectionIdentity','sourceContextIdentity','completedStepIndex','completedAction','nextStepIndex','nextAction','exactPaths','postObjectIdentities')
        $continuationNames=@($continuationReceipt.PSObject.Properties.Name)
        if(-not($continuationReceipt-is[pscustomobject])-or$continuationNames.Count-ne$continuationFields.Count-or@($continuationFields|Where-Object{$_-cnotin$continuationNames}).Count-ne0){throw 'CONTINUATION_RECEIPT_FIELDS'}
        foreach($name in @('receiptType','status','evidenceGrade','packageIdentity','taskIdentity','taskId','taskOwner','taskActor','actor','repositoryId','projectConfigIdentity','controllerIdentity','userDecision','protectionState','sourceDiscoverReceiptPath','sourceDiscoverReceiptIdentity','sourceSelectionIdentity','sourceContextIdentity','completedAction','nextAction')){if(-not($continuationReceipt.$name-is[string])-or[string]::IsNullOrWhiteSpace([string]$continuationReceipt.$name)){throw ('CONTINUATION_RECEIPT_TYPE|'+$name)}}
        if(-not(Test-JsonInteger $continuationReceipt.schemaVersion)-or[int]$continuationReceipt.schemaVersion-ne1-or-not($continuationReceipt.authorityGranted-is[bool])-or[bool]$continuationReceipt.authorityGranted-or[string]$continuationReceipt.receiptType-cne'AUTHORIZED_ACTION_CONTINUATION'-or[string]$continuationReceipt.status-cne'PASS'-or[string]$continuationReceipt.evidenceGrade-cne'INSTRUCTION_BOUND'){throw 'CONTINUATION_RECEIPT_TYPE'}
        if(-not(Test-JsonInteger $continuationReceipt.completedStepIndex)-or-not(Test-JsonInteger $continuationReceipt.nextStepIndex)){throw 'CONTINUATION_RECEIPT_STEP_TYPE'}
        $completedStep=[int]$continuationReceipt.completedStepIndex;$nextStep=[int]$continuationReceipt.nextStepIndex
        if($completedStep-lt0-or$nextStep-ne($completedStep+1)-or$nextStep-ge$continuationPlan.Count-or[string]$continuationReceipt.completedAction-cne[string]$continuationPlan[$completedStep]-or[string]$continuationReceipt.nextAction-cne[string]$continuationPlan[$nextStep]){throw 'CONTINUATION_RECEIPT_STEP_DRIFT'}
        $packageIdentity=Get-FileIdentity $PackagePath
        $repositoryBinding=if([int]$package.schemaVersion-eq2){[string]$package.repositoryId}else{'REPO_LOCAL'}
        $currentControllerIdentity=if(-not[string]::IsNullOrWhiteSpace($ControllerControlPath)-and(Test-Path -LiteralPath $ControllerControlPath -PathType Leaf)){Get-FileIdentity $ControllerControlPath}else{'MISSING'}
        if([string]$continuationReceipt.packageIdentity-cne$packageIdentity-or[string]$continuationReceipt.taskIdentity-cne[string]$package.taskIdentity-or[string]$continuationReceipt.taskIdentity-cne[string]$actualTaskIdentity-or[string]$continuationReceipt.taskId-cne$ObservedTaskId-or[string]$continuationReceipt.taskOwner-cne$ObservedOwner-or[string]$continuationReceipt.taskActor-cne[string]$taskRouteActor-or[string]$continuationReceipt.actor-cne$ObservedActor-or[string]$continuationReceipt.repositoryId-cne$repositoryBinding-or[string]$continuationReceipt.projectConfigIdentity-cne[string]$package.projectConfigIdentity-or[string]$continuationReceipt.controllerIdentity-cne$currentControllerIdentity-or[string]$continuationReceipt.userDecision-cne[string]$package.userConfirmation){throw 'CONTINUATION_RECEIPT_AUTHORITY_DRIFT'}
        if([string]$continuationReceipt.protectionState-cnotin@('BOUND','NOT_APPLICABLE')){throw 'CONTINUATION_RECEIPT_PROTECTION'}
        foreach($scopeName in @('forbiddenScope','protectedScope')){if(-not($continuationReceipt.$scopeName-is[Array])){throw ('CONTINUATION_RECEIPT_SCOPE_TYPE|'+$scopeName)};foreach($scopePath in @($continuationReceipt.$scopeName)){if(-not($scopePath-is[string])){throw ('CONTINUATION_RECEIPT_SCOPE_TYPE|'+$scopeName)};$normalizedScope=([string]$scopePath).TrimEnd('/');$null=Normalize-RelativePath $normalizedScope}}
        foreach($identityName in @('packageIdentity','taskIdentity','projectConfigIdentity','sourceDiscoverReceiptIdentity')){if([string]$continuationReceipt.$identityName-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw ('CONTINUATION_RECEIPT_IDENTITY_FORMAT|'+$identityName)}}
        foreach($hashName in @('sourceSelectionIdentity','sourceContextIdentity')){if([string]$continuationReceipt.$hashName-cnotmatch'^[A-F0-9]{64}$'){throw ('CONTINUATION_RECEIPT_IDENTITY_FORMAT|'+$hashName)}}
        $sourceReceiptPath=[string]$continuationReceipt.sourceDiscoverReceiptPath
        if(-not[IO.Path]::IsPathRooted($sourceReceiptPath)-or-not(Test-Path -LiteralPath $sourceReceiptPath -PathType Leaf)-or((Get-Item -LiteralPath $sourceReceiptPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or(Get-FileIdentity $sourceReceiptPath)-cne[string]$continuationReceipt.sourceDiscoverReceiptIdentity){throw 'CONTINUATION_SOURCE_RECEIPT_DRIFT'}
        $sourceReceiptText=Read-StrictUtf8 $sourceReceiptPath;Assert-StrictJsonMembers $sourceReceiptText;try{$sourceReceipt=$sourceReceiptText|ConvertFrom-Json}catch{throw 'CONTINUATION_SOURCE_RECEIPT_JSON'}
        if(-not(Test-JsonInteger $sourceReceipt.schemaVersion)-or[int]$sourceReceipt.schemaVersion-notin@(1,2)-or[string]$sourceReceipt.receiptType-cne'PROCESS_REQUIREMENTS_DISCOVER'-or[string]$sourceReceipt.mode-cne'DISCOVER'-or[string]$sourceReceipt.selectionIdentity-cne[string]$continuationReceipt.sourceSelectionIdentity-or[string]$sourceReceipt.contextIdentity-cne[string]$continuationReceipt.sourceContextIdentity){throw 'CONTINUATION_SOURCE_RECEIPT_LINK_DRIFT'}
        $sourceAuthority=if([int]$sourceReceipt.schemaVersion-eq1){$sourceReceipt.authorityContext}else{$sourceReceipt.binding}
        $sourceAction=if([int]$sourceReceipt.schemaVersion-eq1){[string]$sourceReceipt.actionKind}else{[string]$sourceReceipt.intentEnvelope.requestedActionKind}
        if($sourceAction-cne[string]$continuationReceipt.completedAction){throw 'CONTINUATION_SOURCE_ACTION_DRIFT'}
        if($null-eq$sourceAuthority.PSObject.Properties['continuationStepIndex']-or-not(Test-JsonInteger $sourceAuthority.continuationStepIndex)-or[int]$sourceAuthority.continuationStepIndex-ne$completedStep){throw 'CONTINUATION_SOURCE_STEP_DRIFT'}
        if([string]$sourceAuthority.authorizationIdentity-cne$packageIdentity-or[string]$sourceAuthority.taskIdentity-cne[string]$continuationReceipt.taskIdentity-or[string]$sourceAuthority.taskActor-cne[string]$continuationReceipt.taskActor-or[string]$sourceAuthority.actor-cne[string]$continuationReceipt.actor-or[string]::Join("`n",@($sourceAuthority.forbiddenScope))-cne[string]::Join("`n",@($continuationReceipt.forbiddenScope))-or[string]::Join("`n",@($sourceAuthority.protectedScope))-cne[string]::Join("`n",@($continuationReceipt.protectedScope))){throw 'CONTINUATION_SOURCE_RECEIPT_AUTHORITY_DRIFT'}
        if(-not($continuationReceipt.exactPaths-is[Array])-or[string]::Join("`n",@($continuationReceipt.exactPaths))-cne[string]::Join("`n",@($package.exactPaths))){throw 'CONTINUATION_RECEIPT_SCOPE_DRIFT'}
        if(-not($continuationReceipt.postObjectIdentities-is[Array])){throw 'CONTINUATION_RECEIPT_POSTIMAGES'}
        $postMap=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @($continuationReceipt.postObjectIdentities)){
            if(-not($entry-is[pscustomobject])-or@($entry.PSObject.Properties.Name).Count-ne2-or$null-eq$entry.PSObject.Properties['path']-or$null-eq$entry.PSObject.Properties['identity']-or-not($entry.path-is[string])-or-not($entry.identity-is[string])){throw 'CONTINUATION_RECEIPT_POSTIMAGE_FIELDS'}
            $path=Normalize-RelativePath ([string]$entry.path);$identity=[string]$entry.identity
            if(-not$exact.Contains($path)-or$postMap.ContainsKey($path)-or($identity-cne'NEW'-and$identity-cnotmatch'^\d+\|[A-F0-9]{64}$')){throw 'CONTINUATION_RECEIPT_POSTIMAGE_VALUES'}
            $postMap[$path]=$identity
        }
        if($postMap.Count-ne$exact.Count){throw 'CONTINUATION_RECEIPT_POSTIMAGE_SET'}
        foreach($path in $exact){if(-not$postMap.ContainsKey($path)){throw 'CONTINUATION_RECEIPT_POSTIMAGE_SET'};$continuationExpectedIdentityMap[$path]=[string]$postMap[$path]}
    }catch{Add-Reason $reasons ([string]$_.Exception.Message)}
}

if ([int]$package.schemaVersion -eq 3) {
    $postIdentityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($package.postObjectIdentities)) {
        if (-not ($entry -is [pscustomobject]) -or $null -eq $entry.PSObject.Properties['path'] -or $null -eq $entry.PSObject.Properties['identity'] -or @($entry.PSObject.Properties.Name).Count -ne 2) { Add-Reason $reasons 'POST_IDENTITY_ENTRY_FIELDS'; continue }
        if (-not ($entry.path -is [string]) -or -not ($entry.identity -is [string])) { Add-Reason $reasons 'POST_IDENTITY_ENTRY_TYPE'; continue }
        try { $path = Normalize-RelativePath ([string]$entry.path) } catch { Add-Reason $reasons 'POST_IDENTITY_PATH_INVALID'; continue }
        $identity = [string]$entry.identity
        if ($postIdentityMap.ContainsKey($path)) { Add-Reason $reasons 'POST_IDENTITY_PATH_DUPLICATE'; continue }
        if ($identity -cne 'ABSENT' -and $identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'POST_IDENTITY_FORMAT' }
        $postIdentityMap[$path] = $identity
    }
    foreach ($path in $postIdentityMap.Keys) {
        if (-not $exact.Contains($path) -or -not $identityMap.ContainsKey($path)) { Add-Reason $reasons 'POST_IDENTITY_OUTSIDE_EXACT'; continue }
        $pre = [string]$identityMap[$path]; $post = [string]$postIdentityMap[$path]
        if ($pre -ceq $post -or ($pre -ceq 'NEW' -and $post -ceq 'ABSENT')) { Add-Reason $reasons 'POST_IDENTITY_UNCHANGED' }
        if ($path.StartsWith('.ai-workspace/tmp/upgrade-preparation/',[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith('.ai-workspace/upgrade-recovery/',[StringComparison]::OrdinalIgnoreCase)) { Add-Reason $reasons 'POST_IDENTITY_RECOVERY_PATH' }
    }
    foreach ($path in $exact) {
        if ($postIdentityMap.ContainsKey($path)) { continue }
        if (-not ($path.StartsWith('.ai-workspace/tmp/upgrade-preparation/',[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith('.ai-workspace/upgrade-recovery/',[StringComparison]::OrdinalIgnoreCase))) { Add-Reason $reasons 'LIVE_PATH_MISSING_POST_IDENTITY'; continue }
        if ([string]$identityMap[$path] -cne 'NEW') { Add-Reason $reasons 'RECOVERY_PATH_PREIMAGE_NOT_NEW' }
    }
    if ($postIdentityMap.Count -eq 0) { Add-Reason $reasons 'POST_IDENTITY_EMPTY' }
    if ($null -ne $package.PSObject.Properties['targetFrameworkSnapshot']) {
        $snapshot=$package.targetFrameworkSnapshot
        if (-not ($snapshot -is [pscustomobject]) -or @($snapshot.PSObject.Properties.Name).Count -ne 2 -or $null -eq $snapshot.PSObject.Properties['canonical'] -or $null -eq $snapshot.PSObject.Properties['manifestIdentity']) {
            Add-Reason $reasons 'TARGET_FRAMEWORK_SNAPSHOT_FIELDS'
        }
        elseif (-not ($snapshot.canonical -is [string]) -or [string]$snapshot.canonical -cnotmatch '^[A-F0-9]{64}$' -or -not ($snapshot.manifestIdentity -is [string]) -or [string]$snapshot.manifestIdentity -cnotmatch '^\d+\|[A-F0-9]{64}$') {
            Add-Reason $reasons 'TARGET_FRAMEWORK_SNAPSHOT_FORMAT'
        }
    }
}

$observedIdentityMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($pair in $ObservedIdentity) {
    $split = $pair.IndexOf('=')
    if ($split -lt 1) { Add-Reason $reasons 'OBSERVED_IDENTITY_FORMAT'; continue }
    try { $path = Normalize-RelativePath $pair.Substring(0, $split) } catch { Add-Reason $reasons 'OBSERVED_IDENTITY_PATH_INVALID'; continue }
    $identity = $pair.Substring($split + 1)
    if ($identity -cne 'NEW' -and $identity -cnotmatch '^\d+\|[A-F0-9]{64}$') { Add-Reason $reasons 'OBSERVED_IDENTITY_FORMAT'; continue }
    if ($observedIdentityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_IDENTITY_DUPLICATE'; continue }
    $observedIdentityMap[$path] = $identity
}

if($hasContinuationPlan){
    if($hasContinuationPath-and$observedActions.Count-ne1){Add-Reason $reasons 'CONTINUATION_SINGLE_ACTION_REQUIRED'}
    elseif($observedActions.Count-eq1){
        $expectedAction=if($hasContinuationPath-and$null-ne$continuationReceipt){[string]$continuationReceipt.nextAction}else{[string]$continuationPlan[0]}
        if([string]$observedActions[0]-cne$expectedAction){Add-Reason $reasons 'CONTINUATION_ACTION_ORDER_DRIFT'}
    }
}

$observedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($pathValue in $ObservedPath) {
    try { $path = Normalize-RelativePath $pathValue } catch { Add-Reason $reasons 'OBSERVED_PATH_INVALID'; continue }
    if (-not $observedPaths.Add($path)) { Add-Reason $reasons 'OBSERVED_PATH_DUPLICATE'; continue }
    if (-not $exact.Contains($path)) { Add-Reason $reasons 'OBSERVED_PATH_OUTSIDE_EXACT'; continue }
    if (-not $identityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_PATH_WITHOUT_IDENTITY'; continue }
    $expectedIdentity = [string]$continuationExpectedIdentityMap[$path]
    if (-not $observedIdentityMap.ContainsKey($path)) { Add-Reason $reasons 'OBSERVED_IDENTITY_MISSING'; continue }
    $observedIdentity = [string]$observedIdentityMap[$path]
    if ($expectedIdentity -ceq 'NEW') {
        if ($observedIdentity -cne 'NEW') { Add-Reason $reasons 'NEW_OBJECT_EXISTS' }
    } elseif ($observedIdentity -cne $expectedIdentity) {
        Add-Reason $reasons 'OBJECT_DRIFT'
    }
}
if($hasContinuationPlan-and$observedPaths.Count-ne$exact.Count){Add-Reason $reasons 'CONTINUATION_EXACT_SCOPE_REQUIRED'}

if ($reasons.Count -gt 0) {
    Write-Output ('FAIL|' + ($reasons -join ','))
    exit 2
}

foreach ($action in $observedActions) {
    Write-Output ('PASS|task=' + [string]$package.taskId + '|actor=' + $ObservedActor + '|action=' + $action + '|paths=' + $ObservedPath.Count)
}
exit 0
