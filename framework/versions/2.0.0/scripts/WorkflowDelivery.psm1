Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ResultEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'StrictJsonInput.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1')

# Internal release shared by input consumption and the original final callers.
# Expiry is supplied by the caller, never inferred from a name or a closed card.
function Remove-AiwConsumedRuntimeFiles {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ScopeRoot,
        [AllowEmptyCollection()][string[]]$LiteralPath=@(),[string]$ConsumedPathListPath,
        [string[]]$EmptyDirectoryPath=@(),[string[]]$RetainedPath=@(),[string[]]$ForbiddenPath=@(),[object[]]$ExpectedObject=@())
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $removed=[Collections.Generic.List[string]]::new();$absent=[Collections.Generic.List[string]]::new()
    $retained=[Collections.Generic.List[string]]::new();$failures=[Collections.Generic.List[object]]::new()
    $remaining=[Collections.Generic.List[string]]::new();$directoriesRemoved=[Collections.Generic.List[string]]::new()
    [long]$removedBytes=0;$listReleased=$false;$status='PASS'
    $paths=@($LiteralPath)
    $observations=[Collections.Generic.List[object]]::new()
    function Entry([string]$Path){try{Get-Item -LiteralPath $Path -Force -ErrorAction Stop}catch [System.Management.Automation.ItemNotFoundException]{$null}}
    function Overlap([string]$Path,[string]$Prefix){$Path.Equals($Prefix,[StringComparison]::OrdinalIgnoreCase)-or$Path.StartsWith($Prefix+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}
    function Ordinary([string]$Path){
        $stack=[Collections.Generic.Stack[string]]::new();$cursor=$Path
        while($cursor){if($checked.Contains($cursor)){break};$stack.Push($cursor);$parent=[IO.Path]::GetDirectoryName($cursor);if($parent-eq$cursor){break};$cursor=$parent}
        foreach($cursor in $stack){$item=Entry $cursor;if($null-ne$item-and($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw ('REPARSE_NOT_ALLOWED|'+$cursor)};if($null-ne$item-and$item.PSIsContainer){$null=$checked.Add($cursor)}}
    }
    function Exact([string]$Path){
        if([string]::IsNullOrWhiteSpace($Path)-or-not[IO.Path]::IsPathFullyQualified($Path)){throw 'ABSOLUTE_PATH_REQUIRED'}
        $full=[IO.Path]::GetFullPath($Path)
        if(-not(Overlap $full $root)-or$full.Equals($root,[StringComparison]::OrdinalIgnoreCase)){throw ('OUTSIDE_SCOPE|'+$full)}
        if($full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')){throw 'ALTERNATE_STREAM_NOT_ALLOWED'}
        foreach($prefix in $forbidden){if(Overlap $full $prefix){throw ('FORBIDDEN_PATH|'+$full)}}
        return $full
    }
    function Keep([string]$Path,[switch]$Directory){foreach($prefix in $keep){if((Overlap $Path $prefix)-or($Directory-and(Overlap $prefix $Path))){return $true}};return $false}
    function Failure([string]$Path,$Record){
        $kind=if($Record.Exception-is[System.Management.Automation.PSSecurityException]){'HOST_POLICY_REJECTED'}else{'IO_ERROR'}
        $failures.Add([pscustomobject]@{path=$Path;kind=$kind;errorId=$Record.FullyQualifiedErrorId;message=$Record.Exception.Message})
    }
    try{
        if(-not[IO.Path]::IsPathFullyQualified($ScopeRoot)){throw 'ABSOLUTE_SCOPE_REQUIRED'}
        $root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ScopeRoot))
        if($root.Equals([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetPathRoot($root)),[StringComparison]::OrdinalIgnoreCase)){throw 'VOLUME_ROOT_NOT_ALLOWED'}
        $forbidden=@($ForbiddenPath|ForEach-Object{[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($_))})
        $keep=@($RetainedPath|ForEach-Object{[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($_))})
        foreach($prefix in $forbidden){if(Overlap $root $prefix){throw 'FORBIDDEN_SCOPE'}}
        $checked=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Ordinary $root;$rootEntry=Entry $root;if($null-eq$rootEntry-or-not$rootEntry.PSIsContainer){throw 'SCOPE_DIRECTORY_REQUIRED'}
        $listFull=$null
        if($ConsumedPathListPath){
            $listFull=Exact $ConsumedPathListPath;Ordinary $listFull
            $item=Entry $listFull;if($null-eq$item-or$item.PSIsContainer){throw 'PATH_LIST_FILE_REQUIRED'}
            $bytes=[IO.File]::ReadAllBytes($listFull)
            if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'PATH_LIST_BOM'}
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
            if($text.Contains([char]0)-or$text.Contains([char]0xFFFD)){throw 'PATH_LIST_TEXT_FORMAT'}
            $document=[Text.Json.JsonDocument]::Parse($text)
            try{
                if($document.RootElement.ValueKind-ne[Text.Json.JsonValueKind]::Array){throw 'JSON_FILE_PATH_ARRAY_REQUIRED'}
                $members=@(foreach($token in $document.RootElement.EnumerateArray()){
                    if($token.ValueKind-ne[Text.Json.JsonValueKind]::String){throw 'STRING_FILE_PATH_REQUIRED'}
                    $token.GetString()
                })
            }finally{$document.Dispose()}
            foreach($member in $members){if($member-isnot[string]-or[string]::IsNullOrWhiteSpace($member)){throw 'STRING_FILE_PATH_REQUIRED'};if((Exact $member).Equals($listFull,[StringComparison]::OrdinalIgnoreCase)){throw 'PATH_LIST_CANNOT_LIST_ITSELF'}}
            $paths+=@($members)
        }
        $files=[Collections.Generic.List[string]]::new();$directories=[Collections.Generic.List[string]]::new()
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        # The entire explicit group, including directories, is checked before deletion.
        foreach($path in $paths){$full=Exact $path;if(-not$seen.Add($full)){continue};if($listFull-and$full.Equals($listFull,[StringComparison]::OrdinalIgnoreCase)){continue};if(Keep $full){$retained.Add($full);continue};Ordinary $full;$item=Entry $full;if($null-ne$item-and$item.PSIsContainer){throw ('DIRECTORY_NOT_ALLOWED|'+$full)};$files.Add($full)}
        foreach($path in $EmptyDirectoryPath){$full=Exact $path;if(-not$seen.Add($full)){throw 'FILE_DIRECTORY_COLLISION'};if(Keep $full -Directory){$retained.Add($full);continue};Ordinary $full;$item=Entry $full;if($null-ne$item-and-not$item.PSIsContainer){throw ('DIRECTORY_REQUIRED|'+$full)};$directories.Add($full)}
        $expected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($object in $ExpectedObject){
            if($null-eq$object-or$object.path-isnot[string]-or$object.identity-isnot[string]-or$object.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'EXPECTED_OBJECT_FORMAT'}
            $full=Exact $object.path
            if(-not$seen.Contains($full)-or$expected.ContainsKey($full)){throw 'EXPECTED_OBJECT_SCOPE'}
            $expected.Add($full,$object.identity)
        }
        foreach($path in $files){
            try{Ordinary $path;$item=Entry $path;if($null-eq$item){$absent.Add($path);continue};if($item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'FILE_TYPE_CHANGED'};if($expected.ContainsKey($path)){$bytes=[IO.File]::ReadAllBytes($path);$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));if($identity-cne$expected[$path]){$retained.Add($path);$observations.Add([pscustomobject]@{path=$path;reason='CONSUMED_OBJECT_CHANGED'});continue}};$size=$item.Length;Remove-Item -LiteralPath $path -ErrorAction Stop;$removed.Add($path);$removedBytes+=$size}
            catch{Failure $path $_;$remaining.Add($path)}
        }
        foreach($path in $retained){$remaining.Add($path)}
        if($listFull){
            if($remaining.Count-or(Keep $listFull)){$remaining.Add($listFull)}
            else{try{Ordinary $listFull;$item=Entry $listFull;if($null-ne$item){if($item.PSIsContainer){throw 'FILE_TYPE_CHANGED'};$size=$item.Length;Remove-Item -LiteralPath $listFull -ErrorAction Stop;$removed.Add($listFull);$removedBytes+=$size};$listReleased=$true}catch{Failure $listFull $_;$remaining.Add($listFull)}}
        }
        foreach($path in @($directories|Sort-Object Length -Descending)){
            if($remaining.Count){$remaining.Add($path);continue}
            try{Ordinary $path;$item=Entry $path;if($null-eq$item){continue};if(-not$item.PSIsContainer){throw 'DIRECTORY_TYPE_CHANGED'};$entries=[IO.Directory]::EnumerateFileSystemEntries($path).GetEnumerator();try{if($entries.MoveNext()){throw 'DIRECTORY_NOT_EMPTY'}}finally{$entries.Dispose()};Remove-Item -LiteralPath $path -ErrorAction Stop;$directoriesRemoved.Add($path)}
            catch{Failure $path $_;$remaining.Add($path)}
        }
        if($failures.Count){$status='PARTIAL_FAILURE'}elseif($remaining.Count){$status='RETAINED'}
    }catch{
        $status='REJECTED';$kind=if($_.Exception-is[IO.IOException]-or$_.Exception-is[UnauthorizedAccessException]){'IO_ERROR'}elseif($_.Exception-is[System.Management.Automation.PSSecurityException]){'HOST_POLICY_REJECTED'}else{'FRAMEWORK_REJECTED'}
        $failures.Add([pscustomobject]@{path=$ScopeRoot;kind=$kind;errorId=$_.FullyQualifiedErrorId;message=$_.Exception.Message})
        $remaining.Clear();foreach($path in @($paths)+@($ConsumedPathListPath|Where-Object{$_})+@($EmptyDirectoryPath)){$remaining.Add($path)}
    }
    $watch.Stop()
    [pscustomobject]@{status=$status;removed=@($removed.ToArray());removedBytes=$removedBytes;alreadyAbsent=@($absent.ToArray());retained=@($retained.ToArray());remaining=@($remaining.ToArray());directoriesRemoved=@($directoriesRemoved.ToArray());pathListReleased=$listReleased;failures=@($failures.ToArray());observations=@($observations.ToArray());elapsedMs=$watch.Elapsed.TotalMilliseconds}
}

