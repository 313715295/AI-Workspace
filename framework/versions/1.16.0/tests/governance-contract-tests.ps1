[CmdletBinding()]
param([switch]$SkipPerformanceSmoke)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSEdition-cne'Core'-or$PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL7_REQUIRED'}
$utf8=[Text.UTF8Encoding]::new($false)
$script:passed=0

function Assert-True([bool]$Value,[string]$Name){if(-not$Value){throw ('ASSERT_FAIL|'+$Name)};$script:passed++;Write-Output ('PASS|'+$Name)}
function Get-Identity([string]$Path){$bytes=[IO.File]::ReadAllBytes($Path);return $bytes.Length.ToString()+'|'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
function Write-Utf8([string]$Path,[string]$Text){$parent=Split-Path -Parent $Path;if($parent-and-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$value=$Text.Replace("`r`n","`n").Replace("`r","`n");if(-not$value.EndsWith("`n")){$value+="`n"};[IO.File]::WriteAllText($Path,$value,$utf8)}
function Invoke-Ps([string]$Script,[string[]]$Arguments){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$output=@(& ([Environment]::ProcessPath) -NoProfile -NonInteractive -File $Script @Arguments 2>&1|ForEach-Object{[string]$_});$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old};return [pscustomobject]@{Code=$code;Output=$output;Text=($output-join"`n")}}
function Get-RequirementBlock([string]$Path,[string]$Id){$text=Get-Content -Raw -Encoding utf8 -LiteralPath $Path;$begin='<!-- AIW-REQUIREMENT:'+$Id+':BEGIN -->';$end='<!-- AIW-REQUIREMENT:'+$Id+':END -->';$first=$text.IndexOf($begin,[StringComparison]::Ordinal);$last=$text.IndexOf($end,[StringComparison]::Ordinal);if($first-lt0-or$last-le$first-or$text.IndexOf($begin,$first+1,[StringComparison]::Ordinal)-ge0-or$text.IndexOf($end,$last+1,[StringComparison]::Ordinal)-ge0){throw ('REQUIREMENT_BLOCK_CARDINALITY|'+$Id)};return $text.Substring($first+$begin.Length,$last-($first+$begin.Length)).Trim()}

$versionRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
$repositoryRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((Join-Path $versionRoot '..\..\..')))
$catalogPath=Join-Path $versionRoot 'PROCESS_REQUIREMENTS.json'
$catalogGenerator=Join-Path $versionRoot 'scripts\build-process-requirements.ps1'
$catalogText=Get-Content -Raw -Encoding utf8 -LiteralPath $catalogPath
$catalog=$catalogText|ConvertFrom-Json
$inventory=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'NORMATIVE_SURFACE_INVENTORY.json')|ConvertFrom-Json
$budget=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'tests\PROCESS_REQUIREMENTS_BUDGETS.json')|ConvertFrom-Json
$coverage=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'CORRECTION_COVERAGE.json')|ConvertFrom-Json

$catalogCheck=Invoke-Ps $catalogGenerator @('-Check')
Assert-True ($catalogCheck.Code-eq0-and$catalogCheck.Text.Contains('PASS|requirements=35|fragments=9')) 'process-requirements-canonical-fragments-match-generated-catalog'
$blockProjectionValid=-not$catalogText.Contains('"fullText"')
foreach($fragmentPath in Get-ChildItem -LiteralPath (Join-Path $versionRoot 'requirements\fragments') -File -Filter '*.json'){if((Get-Content -Raw -Encoding utf8 -LiteralPath $fragmentPath.FullName).Contains('"fullText"')){$blockProjectionValid=$false}}
foreach($requirement in @($catalog.requirements)){$ownerPath=Join-Path $versionRoot ([string]$requirement.ownerModule);try{$body=Get-RequirementBlock $ownerPath ([string]$requirement.requirementId)}catch{$blockProjectionValid=$false;continue};if([string]$requirement.exactBlockLocator-cne('AIW-REQUIREMENT:'+[string]$requirement.requirementId)-or[string]::IsNullOrWhiteSpace($body)){$blockProjectionValid=$false}}
Assert-True ($blockProjectionValid-and@($catalog.requirements).Count-eq35) 'process-requirements-metadata-only-catalog-exact-markdown-blocks-nonempty'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('aiw-governance-contract-'+[guid]::NewGuid().ToString('N'))
try{
    Copy-Item -LiteralPath $versionRoot -Destination $temp -Recurse
    $driftCatalog=Join-Path $temp 'PROCESS_REQUIREMENTS.json'
    Write-Utf8 $driftCatalog ((Get-Content -Raw -Encoding utf8 -LiteralPath $driftCatalog).Replace('Independent action authorization','Drifted title'))
    $driftCheck=Invoke-Ps (Join-Path $temp 'scripts\build-process-requirements.ps1') @('-Check')
    Assert-True ($driftCheck.Code-ne0-and$driftCheck.Text.Contains('PROCESS_REQUIREMENTS_PROJECTION_DRIFT')) 'process-requirements-generated-catalog-drift-rejected'
}finally{
    if(Test-Path -LiteralPath $temp){$tempRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()));$resolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($temp));if([IO.Path]::GetDirectoryName($resolved)-cne$tempRoot-or[IO.Path]::GetFileName($resolved)-cnotmatch'^aiw-governance-contract-[a-f0-9]{32}$'){throw 'GOVERNANCE_TEMP_CLEANUP_BOUNDARY'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}

