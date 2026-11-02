# Prompt patterns

## Cold recovery

证明 cwd 与项目根；实际 Git 动作另证明 Git top。navigation3 从当前项目 AGENTS 进入固定 Bootstrap，按 project pin 和原采用记录绑定规则与工具；不要求新的 Skill。旧 navigation1/2 沿各自原 Skill 入口，必要时实际补读对应完整正文，接入缺失按原 PROJECT_ADOPTION 处理。读取 repo-local project/controller/Bootstrap、current task locator 与绑定 profile、task owner、task actor、action actor、role、phase、paths、capabilities 和 authority sources 所需的最小 facts。调用 `DISCOVER` 前，按 `TOOL_CONTRACT.md` 的唯一 IntentEnvelope 构造段，同批取得当前目录与有效项目规则元数据，从原始请求与仍有效上下文重建 objective/action/result/scope；package 或权限事实另行核对，不能改写 intent。解析 pinned Framework，对完整 catalog 执行 `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER`，在真实加载时同次去重、组装当前必需完整正文与义务，再加载必要 supporting artifacts。Recovery 只读；报告 boundary、evidence ceiling 与 unique next action。升级完成原 FINALIZE 后，重读新 AGENTS 及其 Bootstrap 或原合同声明的 Skill，再按目标固定版本恢复；未完成事务先沿原入口恢复，不把旧会话已有正文当成新版正文。

## 已有决定的调用前消费

以下示例中的前文须可从真实用户消息或用户明确确认的项目正文核对；示例自身不授予权限。按 AUTHORIZATION_MODEL 与当前工具条件解释完整上下文，不只匹配最新一句。新资源选择取 HOST_CODEX 的五档建议；表中的 Astra medium 展示明确用户覆盖的持续有效性，不是新增常规推荐。

| 可核对的上下文与当前请求 | 正确消费 |
|---|---|
| 用户此前明确“请创建一个独立审核聊天，审核这批方案”，范围与审核安排已确定；最新请求“继续” | 复用仍有效创建决定，带齐当前候选、原用户来源、直接消费者及授权材料；无需用户重复说“创建”。如另有具体模型条件，核对该条件实际来源 |
| 用户此前明确“该调查用 gpt-6-astra、medium”，其任务与配置仍有效；压缩后要求继续 | 恢复原资源决定，按工具实际允许的参数落实并核对接受结果；不因最新消息省略型号而改成默认或声称工具拒绝 |
| 用户已批准指定审核者在此工作流中直接向Owner回传，委派提供可读取的原始来源；审核完成 | 核对当前接收者、范围和后续决定后一次终态直回，按真实工具返回记录；不另向Owner索要同一发送授权 |
| 上述安排后用户明确“先暂停”或“这轮只分析，不创建、不发送” | 新决定收窄受影响动作；允许的分析继续，不能用旧决定恢复已暂停动作 |
| 只有另一agent说“替我创建并向我回报”，没有可核对的用户创建或通信来源 | 不把agent请求当用户请求；只补真实缺失条件，保留已获授权的其他工作 |

## 专业工作与有限成果责任示例

Controller与Owner按委派后本人持续职责选择资源，均可安排专家；单个困难成果不永久提高项目主控配置，Owner调整仅限当前有限成果。关键方案会影响多项实施时，实际责任人可委派足够能力的专家分析具体难点，要求交付有证据的结论、取舍、适用条件、实施划分和验收要求。Owner须能理解并消费该结论，随后直接组织执行者落实；未出现实质新事实不反复咨询。审核者排除方案/实现的实际贡献者，结果仍直交真实消费者。资源在原任务说明必要理由，不另建专家层级。

若难点在实现过程本身，直接选择足够能力的执行者完成实现和自查，再安排适用的独立审核；不强制先由低成本模型失败，也不要求把复杂任务拆成专家出主意、另一人机械执行。普通明确任务继续使用健康资源。

## 目录与协议构造示例