function Get-DeliveryRuntimeReferences([string]$ProjectRoot,[string]$ScopeRoot,$Values,$EvidenceContext){
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expired=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ambiguous=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $deferred=[Collections.Generic.List[object]]::new()
    $queue=[Collections.Generic.Queue[object]]::new();foreach($value in $Values){if($null-ne$value){$queue.Enqueue($value)}}
    $prefix=$ScopeRoot+[IO.Path]::DirectorySeparatorChar
    function Follow([string]$Candidate){
        if($Candidate.StartsWith('.ai-workspace/',[StringComparison]::Ordinal)){$Candidate=Join-Path $ProjectRoot $Candidate}
        if(-not[IO.Path]::IsPathFullyQualified($Candidate)){return}
        $full=[IO.Path]::GetFullPath($Candidate)
        if(-not@($EvidenceContext.Roots|Where-Object{$full.StartsWith(($_+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)}).Count){return}
        # The original evidence guard owns root-relative exclusions, protection
        # and reparse checks before metadata. Retention does not revalidate old bytes.
        $full=Resolve-AiwEvidenceObservationPath $EvidenceContext $Candidate
        if(-not$paths.Add($full)){return}
        if([IO.File]::Exists($full)-and[IO.Path]::GetExtension($full)-cin@('.json','.txt')){
            try{$linked=(Read-AiwStrictInputJson $full).Value}catch{if([IO.Path]::GetExtension($full)-ceq'.json'){throw 'RUNTIME_PROOF_JSON_UNREADABLE'};return}
            if($null-ne$linked){$queue.Enqueue($linked)}
        }
    }
    function Deferred([string]$Path,[string]$Reason){$deferred.Add([pscustomobject]@{path=$Path;reason=$Reason})}
    while($queue.Count){
        $value=$queue.Dequeue()
        if($value-is[string]){
            if($value-cmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){Follow $Matches[1];continue}
            foreach($part in $value.Split('|')){Follow ($part -replace '#\d+$','')}
        }elseif($value-is[Array]){foreach($item in $value){if($null-ne$item){$queue.Enqueue($item)}}}
        elseif($value-is[Collections.IDictionary]){foreach($key in $value.Keys){if([string]$key-cin@('forbiddenScope','forbiddenPaths','protectedScope','protectedPaths','routineExcludedPaths')){continue};if($null-ne$value[$key]){$queue.Enqueue($value[$key])}}}
        elseif($value-is[pscustomobject]){
            if($null-ne$value.PSObject.Properties['path']-and$null-ne$value.PSObject.Properties['identity']-and$value.path-is[string]-and$value.identity-is[string]){
                Follow $(if([IO.Path]::IsPathFullyQualified($value.path)){$value.path}else{Join-Path $ProjectRoot $value.path})
            }
            $consumedInput=$false
            if($null-ne$value.PSObject.Properties['inputCleanup']-and$null-ne$value.PSObject.Properties['mode']-and$null-ne$value.PSObject.Properties['status']-and$value.mode-cin@('DISCOVER','ADMIT_ACTION','FINALIZE_OUTPUT')){
                $observation=$value.inputCleanup
                if($null-ne$observation-and$null-ne$observation.PSObject.Properties['removed']-and$null-ne$observation.PSObject.Properties['alreadyAbsent']-and$null-ne$observation.PSObject.Properties['remaining']-and$observation.status-cin@('PASS','PARTIAL_FAILURE')){
                    $success=$value.status-ceq'PASS'-or($value.mode-ceq'DISCOVER'-and$value.status-ceq'EVALUATION_ONLY')
                    if($value.mode-ceq'FINALIZE_OUTPUT'){$success=$success-and$null-ne$value.PSObject.Properties['actionOutcome']-and$value.actionOutcome-cin@('PASS','OBSERVED')}
                    $failureRows=if($null-ne$observation.PSObject.Properties['failures']){@($observation.failures)}else{@()}
                    $reason=if($success){'RECOVERY_FAILURE_UNKNOWN'}else{'PRODUCER_NOT_SUCCESSFUL'}
                    $recoverable=$success
                    foreach($failure in $failureRows){
                        if($null-eq$failure.PSObject.Properties['kind']-or$failure.kind-cne'IO_ERROR'){$recoverable=$false;if($null-ne$failure.PSObject.Properties['kind']-and$failure.kind-ceq'HOST_POLICY_REJECTED'){$reason='HOST_POLICY_REJECTED'}}
                    }
                    if($recoverable){
                        $consumedInput=$true
                        # Removed/absent observations never authorize deleting a
                        # newly appearing object. Only matching IO remnants retry.
                        foreach($path in $observation.remaining){
                            if($path-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($path)){throw 'RUNTIME_INPUT_OBSERVATION_PATH'}
                            $full=Resolve-AiwEvidenceObservationPath $EvidenceContext $path
                            $rows=@($failureRows|Where-Object{$null-ne$_.PSObject.Properties['path']-and$_.path-is[string]-and$_.path.Equals($full,[StringComparison]::OrdinalIgnoreCase)-and$_.kind-ceq'IO_ERROR'})
                            $original=if($null-ne$observation.PSObject.Properties['consumedObject']){$observation.consumedObject}else{$null}
                            if($rows.Count-ne1-or$null-eq$original-or$null-eq$original.PSObject.Properties['path']-or$null-eq$original.PSObject.Properties['identity']-or$original.path-isnot[string]-or-not$original.path.Equals($full,[StringComparison]::OrdinalIgnoreCase)-or$original.identity-isnot[string]-or$original.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){
                                Follow $full;Deferred $full 'CONSUMED_OBJECT_IDENTITY_UNKNOWN';continue
                            }
                            if($ambiguous.Contains($full)){continue}
                            if($expired.ContainsKey($full)-and$expired[$full]-cne$original.identity){$expired.Remove($full)|Out-Null;$null=$ambiguous.Add($full);Follow $full;Deferred $full 'CONSUMED_OBJECT_IDENTITY_AMBIGUOUS'}
                            elseif(-not$expired.ContainsKey($full)){$expired.Add($full,$original.identity)}
                        }
                    }else{
                        foreach($path in $observation.remaining){if($path-is[string]){Deferred $path $reason}}
                        # Failed/unknown/policy-denied producer inputs remain real
                        # proof links; ordinary guarded traversal retains them.
                    }
                }
            }
            foreach($property in $value.PSObject.Properties){if($property.Name-cin@('forbiddenScope','forbiddenPaths','protectedScope','protectedPaths','routineExcludedPaths')-or($property.Name-ceq'inputCleanup'-and$consumedInput)){continue};if($null-ne$property.Value){$queue.Enqueue($property.Value)}}
        }
    }
    [pscustomobject]@{retained=@($paths|Where-Object{$_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)});expiredInputs=@($expired.Keys);expectedObjects=@(foreach($entry in $expired.GetEnumerator()){[pscustomobject]@{path=$entry.Key;identity=$entry.Value}});deferred=@($deferred.ToArray())}
}

