[CmdletBinding()]param([switch]$KeepFixture)
. (Join-Path $PSScriptRoot '../../framework/versions/2.0.0/tests/object-formats-tests.ps1') -FixtureHelpersOnly
Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionProjection.psm1') -Force
Import-Module (Join-Path $sourceRoot 'scripts/ProjectAdoptionTransaction.psm1') -Force
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-adoption-'+[guid]::NewGuid().ToString('N'))
try{
    $current=NewTestProject $temp;$legacy=Clone $current;$legacy.schemaVersion=5;$legacy.PSObject.Properties.Remove('sourceBindings');$legacy.processPolicy.schemaVersion=1
    $projectPath=Join-Path $temp '.ai-workspace/project.json';Store $projectPath $legacy
    Store (Join-Path $temp '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=1;contractVersion='2.0.0';projectId='fixture';selectedRulePackBytes=100;rules=@()})
    Store (Join-Path $temp '.ai-workspace/corrections.json') ([pscustomobject]@{schemaVersion=2;contractVersion='2.0.0';projectId='fixture';corrections=@()})
    $before=@($projectPath,(Join-Path $temp '.ai-workspace/process-policy.json'),(Join-Path $temp '.ai-workspace/corrections.json')|ForEach-Object{Identity $_})
    $preview=New-AiwBootstrapFormatProjection -RepositoryRoot $temp -TargetVersionRoot $versionRoot
    Check ($preview.project.schemaVersion-eq7-and$preview.policy.schemaVersion-eq3-and$preview.corrections.schemaVersion-eq3-and$preview.formatWriteRequired) 'bootstrap-group-complete-isolated-preview'
    Check (($before-join',')-ceq(@($projectPath,(Join-Path $temp '.ai-workspace/process-policy.json'),(Join-Path $temp '.ai-workspace/corrections.json')|ForEach-Object{Identity $_})-join',')) 'preview-zero-live-writes'
    $journal='.ai-workspace/runtime/project-adoption/refresh/state.json'
    Reject {Invoke-AiwProjectProjectionTransaction $temp $preview.projection $journal {param($r,$p)$true} {param($r,$p)$true} -Preflight {param($r,$p)throw 'ORIGINAL_ADMIT_MISSING'}} 'ORIGINAL_ADMIT_MISSING' 'original-admission-rejection-before-any-write'
    Check ((Identity $projectPath)-ceq$before[0]-and-not(Test-Path -LiteralPath (Join-Path $temp $journal))) 'no-transaction-created-on-admission-rejection'
    # Test the existing storage engine only. These artificial callbacks do not
    # establish original admission or authorize real adoption.
    $result=Invoke-AiwProjectProjectionTransaction $temp $preview.projection $journal {param($r,$p)$true} {param($r,$p)$true} -InterruptBeforeJournalWrite 1 -Metadata @{operation='UPGRADE_FORMAT_TRANSITION'}
    Check ($result.status-ceq'INTERRUPTED') 'interruption-after-bytes-before-journal'
    $first=@($preview.projection.objects|Where-Object changed)[0];WriteText (Join-Path $temp $first.path) 'Third-party bytes'
    Reject {Resume-AiwProjectProjectionRollback -RepositoryRoot $temp -TransactionRelativePath $journal -ExpectedTransactionIdentity (Identity (Join-Path $temp $journal)) -RollbackPostcheck {param($r,$p)$true}} 'DRIFT' 'third-party-byte-recovery-rejected'
    Check ([IO.File]::ReadAllText((Join-Path $temp $first.path))-ceq'Third-party bytes') 'recovery-rejection-does-not-overwrite-third-party'
    # A completed storage journal alone cannot enable target-format work.
    foreach($entry in $preview.projection.objects){[IO.File]::WriteAllBytes((Join-Path $temp $entry.path),[Convert]::FromBase64String($entry.newBase64))}
    $state=Get-Content (Join-Path $temp $journal) -Raw|ConvertFrom-Json -Depth 100;$state.state='COMPLETE';$state.transactionComplete=$true;Store (Join-Path $temp $journal) $state
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $projectPath (Identity $projectPath) ([pscustomobject]@{})} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' 'target-work-waits-for-original-finalize'
    $prospective=Read-AiwCurrentObject PROJECT_CONFIG $projectPath (Identity $projectPath) ([pscustomobject]@{ProspectiveAdoptionProjection=$true})
    Check ($prospective.Status-ceq'CURRENT'-and-not$prospective.Authority) 'prospective-validation-never-grants-authority'
    # Real storage transactions, with a prior completed journal at the same
    # path. These checks do not stand in for the public old-runtime bridge.
    $historyRoot=Join-Path $temp 'prior-journal';$null=[IO.Directory]::CreateDirectory($historyRoot)
    $marker=Join-Path $historyRoot 'marker.txt';WriteText $marker 'before-history'
    $historyProjection=New-AiwProjectProjection $historyRoot @([pscustomobject]@{path='marker.txt';text='old'})
    $journalRelative='.ai-workspace/runtime/project-adoption/upgrade/state.json';$journalPath=Join-Path $historyRoot $journalRelative
    $null=Invoke-AiwProjectProjectionTransaction $historyRoot $historyProjection $journalRelative {$true} {$true}
    $historyBytes=[IO.File]::ReadAllBytes($journalPath);$historyIdentity=Identity $journalPath;$markerIdentity=Identity $marker
    $change=New-AiwProjectProjection $historyRoot @([pscustomobject]@{path='marker.txt';text='new'})
    Reject {Invoke-AiwProjectProjectionTransaction $historyRoot $change $journalRelative {$true} {$true} -FailAfterWrite 1 -Metadata @{operation='UPGRADE_FORMAT_TRANSITION'}} 'TRANSACTION_ROLLED_BACK' 'exception-rolls-back-over-existing-complete-journal'
    Check ((Identity $journalPath)-ceq$historyIdentity-and(Identity $marker)-ceq$markerIdentity) 'exception-restores-original-journal-and-object-bytes'
    $stopped=Invoke-AiwProjectProjectionTransaction $historyRoot $change $journalRelative {$true} {$true} -InterruptBeforeJournalWrite 1 -Metadata @{operation='UPGRADE_FORMAT_TRANSITION'}
    Check ($stopped.status-ceq'INTERRUPTED') 'existing-journal-interruption-before-progress-write'
    $pendingBytes=[IO.File]::ReadAllBytes($journalPath);$pendingIdentity=Identity $journalPath;$newMarkerIdentity=Identity $marker
    WriteText $journalPath 'third-party journal'
    Reject {Resume-AiwProjectProjectionRollback $historyRoot $journalRelative $pendingIdentity {$true}} 'TRANSACTION_STATE_DRIFT' 'third-party-journal-refused-before-rollback'
    Check ([IO.File]::ReadAllText($journalPath)-ceq'third-party journal'-and(Identity $marker)-ceq$newMarkerIdentity) 'third-party-journal-and-projection-not-overwritten'
    [IO.File]::WriteAllBytes($journalPath,$pendingBytes)
    $damaged=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json -Depth 100;$damaged.previousTransaction.identity='1|'+('A'*64);Store $journalPath $damaged
    $damagedIdentity=Identity $journalPath
    Reject {Resume-AiwProjectProjectionRollback $historyRoot $journalRelative $damagedIdentity {$true}} 'PREVIOUS_TRANSACTION_IDENTITY' 'damaged-prior-proof-rejected-before-restoration'
    Check ((Identity $marker)-ceq$newMarkerIdentity-and(Identity $journalPath)-ceq$damagedIdentity) 'damaged-prior-proof-rejection-writes-zero'
    [IO.File]::WriteAllBytes($journalPath,$pendingBytes)
    Reject {Resume-AiwProjectProjectionRollback $historyRoot $journalRelative $pendingIdentity {throw 'INTERRUPTED_BEFORE_JOURNAL_RESTORE'}} 'INTERRUPTED_BEFORE_JOURNAL_RESTORE' 'rollback-interrupted-after-objects-before-prior-journal'
    $retryState=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json -Depth 100
    Check ($retryState.state-ceq'ROLLING_BACK'-and$retryState.previousTransaction.identity-ceq$historyIdentity-and(Identity $marker)-ceq$markerIdentity) 'interrupted-rollback-retains-exact-prior-proof-for-retry'
    $restored=Resume-AiwProjectProjectionRollback $historyRoot $journalRelative (Identity $journalPath) {$true}
    Check ($restored.status-ceq'ROLLED_BACK'-and(Identity $journalPath)-ceq$historyIdentity-and(Identity $marker)-ceq$markerIdentity) 'rollback-retry-restores-original-complete-journal'
    $null=Invoke-AiwProjectProjectionTransaction $historyRoot $change $journalRelative {$true} {$true}
    $committed=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json -Depth 100
    Check ($committed.state-ceq'COMPLETE'-and$null-eq$committed.PSObject.Properties['previousTransaction']) 'successful-commit-does-not-accumulate-nested-journal-history'
    # Original absence is a transaction preimage, not an empty completed
    # journal. Exercise actual file persistence and the retirement interruption.
    $absentRoot=Join-Path $temp 'absent-journal';$null=[IO.Directory]::CreateDirectory($absentRoot)
    WriteText (Join-Path $absentRoot 'marker.txt') 'before'
    $absentProjection=New-AiwProjectProjection $absentRoot @([pscustomobject]@{path='marker.txt';text='after'})
    $absentJournal=Join-Path $absentRoot $journalRelative
    $null=Invoke-AiwProjectProjectionTransaction $absentRoot $absentProjection $journalRelative {$true} {$true} -InterruptBeforeJournalWrite 1 -Metadata @{operation='UPGRADE_FORMAT_TRANSITION'}
    $absentState=Get-Content -LiteralPath $absentJournal -Raw|ConvertFrom-Json -Depth 100
    Check ($absentState.previousTransaction.identity-ceq'MISSING'-and$absentState.previousTransaction.base64-ceq'') 'missing-original-journal-explicitly-bound'
    $historyPath=Join-Path $absentRoot $absentState.previousTransaction.rollbackHistoryRelativePath
    $null=[IO.Directory]::CreateDirectory($historyPath)
    Reject {Resume-AiwProjectProjectionRollback $absentRoot $journalRelative (Identity $absentJournal) {$true}} 'ROLLBACK_HISTORY_DRIFT' 'history-storage-failure-keeps-active-recovery'
    Check ((Test-Path -LiteralPath $absentJournal -PathType Leaf)-and[IO.File]::ReadAllText((Join-Path $absentRoot 'marker.txt'))-ceq'before') 'history-failure-preserves-recovery-and-old-objects'
    [IO.Directory]::Delete($historyPath)
    Reject {Resume-AiwProjectProjectionRollback $absentRoot $journalRelative (Identity $absentJournal) {$true} -InterruptAfterRollbackHistory} 'ROLLBACK_JOURNAL_RETIRE_INTERRUPTED' 'interruption-after-terminal-history-before-active-exit'
    $retained=Get-Content -LiteralPath $historyPath -Raw|ConvertFrom-Json -Depth 100
    $retainedIdentity=Identity $historyPath;$retryIdentity=Identity $absentJournal;$retryBytes=[IO.File]::ReadAllBytes($absentJournal)
    Check ($retained.state-ceq'ROLLED_BACK'-and$retained.transactionComplete-and(Test-Path -LiteralPath $absentJournal -PathType Leaf)) 'terminal-history-durable-before-active-exit'
    WriteText $absentJournal 'unknown active journal'
    Reject {Resume-AiwProjectProjectionRollback $absentRoot $journalRelative $retryIdentity {$true}} 'TRANSACTION_STATE_DRIFT' 'retirement-never-deletes-unknown-journal'
    Check ([IO.File]::ReadAllText($absentJournal)-ceq'unknown active journal') 'unknown-journal-preserved'
    [IO.File]::WriteAllBytes($absentJournal,$retryBytes)
    $retired=Resume-AiwProjectProjectionRollback $absentRoot $journalRelative $retryIdentity {$true}
    Check ($retired.status-ceq'ROLLED_BACK'-and$retired.transactionIdentity-ceq'MISSING'-and-not(Test-Path -LiteralPath $absentJournal)-and(Identity $historyPath)-ceq$retainedIdentity) 'same-plan-retry-restores-original-absence-and-keeps-history'
    $reapply=Invoke-AiwProjectProjectionTransaction $absentRoot $absentProjection $journalRelative {$true} {$true}
    Check ($reapply.status-ceq'COMPLETE') 'fresh-upgrade-after-absent-journal-rollback'
    Write-Output ('FORMAT_TRANSITION_STORAGE_TESTS|PASS|'+$passed+'|original-runtime-bridge=separate-required')
}finally{if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{RemoveTestRoot $temp}}