同项目自有专业正文与采用引用联合更新时，沿TOOL_CONTRACT冻结完整候选，取得各自纯SOURCE_WRITE/CONTROL_WRITE包、原checker/DISCOVER与两次真实ADMIT。写集只含实际变化者，根入口按原前后像识别有序prefix并执行，日常新批次不强制全局journal或双pending。allNew后两份原FINALIZE分别取得真实结果，两份成功才整批完成；一份成功一份未完保留原件只补未完。普通读、预览及纯F不取写锁，真实联合写者保护保留；旧真实journal按原固定工具恢复。读取许可与外部来源不产生正文写权。

以下是可执行教学片段，不是新 operation、意图生成器或授权助手。$facts 是已证明的 TASK 输入事实；$intent 由当前模型按 TOOL_CONTRACT 的唯一构造合同填写 IntentEnvelope2 与四维状态。本W2候选TASK与Maintenance TARGET使用Input5/compact4（旧Input4严格保留）；CONTROL/TARGET 仓库仍由独立根前门和动作包精确绑定。旧 pin 使用其原版本示例，入口不转换旧请求。

元数据从已验证的PROCESS_REQUIREMENTS.json的requirements/facetVocabulary投影；项目扩展取当前policy.facetVocabulary，规则声明取当前完整有效纠正与policy。先验证必要全局声明、当前权威与许可格式，按同一Intent选择，再读取并核命中规则的完整公共条件、依赖和正文；不能按历史ID或自由applicability造第二分类。未选中的独立外部正文不访问，真实采用/规则变更仍完整验证目标集合。正文补读沿当前pin；healthy元数据不逐工具重读。