$recoveryPath=Join-Path $versionRoot 'RECOVERY_CORE.md'
$recoveryBlock=Get-RequirementBlock $recoveryPath 'PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES'
$taskBlock=Get-RequirementBlock (Join-Path $versionRoot 'TASK_AND_SCOPE.md') 'PR_TASK_SCOPE_AND_FORBIDDEN'
$authorizationBlock=Get-RequirementBlock (Join-Path $versionRoot 'AUTHORIZATION_MODEL.md') 'PR_ACTION_AUTHORIZATION_INDEPENDENT'
$hostBlock=Get-RequirementBlock (Join-Path $versionRoot 'HOST_CODEX.md') 'PR_CODEX_ROUTER_REACTIVATION'
$routerText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'skills\ai-workspace-router\SKILL.md')
$starterText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'project-starter\BOOTSTRAP.md')
$maintenanceText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'framework\maintenance-overlay\BOOTSTRAP.md')
$toolContractText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'TOOL_CONTRACT.md')
$mainTestText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'tests\run-framework-tests.ps1')
Assert-True ($recoveryBlock.Contains('source composition')-and$recoveryBlock.Contains('boundary decision')-and$recoveryBlock.Contains('current model fullText availability')-and$recoveryBlock.Contains('summary、cache、source hash')-and$recoveryBlock.Contains('compact/continuation receipt')-and$recoveryBlock.Contains('旧 receipt')-and$recoveryBlock.Contains('fresh authorization')-and$recoveryBlock.Contains('actual authority、task route 或 phase drift')) 'recovery-core-owns-composition-decision-and-model-body-availability-contract'
Assert-True ($taskBlock.Contains('RECOVERY_CORE.md')-and$hostBlock.Contains('RECOVERY_CORE.md')-and$routerText.Contains('RECOVERY_CORE.md')-and$starterText.Contains('RECOVERY_CORE.md')-and$maintenanceText.Contains('RECOVERY_CORE.md')) 'recovery-router-host-task-and-bootstraps-use-one-owner-with-thin-pointers'
Assert-True ($recoveryBlock.Contains('机械校验通过')-and$recoveryBlock.Contains('不能证明正文已在当前模型上下文')-and$recoveryBlock.Contains('下一 substantive action 前读取')-and$recoveryBlock.Contains('current `DISCOVER`')-and$recoveryBlock.Contains('每个 `fullText`')) 'recovery-static-contract-does-not-claim-model-fulltext-read-from-mechanical-evidence'
Assert-True ($taskBlock.Contains('可验收的 bounded batch')-and$taskBlock.Contains('不把 diagnosis、文件或局部修复拆成新决定')-and$taskBlock.Contains('continuationPlan')-and$taskBlock.Contains('Executor 自主选择实现方法、工具和执行顺序')-and$taskBlock.Contains('independent Review')-and$taskBlock.Contains('`OWNER_ACCEPT`')) 'task-contract-batches-predictable-work-without-merging-independent-gates'
Assert-True ($authorizationBlock.Contains('AUTHORIZED_ACTION_CONTINUATION')-and$authorizationBlock.Contains('CONTINUATION_RESULT_DRIFT')-and$authorizationBlock.Contains('INSTRUCTION_BOUND')-and$authorizationBlock.Contains('source Discover identity及其实际 action/`continuationStepIndex`')-and$toolContractText.Contains('continuationReceiptPath + expectedContinuationReceiptIdentity')-and$toolContractText.Contains('不保存无法由 checker 复验的 finalize hash')-and-not$toolContractText.Contains('sourceFinalizeDecisionIdentity')-and$maintenanceText.Contains('authorization/process adapter')) 'authorization-continuation-has-one-postimage-bound-consumer-contract'
Assert-True ([regex]::Matches($mainTestText,'authorization-receipt-regression-tests\.ps1').Count-eq1-and$mainTestText.Contains('AUTHORIZATION_RECEIPT_REGRESSION_TESTS')) 'main-suite-invokes-one-authorization-receipt-specialty-and-propagates-failure'

