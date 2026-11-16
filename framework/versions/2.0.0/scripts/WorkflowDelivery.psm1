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
        [string[]]$EmptyDirectoryPath=@(),[string[]]$RetainedPath=@(),[string[]]$ForbiddenPath=@(),[object[]]$ExpectedObject=@(),[switch]$PreflightOnly)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $removed=[Collections.Generic.List[string]]::new();$absent=[Collections.Generic.List[string]]::new()
    $retained=[Collections.Generic.List[string]]::new();$failures=[Collections.Generic.List[object]]::new()
    $remaining=[Collections.Generic.List[string]]::new();$directoriesRemoved=[Collections.Generic.List[string]]::new()
    [long]$removedBytes=0;$listReleased=$false;$status='PASS';$listMembersKnown=-not[bool]$ConsumedPathListPath
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
            $paths+=@($members)
            $listMembersKnown=$true
            foreach($member in $members){if($member-isnot[string]-or[string]::IsNullOrWhiteSpace($member)){throw 'STRING_FILE_PATH_REQUIRED'};if((Exact $member).Equals($listFull,[StringComparison]::OrdinalIgnoreCase)){throw 'PATH_LIST_CANNOT_LIST_ITSELF'}}
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
            try{$checked.Clear();Ordinary $path;$item=Entry $path;if($null-eq$item){$absent.Add($path);continue};if($item.PSIsContainer-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'FILE_TYPE_CHANGED'};if($expected.ContainsKey($path)){$bytes=[IO.File]::ReadAllBytes($path);$identity=$bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));if($identity-cne$expected[$path]){$retained.Add($path);$observations.Add([pscustomobject]@{path=$path;reason='CONSUMED_OBJECT_CHANGED'});continue}};if($PreflightOnly){continue};$size=$item.Length;Remove-Item -LiteralPath $path -ErrorAction Stop;$removed.Add($path);$removedBytes+=$size}
            catch{Failure $path $_;$remaining.Add($path)}
        }
        foreach($path in $retained){$remaining.Add($path)}
        if($listFull-and-not$PreflightOnly){
            if($remaining.Count-or(Keep $listFull)){$remaining.Add($listFull)}
            else{try{Ordinary $listFull;$item=Entry $listFull;if($null-ne$item){if($item.PSIsContainer){throw 'FILE_TYPE_CHANGED'};$size=$item.Length;Remove-Item -LiteralPath $listFull -ErrorAction Stop;$removed.Add($listFull);$removedBytes+=$size};$listReleased=$true}catch{Failure $listFull $_;$remaining.Add($listFull)}}
        }
        foreach($path in @($directories|Sort-Object Length -Descending)){
            if($PreflightOnly){continue}
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
    [pscustomobject]@{status=$status;removed=@($removed.ToArray());removedBytes=$removedBytes;alreadyAbsent=@($absent.ToArray());retained=@($retained.ToArray());remaining=@($remaining.ToArray());directoriesRemoved=@($directoriesRemoved.ToArray());pathListReleased=$listReleased;pathListMembersKnown=$listMembersKnown;preflightOnly=[bool]$PreflightOnly;failures=@($failures.ToArray());observations=@($observations.ToArray());elapsedMs=$watch.Elapsed.TotalMilliseconds}
}