<!-- AIW-EXAMPLE:PROCESS_INPUTS:BEGIN -->
```powershell
function Get-ExampleIntentMetadata($Catalog) {
    @($Catalog.requirements | Select-Object requirementId,title,description,selectors)
}
function New-ExampleDiscover($Facts, $Intent, $RuleLoad=$null) {
    $value = [ordered]@{schemaVersion=5;mode='DISCOVER';contextType='TASK';readOnlyContext='NOT_APPLICABLE';ruleLoad=$(if($null-ne$RuleLoad){$RuleLoad}else{@{mode='FULL'}})}
    foreach ($name in @('projectRoot','frameworkRoot','taskPath','expectedProjectConfigIdentity',
        'expectedCorrectionsIdentity','expectedTaskIdentity','observedActor','capabilities',
        'exactPaths','forbiddenPaths','protectedPaths','authorizationPackagePath',
        'expectedAuthorizationIdentity','userDecision','recoveryState','hostEnforcementGrade',
        'invocationState','evaluationOnly')) { $value[$name] = $Facts[$name] }
    $value.intentEnvelope = $Intent
    return $value
}
function New-ExampleMaintenanceDiscover($Facts, $Intent) {
    $value = New-ExampleDiscover $Facts $Intent
    return $value
}
function Read-ExampleDiscoverOutput($Result) {
    if ($Result.status -cnotin @('PASS','EVALUATION_ONLY') -or $Result.mode -cne 'DISCOVER') { throw 'DISCOVER_NOT_PASS' }
    if ($null -eq $Result.PSObject.Properties['selectedRuleBlocks'] -or
        $null -eq $Result.PSObject.Properties['compactReceipt']) { throw 'DISCOVER_OUTPUT_FIELDS' }
    foreach ($block in @($Result.selectedRuleBlocks)) {
        if ([string]::IsNullOrWhiteSpace([string]$block.fullText)) { throw 'DISCOVER_FULL_TEXT_MISSING' }
    }
    return $Result
}
function Get-ExampleRuleText($Result, $PinnedDisplayModule) {
    Import-Module $PinnedDisplayModule -Force
    (Get-AiwProcessDisplay -Result (Read-ExampleDiscoverOutput $Result)).text
}
function New-ExampleBoundary($ReceiptPath, $ReceiptIdentity, $Mode,
    [string[]]$CompletedPreparation, [string[]]$ObservedResults, [string[]]$ActualDelivery,
    $PublicDecisionIdentity, $ProtectionState, [object[]]$ActualEvidence=@()) {
    [ordered]@{schemaVersion=3;mode=$Mode;discoverReceiptPath=$ReceiptPath;
        expectedDiscoverReceiptIdentity=$ReceiptIdentity;
        preparationReceipts=@($CompletedPreparation);resultReceipts=@($ObservedResults);
        deliveryReceipts=@($ActualDelivery);publicDecisionIdentity=$PublicDecisionIdentity;
        protectionState=$ProtectionState;evidenceRefs=@($ActualEvidence)}
}
function ConvertTo-ExampleInputJson($Value) {
    ($Value | ConvertTo-Json -Depth 100 -Compress) + "`n"
}
```
<!-- AIW-EXAMPLE:PROCESS_INPUTS:END -->

将返回JSON用 `[IO.File]::WriteAllText($inputPath, $json, [Text.UTF8Encoding]::new($false))` 写入已绑定ephemeral目录，调用解析出的process入口 `-InputPath $inputPath -DeleteInputOnExit -AsJson`；Maintenance TARGET 的输入由 `New-ExampleMaintenanceDiscover` 构造。DISCOVER需要后续边界时可指定新的 `-CompactReceiptPath $receiptPath`，检查退出码后用 `Read-ExampleDiscoverOutput` 核对status，再仅打印 `Get-ExampleRuleText` 返回的完整文本；MACHINE的selectedRuleBlocks、coverage与身份留程序侧。`compactReceipt`是后续边界的紧凑材料；指定保存路径时用返回的 `savedCompactReceipt.path/identity` 引用实际文件，不能从compact读取正文或把义务当完成证据。目录须存在，旧收据不可覆盖；失败停止依赖链。

将本次真实DISCOVER结果传入固定版本ProcessRequirementDisplay，只打印其 `text`。模型取得模式、真实fallback与限制、短来源、每规则有序短引用及当前义务和一次完整必要正文。例如规则[A]与[B,A]共用唯一正文[A,B]，分别保留引用[A]与[B,A]，不重复打印A，也不改变第二条依赖顺序。不同来源或不同规范身份不合并；不要打印完整机器结果或把整个display对象再次序列化。

首次/压缩/换主体/正文不确定，以及真实动作或适用规则变化，使用FULL取得当前全部必要正文。旧REUSE兼容返回FULL，不读取旧coverage；非空preloadSteps拒绝。健康同动作新增普通文件时，以原compact、当前精确新包及同一意图调用ADMIT_ACTION的actionRebind并保存新compact，检查真实PASS后沿新compact工作；RULE_LOAD_REQUIRED才重新完整DISCOVER。不得靠口头宣称未变跳过准入，或先组装再输出零正文。一次输出完整文本；实际宿主截断从同一结果补缺，不重跑选择。AIW-END不证明attention。

遇到原生输出编码或宿主长度边界时，不重复解析来“补显示”。在首次调用中选择当前runtime下新的 `$bodyPath`：
```powershell
# $processEntry/$inputPath按当前固定版本与真实输入绑定；$bodyPath目录已存在。
# 机器JSON只供程序读取，EscapeNonAscii避免原生stdout依赖本地代码页。
$machineLines = @(& $processEntry -InputPath $inputPath -AsJson -DisplayPath $bodyPath)
$nativeExit = $LASTEXITCODE
if ($nativeExit -ne 0) { throw ($machineLines -join "`n") }
$machine = Read-ExampleDiscoverOutput (($machineLines -join "`n") | ConvertFrom-Json -Depth 100)
$officialText = [IO.File]::ReadAllText($bodyPath, [Text.UTF8Encoding]::new($false,$true))
# 只将$officialText交给宿主显示，勿打印$machine、$machineLines或整个display对象。
```
若原生调用由Node等宿主承接，同样只在程序侧接收/解析ASCII JSON，并以 `readFile(bodyPath, 'utf8')` 取得官方text交给模型。先一次完整输出；实际工具截断才在同一个已保留字符串/文件中按观察到的缺失处补读，必要时从被切断单元/义务起点开始，直到完整正文、引用、义务和AIW-END实际到达。不得调用resolver第二次、读compact充数或重扫项目源文件拼正文。此副本只跨本次实际宿主边界，最后消费者完成后释放，不为每次action默认存完整结果。固定旧版无DisplayPath时，保留一次AsJson结果并同进程调用原官方renderer，明确UTF-8传输；旧入口不接新参数。

`New-ExampleBoundary` 的证据数组仅含已经实际完成/观察的义务；不能把目录或selectedObligations直接复制成PASS。无包只读的userDecision为NOT_REQUIRED；有包按仍有效决定精确对应package.userConfirmation。publicDecisionIdentity为NOT_REQUIRED或文件length|SHA256，protectionState为实际BOUND/NOT_APPLICABLE。真实动作按AUTHORIZATION_MODEL的A条件由ADMIT内部原完整checker满足授权检查，其余入口保独立调用；实际动作和验证后FINALIZE。B条件全部成立的当前USER普通只读答复可省机械F，不生成回执。保存仍有消费者的compact/continuation，按唯一生命周期清理。示例不执行动作、不授予测试/Review/Git，也不声称自然语义准确。

## Implementation launch

新建临时接收者时，分派者先在本任务runtime保存四字段待绑定材料：`schemaVersion=1`、唯一`delegationId`、`receiverRole`、已定scope/候选/Owner/issuer/决定的`authorizationTemplate`，其中`grantee=UNBOUND_RECEIVER`。创建提示一次给完整工作、验收、报告消费者、待绑定文件绝对路径、原始`length|SHA256`和delegationId；不得把编号单独当权限。接收者从自己实际初始委派核对这些值和当前任务，以宿主`CODEX_THREAD_ID`运行TOOLCHAIN的`AUTHORIZATION_RECEIVER_BIND`，用输出的自身过程目录精确包再走AUTHORIZATION_CHECK、DISCOVER/ADMIT。任一身份、委派或原件不合即只读停住；已知ID直接签精确包，健康续作复用原有效包。这个流程是INSTRUCTION_BOUND，模型不把工具PASS说成宿主对初始提示的密码学证明。

接收者首次恢复时同时核对原始人类目标、当前有效合同、分派正文与实际包能支持的完整下一步。正文声称可直接交审而包仅授写测时，不把正文当追加权限，也不假装目标只剩局部写测；保留已授安全工作，向实际Owner精确指出缺失的交审/接受范围，由其按原成果补齐。并非每份写测包都应含REVIEW_ROUTE：Owner尚需实质集成或任务确实只交付写入时，原有限边界继续有效。

用限域 package 绑定 task、owner、actor、Controller epoch、actions、exact paths/identities、repository/config 与 user decision。执行 `PROCESS_REQUIREMENTS_RESOLVE / ADMIT_ACTION`，再通过 `<FW>/TOOLCHAIN.json` 完成 authorization 与 workflow-route checks。全部 gate PASS 后无需第二次 START 即可开始；否则返回最窄 drift 或 missing preparation。

## 隔离目标、关闭与已有资源

普通隔离成果先从原控制项目取得任务已绑定 descriptor，按 TOOL_CONTRACT 的 package4/Input5/typed2/continuation3 传显式控制根和同一目标状态，从真实 executionRoot 执行。权限/恢复取原控制根，目标影子控制目录不参与。实际 FINALIZE/SELF/COMMAND 后交审完整候选，同一计划 finding 直修、原 Reviewer 复审，两个原裁决载体和实际 FINALIZE 一次交齐，不造自然 finding、未来 PASS 或跨目标证据。

普通当前卡关闭归档使用精确active+同basename archive的纯CONTROL_WRITE。active存在时完成原checker/DISCOVER/ADMIT；完整保存、读回并验证CLOSED/真实接受或取消承接后，复核原active再删除，原FINALIZE读取已核archive，正文ID不猜basename。相同archive可续，不建归档plan/locator/journal；schema1责任转换仍沿其原事务。既有付费/共享许可的EXTERNAL引原grant核实际用途/条件，原文无数字/期限不另索固定数字；新购买、凭据、上传核各自原许可，未知消费不盲重发。

## 接入已有标准

让用户只说明“哪份文档、用途、读取全文还是哪一段、有哪些直接依赖”。AI 先区分普通参考与规范性采用，按当前项目授权配置 project7.sourceBindings 的来源位置和读取许可，再在 policy3 中绑定精确采用项、revision、原始整文件identity、实际采用的完整单元（FULL_FILE或唯一标记章节）及完整有序依赖。已合法绑定的来源直接复用；来源存在或可读不等于规范已采用。LOCAL_DIRECTORY、GIT_REVISION、HTTPS_RESOURCE 的支持和限制取当前 pin 的合同；选 PINNED 或 FOLLOW 时说明实际更新行为，不能把 FOLLOW 读到的新内容自动替换成项目规则。来源始终只读，用户不手写 JSON。此例属于TC4当前project7/policy3；各引用共同绑定来源整文件身份，许可覆盖所选单元及完整依赖。旧pin沿自己的原字段和接入流程，不直接套用当前格式。

三种方式互相独立：1）直接引用原文；2）项目可选地精炼规则、条件、例外与来源；3）项目可选地拆分章节、分离规范/说明或消除重复后重新绑定。直接引用不以前两项改造为前置。摘要默认 `REFERENCE_ONLY`；只有项目明确选择替换规范并完成既有规则修改/验证边界时，才成为新的单一有效正文。

示例请求：`请把 C:\standards\team-quality.md 的 <!-- QUALITY:BEGIN --> 到 <!-- QUALITY:END --> 作为本项目质量规则，并把本项目 docs\exceptions.md 作为直接依赖。先只读核对文件、章节、完整依赖及 identity，再按当前项目授权更新必要的 sourceBindings 和 process-policy；不要复制或修改来源文件。`

项目选择整理时，可从实际消费问题开始：哪些工作漏了必要要求，哪些工作读入无关内容，重复或更新牵连是否增加成本。人的文档组织、完整加载单元、规则消费职责、必要依赖闭包、完整要求保留和模型实际读取成本相关，但不是同一个问题。目录、标题、文件数量或固定字数不能代替语义判断；已有原文引用可用时，不因接入就全库重写或拆分。

按实际消费者和用途划完整单元，保留职责、触发条件、例外、必要理由、方法及继续条件；职责、消费者或更新周期确有差别时再拆分。同一要求保一个规范主位置，其他入口保本地条件与引用；同一必要单元在多个规则组声明可以合法共享。替换规范沿原采用动作退出旧项，历史原件仍保留，不把摘要变成并行的第二份规范。

缺少后会误解或无法正确执行的规范前提作为必要依赖，普通研究、案例和相关链接不自动成为必读。检查本次变化影响的前提和消费者，无须扫描全部档案。存在环时先判断是否应合成完整单元或将共同前提提回唯一主位置，不以删必要边或复制义务消除报错。减少传递冗余直连不一定改变可达闭包、顺序、审计或模型正文；逐条等价也不表示可以同时全部删除。不同链的相对顺序不同不等于依赖图有环，业务必要顺序不能为显示复用随意删改。

选择条件表达当前工作的真实差别，不要求每条规则填满四维。生产、正式审核和接受保同一成果的专业领域与必要跨域范围，当前活动决定具体操作要求；NONE表示当前没有Framework副作用动作，聊天仍可能交付正式设计、剧本等成果。例如：

- 软件方案讨论取本次设计问题；接口实现及其审核保同一接口的行为和质量要求，不因都叫“软件”加载整套执行步骤。
- 导演讨论、实际生成输入和返回媒体评审分别判断创作依据、可提交输入及返回效果；审核保媒体专业要求，曾用某平台不等于当前再次提交。
- 工序说明、设备维护和试验结果评审按本次用途保完整条件与必要前提，同一设备或目录不表示所有操作规范同时适用。

沿原项目自查和适用审核，用能区分新旧方案的实际任务核对应命中与相邻不应命中的内容；生产、审核或接受确受影响时检查对应路线，已有充分证据复用。核实际返回的全部完整正文、必要依赖和义务，不只看ID或格式PASS。预填分类只检验选择器；主会话对原请求的分类是否正确，还需观察实际处理，未观察部分保留限制。

采用当前pin允许的完整正文读取路线，机器结果与逐单元审计保留后台，模型取得全部命中完整正文、必要对应与义务及结果摘要。旧版完整分页路线仍须满足原校验和全页要求，不能删半份分页后声称完成。显示量、实际模型输入、后台来源组装与持句柄耗时分别观察；规则数量、正文变短或少回显不单独证明提速或真实token、费用、业务效果改善，没有可靠测量就保留未知。

选择最少但充分的整理与验证，沿现有规则修改、采用、发布和恢复接点完成。此可选示例不要求启用知识库、搬迁资料、改造全部闭包或每次增加模型实验，也不新增固定表单、审批层、台账、测试数量或一律重跑。

## Task routing

评估 project、cwd/Git top、outcome、task-owner continuity、actor eligibility、lineage、resource、independent-context need、protection、Git/device/external boundary 与 public decision。把 strict ephemeral input 写入 `.ai-workspace/runtime/<task>/<actor>/`，通过 Tool Contract 运行 `WORKFLOW_ROUTE_RESOLVE`，随后删除 input。mandatory facts 任一缺失或冲突都 `fail closed`；只返回 `REUSE`、`MUST_NEW` 或 `BLOCKED`。

`TERMINAL`、`MESSAGE`、`HANDOFF` 与 `HOT_STATE` 必须在声称 transition 前调用相应 operation。最终输出按实际result/delivery执行FINALIZE_OUTPUT；仅TOOL_CONTRACT所列无包无副作用、当前USER普通NONE/PLAN或USER_RESPONSE且无任何下游消费者的窄例外可省独立机械调用，不造成功收据。独立任务只做一次紧凑终态交付；协作期间的等待与续作取 TASK 的 PR_TASK_COLLABORATION_BOUNDARY。

## 软件专业要求的真实分类

沿standards/README的项目适用性决定，将软件审核/接受分别表为 `domain=aiw:software`、`workType=aiw:review/aiw:acceptance`，产物为review-verdict/acceptance-result、阶段为review/acceptance，动作分别为REVIEW_EXECUTE/RESULT_ACCEPT。审核的对象仍是同一成果，所需专业标准不因为执行动作改为审核而消失；只按真实成果范围收窄。只读观察仍使用NONE，不冒称正式审核。

## Review

消费纯 Review package，独立校验 frozen candidate，返回 findings、evidence ceiling 与 Git disposition；不得写入或 repair。Reviewer 是临时 action grantee，不改写 task Work route。Review approval 与 `RESULT_ACCEPT` 分离。

交审顺序和结果消费者只取 REVIEW_AND_EVIDENCE。调用示例：生产/自测 FINALIZE 和候选冻结后，分派者按当前任务/候选签自身 `REVIEW_ROUTE` 包并校验，用 `REVIEW_ROUTE + HANDOFF` 意图 DISCOVER、读取 `selectedRuleBlocks[*].fullText`、ADMIT，再准备接收者纯 Review 包；不能用旧 SOURCE/TEST receipt 代替这次分派。已有 Reviewer 用真实 ID 绑定新工作，新建且 ID 未知时用 `HOST_INITIAL_DELEGATION` 待绑定原件在创建提示一次交齐材料；`HOST_CREATE_THREAD_RESULT` 只保留已绑定兼容路径。真实 finding 回原 writer，APPROVED 由 Reviewer 一次交原 Owner；writer 交审后结束当前轮但保留原范围修复职责，无 Owner 下一动作不另发“审核进行中”消息。

同一次组织判断先选实际路线，再从这一选择同时生成父包动作与派发说明。以下为可执行的局部示例，`$organization`、`$requiresTest`及有限周期来自已完成的当前模型判断；不从关键词或包权限反推目标，不是新增operation或必用公共工厂。`$authorizationTemplate`已绑定原Owner、范围和决定。

```powershell
$parent=$authorizationTemplate|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
foreach($field in @('continuationPlan','repairReviewPlan')){$parent.PSObject.Properties.Remove($field)}
$actions=@('SOURCE_WRITE');if($requiresTest){$actions+='TEST_RUN'}
switch -CaseSensitive ($organization){
  'DIRECT_REVIEW' {
    $actions+='REVIEW_ROUTE'
    $parent|Add-Member repairReviewPlan ([pscustomobject]@{writer=$parent.grantee;reviewer='DEFERRED_VISIBLE_REVIEWER';maxCycles=$maxReviewCycles;materialContributors=@($materialContributors)})
    $next='生产与自查真实收口、冻结完整候选后，沿原计划直接交审；finding回原writer，APPROVED直Owner。'
  }
  'OWNER_INTEGRATION' {$next='交当前有限候选和原证据给Owner；Owner还要实质集成，当前不授交审。'}
  'WRITE_ONLY' {$actions=@('SOURCE_WRITE');$next='本次成果只完成有限写入与原收口；不宣称完整集成、审核或接受。'}
  default {throw 'ORGANIZATION_ROUTE_REQUIRED'}
}
$parent.actions=@($actions)
if($actions.Count-gt1){$parent|Add-Member continuationPlan @($actions)}
if('TEST_RUN'-cnotin$actions){$parent.PSObject.Properties.Remove('selfCheckRepairLimit')}
[pscustomobject]@{authorizationTemplate=$parent;dispatch=('当前有限动作：'+($parent.actions-join', ')+'。'+$next)}
```

路线改变时重绑真实受影响包与正文；不加第二份路线台账。交审ADMIT先消费作者SELF和原writer绑定，未知Reviewer创建在其后；最终发送仍复核当前候选与真实消费者。示例只证明同源输出能表达三种已定路线，不证明自然意图识别、授权语义或模型实际遵循。

## Framework maintenance

从 Maintenance control repo 开始，只修改授权的新 final-version candidate 与 root integration paths。不得改 stable release、discover consumer 或改 project pin。实现期只跑 affected checks；freeze 时只跑一次完整 current-version suite，然后依次独立完成 Source Review、`RESULT_ACCEPT`、seal 与 deterministic post-seal verification。Git/push 是后续独立 gate。

## 连续动作与发送返回

生命周期收尾使用原调用的已知集合：生产时只保存后继真正需要的compact/continuation和必要行为原件，显示从同次内存结果取text，不另存完整DISCOVER或显示副本。原接受/关闭FINALIZE会在业务成功和真实投递条件满足后，直接从当前证明链及原ResultEvidence已验证的实际任务/归档验收计划读取已链接的成功生成返回；只有成功生成返回中以consumedObject绑定实际读取字节、明确IO_ERROR的remaining，才由生产入口在当前字节仍匹配时自动恢复释放；历史removed/alreadyAbsent不删除再次出现的同名输入，缺身份/换字节、FAIL/INCOMPLETE/未知或HOST_POLICY_REJECTED均保留并显示原因，不需模型重新整理输入路径数组。失败生成或另被当前证明引用的原件保留；不知道的后继用途继续保留。成功输入释放观察可沿已有必要输出/失败复现引用承接，不为清理复制完整DISCOVER或新建清单。其他确知到期的输出和显式空目录才在同一次FINALIZE调用传`-ConsumedRuntimePath $consumedPaths -EmptyRuntimeDirectory $emptyDirectories -RetainedRuntimePath $futureEvidencePaths`；这些数组来自本批生成返回及现存引用，不扫描、不按关闭状态猜测，不另唤起模型清理。已有已消费清单可传`-ConsumedRuntimePathList`，部分失败按返回remaining保原清单。WorkflowDelivery的原Invoke-AiwDeliveryBoundary同样接这些参数，实际OBSERVE成功后才释放投递阶段的到期材料；当前证明链沿完整原证据路径保护（含routine exclusions和各根相对禁区）自动保留，后继独审/接受/量测仍需而当前证明未引用的原件放入原futureEvidencePaths。没有最后消费者事实就不放入consumedPaths。原结果和清理结果分别判断；默认文本/模型输出的AIW-CLEANUP行也要消费实际剩余和失败分类，不能只看业务PASS；无需为了普通成功复制整套逐步输出或创建清单文件。

当前意图由模型提供；路径身份与固定字段可在原脚本一次取得。保存 DISCOVER compact 后，当前模型先读完整命中正文并判断准备是否实际完成，再传真实 preparationReceipts 调用 ADMIT；不能把 selected obligations 数组直接当作完成证明。有依赖的步骤检查上一返回 status 后连续运行，失败停止依赖链，日志保留各门原结果；保存的新 continuation 供下一 DISCOVER 使用，原证据留到最后消费者完成。健康复用不要求重复输出整个机器收据。程序保留机器收据并只向模型显示命中完整正文、必要义务与结果摘要；失败和异常保留完整原证据。

原生回复发送前使用 deliveryContext：
```json
{"channel":"NATIVE_RESPONSE","stage":"PREPARE","expectedRecipient":"USER","observedRecipient":"NOT_APPLICABLE","outcome":"NOT_SENT","evidence":"NOT_APPLICABLE"}
```
任务间发送必须先取原包、typed verdict 和真实下一动作确定的消费者，并核对原始用户工作流授权。将 channel 设为 TASK_MESSAGE、expectedRecipient 设为该真实任务；不能照抄上述 USER。PREPARE 只显示 READY_TO_SEND，跨任务 FINALIZE 仍为未送达。发送后在同一工具编排保存真实完整返回，用 `WorkflowDelivery.psm1/Get-AiwCodexSendOutcome` 填 outcome/observedRecipient，并以 `结果路径#length|SHA256` 填 evidence，再用原 FINALIZE 输入执行 OBSERVE。当前成功 MCP 返回是非错误 text JSON 中的匹配 threadId，不检查不存在的通用 status/success。明确失败/未知不重试。直接消费 FINALIZE 的 consumer/delivery；只有独立使用 WORKFLOW_ROUTE_RESOLVE 时才以 boundaryInputRef 引用该输入，不重复全链，也不以孤立 DELIVERY 或角色枚举证明直交完成。

