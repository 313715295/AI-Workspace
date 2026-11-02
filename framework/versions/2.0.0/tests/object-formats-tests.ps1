[CmdletBinding()]param([switch]$FixtureHelpersOnly,[switch]$KeepFixture)
Import-Module (Join-Path $PSScriptRoot 'TestNativeOutput.psm1')
Initialize-AiwTestNativeOutput
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$versionRoot=Split-Path -Parent $PSScriptRoot
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $versionRoot '../../..'))
$utf8=[Text.UTF8Encoding]::new($false);$passed=0
Import-Module (Join-Path $versionRoot 'scripts/ObjectFormats.psm1') -Force
Import-Module (Join-Path $versionRoot 'scripts/ContentSources.psm1') -Force
function Store([string]$Path,$Value){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100 -Compress)+"`n",$utf8)}
function WriteText([string]$Path,[string]$Text){$null=[IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Identity([string]$Path){Get-AiwContentByteIdentity ([IO.File]::ReadAllBytes($Path))}
function Clone($Value){$Value|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100 -DateKind String}
function Check([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Reject([scriptblock]$Action,[string]$Signal,[string]$Name){$errorText='';try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message};Check ($errorText.Contains($Signal)) ($Name+'|'+$errorText)}
function NewTestProject([string]$Root,[string]$Id='fixture'){
    $configuration=[pscustomobject]@{schemaVersion=7;id=$Id;displayName='Format fixture';controlPlaneLayout='repo-local';repositoryRoot='..';frameworkVersion='2.0.0';frameworkToolBackend='powershell7';routineExcludedPaths=@();frameworkCapabilities=[pscustomobject]@{};sourceBindings=@();processPolicy=[pscustomobject]@{schemaVersion=3;locator='.ai-workspace/process-policy.json'}}
    Store (Join-Path $Root '.ai-workspace/project.json') $configuration
    Store (Join-Path $Root '.ai-workspace/process-policy.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$Id;rules=@()})
    Store (Join-Path $Root '.ai-workspace/corrections.json') ([pscustomobject]@{schemaVersion=3;contractVersion='2.0.0';projectId=$Id;corrections=@()})
    return $configuration
}
function RemoveTestRoot([string]$Root){$base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))+[IO.Path]::DirectorySeparatorChar;$full=[IO.Path]::GetFullPath($Root);if(-not$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)-or-not[IO.Path]::GetFileName($full).StartsWith('aiw-w2-')){throw 'TEST_CLEANUP_SCOPE'};if(Test-Path -LiteralPath $full){[IO.Directory]::Delete($full,$true)}}
if($FixtureHelpersOnly){return}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-w2-formats-'+[guid]::NewGuid().ToString('N'))
try{
    $profile=Get-Content -LiteralPath (Join-Path $versionRoot 'ADOPTION_PROFILE.json') -Raw|ConvertFrom-Json -Depth 100
    $null=Assert-AiwFormatAdoptionProfile $profile $versionRoot '2.0.0'
    Check ($profile.projectControl.schemaVersion-eq7-and$profile.projectControl.navigationProjection-ceq'PROJECT_BOOTSTRAP_MANAGED_AGENTS') 'current-profile-binds-project-seven-and-bootstrap-navigation'
    $wrongProfile=Clone $profile;$wrongProfile.projectControl.navigationProjection='ROOT_CANONICAL_SKILL_MANAGED_AGENTS'
    Reject {Assert-AiwFormatAdoptionProfile $wrongProfile $versionRoot '2.0.0'} 'ADOPTION_PROFILE_VALUES' 'current-profile-cannot-restore-Skill-navigation'
    $current=NewTestProject $temp;$path=Join-Path $temp '.ai-workspace/project.json';$original=Identity $path
    $zero=Read-AiwCurrentObject PROJECT_CONFIG $path $original ([pscustomobject]@{})
    Check ($zero.Status-ceq'CURRENT'-and$zero.Segments.Count-eq0-and$zero.OriginalIdentity-ceq$zero.CurrentIdentity-and-not$zero.Persisted) 'current-project-seven-preserves-exact-bytes'
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path ('1|'+('A'*64)) ([pscustomobject]@{})} 'FORMAT_ORIGINAL_IDENTITY_DRIFT' 'identity-before-conversion'
    $legacy=Clone $current;$legacy.schemaVersion=4;$legacy.PSObject.Properties.Remove('sourceBindings');$legacy.processPolicy.schemaVersion=1
    $policy=[pscustomobject]@{schemaVersion=1;contractVersion='2.0.0';projectId='fixture';selectedRulePackBytes=100;rules=@()}
    Store $path $legacy;$before=Identity $path
    $ctx=[pscustomobject]@{LegacyPolicy=$policy;ProjectId='fixture';LibraryId='fixture';TargetProcessContractVersion='2.0.0';ForbiddenPaths=@()}
    $converted=Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx
    Check ($converted.Status-ceq'FORMAT_WRITE_REQUIRED'-and$converted.Segments.Count-eq3-and$converted.Value.schemaVersion-eq7-and(Identity $path)-ceq$before) 'real-four-five-six-seven-chain-is-readonly-preview'
    $callbackCalled=$false;$ctx|Add-Member SaveOriginalAdmittedObject {param($p,$i,$b)$script:callbackCalled=$true}
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx AUTHORIZED_MUTATION} 'FORMAT_USE_ORIGINAL_ADOPTION_TRANSACTION' 'callback-cannot-forge-original-admission'
    Check (-not$callbackCalled-and(Identity $path)-ceq$before) 'rejected-save-has-zero-write'
    $ctx|Add-Member SourceBindings @($converted.Value.sourceBindings)
    $policyPath=Join-Path $temp 'legacy-policy.json';Store $policyPath $policy
    $convertedPolicy=Read-AiwCurrentObject PROCESS_POLICY $policyPath (Identity $policyPath) $ctx
    Check ($convertedPolicy.Value.schemaVersion-eq3-and$null-eq$convertedPolicy.Value.PSObject.Properties['selectedRulePackBytes']) 'policy-format-removes-quota-without-losing-rules'
    $legacyRecord=[pscustomobject]@{correctionId='LEGACY';introducedAgainstFramework='1.16.0';requirementReason='Preserve the original decision.';effectiveRule='Keep the legacy statement.';applicability='Free prose about DOMAIN_OWNER and SOURCE_WRITE is not permission.';decisionLocator='fixture:original-user'}
    $corrections=[pscustomobject]@{schemaVersion=1;projectId='fixture';corrections=@($legacyRecord)};$correctionPath=Join-Path $temp 'legacy-corrections.json';Store $correctionPath $corrections
    $convertedCorrections=Read-AiwCurrentObject PROJECT_CORRECTIONS $correctionPath (Identity $correctionPath) $ctx
    Check ($convertedCorrections.CurrentFormat-eq3-and$convertedCorrections.Segments.Count-eq2) 'corrections-real-one-two-three-chain'
    Check ($convertedCorrections.Value.corrections[0].applicability-ceq$legacyRecord.applicability-and$convertedCorrections.Value.corrections[0].selectors.roles.Count-eq0-and$convertedCorrections.Value.corrections[0].selectors.actionKinds.Count-eq0) 'legacy-free-applicability-preserved-without-guessed-authority'
    $indexPath=Join-Path $temp 'legacy-index.json';Store $indexPath ([pscustomobject]@{schemaVersion=1;projectId='fixture';entries=@()});$indexBefore=Identity $indexPath
    $index=Read-AiwCurrentObject KNOWLEDGE_INDEX $indexPath $indexBefore $ctx
    Check ($index.CurrentFormat-eq3-and$index.StorageClass-ceq'EXTERNAL_READ_ONLY'-and(Identity $indexPath)-ceq$indexBefore) 'external-index-original-facts-retained'
    Store (Join-Path $temp 'controller.json') ([pscustomobject]@{schemaVersion=1;projectId='fixture';controllerId='actor';controllerEpoch=1;state='CURRENT'})
    $controller=Read-AiwCurrentObject CONTROLLER (Join-Path $temp 'controller.json') (Identity (Join-Path $temp 'controller.json')) $ctx
    Check ($controller.Segments.Count-eq0-and$controller.OriginalIdentity-ceq$controller.CurrentIdentity) 'immutable-controller-zero-conversion'
    # Plans 1 and 2 are native immutable originals, never an adapter chain.
    $planPath=Join-Path $temp 'acceptance-plan.json'
    $required=[pscustomobject]@{path='requirements.md';identity=('1|'+('D'*64))}
    $stage=[pscustomobject]@{id='self';kind='SELF_CHECK';requiredBy=$required;dependsOn=@();candidateRef=@();evidenceRefs=@()}
    $planOne=[pscustomobject]@{schemaVersion=1;stages=@($stage)}
    Store $planPath $planOne;$planIdentity=Identity $planPath
    $readPlan=Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath $planIdentity $ctx
    Check ($readPlan.OriginalFormat-eq1-and$readPlan.CurrentFormat-eq1-and$readPlan.Segments.Count-eq0-and-not$readPlan.Persisted-and(Identity $planPath)-ceq$planIdentity) 'plan-one-native-original-no-conversion'
    $binding=[pscustomobject]@{schemaVersion=1;policyRef=[pscustomobject]@{path='.ai-workspace/process-policy.json';identity=('1|'+('E'*64))};subject=[pscustomobject]@{repositoryId='REPO_LOCAL';exactPaths=@('result.md');facets=[pscustomobject]@{domain=[pscustomobject]@{state='KNOWN';values=@('aiw:software')};deliverableType=[pscustomobject]@{state='KNOWN';values=@('aiw:code')}}};effectiveStages=@()}
    $planTwo=[pscustomobject]@{schemaVersion=2;qualityBinding=$binding;stages=@()}
    Store $planPath $planTwo;$planIdentity=Identity $planPath
    $readPlan=Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath $planIdentity $ctx
    Check ($readPlan.OriginalFormat-eq2-and$readPlan.CurrentFormat-eq2-and$readPlan.Segments.Count-eq0-and-not$readPlan.Persisted-and$readPlan.Value.stages.Count-eq0-and(Identity $planPath)-ceq$planIdentity) 'plan-two-explicit-zero-native-original-no-conversion'
    $invalid=Clone $planTwo;$invalid.schemaVersion=3;Store $planPath $invalid
    Reject {Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath (Identity $planPath) $ctx} 'FORMAT_START_UNSUPPORTED' 'plan-unknown-format-rejected'
    $invalid=Clone $planTwo;$invalid|Add-Member unexplained $true;Store $planPath $invalid
    Reject {Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath (Identity $planPath) $ctx} 'FORMAT_CURRENT_VALIDATION_FAILED' 'plan-two-unknown-field-rejected'
    $invalid=Clone $planTwo;$invalid.qualityBinding.effectiveStages=@('SELF_CHECK');Store $planPath $invalid
    Reject {Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath (Identity $planPath) $ctx} 'QUALITY_PLAN_STAGE_MISSING' 'plan-two-selected-stage-cannot-be-empty'
    $invalid=Clone $planTwo;$invalid.stages=@((Clone $stage));$invalid.stages[0].dependsOn=@('missing');Store $planPath $invalid
    Reject {Read-AiwCurrentObject ACCEPTANCE_PLAN $planPath (Identity $planPath) $ctx} 'ACCEPTANCE_PLAN_UNKNOWN_DEPENDENCY' 'plan-two-dag-validated-by-native-reader'
    # Format6's original adoption journals retain their original completion
    # obligations; forbidden journal targets must be rejected before even probing.
    $six=Clone $current;$six.schemaVersion=6;$six.processPolicy.schemaVersion=2
    Store $path $six;$sixIdentity=Identity $path
    $journalContext=[pscustomobject]@{ForbiddenPaths=@()}
    $sixPreview=Read-AiwCurrentObject PROJECT_CONFIG $path $sixIdentity $journalContext
    Check ($sixPreview.Status-ceq'FORMAT_WRITE_REQUIRED'-and$sixPreview.Segments.Count-eq1-and(Identity $path)-ceq$sixIdentity) 'format6-allowed-missing-journals-retains-readonly-preview'
    $formatModule=(Get-Command Read-AiwCurrentObject).Module;$journalAudit=[Collections.Generic.List[object]]::new()
    & $formatModule {
        param($Trace)
        $script:JournalAuditTrace=$Trace;$script:JournalAuditTarget=''
        function script:Test-Path {
            [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[string[]]$LiteralPath,[Microsoft.PowerShell.Commands.TestPathType]$PathType)
            foreach($value in @($Path)+@($LiteralPath)){if($script:JournalAuditTarget-and[string]::Equals($value,$script:JournalAuditTarget,[StringComparison]::OrdinalIgnoreCase)){$script:JournalAuditTrace.Add('EXISTENCE')}}
            Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
        }
        function script:Get-Item {
            [CmdletBinding()]param([Parameter(Position=0)][string[]]$Path,[string[]]$LiteralPath,[switch]$Force)
            foreach($value in @($Path)+@($LiteralPath)){if($script:JournalAuditTarget-and[string]::Equals($value,$script:JournalAuditTarget,[StringComparison]::OrdinalIgnoreCase)){$script:JournalAuditTrace.Add('METADATA')}}
            Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
        }
    } $journalAudit
    try{
        foreach($kind in @('upgrade','refresh')){
            $journal=Join-Path $temp ('.ai-workspace/runtime/project-adoption/'+$kind+'/state.json')
            foreach($present in @($false,$true)){
                if($present){Store $journal ([pscustomobject]@{metadata=[pscustomobject]@{operation='REGISTER'};state='COMPLETE';transactionComplete=$true})}
                $journalContext.ForbiddenPaths=@($journal)
                & $formatModule {param($Target)$script:JournalAuditTarget=$Target} $journal
                $journalAudit.Clear();$caught='';try{$null=Read-AiwCurrentObject PROJECT_CONFIG $path $sixIdentity $journalContext}catch{$caught=$_.Exception.Message}
                Check ($caught-ceq'FORMAT_SOURCE_DENIED'-and$journalAudit.Count-eq0-and(Identity $path)-ceq$sixIdentity) ('format6-forbidden-'+$kind+'-journal-before-any-probe-present-'+$present)
                & $formatModule {$script:JournalAuditTarget=''}
                $journalContext.ForbiddenPaths=@()
                if($present){
                    $allowed=Read-AiwCurrentObject PROJECT_CONFIG $path $sixIdentity $journalContext
                    Check ($allowed.Status-ceq'FORMAT_WRITE_REQUIRED') ('format6-allowed-existing-nontransition-'+$kind+'-journal-is-read')
                    Store $journal ([pscustomobject]@{metadata=[pscustomobject]@{operation='UPGRADE_FORMAT_TRANSITION'};state='APPLYING';transactionComplete=$false})
                    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $sixIdentity $journalContext} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' ('format6-incomplete-original-'+$kind+'-journal-still-rejected')
                    Store $journal ([pscustomobject]@{metadata=[pscustomobject]@{operation='UPGRADE_FORMAT_TRANSITION'};projection=[pscustomobject]@{objects=@()};state='COMPLETE';transactionComplete=$true})
                    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $sixIdentity $journalContext} 'ADOPTION_ORIGINAL_FINALIZE_REQUIRED' ('format6-complete-marker-without-original-proof-'+$kind+'-still-rejected')
                    [IO.File]::Delete($journal)
                }
            }
        }
    }finally{& $formatModule {Remove-Item -LiteralPath function:script:Test-Path,function:script:Get-Item}}
    # Continue the original assembly-chain counterexamples from their original4.
    Store $path $legacy
    $assemblyPath=Join-Path $temp 'assembly/ASSEMBLY.json';$assembly=Get-Content (Join-Path $versionRoot 'object-formats/ASSEMBLY.json') -Raw|ConvertFrom-Json -Depth 100
    $null=[IO.Directory]::CreateDirectory((Split-Path $assemblyPath -Parent));Copy-Item -LiteralPath (Join-Path $versionRoot 'object-formats/adapters') -Destination (Join-Path $temp 'assembly/adapters') -Recurse
    $ctx|Add-Member AssemblyPath $assemblyPath
    $bad=Clone $assembly;$projectType=@($bad.objectTypes|Where-Object objectType -CEQ PROJECT_CONFIG)[0];$projectType.entries=@();Store $assemblyPath $bad
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_ENTRY_MISSING' 'missing-chain-fails'
    $bad=Clone $assembly;$projectType=@($bad.objectTypes|Where-Object objectType -CEQ PROJECT_CONFIG)[0];$projectType.entries+=@($projectType.entries[0]);Store $assemblyPath $bad
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_ENTRY_AMBIGUOUS_OR_MISSING' 'ambiguous-entry-fails'
    $bad=Clone $assembly;$projectType=@($bad.objectTypes|Where-Object objectType -CEQ PROJECT_CONFIG)[0];$projectType.adapters[0].toFormat=4;Store $assemblyPath $bad
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_NON_ADVANCING_SEGMENT' 'non-advancing-chain-fails'
    $bad=Clone $assembly;$projectType=@($bad.objectTypes|Where-Object objectType -CEQ PROJECT_CONFIG)[0];$projectType.adapters[0].next=$projectType.adapters[0].adapterId;Store $assemblyPath $bad
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_CHAIN_CYCLE' 'cycle-fails'
    Store $assemblyPath $assembly;WriteText (Join-Path $temp 'assembly/adapters/project-config-4-to-5.ps1') 'param($Value,$Context) $Value'
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_IMPLEMENTATION_DRIFT' 'segment-byte-drift-fails-before-execution'
    $bad=Clone $assembly;$projectType=@($bad.objectTypes|Where-Object objectType -CEQ PROJECT_CONFIG)[0];$projectType.adapters[0].implementationIdentity=Identity (Join-Path $temp 'assembly/adapters/project-config-4-to-5.ps1');Store $assemblyPath $bad
    Reject {Read-AiwCurrentObject PROJECT_CONFIG $path $before $ctx} 'FORMAT_SEGMENT_OUTPUT_FORMAT' 'wrong-output-format-fails'
    Write-Output ('OBJECT_FORMATS_TESTS|PASS|'+$passed)
}finally{if($KeepFixture){Write-Output ('FIXTURE|'+$temp)}else{RemoveTestRoot $temp}}