function Get-DeliveryProducerRemnants($Producers,[string]$ScopeRoot){
    $candidates=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $blocked=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $deferred=[Collections.Generic.List[object]]::new()
    foreach($producer in $Producers){
        if($null-eq$producer.result.PSObject.Properties['inputCleanup']-or$null-eq$producer.result.inputCleanup){continue}
        $observation=$producer.result.inputCleanup
        foreach($field in @('removed','alreadyAbsent')){if($null-ne$observation.PSObject.Properties[$field]){foreach($path in $observation.$field){if($path-is[string]-and[IO.Path]::IsPathFullyQualified($path)){$full=[IO.Path]::GetFullPath($path);$null=$blocked.Add($full);$null=$candidates.Remove($full)}}}}
        if($null-eq$observation.PSObject.Properties['remaining']){continue}
        foreach($path in $observation.remaining){
            if($path-isnot[string]-or-not[IO.Path]::IsPathFullyQualified($path)){throw 'RUNTIME_INPUT_OBSERVATION_PATH'}
            $full=[IO.Path]::GetFullPath($path);$reason='RECOVERY_FAILURE_UNKNOWN'
            $rows=if($null-ne$observation.PSObject.Properties['failures']){@($observation.failures|Where-Object{$null-ne$_.PSObject.Properties['path']-and$_.path-is[string]-and$_.path.Equals($full,[StringComparison]::OrdinalIgnoreCase)})}else{@()}
            $original=if($null-ne$observation.PSObject.Properties['consumedObject']){$observation.consumedObject}else{$null}
            $eligible=$null-ne$observation.PSObject.Properties['status']-and$observation.status-cin@('PARTIAL_FAILURE','REJECTED')-and$rows.Count-eq1-and$null-ne$rows[0].PSObject.Properties['kind']-and$rows[0].kind-ceq'IO_ERROR'
            if($eligible){
                $eligible=$null-ne$original-and$null-ne$original.PSObject.Properties['path']-and$null-ne$original.PSObject.Properties['identity']-and$original.path-is[string]-and$original.path.Equals($full,[StringComparison]::OrdinalIgnoreCase)-and$original.identity-is[string]-and$original.identity-cmatch'^\d+\|[A-F0-9]{64}$'
                $reason='CONSUMED_OBJECT_IDENTITY_UNKNOWN'
            }elseif(@($rows|Where-Object{$null-ne$_.PSObject.Properties['kind']-and$_.kind-ceq'HOST_POLICY_REJECTED'}).Count){$reason='HOST_POLICY_REJECTED'}
            if($eligible-and-not$full.StartsWith($ScopeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$eligible=$false;$reason='OUTSIDE_CURRENT_RUNTIME'}
            if($eligible-and$candidates.ContainsKey($full)-and$candidates[$full]-cne$original.identity){$eligible=$false;$reason='CONSUMED_OBJECT_IDENTITY_AMBIGUOUS'}
            if(-not$eligible){$null=$candidates.Remove($full);$null=$blocked.Add($full);$deferred.Add([pscustomobject]@{path=$full;reason=$reason})}
            elseif(-not$blocked.Contains($full)-and-not$candidates.ContainsKey($full)){$candidates.Add($full,$original.identity)}
        }
    }
    [pscustomobject]@{paths=@($candidates.Keys);expectedObjects=@(foreach($entry in $candidates.GetEnumerator()){[pscustomobject]@{path=$entry.Key;identity=$entry.Value}});deferred=@($deferred.ToArray())}
}

function Get-DeliveryRuntimeReferences([string]$ProjectRoot,[string]$ScopeRoot,$Values,$EvidenceContext,$VerifiedProducers=@(),[string[]]$TraversalLeaves=@()){
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expanded=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expandedDocuments=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $verifiedResults=[Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    foreach($producer in $VerifiedProducers){$null=$verifiedResults.Add($producer.result)}
    $queue=[Collections.Generic.Queue[object]]::new()
    foreach($value in $Values){if($null-ne$value){$queue.Enqueue([pscustomobject]@{value=$value;field='ROOT'})}}
    $prefix=$ScopeRoot+[IO.Path]::DirectorySeparatorChar
    function Follow([string]$Candidate,$Reference=$null,[switch]$Expand,[string]$Kind=''){
        if(-not[IO.Path]::IsPathFullyQualified($Candidate)){$Candidate=Join-Path $ProjectRoot $Candidate}
        $full=[IO.Path]::GetFullPath($Candidate)
        if(-not@($EvidenceContext.Roots|Where-Object{$full.StartsWith(($_+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)}).Count){return}
        $full=Resolve-AiwEvidenceObservationPath $EvidenceContext $full
        $null=$paths.Add($full)
        # Artifact/typed references are leaves. Only an explicit existing
        # continuation/recovery field requests another known-format object.
        if(-not$Expand-or$full-in$TraversalLeaves){return}
        if($null-eq$Reference-or(-not$Kind-and-not[IO.File]::Exists($full))){return}
        if($expandedDocuments.ContainsKey($full)){
            $observed=$expandedDocuments[$full]
            if($observed.identity-cne$Reference.identity){throw 'RUNTIME_REFERENCE_IDENTITY_CONFLICT'}
            $linked=$observed.document
        }else{
            try{$linked=Read-AiwEvidenceReference $EvidenceContext $Reference -Json}
            catch{throw ('RUNTIME_PROOF_JSON_UNREADABLE|'+$full+'|'+$_.Exception.Message)}
            $expandedDocuments.Add($full,[pscustomobject]@{identity=$Reference.identity;document=$linked})
        }
        if($linked-isnot[pscustomobject]){throw ('RUNTIME_RECOVERY_OBJECT_REQUIRED|'+$full)}
        switch($Kind){
            OPERATION{if($linked.schemaVersion-ne5-or$linked.receiptType-cne'PROCESS_REQUIREMENTS_OPERATION'-or$null-eq$linked.PSObject.Properties['operation']){throw 'RUNTIME_OPERATION_FORMAT'}}
            RULE_READ{if($linked.schemaVersion-ne5-or$linked.mode-cne'DISCOVER'-or$null-eq$linked.PSObject.Properties['ruleRead']-or$null-ne$linked.PSObject.Properties['ruleReadRef']){throw 'RUNTIME_DIRECT_FULL_FORMAT'}}
            PREPARED_INPUT{if($linked.schemaVersion-ne4-or$linked.mode-cne'FINALIZE_OUTPUT'-or$null-eq$linked.PSObject.Properties['deliveryContext']-or$linked.deliveryContext.stage-cne'PREPARE'){throw 'RUNTIME_PREPARED_INPUT_FORMAT'}}
            PREPARED_RESULT{if($linked.mode-cne'FINALIZE_OUTPUT'-or$linked.status-cne'BLOCKED'-or$null-eq$linked.PSObject.Properties['delivery']-or$linked.delivery.status-cne'READY_TO_SEND'){throw 'RUNTIME_PREPARED_RESULT_FORMAT'}}
        }
        if(-not$expanded.Add($full)){return}
        $queue.Enqueue([pscustomobject]@{value=$linked;field='RECOVERY'})
    }
    $containers=@('context','requestContext','acceptancePlan','predecessorRef','closureFinalize','operation','currentOperation','construction','sourceLocators','authorityContext','binding','acceptanceBinding','prerequisiteConsumption','evidenceConsumption','stages','qualityBinding','subject','repairReviewPlan','repairReviewBinding','receiverBinding','sourcePublicationBinding','acceptedOutcomeBinding','assuranceConsumption','additionalConsumption','assuranceEvidence','additionalEvidence','originalFinalize','mappings','deliveryContext','inputCleanup','consumedObject','postObjectIdentities','objectIdentities')
    $pathFields=@('discoverReceiptPath','authorizationPackagePath','continuationReceiptPath','parentPackagePath','verdictFinalizeInputPath','verdictFinalizeResultPath','repairFinalizeInputPath','repairFinalizeResultPath','productionFinalizeInputPath','productionFinalizeResultPath','sourceDiscoverReceiptPath','previousReceiptPath','authorizationParentPath')
    while($queue.Count){
        $item=$queue.Dequeue();$value=$item.value
        if($value-is[string]){
            # A caller-supplied exact locator is a leaf. Prose/command strings
            # are never split on pipes or interpreted as dependency programs.
            if($item.field-ceq'ROOT'-and($value.StartsWith('.ai-workspace/',[StringComparison]::Ordinal)-or[IO.Path]::IsPathFullyQualified($value))){Follow $value}
            continue
        }
        if($value-is[Array]){foreach($child in $value){if($null-ne$child){$queue.Enqueue([pscustomobject]@{value=$child;field=$item.field})}};continue}
        if($value-is[Collections.IDictionary]){$value=[pscustomobject]$value}
        if($value-isnot[pscustomobject]){continue}
        if($null-ne$value.PSObject.Properties['path']-and$null-ne$value.PSObject.Properties['identity']-and$value.path-is[string]-and$value.identity-is[string]){Follow $value.path;continue}
        foreach($property in $value.PSObject.Properties){
            $name=$property.Name;$child=$property.Value
            if($null-eq$child){continue}
            if($name-ceq'inputCleanup'-and$verifiedResults.Contains($value)){continue}
            if($name-cin@('operationRef','ruleReadRef')){
                if($child-isnot[pscustomobject]-or(@($child.PSObject.Properties.Name|Sort-Object)-join'|')-cne'identity|path'-or$child.path-isnot[string]-or$child.identity-isnot[string]-or$child.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RUNTIME_OPERATION_REFERENCE_FIELDS'}
                Follow $child.path $child -Expand -Kind $(if($name-ceq'operationRef'){'OPERATION'}else{'RULE_READ'})
            }elseif($name-ceq'preparedDeliveryRef'){
                if($child-isnot[pscustomobject]-or(@($child.PSObject.Properties.Name|Sort-Object)-join'|')-cne'inputRef|resultRef'){throw 'RUNTIME_PREPARED_REFERENCE_FIELDS'}
                foreach($side in @('inputRef','resultRef')){
                    $reference=$child.$side
                    if($reference-isnot[pscustomobject]-or(@($reference.PSObject.Properties.Name|Sort-Object)-join'|')-cne'identity|path'-or$reference.path-isnot[string]-or$reference.identity-isnot[string]-or$reference.identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RUNTIME_PREPARED_REFERENCE_FIELDS'}
                    Follow $reference.path $reference -Expand -Kind $(if($side-ceq'inputRef'){'PREPARED_INPUT'}else{'PREPARED_RESULT'})
                }
            }elseif($name-cin$pathFields-and$child-is[string]-and$child-cnotin@('NOT_REQUIRED','NOT_APPLICABLE')){
                $identityName=$name.Substring(0,$name.Length-4)+'Identity'
                $identity=if($null-ne$value.PSObject.Properties[$identityName]){[string]$value.$identityName}else{''}
                $ref=if($identity-cmatch'^\d+\|[A-F0-9]{64}$'){[pscustomobject]@{path=$child;identity=$identity}}else{$null}
                Follow $child $ref -Expand:($null-ne$ref)
            }elseif($name-ceq'evidence'-and$item.field-ceq'deliveryContext'-and$child-is[string]-and$child-cmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){
                Follow $Matches[1]
            }elseif($name-cin$containers-or$name-cmatch'(?:Ref|Refs)$'){
                $queue.Enqueue([pscustomobject]@{value=$child;field=$name})
            }elseif($item.field-ceq'inputCleanup'-and$name-cin@('remaining','removed','alreadyAbsent')){
                foreach($path in $child){if($path-is[string]){Follow $path}}
            }
        }
    }
    [pscustomobject]@{retained=@($paths|Where-Object{$_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)})}
}

function Complete-AiwRuntimeConsumption($Result,$Boundary,$Receipt,[string]$InputPath,
    [string[]]$ConsumedRuntimePath=@(),[string]$ConsumedRuntimePathList,
    [string[]]$EmptyRuntimeDirectory=@(),[string[]]$RetainedRuntimePath=@(),$Evidence=$null){
    $explicit=$ConsumedRuntimePath.Count-or$ConsumedRuntimePathList-or$EmptyRuntimeDirectory.Count
    if($Boundary.mode-cne'FINALIZE_OUTPUT'-and-not$explicit){return $null}
    if($Boundary.mode-cne'FINALIZE_OUTPUT'-or$Result.status-cne'PASS'-or$Result.actionOutcome-cnotin@('OBSERVED','PASS')){return [pscustomobject]@{status='DEFERRED';reason='LAST_CONSUMER_NOT_COMPLETE'}}
    if($null-ne$Boundary.PSObject.Properties['deliveryContext']-and$Boundary.deliveryContext.channel-ceq'TASK_MESSAGE'-and($Boundary.deliveryContext.stage-cne'OBSERVE'-or-not$Result.delivery.delivered)){return [pscustomobject]@{status='DEFERRED';reason='DELIVERY_NOT_OBSERVED'}}
    $producers=@(if($null-ne$Evidence-and$null-ne$Evidence.PSObject.Properties['retentionProducers']){$Evidence.retentionProducers})
    # No historical search is needed to discover that there is no work.
    if(-not$explicit-and-not$producers.Count){return $null}
    $consumptionWatch=[Diagnostics.Stopwatch]::StartNew()
    $remnants=$null
    try{
        $r=Get-DeliveryReceiptView $Receipt;$project=[IO.Path]::GetFullPath($r.sourceLocators.projectRoot)
        $segment=if($r.taskId-ceq'NOT_APPLICABLE'){$r.authorityContext.contextLocator}else{$r.taskId}
        if($segment-cnotmatch'^[0-9A-Za-z][0-9A-Za-z._-]*$'){throw 'RUNTIME_CONTEXT_UNBOUND'}
        $scope=[IO.Path]::GetFullPath((Join-Path $project ('.ai-workspace/runtime/'+$segment)))
        $remnants=Get-DeliveryProducerRemnants $producers $scope
        $ConsumedRuntimePath=@($ConsumedRuntimePath)+@($remnants.paths)
        if(-not$explicit-and-not$remnants.paths.Count){
            if(-not$remnants.deferred.Count){return $null}
            $deferredPaths=@($remnants.deferred.path|Select-Object -Unique)
            return [pscustomobject]@{status='RETAINED';retained=$deferredPaths;remaining=$deferredPaths;observations=@($remnants.deferred)}
        }
        if($null-eq$Evidence-or$null-eq$Evidence.PSObject.Properties['retentionContext']){throw 'RUNTIME_RETENTION_CONTEXT_REQUIRED'}
        $context=$Evidence.retentionContext
        $forbidden=@(foreach($ban in $context.ForbiddenPaths){
            if([IO.Path]::IsPathFullyQualified($ban)){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ban))}
            else{foreach($root in $context.Roots){[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $root $ban)))}}
        })
        $values=@($Receipt,$Boundary)+@($Evidence.retentionValues)
        foreach($producer in $producers){$values+=@($producer.source,$producer.input,$producer.result)}
        $current=Get-DeliveryRuntimeReferences $project $scope $values $context $producers
        $keep=@($InputPath)+@($RetainedRuntimePath)+@($current.retained)+@($remnants.deferred|ForEach-Object path)
    }catch{
        $remaining=@($ConsumedRuntimePath)+@($ConsumedRuntimePathList|Where-Object{$_})+@($EmptyRuntimeDirectory)
        if($null-ne$remnants){$remaining+=@($remnants.deferred|ForEach-Object path)}
        return [pscustomobject]@{status='REJECTED';reason=$_.Exception.Message;failureKind='FRAMEWORK_REJECTED';remaining=@($remaining|Select-Object -Unique);pathListMembersKnown=(-not[bool]$ConsumedRuntimePathList)}
    }
    $release=Remove-AiwConsumedRuntimeFiles -ScopeRoot $scope -LiteralPath $ConsumedRuntimePath -ConsumedPathListPath $ConsumedRuntimePathList -EmptyDirectoryPath $EmptyRuntimeDirectory -RetainedPath $keep -ForbiddenPath $forbidden -ExpectedObject $remnants.expectedObjects
    if($remnants.deferred.Count){
        $release.retained=@(@($release.retained)+@($remnants.deferred.path)|Select-Object -Unique)
        $release.remaining=@(@($release.remaining)+@($remnants.deferred.path)|Select-Object -Unique)
        $release.observations=@($release.observations)+@($remnants.deferred)
        if($release.status-ceq'PASS'){$release.status='RETAINED'}
    }
    $consumptionWatch.Stop();$release|Add-Member releaseMs $release.elapsedMs;$release.elapsedMs=$consumptionWatch.Elapsed.TotalMilliseconds
    $release
}