$catalogIdentity=Get-Identity $catalogPath
$coverageBindings=@($coverage.versions[0].incorporationMappings|ForEach-Object{[string]$_.nativeCatalogIdentity})
Assert-True ([string]$budget.baseline.version-ceq'1.15.1'-and[string]$budget.baseline.catalogIdentity-ceq'48098|547BBC615BCFC0A281723A1B84AEFD36FECD5CA421C7155C1897D8F4F0CC74C5'-and[string]$budget.candidate.catalogIdentity-ceq$catalogIdentity) 'process-budget-minor-baseline-and-candidate-catalog-identities-exact'
Assert-True (@($coverageBindings).Count-gt0-and@($coverageBindings|Where-Object{$_-cne$catalogIdentity}).Count-eq0-and@($inventory.schemaAndMechanicalInputs)-contains'tests/canonical-identity-tests.ps1'-and@($inventory.schemaAndMechanicalInputs)-contains'tests/governance-contract-tests.ps1') 'governance-focused-entrypoint-binds-catalog-coverage-budget-and-inventory'
if($SkipPerformanceSmoke){Assert-True $true 'process-budget-six-fixtures-replay-selected-pack-skipped-for-affected-run'}else{
    $measurement=Invoke-Ps (Join-Path $versionRoot 'tests\measure-process-requirements.ps1') @('-Warmups','1','-MeasuredRuns','1','-AsJson')
    $measurementValue=if($measurement.Code-eq0){$measurement.Text|ConvertFrom-Json}else{$null}
    $measurementMatches=$measurement.Code-eq0-and@($measurementValue.fixtures).Count-eq6
    if($measurementMatches){foreach($fixture in @($measurementValue.fixtures)){$budgetFixture=@($budget.fixtures|Where-Object{[string]$_.fixtureId-ceq[string]$fixture.fixtureId});if($budgetFixture.Count-ne1-or[int]$budgetFixture[0].selectedPackBytes-ne[int]$fixture.selectedPackBytes-or[int]$budgetFixture[0].selectedPackEstimatedTokens-ne[int]$fixture.selectedPackEstimatedTokens-or[int]$budgetFixture[0].selectedRequirementCount-ne[int]$fixture.selectedRequirementCount){$measurementMatches=$false}}}
    Assert-True $measurementMatches 'process-budget-six-fixtures-replay-selected-pack'
}

$releasePath=Join-Path $repositoryRoot 'framework\FRAMEWORK_RELEASE.md'
$releaseText=Get-Content -Raw -Encoding utf8 -LiteralPath $releasePath
$reviewText=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $versionRoot 'REVIEW_AND_EVIDENCE.md')
Assert-True ((Test-Path -LiteralPath $releasePath -PathType Leaf)-and-not(Test-Path -LiteralPath (Join-Path $versionRoot 'FRAMEWORK_RELEASE.md'))-and@($inventory.explanationAndHistory)-cnotcontains'FRAMEWORK_RELEASE.md'-and-not$reviewText.Contains('PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE')-and-not$catalogText.Contains('"requirementId": "PR_REVIEW_CANDIDATE_FREEZE_AND_SEQUENCE"')-and(Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repositoryRoot 'AGENTS.md')).Contains('framework/FRAMEWORK_RELEASE.md')) 'release-governance-root-owned-and-absent-from-version-payload'
Assert-True ($releaseText.Contains('final candidate freeze 运行一次 complete current-version suite')-and$releaseText.Contains('baseline executable regression 只适用于仍声明支持且确被')-and$releaseText.Contains('已退出版本只保留历史 identity 与 recovery evidence，不恢复退役套件')-and$releaseText.Contains('一个 independent CRITICAL Source Review')-and$releaseText.Contains('Maintenance `OWNER_ACCEPT` 独立接受 exact approved candidate')-and$releaseText.Contains('没有未 Review 的 free-form/executable change 时，不需要第二次 semantic post-seal Review')-and$releaseText.Contains('deterministic publication preflight')-and$releaseText.Contains('publication 顺序为 `github/main` 后 `origin/main`')-and$releaseText.Contains('失败即停止')-and$releaseText.Contains('tests/canonical-identity-tests.ps1')-and$releaseText.Contains('tests/governance-contract-tests.ps1')-and$reviewText.Contains('same-scope repair 使用新 writer package')-and$reviewText.Contains('focused rereview')) 'release-sequence-proportional-review-owner-accept-seal-git-review-and-two-remote-stopline'

Write-Output 'EVIDENCE_CEILING|MECHANICAL_CONTRACT_ONLY|MODEL_FULLTEXT_READ_AND_HOST_ENFORCEMENT_NOT_PROVEN'
Write-Output ('RESULT|'+$script:passed+'/'+$script:passed+' passed|scope=governance-contract')