function Complete-AiwRuntimeConsumption($Result,$Boundary,$Receipt,[string]$InputPath,
    [string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,
    [string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),$Evidence=$null){
    $explicit=$ConsumedRuntimePath.Count-or$ConsumedRuntimePathList-or$EmptyRuntimeDirectory.Count
    if($Boundary.mode-cne'FINALIZE_OUTPUT'-and-not$explicit){return $null}
    if($Boundary.mode-cne'FINALIZE_OUTPUT'-or$Result.status-cne'PASS'-or$Result.actionOutcome-cnotin@('OBSERVED','PASS')){return [pscustomobject]@{status='DEFERRED';reason='LAST_CONSUMER_NOT_COMPLETE'}}
    if($null-ne$Boundary.PSObject.Properties['deliveryContext']-and$Boundary.deliveryContext.channel-ceq'TASK_MESSAGE'-and($Boundary.deliveryContext.stage-cne'OBSERVE'-or-not$Result.delivery.delivered)){return [pscustomobject]@{status='DEFERRED';reason='DELIVERY_NOT_OBSERVED'}}
    $r=Get-DeliveryReceiptView $Receipt;$project=[IO.Path]::GetFullPath($r.sourceLocators.projectRoot)
    $segment=if($r.taskId-ceq'NOT_APPLICABLE'){$r.authorityContext.contextLocator}else{$r.taskId}
    if($segment-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){return [pscustomobject]@{status='REJECTED';reason='RUNTIME_CONTEXT_UNBOUND'}}
    $scope=[IO.Path]::GetFullPath((Join-Path $project ('.ai-workspace/runtime/'+$segment)))
    if($null-eq$Evidence-or$null-eq$Evidence.PSObject.Properties['retentionContext']){return [pscustomobject]@{status='REJECTED';failureKind='FRAMEWORK_REJECTED';reason='RUNTIME_RETENTION_CONTEXT_REQUIRED';remaining=@($ConsumedRuntimePath)}}
    $context=$Evidence.retentionContext
    $forbidden=@(foreach($ban in $context.ForbiddenPaths){
        if([IO.Path]::IsPathFullyQualified($ban)){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ban))}
        else{foreach($root in $context.Roots){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $root $ban)))}}
    })
    $consumptionWatch=[Diagnostics.Stopwatch]::StartNew()
    $values=@($Receipt,$Boundary)+@($Evidence.retentionValues)
    try{$current=Get-DeliveryRuntimeReferences $project $scope $values $context;$keep=@($InputPath)+@($RetainedRuntimePath)+@($current.retained);$ConsumedRuntimePath=@($ConsumedRuntimePath)+@($current.expiredInputs)}catch{return [pscustomobject]@{status='REJECTED';reason=$_.Exception.Message;failureKind='FRAMEWORK_REJECTED';remaining=@($ConsumedRuntimePath)}}
    if(-not$ConsumedRuntimePath.Count-and-not$ConsumedRuntimePathList-and-not$EmptyRuntimeDirectory.Count){
        if(-not$current.deferred.Count){return $null}
        return [pscustomobject]@{status='RETAINED';retained=@($current.deferred.path|Select-Object -Unique);remaining=@($current.deferred.path|Select-Object -Unique);observations=@($current.deferred)}
    }
    $release=Remove-AiwConsumedRuntimeFiles -ScopeRoot $scope -LiteralPath $ConsumedRuntimePath -ConsumedPathListPath $ConsumedRuntimePathList -EmptyDirectoryPath $EmptyRuntimeDirectory -RetainedPath $keep -ForbiddenPath $forbidden -ExpectedObject $current.expectedObjects
    if($current.deferred.Count){
        $release.retained=@(@($release.retained)+@($current.deferred.path)|Select-Object -Unique)
        $release.remaining=@(@($release.remaining)+@($current.deferred.path)|Select-Object -Unique)
        $release.observations=@($release.observations)+@($current.deferred)
        if($release.status-ceq'PASS'){$release.status='RETAINED'}
    }
    $consumptionWatch.Stop();$release|Add-Member releaseMs $release.elapsedMs;$release.elapsedMs=$consumptionWatch.Elapsed.TotalMilliseconds
    $release
}