function Invoke-AiwRuntimeMaintenance($Request,[string]$RequestPath=''){
    $project=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Request.projectRoot))
    $framework=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
    $ctx=New-AiwEvidenceContext $project '' $framework
    $admit=Read-AiwEvidenceReference $ctx $Request.admitInputRef -Json
    if($admit.schemaVersion-ne3-or$admit.mode-cne'ADMIT_ACTION'-or$null-ne$admit.PSObject.Properties['actionRebind']){throw 'RUNTIME_MAINTENANCE_ORIGINAL_ADMIT_REQUIRED'}
    $compactRef=[pscustomobject]@{path=$admit.discoverReceiptPath;identity=$admit.expectedDiscoverReceiptIdentity}
    $compact=Read-AiwEvidenceReference $ctx $compactRef -Json
    $r=Get-DeliveryReceiptView $compact
    if($r.actionKind-cne'CONTROL_WRITE'-or$r.authorityContext.contextType-cne'TASK'-or-not([IO.Path]::GetFullPath($r.sourceLocators.projectRoot)).Equals($project,[StringComparison]::OrdinalIgnoreCase)-or-not([IO.Path]::GetFullPath($r.sourceLocators.frameworkRoot)).Equals($framework,[StringComparison]::OrdinalIgnoreCase)){throw 'RUNTIME_MAINTENANCE_SOURCE_OR_ACTION_DRIFT'}
    if([string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)-or$r.actor-cne$env:CODEX_THREAD_ID){throw 'RUNTIME_MAINTENANCE_CURRENT_ACTOR_REQUIRED'}
    # Install the original current protection before following any further refs.
    $ctx=New-AiwEvidenceContext $project '' $framework (@($r.authorityContext.forbiddenScope)+@($r.authorityContext.protectedScope))
    $packageRef=[pscustomobject]@{path=$r.sourceLocators.authorizationPackagePath;identity=$r.authorityContext.authorizationIdentity}
    $package=Read-AiwEvidenceReference $ctx $packageRef -Json
    if(($package.schemaVersion-ne1-and-not($package.schemaVersion-eq2-and$package.repositoryId-ceq'CONTROL'))-or@($package.actions).Count-ne1-or$package.actions[0]-cne'CONTROL_WRITE'-or$package.lifecycle-cne'ACTIVE'){throw 'RUNTIME_MAINTENANCE_PURE_CONTROL_REQUIRED'}
    foreach($field in @('continuationPlan','transitionPlan','repairReviewPlan','sourcePublicationBinding','acceptanceBinding','externalBinding','receiverBinding','reviewRouteBinding')){if($null-ne$package.PSObject.Properties[$field]){throw 'RUNTIME_MAINTENANCE_SPECIAL_ACTION_DENIED'}}
    if($r.sourceLocators.taskRelativePath-cnotmatch'^\.ai-workspace/tasks/active/[^/]+\.md$'){throw 'RUNTIME_MAINTENANCE_ACTIVE_TASK_REQUIRED'}
    $taskRef=[pscustomobject]@{path=$r.sourceLocators.taskRelativePath;identity=$r.taskIdentity}
    $taskPath=Read-AiwEvidenceReference $ctx $taskRef
    $taskText=[IO.File]::ReadAllText($taskPath)
    if($taskText-cnotmatch'(?m)^- Status: ACTIVE\r?$'-or$taskText-cnotmatch'(?m)^- Range summary:[^\r\n]*lifecycle=ACTIVE;'){throw 'RUNTIME_MAINTENANCE_ACTIVE_TASK_REQUIRED'}
    if($Request.retainedRefs-isnot[Array]-or$Request.retainedPaths-isnot[Array]){throw 'RUNTIME_MAINTENANCE_RETAINED_ARRAY_REQUIRED'}
    $files=[Collections.Generic.List[string]]::new();$expected=[Collections.Generic.List[object]]::new()
    foreach($path in $package.exactPaths){
        if($path-isnot[string]-or$path-cnotmatch'^\.ai-workspace/(runtime|tmp)/[^/].+') {throw 'RUNTIME_MAINTENANCE_FILE_SCOPE'}
        $rows=@($package.objectIdentities|Where-Object path -CEQ $path)
        if($rows.Count-ne1-or$rows[0].identity-cnotmatch'^\d+\|[A-F0-9]{64}$'){throw 'RUNTIME_MAINTENANCE_EXISTING_FILE_REQUIRED'}
        $full=Read-AiwEvidenceReference $ctx $rows[0] -Candidate
        $files.Add($full);$expected.Add([pscustomobject]@{path=$full;identity=$rows[0].identity})
    }
    if(-not$files.Count){throw 'RUNTIME_MAINTENANCE_EMPTY_SCOPE'}
    $admitPath=Read-AiwEvidenceReference $ctx $Request.admitInputRef
    $keep=@($admitPath,(Read-AiwEvidenceReference $ctx $compactRef),(Read-AiwEvidenceReference $ctx $packageRef),$taskPath)
    if($RequestPath){$keep+=Resolve-AiwEvidenceObservationPath $ctx $RequestPath}
    foreach($path in $Request.retainedPaths){if($path-isnot[string]-or[string]::IsNullOrWhiteSpace($path)){throw 'RUNTIME_MAINTENANCE_RETAINED_PATH'};$keep+=Resolve-AiwEvidenceObservationPath $ctx $path}
    foreach($ref in $Request.retainedRefs){$keep+=Read-AiwEvidenceReference $ctx $ref}
    $configPath=Resolve-AiwEvidenceObservationPath $ctx '.ai-workspace/project.json'
    $config=(Read-AiwStrictInputJson $configPath).Value
    # The current authorization's deletion subjects are not dependency refs.
    # These three exact, already read chain files remain retained leaves.
    $chainLeaves=@($keep[0..2])
    $values=@($r.sourceLocators,$admit,$package.userConfirmation,$config,(Get-AiwAcceptancePlan $taskText))+@($Request.retainedRefs)
    # Retain the three exact journals consumed by the current adoption reader.
    # Keep these self-contained recovery originals as leaves, without replaying proofs.
    foreach($relative in @('.ai-workspace/controller.json','.ai-workspace/process-policy.json','.ai-workspace/corrections.json',('.ai-workspace/upgrade-recovery/'+$config.frameworkVersion+'/state.json'),
        '.ai-workspace/runtime/project-adoption/register/state.json',
        '.ai-workspace/runtime/project-adoption/upgrade/state.json',
        '.ai-workspace/runtime/project-adoption/refresh/state.json')){
        $full=Resolve-AiwEvidenceObservationPath $ctx $relative
        if([IO.File]::Exists($full)){$keep+=$full;$values+=[pscustomobject]@{path=$full;identity=(Get-AiwFileIdentity $full)}}
    }
    $runtime=Join-Path $project '.ai-workspace/runtime';$tmp=Join-Path $project '.ai-workspace/tmp'
    $references=Get-DeliveryRuntimeReferences $project (Join-Path $project '.ai-workspace') $values $ctx @() $chainLeaves
    $keep+=@($references.retained)
    $forbidden=@($ctx.ForbiddenPaths)
    $releases=[Collections.Generic.List[object]]::new()
    $preflight=@(foreach($root in @($runtime,$tmp)){
        $members=@($files|Where-Object{$_.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)})
        if($members.Count){Remove-AiwConsumedRuntimeFiles -ScopeRoot $root -LiteralPath $members -RetainedPath $keep -ForbiddenPath $forbidden -ExpectedObject @($expected|Where-Object{$_.path-in$members}) -PreflightOnly}
    })
    if(@($preflight|Where-Object status -CNE 'PASS').Count){
        return [pscustomobject]@{status='REJECTED';reason='RUNTIME_MAINTENANCE_PREFLIGHT';actor=$r.actor;taskId=$r.taskId;removed=@();removedBytes=0;alreadyAbsent=@();retained=@($preflight|ForEach-Object retained);remaining=@($files);failures=@($preflight|ForEach-Object failures);observations=@($preflight|ForEach-Object observations);admission=$null;postimages=@()}
    }
    # The maintenance layout must enter its fixed root adapter, including the
    # complete schema2 checker and topology check. No version-level bypass.
    if($config.controlPlaneLayout-ceq'framework-maintenance-sibling'){
        if($package.schemaVersion-ne2){throw 'RUNTIME_MAINTENANCE_CONTROL_PACKAGE_REQUIRED'}
        $entry=Resolve-AiwEvidenceObservationPath $ctx (Join-Path $framework 'scripts/resolve-framework-maintenance-process-requirements.ps1')
        $output=@(& (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -File $entry -InputPath $admitPath -AsJson 2>&1|ForEach-Object{[string]$_});$exitCode=$LASTEXITCODE
    }elseif($config.controlPlaneLayout-ceq'repo-local'){
        if($package.schemaVersion-ne1){throw 'RUNTIME_MAINTENANCE_LOCAL_PACKAGE_REQUIRED'}
        Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementBoundary.psm1')
        $response=Invoke-AiwProcessRequirementBoundary -InputPath $admitPath -AsJson;$output=@($response.output);$exitCode=$response.exitCode
    }else{throw 'RUNTIME_MAINTENANCE_LAYOUT'}
    $admission=ConvertFrom-AiwStrictInputJson ($output-join"`n")
    if($exitCode-ne0-or$admission.Value.status-cne'PASS'){throw ('RUNTIME_MAINTENANCE_ADMIT_FAILED|'+($output-join"`n"))}
    foreach($ref in @($Request.admitInputRef,$compactRef,$packageRef)){$null=Read-AiwEvidenceReference $ctx $ref}
    foreach($root in @($runtime,$tmp)){
        $members=@($files|Where-Object{$_.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)})
        if($members.Count){$releases.Add((Remove-AiwConsumedRuntimeFiles -ScopeRoot $root -LiteralPath $members -RetainedPath $keep -ForbiddenPath $forbidden -ExpectedObject @($expected|Where-Object{$_.path-in$members})))}
    }
    $removed=@($releases|ForEach-Object removed);$remaining=@($releases|ForEach-Object remaining)
    $failures=@($releases|ForEach-Object failures);$posts=@(foreach($path in $package.exactPaths){
        try{$full=Resolve-AiwEvidenceObservationPath $ctx $path;$identity=if([IO.File]::Exists($full)){Get-AiwFileIdentity $full}else{'MISSING'}}catch{$identity='UNKNOWN';$remaining+=Join-Path $project $path;$failures+=[pscustomobject]@{path=$path;kind='POSTIMAGE_UNKNOWN';message=$_.Exception.Message}}
        [pscustomobject]@{path=$path;identity=$identity}
    })
    $status=if($failures.Count){'PARTIAL_FAILURE'}elseif($remaining.Count){'RETAINED'}else{'PASS'}
    [pscustomobject]@{status=$status;actor=$r.actor;taskId=$r.taskId;removed=$removed;removedBytes=($releases.removedBytes|Measure-Object -Sum).Sum;alreadyAbsent=@($releases|ForEach-Object alreadyAbsent);retained=@($releases|ForEach-Object retained);remaining=@($remaining|Select-Object -Unique);failures=$failures;observations=@($releases|ForEach-Object observations);admission=$admission.Value;admitInputRef=$Request.admitInputRef;postimages=$posts;finalizeRequired=$true;evidenceCeiling='INSTRUCTION_BOUND';limits=@('Expiry is supplied by the current task; only known references were followed.','The caller must finalize the original CONTROL_WRITE with actual postimages.')}
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
    if($null-ne$Receipt.PSObject.Properties['schemaVersion']-and$Receipt.schemaVersion-eq5-and$null-ne$Receipt.PSObject.Properties['operation']){
        $codec=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
        $Receipt=& $codec {param($raw)ConvertFrom-AiwOperationCompact $raw} $Receipt
    }
    if($null-eq$Receipt.PSObject.Properties['binding']){return $Receipt}
    $b=$Receipt.binding
    $view=[pscustomobject]@{taskId=$b.taskId;taskIdentity=$b.taskIdentity;taskOwner=$b.taskOwner;taskActor=$b.taskActor;actor=$b.actor;actionKind=$Receipt.intentEnvelope.requestedActionKind;resultKind=$Receipt.intentEnvelope.requestedResultKind;exactPaths=@($b.exactScope);authorityContext=$b;sourceLocators=[pscustomobject]@{projectRoot=$b.projectRoot;frameworkRoot=$Receipt.sourceLocators.frameworkRoot;taskRelativePath=$Receipt.sourceLocators.taskRelativePath;authorizationPackagePath=$Receipt.sourceLocators.authorizationPackagePath}}
    if($null-ne$b.PSObject.Properties['contextType']-and$b.contextType-ceq'PROJECT_WORK'){$view.taskOwner=$b.context.requestContext.owner;$view.taskActor=$b.context.requestContext.actor}
    return $view
}
function Get-DeliveryReviewRouteQualification($Receipt,$Boundary,$Package,$ctx) {
    $r=Get-DeliveryReceiptView $Receipt
    if($r.actionKind-cne'REVIEW_ROUTE'){throw 'DELIVERY_REVIEW_ROUTE_REQUIRED'}
    $context=if($null-ne$Boundary.PSObject.Properties['deliveryContext']){$Boundary.deliveryContext}else{[pscustomobject]@{}}
    if($Package.owner-cne$r.taskOwner-or-not(Test-AiwSameResultContext $Package $r)-or$Package.grantee-cne$r.actor){throw 'DELIVERY_PACKAGE_CONTEXT_DRIFT'}
    $review=$null;$writer=$null
    if($null-ne$context.PSObject.Properties['reviewPackageRef']){
            $review=Read-AiwEvidenceReference $ctx $context.reviewPackageRef -Json
            $fields=if($package.schemaVersion-eq5){@('schemaVersion','owner','profile','projectConfigIdentity','userConfirmation','repositoryId')}else{@('taskId','taskIdentity','owner','projectConfigIdentity','userConfirmation')}
            foreach($field in $fields){if($review.$field-cne$package.$field){throw 'DELIVERY_REVIEW_PACKAGE_DRIFT'}}
            if($package.schemaVersion-eq5-and-not(Test-AiwSameResultContext $review $package)){throw 'DELIVERY_REVIEW_REQUEST_DRIFT'}
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
            $plan=if($Package.schemaVersion-eq5){Get-AiwProjectWorkPlan $Package.requestContext}else{$null}
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
        $assignmentFields=@('source','createdBy','threadId','hostId','parentPackageIdentity')+$(if($Package.schemaVersion-eq5){@('context')}else{@('taskId')})
        if((@($a.PSObject.Properties.Name|Sort-Object)-join'|')-cne(@($assignmentFields|Sort-Object)-join'|')){throw 'DELIVERY_ASSIGNMENT_FIELDS'}
        $assignmentContextMatches=if($Package.schemaVersion-eq5){Test-AiwSameResultContext $a.context $Package}else{$a.taskId-ceq$r.taskId}
        if($a.source-cne'HOST_CREATE_THREAD_RESULT'-or$a.createdBy-cne$Package.grantee-or-not$assignmentContextMatches-or$a.parentPackageIdentity-cne$r.authorityContext.authorizationIdentity-or[string]::IsNullOrWhiteSpace($a.hostId)){throw 'DELIVERY_ASSIGNMENT_DRIFT'}
        if($recipient-cnotin@('UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')-and$recipient-cne$a.threadId){throw 'DELIVERY_ASSIGNMENT_RECIPIENT_DRIFT'}
        $recipient=[string]$a.threadId
    }
    $excluded=@($Package.owner,$Package.issuer,$Package.grantee)
    if($null-ne$Package.PSObject.Properties['repairReviewPlan']){$excluded+=@($Package.repairReviewPlan.materialContributors)}
    if([string]::IsNullOrWhiteSpace($recipient)-or$recipient-cin(@('USER','UNBOUND_RECEIVER','DEFERRED_VISIBLE_REVIEWER')+$excluded)){throw 'DELIVERY_REVIEWER_UNBOUND_OR_DEPENDENT'}
    return $recipient
}
function Get-AiwBoundDelivery($Receipt,$Boundary,$Evidence=$null,[string[]]$ForbiddenPaths=@(),[string[]]$ProtectedPaths=@()) {
    if($null-ne$Receipt.PSObject.Properties['schemaVersion']-and$Receipt.schemaVersion-eq5-and$null-ne$Receipt.PSObject.Properties['operation']){
        $codec=@(Import-Module (Join-Path $PSScriptRoot 'ProcessRequirementComposition.psm1') -PassThru)[0]
        $guarded=New-AiwEvidenceContext $Receipt.operation.binding.projectRoot '' $Receipt.operation.sourceLocators.frameworkRoot @(@($Receipt.operation.binding.forbiddenScope)+$ForbiddenPaths|Select-Object -Unique) @(@($Receipt.operation.binding.protectedScope)+$ProtectedPaths|Select-Object -Unique)
        $Receipt=& $codec {param($raw,$ctx)ConvertFrom-AiwOperationCompact $raw -EvidenceContext $ctx} $Receipt $guarded
    }
    if($Boundary.schemaVersion-eq4-and$null-eq$Boundary.PSObject.Properties['deliveryContext']-and$null-ne$Boundary.PSObject.Properties['preparedDeliveryRef']){throw 'PREPARED_DELIVERY_REF_BOUNDARY'}
    $r=Get-DeliveryReceiptView $Receipt
    $isReview=$r.actionKind-cin@('REVIEW_ROUTE','REVIEW_EXECUTE')
    if($null-eq$Boundary.PSObject.Properties['deliveryContext']){
        if($isReview-or($null-ne$r.authorityContext.PSObject.Properties['contextType']-and$r.authorityContext.contextType-ceq'PROJECT_WORK')){throw 'DELIVERY_CONTEXT_REQUIRED'}
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
        if($package.owner-cne$r.taskOwner-or-not(Test-AiwSameResultContext $package $r)-or$package.grantee-cne$r.actor){throw 'DELIVERY_PACKAGE_CONTEXT_DRIFT'}
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
    if($null-ne$r.authorityContext.PSObject.Properties['contextType']-and$r.authorityContext.contextType-ceq'PROJECT_WORK'){
        $request=$r.authorityContext.context.requestContext
        Assert-AiwProjectWorkContext $request
        if($r.actionKind-cne'REVIEW_ROUTE'-and$request.actor-cne$request.owner-and$request.resultConsumer.recipient-cne$request.owner){throw 'PROJECT_WORK_CONTRIBUTION_OWNER_REQUIRED'}
        if($r.actionKind-cnotin@('REVIEW_ROUTE','REVIEW_EXECUTE')){$recipient=$request.resultConsumer.recipient;$reason='PROJECT_WORK_CONSUMER'}
        if($r.actionKind-ceq'REVIEW_EXECUTE'){
            if($request.resultConsumer.channel-cne'TASK_MESSAGE'-or$request.resultConsumer.recipient-cne$request.owner){throw 'PROJECT_WORK_REVIEW_TO_OWNER_REQUIRED'}
            # The existing verdict reader determines a real finding's writer.
            # It is the only exceptional recipient of this review result.
        }elseif($request.resultConsumer.recipient-cne$recipient-or$request.resultConsumer.channel-cne$(if($recipient-ceq'USER'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'})){throw 'PROJECT_WORK_CONSUMER_DRIFT'}
        if($r.actionKind-ceq'REVIEW_EXECUTE'-and$recipient-ceq'USER'){throw 'PROJECT_WORK_REVIEW_TO_OWNER_REQUIRED'}
    }
    $channel=if($recipient-ceq'USER'){'NATIVE_RESPONSE'}else{'TASK_MESSAGE'}
    if($context.expectedRecipient-cne$recipient-or$context.channel-cne$channel){throw 'DELIVERY_CONSUMER_CHANNEL_MISMATCH'}
    $consumer=[pscustomobject]@{recipient=$recipient;channel=$channel;reason=$reason;authorizationIdentity=$r.authorityContext.authorizationIdentity;userDecisionIdentity=$userDecision;userAuthorizationProven=$false;recipientWorkProven=$false;evidenceCeiling='INSTRUCTION_BOUND'}
    if($Boundary.schemaVersion-eq4){Assert-AiwPreparedOperationDelivery $Receipt $Boundary $ctx $consumer}
    if($context.stage-ceq'OBSERVE'){
        if($context.evidence-cnotmatch'^(.+)#(\d+\|[A-F0-9]{64})$'){throw 'DELIVERY_HOST_REFERENCE_REQUIRED'}
        $hostResult=Read-AiwEvidenceReference $ctx ([pscustomobject]@{path=$Matches[1];identity=$Matches[2]}) -Json
        $actual=Get-AiwCodexSendOutcome $hostResult $recipient
        if($actual.outcome-ceq'WRONG_RECIPIENT'-or$actual.outcome-cne$context.outcome-or$actual.observedRecipient-cne$context.observedRecipient){throw 'DELIVERY_HOST_RESULT_MISMATCH'}
    }
    [pscustomobject]@{delivery=$observation;consumer=$consumer;closureSatisfied=($channel-ceq'NATIVE_RESPONSE'-or$observation.delivered)}
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
Export-ModuleMember -Function Get-AiwCodexSendOutcome,Get-AiwBoundDelivery,Invoke-AiwDeliveryBoundary,Assert-AiwReviewRoutePreparation,Remove-AiwConsumedRuntimeFiles,Complete-AiwRuntimeConsumption,Write-AiwRuntimeCleanupObservation,Invoke-AiwRuntimeMaintenance


function Assert-AiwPreparedOperationDelivery($Receipt,$Boundary,$Context,$Consumer){
 if($Boundary.schemaVersion-ne4){return}
 $isObserved=$Boundary.mode-ceq'FINALIZE_OUTPUT'-and$null-ne$Boundary.PSObject.Properties['deliveryContext']-and$Boundary.deliveryContext.channel-ceq'TASK_MESSAGE'-and$Boundary.deliveryContext.stage-ceq'OBSERVE'
 $hasPrepared=$null-ne$Boundary.PSObject.Properties['preparedDeliveryRef']
 if($isObserved-ne$hasPrepared){throw 'PREPARED_DELIVERY_REF_BOUNDARY'}
 if(-not$isObserved){return}
 $pair=$Boundary.preparedDeliveryRef
 if($pair-isnot[pscustomobject]-or(@($pair.PSObject.Properties.Name|Sort-Object)-join'|')-cne'inputRef|resultRef'){throw 'PREPARED_DELIVERY_REF_FIELDS'}
 $ctx=$Context
 $prepared=Read-AiwEvidenceReference $ctx $pair.inputRef -Json
 $result=Read-AiwEvidenceReference $ctx $pair.resultRef -Json
 if($prepared.schemaVersion-ne4-or$prepared.mode-cne'FINALIZE_OUTPUT'-or$prepared.deliveryContext.stage-cne'PREPARE'-or$prepared.deliveryContext.channel-cne'TASK_MESSAGE'-or$null-ne$prepared.PSObject.Properties['preparedDeliveryRef']-or$result.mode-cne'FINALIZE_OUTPUT'-or$result.status-cne'BLOCKED'-or$result.delivery.status-cne'READY_TO_SEND'-or@($result.missingPreparation).Count-or(@($result.missingResult)-join'|')-cne'DELIVERY_NOT_CONFIRMED'){throw 'PREPARED_DELIVERY_READY_REQUIRED'}
 if((Get-AiwContentDescriptorIdentity $result.operationRef)-cne(Get-AiwContentDescriptorIdentity $Boundary.operationRef)-or$result.selectionIdentity-cne$Receipt.selectionIdentity){throw 'PREPARED_DELIVERY_OPERATION_DRIFT'}
 if($null-ne$prepared.PSObject.Properties['operationRef']){
  if((Get-AiwContentDescriptorIdentity $prepared.operationRef)-cne(Get-AiwContentDescriptorIdentity $Boundary.operationRef)){throw 'PREPARED_DELIVERY_OPERATION_DRIFT'}
 }elseif($null-ne$prepared.PSObject.Properties['currentOperation']){
  if($Receipt.construction.entry-cne'FINALIZE_PREPARE'-or(Get-AiwContentDescriptorIdentity $Receipt.construction.boundaryRef)-cne(Get-AiwContentDescriptorIdentity $pair.inputRef)){throw 'PREPARED_DELIVERY_CONSTRUCTION_DRIFT'}
 }else{throw 'PREPARED_DELIVERY_OPERATION_REQUIRED'}
 foreach($field in @('preparationReceipts','resultReceipts','evidenceRefs','publicDecisionIdentity','protectionState','productionFinalizeRef','continuationDisposition')){
  $before=$prepared.PSObject.Properties[$field];$after=$Boundary.PSObject.Properties[$field]
  if(($null-eq$before)-ne($null-eq$after)){throw ('PREPARED_DELIVERY_EVIDENCE_DRIFT|'+$field)}
  if($null-ne$before-and(Get-AiwContentDescriptorIdentity $before.Value)-cne(Get-AiwContentDescriptorIdentity $after.Value)){throw ('PREPARED_DELIVERY_EVIDENCE_DRIFT|'+$field)}
 }
 $before=$prepared.deliveryContext|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 $after=$Boundary.deliveryContext|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
 foreach($field in @('stage','outcome','observedRecipient','evidence')){$before.PSObject.Properties.Remove($field);$after.PSObject.Properties.Remove($field)}
 if((Get-AiwContentDescriptorIdentity $before)-cne(Get-AiwContentDescriptorIdentity $after)){throw 'PREPARED_DELIVERY_CONSUMER_DRIFT'}
 if(@($prepared.deliveryReceipts).Count){throw 'PREPARED_DELIVERY_FUTURE_RECEIPT'}
 if((Get-AiwContentDescriptorIdentity $result.consumer)-cne(Get-AiwContentDescriptorIdentity $Consumer)-or(Get-AiwContentDescriptorIdentity $result.delivery)-cne(Get-AiwContentDescriptorIdentity (Get-AiwDeliveryObservation $prepared.deliveryContext))){throw 'PREPARED_DELIVERY_RESULT_DRIFT'}
}

