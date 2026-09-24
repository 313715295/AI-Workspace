[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ControlRoot,
    [Parameter(Mandatory)][string]$PendingPath,
    [Parameter(Mandatory)][string]$ExpectedPendingIdentity,
    [Parameter(Mandatory)][string]$ReceivedDelegationId
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){Write-Output 'FAIL|POWERSHELL7_REQUIRED';exit 4}
try{
    $actor=[Environment]::GetEnvironmentVariable('CODEX_THREAD_ID','Process')
    if($actor-cnotmatch'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$'){throw 'HOST_THREAD_ID_UNAVAILABLE'}
    if($ReceivedDelegationId-cnotmatch'^[A-Za-z0-9._-]{8,128}$'-or$ExpectedPendingIdentity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'INITIAL_DELEGATION_INPUT'}
    $control=[IO.Path]::GetFullPath($ControlRoot);$runtime=[IO.Path]::GetFullPath((Join-Path $control '.ai-workspace/runtime'));$pendingFull=[IO.Path]::GetFullPath($PendingPath)
    if(-not$pendingFull.StartsWith($runtime+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $pendingFull -PathType Leaf)){throw 'PENDING_LOCATOR'}
    $cursor=$pendingFull;while($cursor.StartsWith($runtime,[StringComparison]::OrdinalIgnoreCase)){
        if(((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'PENDING_REPARSE'}
        if($cursor-ceq$runtime){break};$cursor=Split-Path -Parent $cursor
    }
    $bytes=[IO.File]::ReadAllBytes($pendingFull);$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if($identity-cne$ExpectedPendingIdentity){throw 'PENDING_IDENTITY_DRIFT'}
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'PENDING_BOM'}
    $raw=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $options=[Text.Json.JsonDocumentOptions]::new();$options.AllowTrailingCommas=$false;$options.CommentHandling=[Text.Json.JsonCommentHandling]::Disallow
    $json=[Text.Json.JsonDocument]::Parse($raw,$options);try{
        function Assert-Unique($element){if($element.ValueKind-eq[Text.Json.JsonValueKind]::Object){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($prop in $element.EnumerateObject()){if(-not$seen.Add([string]$prop.Name)){throw 'PENDING_DUPLICATE_MEMBER'};Assert-Unique $prop.Value}}elseif($element.ValueKind-eq[Text.Json.JsonValueKind]::Array){foreach($item in $element.EnumerateArray()){Assert-Unique $item}}}
        Assert-Unique $json.RootElement
    }finally{$json.Dispose()}
    $pending=$raw|ConvertFrom-Json -Depth 100;$fields=@('schemaVersion','delegationId','receiverRole','authorizationTemplate')
    if($pending-isnot[pscustomobject]-or@($pending.PSObject.Properties).Count-ne$fields.Count-or@($fields|Where-Object{$_-cnotin@($pending.PSObject.Properties.Name)}).Count-or[int]$pending.schemaVersion-ne1-or[string]$pending.delegationId-cne$ReceivedDelegationId-or[string]$pending.receiverRole-cnotin@('IMPLEMENTER','INVESTIGATOR','REVIEWER')){throw 'INITIAL_DELEGATION_MISMATCH'}
    $package=$pending.authorizationTemplate
    if($package-isnot[pscustomobject]-or[int]$package.schemaVersion-notin@(1,2)-or[string]$package.grantee-cne'UNBOUND_RECEIVER'-or$null-ne$package.PSObject.Properties['receiverBinding']){throw 'PENDING_PACKAGE_NOT_TEMPLATE'}
    $actions=@($package.actions)
    if(([string]$pending.receiverRole-ceq'REVIEWER'-and($actions.Count-ne1-or[string]$actions[0]-cne'REVIEW_EXECUTE'-or[string]$package.reviewIndependence-cne'INDEPENDENT'))-or([string]$pending.receiverRole-ceq'IMPLEMENTER'-and($actions.Count-eq0-or@($actions|Where-Object{$_-cnotin@('SOURCE_WRITE','TEST_WRITE','TEST_RUN','REVIEW_ROUTE')}).Count-gt0))-or([string]$pending.receiverRole-ceq'INVESTIGATOR'-and($actions.Count-ne1-or[string]$actions[0]-cne'TEST_RUN'))){throw 'RECEIVER_ROLE_ACTION'}
    if([string]$package.taskId-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw 'PENDING_TASK_ID'}
    $taskDir=Join-Path $runtime ([string]$package.taskId)
    if(-not$pendingFull.StartsWith($taskDir+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PENDING_TASK_DIRECTORY_MISMATCH'}
    $package.grantee=$actor
    if($null-ne$package.PSObject.Properties['repairReviewPlan']){
        if([string]$pending.receiverRole-cne'IMPLEMENTER'){throw 'PENDING_REPAIR_WRITER_ROLE'}
        $plan=$package.repairReviewPlan
        if($plan-isnot[pscustomobject]-or$null-eq$plan.PSObject.Properties['writer']-or[string]$plan.writer-cne'UNBOUND_RECEIVER'){throw 'PENDING_REPAIR_WRITER'}
        $plan.writer=$actor
    }
    if($null-ne$package.PSObject.Properties['repairReviewBinding']-and$null-ne$package.repairReviewBinding.PSObject.Properties['reviewerAssignment']-and[string]$package.repairReviewBinding.reviewerAssignment.source-ceq'HOST_INITIAL_DELEGATION'){
        if([string]$package.repairReviewBinding.reviewerAssignment.threadId-cne'UNBOUND_RECEIVER'){throw 'PENDING_REVIEWER_ASSIGNMENT'}
        $package.repairReviewBinding.reviewerAssignment.threadId=$actor
    }
    $package|Add-Member -NotePropertyName receiverBinding -NotePropertyValue ([pscustomobject][ordered]@{pendingPath=$pendingFull;pendingIdentity=$identity;delegationId=$ReceivedDelegationId;hostActor=$actor;receiverRole=[string]$pending.receiverRole})
    $outputDir=Join-Path $taskDir $actor
    foreach($directory in @($runtime,$taskDir,$outputDir)){
        if(Test-Path -LiteralPath $directory){
            $item=Get-Item -LiteralPath $directory -Force
            if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'RECEIVER_OUTPUT_REPARSE'}
        }else{
            New-Item -ItemType Directory -Path $directory -ErrorAction Stop|Out-Null
            $item=Get-Item -LiteralPath $directory -Force
            if(-not$item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'RECEIVER_OUTPUT_REPARSE'}
        }
    }
    $output=Join-Path $outputDir ('receiver-authorization-'+$ReceivedDelegationId+'.json')
    $outBytes=[Text.UTF8Encoding]::new($false).GetBytes(($package|ConvertTo-Json -Depth 100 -Compress).Replace("`r`n","`n"))
    if(Test-Path -LiteralPath $output -PathType Leaf){if(((Get-Item -LiteralPath $output -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'RECEIVER_OUTPUT_REPARSE'};$existing=[IO.File]::ReadAllBytes($output);if($existing.Length-ne$outBytes.Length-or[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($existing))-cne[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($outBytes))){throw 'RECEIVER_BINDING_ALREADY_EXISTS'};Write-Output ('PASS|package='+$output+'|identity='+$outBytes.Length+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($outBytes)));exit 0}
    [IO.File]::WriteAllBytes($output,$outBytes)
    Write-Output ('PASS|package='+$output+'|identity='+$outBytes.Length+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($outBytes)))
}catch{Write-Output ('FAIL|'+[string]$_.Exception.Message);exit 2}