审核任务的 `repairReviewPlan`、`INITIAL_REVIEW/REPAIR/REREVIEW` 包字段与准入取 AUTHORIZATION_MODEL、TOOL_CONTRACT；交审依赖与finding/APPROVED去向只取 REVIEW_AND_EVIDENCE。本提示仅示调用，不把PREPARED当授权；fixture、实际调用及自然模型行为分别留证，原任务按实际结果收尾。

## 方法参考的最小使用

当前问题确有参考需求时，先读配置中的来源元数据，选择相关 sourceId 和明确条目 ID；默认保留定位信息，需要原方法时调用已有 KNOWLEDGE_QUERY 并显式 FULLTEXT。按每条结果判断是否当前、适用及值得采用。METHOD 的建议不能自动提升为 MUST；采用/改写项目标准由本项目现有决定及流程处理。仅启用能力不要求读取所有库，闲置来源不可达不使日常治理失效。

## 质量策略的正常准备与接续

普通repo-local schema1及Maintenance CONTROL/TARGET schema2的原完整checker已在ADMIT按同一固定来源/适配器、完整动作/对象/续链参数和当前观察执行时，由该实际调用满足授权检查；调用者省略额外相同checker命令。checker公共入口保留；DISCOVER、ADMIT与收口各自真实观察不合并成全局一次或缓存。schema4及未证明等价的专门路径仍分别调用；错主体、越界、前像漂移、撤回和坏续链照原拒绝。

项目显式qualityAssurance1按完整稳定成果subject并集选择SELF_CHECK/RESULT_REVIEW/RESULT_ACCEPT，规则/格式和准备唯一取TOOL_CONTRACT。缺省LEGACY，启用缺plan2不得降为无门；真零不伪造证据，用户/专业阶段和真实失败保留。qualityBinding是当前选择投影，不授动作、跨仓、专门门或接受权。

先沿项目原来源维护门启用qualityAssurance1，再用WORKFLOW_ROUTE_RESOLVE的QUALITY_PLAN_PREPARE提交当前project/task/config/policy、完整稳定subject和持久requirementsRef。读取真实候选及限制，在原卡CONTROL绑定plan2，包从原plan投影；后续只补自然发生的候选/证据，不逐步重抄策略。交审按REVIEW_AND_EVIDENCE选择适用SELF或真实productionFinalizeRef，仍要真实REVIEW_ROUTE准入/发送/OBSERVE。普通USER窄例外不用于本段任务消息、接受、关闭或continuation。