function Write-AiwRuntimeCleanupObservation($Result){
    foreach($name in @('runtimeCleanup','inputCleanup')){
        if($null-eq$Result.PSObject.Properties[$name]){continue}
        $observation=$Result.$name;$summary=[ordered]@{kind=$name;status=$observation.status}
        foreach($field in @('reason','removed','removedBytes','retained','remaining','elapsedMs','failureKind','observations')){if($null-ne$observation.PSObject.Properties[$field]){$summary[$field]=$observation.$field}}
        if($null-ne$observation.PSObject.Properties['failures']){$summary['failures']=@($observation.failures)}
        Write-Output ('AIW-CLEANUP|'+($summary|ConvertTo-Json -Depth 15 -Compress -EscapeHandling EscapeNonAscii))
    }
}

# These are observations of supplied bytes. User provenance and host origin
# remain instruction-bound; neither a file nor a matching ID grants authority.
function Get-AiwCodexSendOutcome($HostResult,[string]$ExpectedRecipient) {
    $outcome='UNKNOWN';$recipient='NOT_APPLICABLE'
    if($HostResult-is[pscustomobject]){
        $errorField=$HostResult.PSObject.Properties['isError']
        if($null-ne$errorField-and$errorField.Value-isnot[bool]){throw 'DELIVERY_HOST_ERROR_TYPE'}
        if($null-ne$errorField-and$errorField.Value){$outcome='FAILURE'}
        elseif($null-ne$HostResult.PSObject.Properties['content']-and$HostResult.content-is[Array]){
            $ids=@(foreach($part in $HostResult.content){
                if($part-isnot[pscustomobject]-or$null-eq$part.PSObject.Properties['type']-or$part.type-cne'text'-or$null-eq$part.PSObject.Properties['text']-or$part.text-isnot[string]){continue}
                try{$value=(ConvertFrom-AiwStrictInputJson $part.text).Value}catch{continue}
                if($value-is[pscustomobject]-and$null-ne$value.PSObject.Properties['threadId']-and$value.threadId-is[string]-and-not[string]::IsNullOrWhiteSpace($value.threadId)){$value.threadId}
            })
            if($ids.Count-eq1){$recipient=$ids[0];if($recipient-ceq$ExpectedRecipient){$outcome='SUCCESS'}else{$outcome='WRONG_RECIPIENT'}}
        }
    }
    [pscustomobject]@{outcome=$outcome;observedRecipient=$recipient;hostAccepted=($outcome-ceq'SUCCESS');recipientWorkProven=$false;userAuthorizationProven=$false}
}
function Get-DeliveryReceiptView($Receipt) {
    if($null-eq$Receipt.PSObject.Properties['binding']){return $Receipt}
    $b=$Receipt.binding
    [pscustomobject]@{taskId=$b.taskId;taskIdentity=$b.taskIdentity;taskOwner=$b.taskOwner;taskActor=$b.taskActor;actor=$b.actor;actionKind=$Receipt.intentEnvelope.requestedActionKind;resultKind=$Receipt.intentEnvelope.requestedResultKind;exactPaths=@($b.exactScope);authorityContext=$b;sourceLocators=[pscustomobject]@{projectRoot=$b.projectRoot;frameworkRoot=$Receipt.sourceLocators.frameworkRoot;taskRelativePath=$Receipt.sourceLocators.taskRelativePath;authorizationPackagePath=$Receipt.sourceLocators.authorizationPackagePath}}
}
function Get-DeliveryReviewRouteQualification($Receipt,$Boundary,$Package,$ctx) {
    $r=Get-DeliveryReceiptView $Receipt
    if($r.actionKind-cne'REVIEW_ROUTE'){throw 'DELIVERY_REVIEW_ROUTE_REQUIRED'}
    $context=if($null-ne$Boundary.PSObject.Properties['deliveryContext']){$Boundary.deliveryContext}else{[pscustomobject]@{}}
    if($Package.owner-cne$r.taskOwner-or$Package.taskId-cne$r.taskId-or$Package.grantee-cne$r.actor){throw 'DELIVERY_PACKAGE_CONTEXT_DRIFT'}
    $review=$null;$writer=$null
    if($null-ne$context.PSObject.Properties['reviewPackageRef']){
            $review=Read-AiwEvidenceReference $ctx $context.reviewPackageRef -Json
            foreach($field in @('taskId','taskIdentity','owner','projectConfigIdentity','userConfirmation')){if($review.$field-cne$package.$field){throw 'DELIVERY_REVIEW_PACKAGE_DRIFT'}}
            if($package.schemaVersion-eq4){foreach($field in @('schemaVersion','repositoryId','controlRoot','executionTargetRef','expectedTargetState')){if(($review.$field|ConvertTo-Json -Compress)-cne($package.$field|ConvertTo-Json -Compress)){throw 'DELIVERY_REVIEW_TARGET_DRIFT'}}}
            if($review.actions-isnot[Array]-or$review.actions.Count-ne1-or$review.actions[0]-cne'REVIEW_EXECUTE'-or$review.reviewIndependence-cne'INDEPENDENT'-or[string]::IsNullOrWhiteSpace($review.candidateWriter)){throw 'DELIVERY_REVIEW_PACKAGE_BOUNDARY'}
            # The route actor organizes delivery; the successful author evidence
            # binds the writer. An Owner may route another writer's candidate.
            if($package.grantee-cne$package.owner-and$package.grantee-cne$review.candidateWriter){throw 'DELIVERY_REVIEW_WRITER_DRIFT'}
            if($null-ne$package.PSObject.Properties['repairReviewPlan']-and$package.repairReviewPlan.writer-cne$review.candidateWriter){throw 'DELIVERY_REVIEW_WRITER_DRIFT'}
            if((@($review.exactPaths|Sort-Object)-join"`n")-cne(@($r.exactPaths|Sort-Object)-join"`n")){throw 'DELIVERY_REVIEW_SCOPE_DRIFT'}
            $plannedScope=@(Get-AiwActionScopeObjects $package 'REVIEW_ROUTE' $ctx)
            if((@($r.exactPaths|Sort-Object)-join'|')-cne(@($plannedScope.path|Sort-Object)-join'|')){throw 'DELIVERY_REVIEW_SCOPE_NOT_GRANTED'}
            if($review.objectIdentities-isnot[Array]-or$review.objectIdentities.Count-eq0-or(@($review.objectIdentities.path|Sort-Object)-join"`n")-cne(@($r.exactPaths|Sort-Object)-join"`n")){throw 'DELIVERY_REVIEW_CANDIDATE_SET'}
            $reviewExcluded=@(Get-AiwReviewExcludedActors $review.owner $review.issuer $review.candidateWriter $review.materialContributors)
            if($review.grantee-cin$reviewExcluded){throw 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'}
        $writer=[string]$review.candidateWriter
    }elseif($null-ne$Package.PSObject.Properties['repairReviewPlan']){
        $writer=[string]$Package.repairReviewPlan.writer
        if([string]::IsNullOrWhiteSpace($writer)-or($Package.grantee-cne$Package.owner-and$Package.grantee-cne$writer)){throw 'DELIVERY_REVIEW_WRITER_DRIFT'}
        $plannedScope=@(Get-AiwActionScopeObjects $Package 'REVIEW_ROUTE' $ctx)
        if((@($r.exactPaths|Sort-Object)-join'|')-cne(@($plannedScope.path|Sort-Object)-join'|')){throw 'DELIVERY_REVIEW_SCOPE_NOT_GRANTED'}
    }else{throw 'DELIVERY_REVIEW_WRITER_REQUIRED'}
    return [pscustomobject]@{review=$review;writer=$writer}
}
function Assert-AiwReviewRoutePreparation($Receipt,$Boundary,$Evidence=$null,$Package=$null,$EvidenceContext=$null) {
    $r=Get-DeliveryReceiptView $Receipt
    if($r.actionKind-cne'REVIEW_ROUTE'){return $null}
    $effectiveForbidden=@($r.authorityContext.forbiddenScope)
    $effectiveProtected=if($null-ne$r.authorityContext.PSObject.Properties['protectedScope']){@($r.authorityContext.protectedScope)}else{@()}
    if($null-eq$Package){
        $base=New-AiwEvidenceContext $r.sourceLocators.projectRoot '' $r.sourceLocators.frameworkRoot $effectiveForbidden $effectiveProtected
        if($r.sourceLocators.authorizationPackagePath-ceq'NOT_REQUIRED'){throw 'DELIVERY_REVIEW_PACKAGE_REQUIRED'}
        $Package=Read-AiwEvidenceReference $base ([pscustomobject]@{path=$r.sourceLocators.authorizationPackagePath;identity=$r.authorityContext.authorizationIdentity}) -Json
    }
    $ctx=$EvidenceContext
    if($null-eq$ctx){$ctx=New-AiwPackageEvidenceContext $r.sourceLocators.projectRoot $Package $r.sourceLocators.frameworkRoot $effectiveForbidden -TaskPath $r.sourceLocators.taskRelativePath -ProtectedPaths $effectiveProtected}
    $qualified=Get-DeliveryReviewRouteQualification $r $Boundary $Package $ctx
    $review=$qualified.review;$writer=$qualified.writer
    # Qualification is shared with original-history validation. Current route
    # admission still reads the actual candidate and successful author evidence.
    if($null-ne$review){foreach($candidate in @(Get-AiwPackageCandidateReferences $review)){$null=Read-AiwEvidenceReference $ctx $candidate -Candidate}}
    # Writer, successful SELF and current candidates are knowable before a
    # deferred Reviewer exists. The same check serves ADMIT and final delivery.
            if($null-eq$Evidence){$Evidence=Get-AiwBoundaryEvidence $r $Boundary $ctx}
            Import-Module (Join-Path $PSScriptRoot 'ControlTransition.psm1')
            $plan=$null
            if($null-ne$Package.PSObject.Properties['qualityBinding']-and$r.sourceLocators.taskRelativePath-cne'NOT_APPLICABLE'){$plan=Get-AiwAcceptancePlan (Read-AiwControlTransitionTask $r.sourceLocators.projectRoot $r.sourceLocators.taskRelativePath).Text}
            if(Test-AiwReviewSelfCheckRequired $plan){
                $selfChecks=@(for($i=0;$i-lt$Evidence.references.Count;$i++){if($Evidence.references[$i].kind-ceq'SELF_CHECK'){$Evidence.records[$i]}})
                if($selfChecks.Count-eq0){throw 'DELIVERY_REVIEW_SELF_CHECK_REQUIRED'}
                foreach($selfCheck in $selfChecks){if($selfCheck.outcome-cne'PASS'-or$selfCheck.actor-cne$writer){throw 'DELIVERY_REVIEW_WRITER_DRIFT'}}
            }else{
                $null=Get-AiwPackageQuality $ctx $Package $plan
                if($null-eq$Boundary.PSObject.Properties['productionFinalizeRef']){throw 'QUALITY_PRODUCTION_FINALIZE_REQUIRED'}
                $current=@(Get-AiwCurrentCandidateReferences $ctx @($r.exactPaths))
                $null=Assert-AiwProductionFinalize $ctx $Boundary.productionFinalizeRef $Package $current $writer
            }
    return $review
}
function Get-DeliveryReviewRouteRecipient($Receipt,$Context,$Package,$Review) {
    $r=Get-DeliveryReceiptView $Receipt
    $recipient='UNBOUND_RECEIVER'
    if($null-ne$Package.PSObject.Properties['repairReviewPlan']){$recipient=[string]$Package.repairReviewPlan.reviewer}
    if($null-ne$Context.PSObject.Properties['reviewPackageRef']){
        if($recipient-cnotin@('UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')-and$recipient-cne$Review.grantee){throw 'DELIVERY_REVIEWER_DRIFT'}
        $recipient=[string]$Review.grantee
    }
    if($null-ne$Context.PSObject.Properties['reviewerAssignment']){
        $a=$Context.reviewerAssignment
        if($null-eq$Package.PSObject.Properties['repairReviewPlan']-or$Package.repairReviewPlan.reviewer-cne'DEFERRED_VISIBLE_REVIEWER'){throw 'DELIVERY_ASSIGNMENT_NOT_DEFERRED'}
        if((@($a.PSObject.Properties.Name|Sort-Object)-join'|')-cne(@('source','createdBy','threadId','hostId','taskId','parentPackageIdentity'|Sort-Object)-join'|')){throw 'DELIVERY_ASSIGNMENT_FIELDS'}
        if($a.source-cne'HOST_CREATE_THREAD_RESULT'-or$a.createdBy-cne$Package.grantee-or$a.taskId-cne$r.taskId-or$a.parentPackageIdentity-cne$r.authorityContext.authorizationIdentity-or[string]::IsNullOrWhiteSpace($a.hostId)){throw 'DELIVERY_ASSIGNMENT_DRIFT'}
        if($recipient-cnotin@('UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')-and$recipient-cne$a.threadId){throw 'DELIVERY_ASSIGNMENT_RECIPIENT_DRIFT'}
        $recipient=[string]$a.threadId
    }
    $excluded=@($Package.owner,$Package.issuer,$Package.grantee)
    if($null-ne$Package.PSObject.Properties['repairReviewPlan']){$excluded+=@($Package.repairReviewPlan.materialContributors)}
    if([string]::IsNullOrWhiteSpace($recipient)-or$recipient-cin(@('USER','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')+$excluded)){throw 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'}
    return $recipient
}
function Get-AiwBoundDelivery($Receipt,$Boundary,$Evidence=$null,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()) {
    $r=Get-DeliveryReceiptView $Receipt
    $isReview=$r.actionKind-cin@('REVIEW_ROUTE','REVIEW_EXECUTE')
    if($null-eq$Boundary.PSObject.Properties['deliveryContext']){
        if($isReview){throw 'DELIVERY_CONTEXT_REQUIRED'}
        return $null
    }
    $context=$Boundary.deliveryContext
    $observation=Get-AiwDeliveryObservation $context
    # Current restrictions tighten the historical scope before any linked read.
    $effectiveForbidden=@(@($r.authorityContext.forbiddenScope)+@($ForbiddenPaths)|Select-Object -Unique)
    $protectedScope=if($null-ne$r.authorityContext.PSObject.Properties['protectedScope']){$r.authorityContext.protectedScope}else{@()}
    $effectiveProtected=@(@($protectedScope)+@($ProtectedPaths)|Select-Object -Unique)
    $base=New-AiwEvidenceContext $r.sourceLocators.projectRoot '' $r.sourceLocators.frameworkRoot $effectiveForbidden $effectiveProtected
    $package=$null
    if($r.sourceLocators.authorizationPackagePath-cne'NOT_REQUIRED'){
        $package=Read-AiwEvidenceReference $base ([pscustomobject]@{path=$r.sourceLocators.authorizationPackagePath;identity=$r.authorityContext.authorizationIdentity}) -Json
        if($package.owner-cne$r.taskOwner-or$package.taskId-cne$r.taskId-or$package.grantee-cne$r.actor){throw 'DELIVERY_PACKAGE_CONTEXT_DRIFT'}
    }
    $ctx=New-AiwPackageEvidenceContext $r.sourceLocators.projectRoot $package $r.sourceLocators.frameworkRoot $effectiveForbidden -TaskPath $r.sourceLocators.taskRelativePath -ProtectedPaths $effectiveProtected
    $preparedReview=if($r.actionKind-ceq'REVIEW_ROUTE'){Assert-AiwReviewRoutePreparation $r $Boundary $Evidence $package $ctx}else{$null}
    $recipient=[string]$r.taskOwner;$reason='TASK_OWNER'
    if($r.taskOwner-ceq'NOT_APPLICABLE'-or$r.actor-ceq$r.taskOwner){$recipient='USER';$reason='CURRENT_USER_RESPONSE'}
    if($r.actionKind-ceq'REVIEW_EXECUTE'){
        if($null-eq$Evidence){$Evidence=Get-AiwBoundaryEvidence $r $Boundary $ctx}
        $verdicts=@(for($i=0;$i-lt$Evidence.references.Count;$i++){if($Evidence.references[$i].kind-ceq'REVIEW_VERDICT'){$Evidence.records[$i]}})
        if($verdicts.Count-ne1){throw 'DELIVERY_VERDICT_REQUIRED'}
        $recipient=[string]$package.owner;$reason='REVIEW_TO_OWNER'
        if($verdicts[0].outcome-cin@('CHANGES_REQUESTED','REJECTED')){
            if($null-eq$package.PSObject.Properties['candidateWriter']-or[string]::IsNullOrWhiteSpace($package.candidateWriter)){throw 'DELIVERY_REPAIR_WRITER_REQUIRED'}
            $recipient=[string]$package.candidateWriter;$reason='FINDING_TO_WRITER'
            $flat=Get-AiwPlannedReviewFlatVerdict $ctx $package $verdicts[0]
            if($null-ne$flat){
                $parent=Read-AiwEvidenceReference $ctx ([pscustomobject]@{path=$package.repairReviewBinding.parentPackagePath;identity=$package.repairReviewBinding.parentPackageIdentity}) -Json
                if($flat.value.scopeChanged-or$flat.value.decisionChanged-or@($flat.value.findingPaths|Where-Object{$_-cnotin$parent.exactPaths}).Count){$recipient=[string]$package.owner;$reason='REVIEW_PLAN_BOUNDARY_TO_OWNER'}
            }

        }
    }elseif($r.actionKind-ceq'REVIEW_ROUTE'){
        $recipient=Get-DeliveryReviewRouteRecipient $r $context $package $preparedReview;$reason='ROUTE_TO_REVIEWER'
    }
    foreach($field in @('reviewPackageRef','reviewerAssignment')){if($r.actionKind-cne'REVIEW_ROUTE'-and$null-ne$context.PSObject.Properties[$field]){throw 'DELIVERY_ROUTE_REFERENCE_UNEXPECTED'}}
    $userDecision='NOT_REQUIRED'
    if($null-ne$context.PSObject.Properties['userDecisionRef']){
        if($Boundary.publicDecisionIdentity-cne$context.userDecisionRef.identity){throw 'DELIVERY_USER_DECISION_UNBOUND'}
        $null=Read-AiwEvidenceReference $ctx $context.userDecisionRef
        $userDecision=$context.userDecisionRef.identity
        if($context.channel-ceq'NATIVE_RESPONSE'){
            if($context.expectedRecipient-cne'USER'){throw 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'}
            $recipient='USER';$reason='EXPLICIT_USER_NATIVE_DELIVERY'
        }else{
            $recipient=[string]$context.expectedRecipient
            if([string]::IsNullOrWhiteSpace($recipient)-or$recipient-cne$recipient.Trim()-or$recipient-cin@('USER','NOT_APPLICABLE','NOT_REQUIRED','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')){throw 'DELIVERY_EXPLICIT_TASK_RECIPIENT_REQUIRED'}
            $reason='EXPLICIT_USER_TASK_DELIVERY'
        }
    }
    $channel=if($recipient-ceq'USER'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'}
    if($context.expectedRecipient-cne$recipient-or$context.channel-cne$channel){throw 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'}
    if($context.stage-ceq'OBSERVE'){
        if($context.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'DELIVERY_HOST_REFERENCE_REQUIRED'}
        $hostResult=Read-AiwEvidenceReference $ctx ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
        $actual=Get-AiwCodexSendOutcome $hostResult $recipient
        if($actual.outcome-ceq'WRONG_RECIPIENT'-or$actual.outcome-cne$context.outcome-or$actual.observedRecipient-cne$context.observedRecipient){throw 'DELIVERY_HOST_RESULT_MISMATCH'}
    }
    [pscustomobject]@{delivery=$observation;consumer=[pscustomobject]@{recipient=$recipient;channel=$channel;reason=$reason;authorizationIdentity=$r.authorityContext.authorizationIdentity;userDecisionIdentity=$userDecision;userAuthorizationProven=$false;recipientWorkProven=$false;evidenceCeiling='INSTRUCTION_BOUND'};closureSatisfied=($channel-ceq'NATIVE_RESPONSE'-or$observation.delivered)}
}
function Invoke-AiwDeliveryBoundary($Reference,[string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,
    [string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@()) {
    if($Reference-isnot[pscustomobject]-or(@($Reference.PSObject.Properties.Name|Sort-Object)-join'|')-cne'identity|path'-or$Reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'-or-not[IO.Path]::IsPathRooted($Reference.path)){throw 'DELIVERY_BOUNDARY_REFERENCE'}
    $path=[IO.Path]::GetFullPath($Reference.path);$cursor=Get-Item -LiteralPath $path -Force
    while($null-ne$cursor){if($cursor.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'DELIVERY_BOUNDARY_REPARSE'};$cursor=if($cursor-is[IO.FileInfo]){$cursor.Directory}else{$cursor.Parent}}
    $bytes=[IO.File]::ReadAllBytes($path);$id=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if($id-cne$Reference.identity){throw 'DELIVERY_BOUNDARY_DRIFT'}
    $inputValue=(Read-AiwStrictInputJson $path).Value
    if($inputValue.mode-cne'FINALIZE_OUTPUT'-or$null-eq$inputValue.PSObject.Properties['deliveryContext']){throw 'DELIVERY_FINAL_BOUNDARY_REQUIRED'}
    # Reuse the exact current final-boundary validator, including source drift,
    # typed evidence and the same consumer resolver. No second authority model.
    Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementBoundary.psm1')
    $response=Invoke-AiwProcessRequirementBoundary -InputPath $path -AsJson -ConsumedRuntimePath $ConsumedRuntimePath -ConsumedRuntimePathList $ConsumedRuntimePathList -EmptyRuntimeDirectory $EmptyRuntimeDirectory -RetainedRuntimePath $RetainedRuntimePath
    $value=($response.output-join"`n")|ConvertFrom-Json -Depth 100
    $value|Add-Member ackRequired $false;$value|Add-Member polling $false
    return $value
}
Export-ModuleMember -Function Get-AiwCodexSendOutcome,Get-AiwBoundDelivery,Invoke-AiwDeliveryBoundary,Assert-AiwReviewRoutePreparation,Remove-AiwConsumedRuntimeFiles,Complete-AiwRuntimeConsumption,Write-AiwRuntimeCleanupObservation
