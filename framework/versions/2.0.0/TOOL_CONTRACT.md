# Tool Contract v4 — bounded actions and isolated targets

## Root 首次候选注册与 origin

根 PROJECT_ADOPTION 导航注册参数。2.0 首次显式 LocalCandidatePilot 只消费合格固定 PACKAGE_MANIFEST schema2 与实际执行同一运行根；复用 root State 的候选资格校验，registrationEligible/localCandidatePilotEligible 均为 true。InitialTaskPath/ExpectedInitialTaskIdentity/InitialTaskRelativePath 成组，后者为 active 下与任务 ID 一致的有限首卡；现有任务 checker 校验整卡、真实 Owner/actor/Work route/profile 与精确范围。仅控制面缺失时 root REGISTER 可初始化该组，稳定默认调用保持。

原采用 state 路径不变。schema7 的严格字段为 schemaVersion、originKind=REGISTER、projectId、repositoryRoot、toVersion、projectionMode=LOCAL_CANDIDATE_MANAGED、transactionComplete、targetReleaseCanonical、targetReleaseManifestIdentity、distributionBinding、origin、currentTransactionRelativePath、registrationTransactionIdentity、projectFormat、projectCapabilities、rootToolRevision、rootToolDependencies、projectionObjects。origin 只含 operation=REGISTER、transactionRelativePath 和 registrationId。首次 currentTransactionRelativePath 为 runtime/project-adoption/register/state.json；registrationTransactionIdentity=SELF_PROJECTION_BOUND，依靠真实 COMPLETE journal 投影中的 state.newIdentity 验证自身，不能把最终 journal hash 再回写自身。projectionObjects 不含 state 自身。

REGISTER journal 保存真实 schema1 事务，metadata 绑定 operation、frameworkPin、targetProjectFormat、rootToolRevision、分发/候选身份、同一 registrationId 和 initialTask 的 relativePath/identity；completedWrites 必须等于 changed projection 数，项目根和路径必须相同。任何缺失、不完整、根/对象/候选漂移均拒绝正常 load；true 字段或模板不是完成证明。首次预检只允许私有实际 SourceRoot/StageRoot 与已核验投影上下文，普通 CLI 没有放行 APPLYING 的开关；Postcheck 检查实际后像，COMPLETE 最后登记，随后正常读取复证。闭合后读取失败明确报告 REGISTERED_RUNTIME_VALIDATION_FAILED，不回滚闭合事务。

schema7→7 使用既有根 PREPARE/原 ADMIT/schema3 Apply/原 FINALIZE/RecoverRuntimeAdoption，不转换成 schema6 或制造升级旧材料。currentTransactionRelativePath 切至独立 refresh/state.json，registrationTransactionIdentity 绑定真实原 COMPLETE REGISTER 整文件身份；原 origin/id/journal 保留。重复刷新仍保持 journal 的临时 previousTransaction 恢复和提交释放语义。schema6 原路及显式格式/major 迁移不扩面。当前任务、规则和项目决定独立校验，初始任务/安装文件可合法演进或归档；正常使用不冻结其今日字节。完成证明属于在用恢复依赖，不能按 runtime 目录名清理。

Framework operation 是 language-independent contract。backend 是 adopting project 一次选择的 immutable implementation，不是 task role、action、resource route 或 authorization capability。

## PROCESS_REQUIREMENTS_RESOLVE

一个 source composer 提供三个 logical mode：

- `DISCOVER` 严格绑定 project、当前 task 或显式 `PROJECT_READ_ONLY` request context、host-authenticated actor、effective role/phase、profile、project-declared capabilities、objective/action/result kind 与 normalized exact scope。task context 继续绑定 whole task、Owner 与 Work route actor；只读 context 必须绑定 session/request 且只能使用 `NONE + PLAN/USER_RESPONSE`，不能伪造任务或绕过已知冲突。`pathHints` 必须位于 scope 内，`capabilityHints` 必须已观察，mutation/external hints 必须匹配 requested action。CLEAR contradiction 失败；UNKNOWN 保留 conservative-load ceiling，不能 admit governed action。resolver 对完整 generated metadata catalog 选择，校验 selected locator 与 owning Markdown module，一次返回每个 exact complete block，并另给 compact receipt。still-effective corrections 与 permanent project rules 保持独立 source。
- package grantee 可执行当前 action 或 `continuationPlan` 中预授予的写/测与最后一步组织 `REVIEW_ROUTE`，不改变 Owner/Work route/task identity。该路由只在真实成功生产FINALIZE及当前候选的适用准备（LEGACY/选SELF为成功typed SELF_CHECK；C无SELF为下述原productionFinalizeRef）后续接，计划绑定顺序；写测复用原整组 exact scope，最后交审可取原包预批的 reviewScope。独立 `REVIEW_EXECUTE`、`RESULT_ACCEPT`、Git、browser/device 与 external 不进入计划。
- `ADMIT_ACTION` 只消费 exact compact DISCOVER receipt，复检 task/Framework/catalog/project/correction/policy/custom identities，按 current exact object bytes 重跑 authorization observation，并校验 selected preparation；它不授予 action。
- `FINALIZE_OUTPUT` 重验 sources 与 observable result/delivery；每个 exact path 必须有唯一且匹配 current object 的 `OBJECT_POSTIMAGE`。有未完成计划时才返回 `INSTRUCTION_BOUND`、`authorityGranted=false` 的 `AUTHORIZED_ACTION_CONTINUATION`，绑定原 package、source Discover identity/action/step、task/actor/repository/config/Controller/decision/protection、下一步骤与整组 postimage；不保存无法由 checker 复验的 finalize hash。

后续 `DISCOVER` 可选成对携带 `continuationReceiptPath + expectedContinuationReceiptIdentity`。resolver/checker 复证 receipt bytes、原 package、source action/step、next step 与 current objects；未知字段、错链、第三方/越界、错包、虚假或 stale postimage 均 fail closed。普通项目与 Maintenance root authorization/process adapter 共用实现，root 只补 topology/repository 验证和透传。

原 `repairReviewPlan` 的四个字段 writer/reviewer/maxCycles/materialContributors 保持必需，可选唯一增量 `reviewScope=[{path,identity}]` 复用 objectIdentities 格式：非空、唯一、规范仓库相对 literal 文件路径，identity 为 length|SHA256 或 NEW。仅原 actions 明确授予 REVIEW_ROUTE 且 continuationPlan 以它结束时可配置。M=父 exactPaths 必须包含于 A=reviewScope.path，M 的冻结身份等于父 objectIdentities；缺省 A=M。实际缺失候选将 NEW 转为 MISSING，路径保护、排除和 reparse 校验在访问前执行。A\\M 必须仍匹配原字节或缺失状态，不能静默吸收新身份。

continuation.exactPaths/postObjectIdentities 表示 nextAction 的范围：生产、测试及有限返工为 M，最终 REVIEW_ROUTE 为 A。已完成动作的范围从原 sourceDiscoverReceipt 读取，逐 path OBJECT_POSTIMAGE 仍只证明该完成范围。只有实际成功生产FINALIZE及适用SELF/原生产证明验证后，才把真实 M 后像与未改冻结 A\\M 合成 A；重新 hash M、伪造 FINALIZE/decision 或结构性 PASS 的失败测试均不能承接。TEST_RUN 的软件 COMMAND/SELF 绑定 M，REVIEW_ROUTE 的候选准备 SELF 绑定完整 A，二者不可互换。selfCheckRepairLimit 链始终限制返写/重测在 M，最终 A receipt 不允许倒退取得 A 写权。

原 package 可选 `selfCheckRepairLimit`，值为正整数且不超过 Int32 最大值，只用于 `SOURCE_WRITE` 或 `TEST_WRITE` → `TEST_RUN` → 可选最终 `REVIEW_ROUTE` 的短计划。它预授予同主体、同整组范围的有限自检返工，与独立 finding 的 `repairReviewPlan` 分开。该值由原成果的实际范围、不确定性和验证成本确定，框架不规定两次或其他统一默认。它是原包预授的有限返工次数，不是每次失败都须重新取得Owner/用户决定的要求，也不是必须用完的重试配额；是否继续及何时因无进展停止按TASK职责判断，判断本身不增加额度。独审修复包从原 finalized verdict 所绑定的实际生产链承接已用 selfRepairCycle，不因新派生包重置；独审 cycle/maxCycles 仍独立计算。缺省仅允许原线性计划；真实预定的 SOURCE→TEST→SOURCE 可按原顺序在失败后续写，不能把预填多轮称上限或在早通过时跳步。

boundary schema3 的 `FINALIZE_OUTPUT` 可选 `continuationDisposition=ADVANCE/REPAIR/RETEST/STOP`，缺省 ADVANCE，显式值进入 decisionIdentity；其他 mode/schema 拒绝该字段。当前 TEST_RUN 的全部 SELF_CHECK 聚合为 FAIL 优先、其次 INCOMPLETE、否则 PASS；缺失、假结果、错误候选或来源仍拒绝。合法失败/不完整输出可结构性 PASS，同时返回 `actionOutcome`（TEST_RUN 为聚合值，其他动作为 OBSERVED）与 `successorState`；它不声明测试、任务或成功前置通过。successorState 为 AVAILABLE 时才有 continuationReceipt；NONE/FINISHED、SELF_CHECK_FAILED、INCOMPLETE、STOPPED、NO_REPAIR_PERMISSION、REPAIR_LIMIT_EXHAUSTED 均没有后继。FAIL 不能进入最终交审，INCOMPLETE/未知退出结果不自动返写或重测，STOP 只收口动作，未完成任务仍归 Owner。

REPAIR/RETEST 只接受当前 TEST_RUN 的真实 FAIL：原有限许可及额度有效时，REPAIR 返回计划第0步，RETEST 返回第1步，每次消耗一次额度；重新 checker/DISCOVER/ADMIT。REPAIR 后真实写入再测试；RETEST 候选须未变，调用者交代实际重测理由，不能补空 SOURCE。无许可或耗尽只收口失败，不生成权限；非 FAIL 或非 TEST 请求分支拒绝。原动作内、健康 lease 的安全重跑继续现有机制。命令未取得退出码时用有原始依据的 MODEL_JUDGMENT/INCOMPLETE，不能虚构 COMMAND exitCode=0。参数、测试或fixture失败不自动免计。耗尽后的新许可由实际issuer依据当前后像、原失败及剩余成果明确签发，保留原链和已用事实；不得修改旧包或把另起包称为原额度自动重置。无权限、来源/保护漂移及未知/不完整状态不因说明“有进展”而放行。

带该许可的 continuation 使用 schema2，在原全部绑定字段上增加 `transitionKind=ADVANCE/REPAIR/RETEST` 与 `selfRepairCycle`；原无许可 schema1 线性路径保持。checker 沿 source DISCOVER 中精确的前序 receipt 引用复算额度和顺序，拒置零、跳轮、断链、循环及来源/保护漂移；只有当前叶后像核对 live bytes，历史失败按冻结后像与原始证据验证，不能要求已合法修正的旧像永远等于 live。该有限链的 DISCOVER、receipt 与独有失败证据留到最后消费者完成，不设消费台账或全历史扫描。成功交审仍复核当前成功 SELF_CHECK；INITIAL_REVIEW/REREVIEW 消费最后实际成功生产/测试 FINALIZE，派生纯审核包移除 parent-only 自检许可。全部关联仍 INSTRUCTION_BOUND，不证明单次消费、物理撤权或抗全本机恶意伪造。

UNKNOWN semantic applicability 保守加载规则。schema1 free-text correction 与 legacy PROJECT-CUSTOM 使用 full-source compatibility loading 和 unchanged-context reuse，并报告 `LEGACY_PROGRESSIVE_SELECTION_UNPROVEN`。

规则包bytes和estimatedTokens是测量，不是用户配额。policy、ADOPTION_PROFILE、旧compact的budget／ceiling字段仅作历史兼容；32/64/96KiB均不作为DISCOVER、后像、纠正、采用或自更新的运行门槛。始终返回完整必要规则；精简依靠精确选择与去重，保留来源、身份、授权和无效组合校验。统计用于定位无关加载、重复及异常增长，不新增软硬阈值、容差、调额、人工确认或虚构外部技术限制。

source composition、progressive selection 与 boundary decision identity 分离，并拥有各自 invalidators。selection 绑定完整 intent envelope，boundary decision 也绑定 discovered context identity。backend 可以重读 unchanged bytes，但 host 未观察时不得声称 physical cache hit。receipt 是 ephemeral、non-authoritative artifact，不是 repository ledger。

项目 AGENTS 中的框架管理内容、区外项目决定由当前模型读取并与后续用户指令对齐；不从固定正文自动推断授权。source binding 的 projectAgentsIdentity 单独绑定 AGENTS 全文件 identity，缺文件为 MISSING；projectCustomIdentity 仍只绑定 Bootstrap custom。决定收窄、撤回或其他字节漂移使旧收据失效；已授权 CONTROL_WRITE 的 AGENTS 后像可沿现有来源转换 FINALIZE，必须匹配包内精确路径及 OBJECT_POSTIMAGE，第三方改动不豁免。旧收据缺此字段且当前也无 AGENTS 时保持兼容；已有 AGENTS 却未绑定则重新 DISCOVER，不增加用户确认或强制创建文件。该字段不把用户决定变成项目标准或授权台账。Review 的载体/材料 preparation 由调用者提交已核对事实，checker 的主体关系排除与候选对象校验继续独立执行，机械 PASS 不证明调用者的语义判断。

`-DeleteInputOnExit` 只删除经过安全验证的 exact input：

- 首选 project-local `.ai-workspace/runtime/<task>/<actor-storage>/<safe-name>.json`，task 与真实 actor 必须匹配 input binding，路径不得是 reparse；
- 只有 project runtime 不可用时，才接受 operating-system temp 下的 exact non-reparse `aiw-*.json`，并公开 fallback evidence ceiling；
- success 或 failure 都只删除该 exact file；unsafe cleanup request 在删除前失败。

临时文件按实际消费者管理：支持的文件输入默认用 `-DeleteInputOnExit`；WORKFLOW_ROUTE_RESOLVE 的 `-InputJson` 与 `-InputPath` 互斥，共用严格 JSON 解析和同一个 dispatcher，直接输入不落盘。两者接受 CRLF 和缺末尾 LF，仍拒绝 BOM、NUL、replacement character、转义后重复键、未知字段及错误类型；JSON 字符串是数据，调用者仍须正确处理宿主参数转义。

材料按职责存放：配置、有效规则和活跃任务留在当前权威入口；长期结果、决定、研究及审核/失败复现证据复用项目既有 reports/research/history 或正式产物位置；纠正完整历史、安装归属及升级恢复留在 upgrade-recovery；临时 input、compact、output、可重建缓存和隔离 fixture 留在 runtime/tmp。业务、美术产物使用项目真实交付位置，不以控制目录代替资产仓；不强制建立空目录或批量重排旧材料。

保留条件是实际用途和最后消费者。当前权威、活跃 continuation、独有审核/失败复现证据、在用 runtime/包、当前采用绑定及未完成事务不得进入到期集合。重要失败证据不要求保存每轮完整输出，普通 DISCOVER 不重复持久化全文。正式结论若长期依赖 runtime 内唯一材料，原任务收尾须落实持久归属及有效引用，保留必要原始证据；不能只搬文件使 identity/链接失效，也不能以摘要代替复现材料。旧位置仍被事务或包精确绑定时先保留，最后消费者释放后再迁移。日常恢复只加载当前必要入口，不遍历历史。

普通到期 input/receipt/output、无独有证据的可重建缓存和 fixture 可在自然收尾集中处理已知集合，无须为了整洁另唤起模型。只按已解析绝对路径非 Force 精确删除；明确成功通常足够。后续正确性依赖不存在、部分失败或恢复/保护风险时才同批核验。宿主 policy 拒绝不重试或改安全设置，报告实际拒绝。不按年龄、后缀、大小、任务关闭或整个目录清理，不建逐文件台账、扫描服务或定时器。磁盘占用、规则加载和模型请求/token 分别评价，文件数或磁盘减少不证明模型收益。

原版本过程入口、Maintenance前门和WorkflowDelivery的Invoke-AiwDeliveryBoundary可接原调用方已知的`ConsumedRuntimePath[]`、`ConsumedRuntimePathList`（已消费的JSON绝对路径数组）、`EmptyRuntimeDirectory[]`、`RetainedRuntimePath[]`。这些调用参数不进入动作输入schema、不产生删除授权或逐任务清单；普通成功不保存完整D/正文/显示副本，集合从本批真实生成返回与原引用在内存中形成。共享释放函数留在原WorkflowDelivery模块，exact-input也复用它。普通接受和关闭/归档的原FINALIZE在实际成功后，沿当前原证据及ResultEvidence已校验的实际任务/归档验收计划，消费已链接成功producer的inputCleanup观察：removed/alreadyAbsent只描述历史结果，不授权删除重新出现的同名对象；仅业务真正成功的producer可凭同次读取字节绑定的consumedObject及明确IO_ERROR剩余，由同一释放函数在当前字节仍匹配时恢复未能删除的原输入。FINALIZE的结构PASS不代替actionOutcome成功；失败、不完整、未知、缺身份、宿主策略拒绝或未知失败均保留，不自动重试，不需要调用者重新手写输入路径数组。失败producer的原输入继续按证据保留；同一路径另有实际证明引用时保留优先。这里只读取当前显式引用的成功生成返回/必要失败原件，不生成每任务清单、扫描或推断未知材料。其他调用方已知到期集合仍可用原参数补充。TASK_MESSAGE须取得真实OBSERVE成功，失败/不完整或尚待投递时保留集合。不会从CLOSED或successorState推断整个目录到期。

释放限当前task/request的runtime子树内精确对象，整组先核范围、类型、reparse与保护；当前FINALIZE输入、仍被原compact/continuation递归验证的引用、原证据引用和调用者明确保留的后继材料不会进入释放。每条读取及删除选择复用本次已验证证据上下文的完整根相关保护（包括routineExcludedPaths和protected scopes），先拒绝禁区再访问元数据/正文；可沿reports等根内显式引用继续核在用闭包，删除范围仍仅当前task/request runtime；实际归档验收计划沿原ResultEvidence返回复用，不另写关闭校验器。不扫描项目历史；尚未给出的后继消费者由原调用方保留，未知就不列为到期。正式结果、采用/恢复及未完事务原件继续按原路径持有。已消费清单即使同时出现在普通路径数组，也只在最后清单阶段处理；只有成员全部成功释放后才释放，部分失败保原清单并返回实际remaining；空目录逐项非递归删除。结果的runtimeCleanup/inputCleanup分别给释放件数/字节/剩余/elapsedMs与FRAMEWORK_REJECTED、IO_ERROR或可观察的HOST_POLICY_REJECTED，清理失败不改已成立的业务status/exitCode。默认文本/模型输出另给紧凑AIW-CLEANUP观察，包含实际状态、剩余及失败分类；不只在AsJson中可见，不重复完整响应或正文。宿主在入口调用前拒绝时没有程序结果，应保原拒绝及UNKNOWN，不绕行或自动重试。旧固定版本仍按各自原合同，不热改运行包。

compact/continuation 留到最后消费者完成。上一步 compact 与 continuation 可能在下一 DISCOVER、ADMIT、FINALIZE 全部复验；先保存新的 successor continuation 再释放前序。失效/中止后在自然收尾释放已无消费者的 artifact；不用持久收据注册表。

PROCESS_REQUIREMENTS_RESOLVE 可显式指定 `-CompactReceiptPath <absolute-path>`：DISCOVER保存既有compactReceipt，或下述ADMIT_ACTION重绑定成功后保存当前compactReceipt。成功响应的 `selectedRuleBlocks[*].fullText` 是本次须读取的完整选中正文；`compactReceipt` 只承接后续 ADMIT/FINALIZE，不含正文，也不能用其中的 selectedObligations 冒充已完成证据。指定路径时输出另有 `savedCompactReceipt={path,identity}`，供后续边界引用所存收据；未指定时原响应形状不变，不另存全文。目录须已存在且精确为当前项目 `.ai-workspace/runtime/<task-or-request>/<actor-storage>/`，文件名安全、全部祖先非 reparse；CreateNew 拒绝任何已有对象，包括输入、旧收据及权威。保存失败整个调用失败，不报告保存成功；中途失败留下的部分文件不得消费。普通 evaluation 无后续边界时不要求保存。Maintenance 前门透传该参数，仍保留其 schema/repository 限制。

actor-storage 仅用于保存和清理的目录定位，不改变认证 actor：匹配小写 `[a-z0-9][a-z0-9._-]*` 、不以点结尾、不是 Windows 保留设备名（含扩展名），且不以保留前缀 `actor-sha256-` 开始的身份沿用原段；其他身份使用 `actor-sha256-` 加真实身份精确 UTF-8 字节的完整 SHA-256 小写十六进制。大小写、斜杠和反斜杠不归一化、不替换字符，不创建身份注册表。输入创建、compact 保存、根采用/恢复收口和 Maintenance 专用清理共用实际绑定 runtime 的映射，authority/package 中始终保留原身份。原过程边界以原 receipt 的 runtime 为准，不因采用后当前 pin 来源变化而移动旧材料；原恢复 FINALIZE 也调用该 runtime 的 resolver。旧固定包仍使用其旧目录合同，不热改包、不将旧收据迁成新布局。

本W2候选新增严格DISCOVER input5 / IntentEnvelope2 → compact4 / authorityContext3；boundary input3保持。旧Input4→compact3/authority2保留明确严格分支，不能把旧收据或来源重标为新格式。TOOLCHAIN导航为3/TC4；注册/升级投影使用本目标声明的PROJECT_BOOTSTRAP，当前候选仍须独立取得实际采用资格。

Input5保留Input4所有字段并必需ruleLoad={mode:FULL|REUSE}。真实加载统一返回FULL：同一意图选择器确定当前完整规则、条件与依赖，单次去重并组装完整正文。旧REUSE可携previousCoverageRef，仅兼容为FULL并记LEGACY_REUSE_RETURNS_FULL；不打开该引用、不求coverage差集、不返回REUSED或DELTA。FULL不得携previousCoverageRef。真实当前权威、声明、来源许可、保护、采用完成链和checker失败独立拒绝。

compact4保留bodyCoverage与loadDecision作为本次来源/显示索引兼容字段。units与rules保留完整身份、有序引用和metadataIdentity；anticipatedSteps、reusedUnitKeys、anticipatedUnitKeys均为空，requiredUnitKeys与returnedUnitKeys为当前完整单元集合，effectiveMode恒为FULL。索引不证明模型记忆。新增可选sourceObservation只绑定该次真实选择、声明与已读来源原始身份，不保存正文、未来状态或前次索引；原compact无此观察仍走原边界完整核对，不取得无正文重绑定资格。

非空ruleLoad.preloadSteps拒绝RULE_LOAD_PRELOAD_RETIRED；空数组仅为旧输入兼容。未来动作到达时以真实意图完整加载并独立准入。

健康同动作普通范围/包变化可在boundary3 ADMIT_ACTION提供actionRebind={authorizationRef:{path,identity},intentEnvelope:<当前完整IntentEnvelope2>,recoveryState:CURRENT|WARM}及新的-CompactReceiptPath。原receipt须为当前actor的TASK compact4并携真实sourceObservation；仅SOURCE_WRITE、TEST_WRITE、TEST_RUN、CONTROL_WRITE普通本地动作。除pathHints外意图不变，Owner/任务/路线/角色/阶段/profile/repository/执行目标不变；不支持特殊发布/转换/审核/接受/Git/外部链。现有checker核新包全部动作、精确对象、前像、当前决定和continuation，旧包不能借新路径扩权。先核路径保护再读候选，重新观察完整声明、当前同一选择器结果及所选来源原始身份；来源/选择实变或恢复不确定返回RULE_LOAD_REQUIRED，调用者完整DISCOVER。已知撤权/越界仍真实拒绝，不以FULL吞错。成功时正文装配与renderer均不调用，保存的新compact绑定当前范围和包，ruleBodyLoaded=false；后续原FINALIZE消费新compact。旧receipt不改写，失败不产生新receipt。sourceObservation是INSTRUCTION_BOUND来源索引，不是跨请求可信缓存、签名、模型记忆证明或授权依据。

policy3/project7支持内联effectiveRule或BOUND_SOURCE_ITEM完整图；content catalog2支持同一声明预览。FULL_FILE/MARKED_SECTION保留原严格整文件identity、marker与有序dependencies，旧descriptor转换为policy3仍是旧精确模式。新document.mode=NORMATIVE_UNIT严格字段为sourceId/bindingId/revision/locator/mode/unitId/sectionStart/sectionEnd/normativeIdentity/commonConditionSourceIds/dependencies，不携物理整文件identity；catalog文档只将bindingId替换为sourceRef。首期新模式限LOCAL_DIRECTORY；Git/HTTPS继续既有固定revision/完整字节读取。project6→7、policy2→3沿原ObjectFormats唯一适配链只准备投影，实际持久化必须原采用事务，不从旧marker猜新规范单元。

UTF8_LF_COMPLETE_UNIT_V1拒BOM/NUL/replacement及重复/不完整marker；显式CRLF/CR→LF，marker独占整行，保留其间全部非空body。unit基本事实含provider、canonical physicalSource、permissionIdentity、mode、unitId、parserVersion、sectionStart/sectionEnd、bodyIdentity；normativeIdentity为canonical{unit:<基本事实>,commonConditions:[声明次序的规范identity],dependencies:[声明次序的规范identity]}的length|SHA256。完整公共条件节点先于有序依赖及当前节点读取；全部引用须已采用且获许可，孤儿/环/重复ID/边/实际单元别名拒绝。物理rawObservation的整文件identity/位置用于真实一致性观察，不进入新规范身份；selector和义务另绑定rule metadata/closure，不能借相同body混同不同条件。

来源模块在同一次私有组装中共享实际读取的物理文件观察和完整规范单元；每次读取核当前许可、路径和实际bytes，并按实际采用的身份验证完整条件与有序依赖。公开输入及返回值不能提供可信缓存或修改私有观察。普通读取不承诺跨文件瞬时一致，不加读锁、快照、重试或退出时整组重读。以后同文件无关章节或位置变化可重新观察raw而保持未变规范单元；body、公共条件、有序依赖、selector、义务、许可和采用的实变须重绑对应闭包。旧精确模式、授权对象和写入前像仍按完整字节严格核对。来源模块编译完整单元图，composer只消费其事实，不另解析marker或跟随普通链接；重叠/包含单元分别完整保留。

同一composer先验证必要全局声明与当前权威：完整catalog、全部纠正/policy的ID、生命周期、selector/facets、义务和来源许可格式；再用原同一选择器确定当前规则，最后读取并验证命中规则的全部公共条件、有序依赖和正文。未命中的独立外部正文及缓存不访问，也不证明其健康。空命中是零个项目来源图，不回退全库。私有来源owner须从实际当前policy独立验证所请求子集的唯一成员及完整声明一致，调用方不能以自报已验证跳过它。重复正文在本次实际选中集合比较LF/Trim；真实注册、升级、规则/纠正采用变更和专业发布仍在其既有边界完整验证目标采用集合，包括未命中成员；不新增日常健康证书。完整同物理有序SharedKey链可共享显示，义务与规则身份不合并；相关漂移撤销旧收据，不改读最新revision救旧动作。

projectStandardsIdentity、effectiveRuleSetIdentity和sourceCompositionIdentity使用SELECTED_RULE_CLOSURE_V1域，绑定当前选择及实际完整闭包；它们不是全库健康身份。当前过程结果的evidenceCeilings包含SOURCE_VALIDATION_SELECTED_CLOSURE_V1，普通readTrace依次为GLOBAL_DECLARATIONS_VALIDATED、SELECTION_STARTED、实际SOURCE_BODY_READ、SELECTED_CLOSURE_VERIFIED。当前Boundary拒绝缺少该标记的旧收据并要求fresh DISCOVER，不把旧全库身份改标为新身份。绑定重查使用原receipt的profile/role/phase/actor/actionKind/resultKind/exactPaths/capabilities/intentEnvelope；真实来源变更使用实际目标能力。根调用者只在实际命令支持相应参数时传递选择上下文；旧运行包按原合同运行，新作用域不得静默退回旧全库绑定。

来源位置和组织方式由使用者决定，各项目在自己的 project7.sourceBindings 与 policy3 中维护当前许可和精确采用。target-before-pin 只在授权隔离投影内复证原来源和原始 bytes；明确外部来源不搬迁、不写入，不纳入项目采用写集。供给方 catalog、方法引用、locator 或缓存都不是项目规则采用或来源写授权。

`requirements/fragments/*.json`（schema3）拥有native requirement ID、结构/facets selectors、受控词表、exact Markdown locator与preparation/result gates。marked Markdown是唯一native rule body；PROCESS_REQUIREMENTS.json是确定性生成的schema3/catalogVersion4元数据投影，不能独立编辑。IntentEnvelope构造可读取完整目录及项目当前词表元数据；全局声明验证后用同一选择器选择，再验证所选完整正文及必要依赖，不增加第二选择器。

普通repo-local schema1及Maintenance CONTROL/TARGET schema2的原完整checker已在ADMIT按同一固定来源/适配器、完整动作/对象/续链参数和当前观察执行时，由该实际调用满足授权检查；调用者省略额外相同checker命令。checker公共入口保留；DISCOVER、ADMIT与收口各自真实观察不合并成全局一次或缓存。schema4及未证明等价的专门路径仍分别调用；错主体、越界、前像漂移、撤回和坏续链照原拒绝。

仅本次实际NONE、无包无副作用，向当前USER作普通PLAN/USER_RESPONSE，且无正式Review/接受、TASK_MESSAGE、关闭/责任转换或continuation消费者时，可省独立机械FINALIZE。当前必要完整规则仍实际读取，事实/来源/限制/未知仍如实说明；不产生假PASS或可被后继借用的成功收据。任一条件不符仍走原收口；显式FINALIZE公共入口保持严格。

### 授权包与可选执行目标

普通包共同必需字段为 schemaVersion、frameworkVersion、taskId、profile、lifecycle、owner、issuer、issuerRole、grantee、bundle、decisionClass、userConfirmation、reviewIndependence、delegatedGitCloser、taskIdentity、actions、exactPaths、objectIdentities、invalidatesOn、projectConfigIdentity。当前任务正文的 profile/lifecycle、完整身份与责任关系必须匹配，ACTIVE 包不能绑定 CLOSED 卡。PROJECT_CONTROLLER 另含 issuerControllerId/issuerControllerEpoch/controllerControlIdentity；schema2 另含 repositoryId 并先过 Maintenance root adapter；schema3 根升级保持原合同。continuationPlan/selfCheckRepairLimit、repairReviewPlan/repairReviewBinding、receiverBinding、transitionPlan、acceptanceBinding、sourcePublicationBinding、externalBinding、gitPushBinding及普通qualityBinding只在各自规定的分支出现，未知或混合字段拒绝。

Input5 可选 executionTargetRef={path,identity}，必须与原 task 唯一 Execution target 引用及其 runtime 内不可变 EXECUTION_TARGET schema1 一致；没有引用即 SAME_ROOT。executionContext 字段仍为 schemaVersion1/targetKind/controlRoot/executionRoot/executionTargetRef/targetObservation；observation 为 schemaVersion1/descriptorIdentity/commonGitDir/worktreeGitDir/gitTop/branch/head/observedUtc/overridesAbsent。初始 branch/baseline 不随当前 action HEAD 改写，null hostWorktreeRef 表示未声称宿主管理。

普通隔离动作使用 package4：共同字段上增加 repositoryId=PROJECT、物理绝对 controlRoot、规范绝对 executionTargetRef 和 expectedTargetState={branch,head}；head 为40或64位大写十六进制。独立 checker 显式传 -ControlRoot，读取该根的配置、Controller 和任务，保留实际 cwd。只支持 SOURCE_WRITE/TEST_WRITE/TEST_RUN/REVIEW_ROUTE/REVIEW_EXECUTE/RESULT_ACCEPT 及分别授予的 GIT_STAGE/GIT_COMMIT/PUSH。schema1/2/3 不证明隔离动作；Maintenance CONTROL/TARGET 不改装为 PROJECT，不承接 CONTROL_WRITE、采用、外部或设备能力。

ExecutionTargetContext 共同核同仓 common/worktree/top、双向 .git 关联、原决定/可选宿主引用字节、覆盖变量、reparse 和替换。相对排除映射到目标，控制仓内绝对保护按词法相对位置映射到目标，两根显式保护取并集，先于目标 metadata/hash/diff/index。目标影子 .ai-workspace 不是权威或候选。authority3.projectRoot=controlRoot；目标动作 objectRoot=executionRoot，CONTROL_WRITE/归档仍定位 controlRoot，保留历史引用但不移动或删除 worktree。SAME_ROOT 不探 Git。

typed2 的 SELF_CHECK/REVIEW_VERDICT/RESULT_ACCEPTANCE 增加同一 executionTargetRef 与 candidateTargetState={branch,head}，typed1 不能给隔离目标补证。continuation3 增加 executionTargetRef、observedTargetState、postTargetState，并总有 transitionKind=ADVANCE/REPAIR/RETEST 与 selfRepairCycle；无返工许可时只能 ADVANCE、cycle=0 和原线性下一步。SOURCE/TEST/REVIEW 连续链不授权 HEAD 变化，仍消费真实 FINALIZE、当前整组后像和适用 SELF/COMMAND。candidateObjects 相对 executionRoot，其他证据相对 controlRoot，绝对引用仍限已绑定根。

DISCOVER/Input5、ADMIT、FINALIZE、receiver、证据、工厂和交付复证同一目标。REPAIR_REVIEW 对 package4 另显式接收 controlRoot/taskPath，repositoryRoot 必须等于实际 executionRoot，不从 taskId 猜 basename。目标缺失、状态或保护漂移、控制采用未完只停止受影响链；重选先完成原动作并取当前精确许可。

GIT_COMMIT 的 FINALIZE 只接受同一分支上实际新 HEAD 的唯一 parent 等于原授权 HEAD，提交路径恰等于独立 Git 包，index 空且工作树候选与提交树一致；返回真实 postTargetState。其他动作不接 HEAD 漂移，后续独立包绑定后态，descriptor baseline 不改。PUSH 仍核原远端/分支/路径/index/URL/ref，typed acceptedCommit 等于实际待推提交。protected safe-Git 的 STATUS/DIFF/INDEX 可携 TaskPath/ExecutionTargetRef/ExpectedTargetState（后两项为严格 JSON 字符串）和 ProtectedPath；配置/保护取控制根，输出取目标，仍不授 Git 权。

Get-AiwTestDependencySnapshot 可显式接收 ControlRoot、TaskPath、executionTargetRef、expectedTargetState，四项同时出现或由同一 options 保存；仅 definition3、声明实际 observer 依赖的 EXACT 组可用。每次重观真实关系/状态，输入根及 native cwd 为 executionRoot，拒 LOGICAL_ROOT 替换。同一已加载 producer 保留首次绑定 observation 的真实 observedUtc，前后重新验证其余完整事实；native 时间另取真实进程记录。跨加载无原观察复用证明则保守 fresh，不冒称业务改变。公开 runner 用同名四参数，ref/state 为严格 JSON 字符串，已有目标 SOURCE_PAYLOAD_V1 输入树不再投到另一个 SourceView。默认 SAME_ROOT/SourceView 和旧分支保持；生产接点不授 TEST_RUN 或发行资格。

### 输出时序与有界修复复审

以下默认消费者可由真正的人类决定显式改变；既有 `userDecisionRef` 例外消费当前输入的精确 expectedRecipient/channel：NATIVE_RESPONSE 仅 USER；TASK_MESSAGE 须为实际确定的任务消费者，拒绝 USER、NOT_APPLICABLE、NOT_REQUIRED、UNBOUND_RECEIVER、DEFERRED_VISIBLE_REVIEWER 等占位。引用须安全可读、原字节匹配，且与 boundary.publicDecisionIdentity 一致。调用者仍亲自核对原始用户来源、语义及后续撤回；文件/hash 不认证用户身份。没有引用仍按下文默认推导；PREPARE 不关闭跨任务交付，只有真实宿主结果唯一匹配才完成 OBSERVE，不追认历史发送或为补闭环重发。

输出边界使用 `deliveryContext={channel,stage,expectedRecipient,observedRecipient,outcome,evidence}`。REVIEW_ROUTE/REVIEW_EXECUTE 的 FINALIZE 必须提供；其他旧无该字段输入仍只保留未验证交付的证据上限。channel 为 NATIVE_RESPONSE/TASK_MESSAGE；PREPARE 为 NOT_SENT，observedRecipient/evidence 为 NOT_APPLICABLE。它返回 READY_TO_SEND；跨任务尚未送达时 FINALIZE 保留 BLOCKED/DELIVERY_NOT_CONFIRMED，不生成可续权结果。原生 USER 输出仅能核定发送准备，无发送后回调证明。

私有 `WorkflowDelivery.psm1/Get-AiwBoundDelivery` 从同一 receipt、当前包和已校验的 typed verdict 推导消费者：finding/rejection 交 candidateWriter，APPROVED 或不能继续的审核结果交 Owner；普通动作交 task Owner，Owner 自身交 USER。REVIEW_ROUTE 取原 repairReviewPlan 的 Reviewer；无预绑定 Reviewer 时，deliveryContext 引用当前纯审核包 `reviewPackageRef={path,identity}`，或携原计划允许的已有 `reviewerAssignment` 形状，以真实创建结果落实 deferred Reviewer。它们只绑定既有分派，不是新授权包。最终收件人和通道须同时吻合；agent 自拟的“仅本会话 final”不能替代直交。用户本人明确改变交付对象时，附 `userDecisionRef={path,identity}` 指向实际原始用户来源，且与当前 boundary.publicDecisionIdentity 一致；调用者仍亲自验证来源和语义，文件/hash 不证明用户身份。

纯审核包的writer/贡献者二字段按AUTHORIZATION_MODEL适用于普通明确绑定及CRITICAL/repair-review场景；直接引用审核包须覆盖当前完整候选、Owner、任务、决定及独立Reviewer，不能以同名任务或只有路径的包替代。未绑定writer的历史普通审核证据不因此失效，但新finding输出须补齐当前合法责任后才能直回。

TASK_MESSAGE/OBSERVE 的 evidence 为 `精确宿主结果路径#length|SHA256`，在既有项目/仓库范围及禁读边界内校验原字节。当前 Codex 成功形状是非错误 MCP result 的 text JSON 含唯一匹配 threadId；`Get-AiwCodexSendOutcome` 只按该返回映射。不存在 status/success 通用字段假设。明确错误、未知、错对象与自报 outcome 冲突均不形成成功；只证明宿主接受发送，不证明接收方工作完成。未调用保持 PREPARE，拒绝/未知不自动重试，不改走中转。

WORKFLOW_ROUTE_RESOLVE 的 TERMINAL 使用 `{operation:'TERMINAL',boundaryInputRef:{path,identity}}`，复验精确现有 FINALIZE 输入及同一消费者函数，不再接受角色枚举自报。DELIVERY 可使用同一 boundaryInputRef；只有孤立 deliveryContext 时仅作 caller-bound 投递观察，明确 consumerBound=false，不能据此关闭回传。直接使用 FINALIZE 返回时无需再重复调用 TERMINAL。修复复审核验也复用同一消费者函数。真实发送、返回保存/解析、OBSERVE 可在同次确定性编排完成，不增加记账模型回合；无 ACK 或轮询。以上均不证明原始用户通信授权、模型注意力或宿主强制执行。

有界修复复审使用原 repairReviewPlan 和新 repairReviewBinding。binding 保留 parentPackagePath/parentPackageIdentity、phase=INITIAL_REVIEW/REPAIR/REREVIEW、cycle、verdictPath/verdictIdentity 及 repairFinalizeInputPath/repairFinalizeInputIdentity/repairFinalizeResultPath/repairFinalizeResultIdentity。INITIAL_REVIEW 的 cycle=0、verdict=NOT_APPLICABLE，四个 repairFinalize 字段绑定真实生产 FINALIZE；REPAIR 的四字段仍为 NOT_APPLICABLE，REREVIEW 绑定实际修复生产 FINALIZE。REPAIR/REREVIEW 还须有 verdictFinalizeInputPath/verdictFinalizeInputIdentity/verdictFinalizeResultPath/verdictFinalizeResultIdentity，绑定原 Reviewer 的真实审核 FINALIZE；首审不携未来字段。后建 Reviewer 的 reviewerAssignment 保持原两种 HOST 分支，已知 Reviewer 不携该字段。

同一次判断保留既有 flat verdict 和 typed REVIEW_VERDICT，typed.evidenceLocators 唯一引用该 flat 原件。flat 字段保持 taskId/owner/reviewer/writer/cycle/verdict/exactPaths/objectIdentities/findingPaths/scopeChanged/decisionChanged。REVIEW_EXECUTE FINALIZE 对照原计划、cycle、完整 A、实际后像、finding/边界变化和 typed outcome；APPROVED 无未解 finding/边界变化，CHANGES_REQUESTED 至少一个真实 finding。写者、工厂继续消费同一 flat 与实际成功 FINALIZE 的关联，不由 Owner 补造裁决，不给普通无计划历史 Review 派生写权。历史 finding 的冻结候选校验只复证修复来源，不满足当前成功门。

materialContributors 为内部唯一的非空字符串数组，candidateWriter 不重复列入。Owner/issuer 可彼此重叠或同时为真实贡献者；另将 Owner/issuer/writer/contributors 合成 Reviewer 排除并集。计划、工厂、checker、证据、交付判定一致，父子 contributors 精确相同。范围内 finding 直 writer，扩面/决定变化或 finding 超 M 则直 Owner，APPROVED 直 Owner/有权接受者。工厂只返回 PREPARED，当前 checker/DISCOVER/ADMIT 和实际交付仍独立。

同一 REPAIR_REVIEW 入口承接首次交审：binding.phase=INITIAL_REVIEW、cycle=0，verdictPath/verdictIdentity=NOT_APPLICABLE；原 repairFinalize 四字段绑定生产动作的实际 FINALIZE 输入/结果，生产包必须是 parentPackage 自身。当前审核候选必须等于真实 M 后像与冻结 A\\M 的合成结果；缺省同范围时仍为该 FINALIZE 的完整后像。Reviewer仍按计划绑定且独立。REPAIR/REREVIEW从真实finding开始，cycle不得超出任务自定maxCycles；首次交审不伪造finding或修复历史。交审材料与必要卡更新的先后依赖只取 REVIEW_AND_EVIDENCE，不在包工厂重复定义。适用任务默认由原 Owner 在生产包配置计划；Reviewer 可稍后创建。若当时真实ID未知，writer 用 `HOST_INITIAL_DELEGATION`、`threadId=UNBOUND_RECEIVER` 准备当前候选的待绑定 Reviewer 模板及完整材料，在创建提示一次交付；Reviewer 从宿主身份自绑定，保留原 Owner/issuer 和生产后像。真实finding后的修复和复审沿同一 assignment 填入已绑定的 Reviewer ID，不重发待绑定包。旧 `HOST_CREATE_THREAD_RESULT` 精确已绑定路径仍有效，临时 writer 不取得 Owner/issuer 身份。

INITIAL_REVIEW/REREVIEW 的纯包及 verdict.exactPaths/objectIdentities 绑定 A；REPAIR 子包仍只绑定 M，以真实 verdict 中 M 的候选身份为修复前像。findingPaths 必须在 A 内，实际需修复路径超出 M 则返回 Owner，不以只读审核范围授予写权。scopeChanged/decisionChanged、任务/配置/Controller、责任主体、贡献者、原决定和保护集合变化继续使原计划失效；不重置 cycle/maxCycles。派生纯审核包仍独立 checker/DISCOVER/ADMIT，最终接受、Git、发布及采用另行授权。

`AUTHORIZATION_RECEIVER_BIND`使用CONTROL根、待绑定材料绝对路径、初始委派给出的原件`length|SHA256`和delegationId；仅从宿主进程`CODEX_THREAD_ID`取实际主体，在`.ai-workspace/runtime/<task>/<actor>/`写精确包。原件为`schemaVersion/delegationId/receiverRole/authorizationTemplate`四字段；角色仅限IMPLEMENTER的写测、INVESTIGATOR的纯NONE或原纯TEST_RUN、独立REVIEWER的纯REVIEW_EXECUTE。IMPLEMENTER模板预先配置repairReviewPlan时，writer必须明确为UNBOUND_RECEIVER；binder只把它和grantee同步派生为同一宿主真实ID，其他角色不得借此携计划。checker的receiverBinding逐字段核验原件身份与派生差异，拒绝原始UNBOUND_RECEIVER包、其他宿主主体、原件漂移、额外权限或不合格Reviewer。接收者必须先核对实际收到的初始委派；此对应关系保持INSTRUCTION_BOUND，上述工具结果不证明消息来源或实际模型执行。派生后仍需原checker、DISCOVER/ADMIT和实际结果FINALIZE。

不在Work route的临时参与者在已知TASK内进行安全NONE读取、交付PLAN或USER_RESPONSE时，可以使用authorizationPackagePath/expectedAuthorizationIdentity=NOT_REQUIRED；TASK DISCOVER取EXECUTOR/PLAN，保留真实task Owner与Work route actor，authorizedActions为空。当前task/config/人类来源与精确路径及保护仍核验，不造PROJECT_READ_ONLY、不改Work route，不以虚构SOURCE/TEST取得正文。正式自检、TEST、Review、写入和外部动作仍须各自当前有限动作包。显式具名有限读取assignment仍可复用schema1/2/4包且actions恰为[NONE]，其当前Owner/issuer/grantee/决定、精确scope、当前对象及执行目标仍全部核验；known ID直接签有限包，unknown ID复用INVESTIGATOR原绑定。纯NONE不得混副作用、continuation/selfRepair/reviewRepair或其他动作绑定；它不授SOURCE/TEST/Review/外部动作。读取候选前经原安全路径消费者应用并透传当前ForbiddenPaths/ProtectedPaths。用户撤回仍是实际有效语义，来源漂移拒绝不冒称工具能自动理解撤回。

PROJECT_READ_ONLY可使用当前真实的管理、执行或观察审核角色；临时观察者可按EXECUTOR表达实际只读职责，无须冒填管理身份或新建卡。它仅允许NONE与PLAN/USER_RESPONSE，REVIEWER标签也不授予正式Review、写入或越界读取。objective、authority context、标准文档数、纠正changes、Knowledge查询数和continuation步骤不设框架统一使用配额；任务仍绑定有限范围、具体计划及退出条件，结构、类型、唯一性和路径验证保持。

### IntentEnvelope 构造

首次 DISCOVER 直接应用上文输入/收据合同，无需先加载 HOST。

首次构造或相关来源改变时，随已知项目事实同批取得当前 generated catalog 的 id/title/description/selectors，以及当前有效纠正和policy对应元数据；健康上下文复用。原生目录直接投影现有 PROCESS_REQUIREMENTS.json，不新增目录文件、operation 或 LOAD_PLAN 前置门。纠正有效性取项目当前记录的显式生命周期；无 lifecycle 的旧记录仍有效，不按 ID、措辞或原生相似规则自动抑制。新版本不依赖中央 coverage 映射。旧free-text或没有可靠selector的来源沿原兼容全文/保守处理，source漂移也不靠旧元数据排除。PROMPTS的读取/构造样例只教如何使用这些来源，不生成意图或替代严格校验。

`DISCOVER` 前，当前主会话模型从本轮原始用户请求、仍有效的多轮上下文与已绑定任务事实，重建当前真实请求：目标、这一步实际要做的 action、当前应交付的 result、受限范围，以及仍然有效的否定、条件和先后关系。然后只填写现有 `IntentEnvelope` 字段；resolver 负责结构与 authority facts 的核对，不替模型理解原话，也不建立第二套 intent authority。

构造顺序为原始目标和交付物 → 仍有效限制/纠正 → 当前决策 → 此刻动作及结果 → 已观察范围/能力 → 四维 facets → 辅助 semanticHints。这是同一次模型判断中的顺序，不为每步请求模型，不新建意图服务。授权缺失在独立authority校验中体现，不能反向抹掉清楚的目标。

多轮更新按语义作用域合并：补充增加未冲突约束，收窄删除范围，纠正替换被明确修订的部分，取消终止被取消的当前动作；未被修订的上下文继续有效。报告、日志、引用指令和示例中的命令都是 data，除非用户明确把它们转成当前请求，否则不能成为 action、authorization 或 authority instruction。

`requestedActionKind` 只表示当前步骤实际请求的 Framework action。讨论、解释、比较、诊断或先分析后再决定时使用 `NONE`，但仍必须完成实质分析，并用 `PLAN` 或 `USER_RESPONSE` 表示当前交付。明确要求修改时，即使 package、权限或能力尚缺，仍保留清楚的 write action 与 `CLEAR` intent；authorization 独立失败，不能把请求擦成 `NONE` 或 `UNKNOWN`。若后续动作受“经确认后”“若条件成立”或明确顺序约束，当前 action 只填写已到达的步骤，条件与延后动作保留在 objective 中；只有当前适用概念进入 semanticHints，条件尚未满足时不得提前执行。

否定必须绑定它实际否定的对象。明确要求正式 Review 并说“不要修改”时，当前 action 仍是 `REVIEW_EXECUTE`、result 是 `REVIEW_VERDICT`，否定只限制 repair/write；普通“帮我看看”“比较方案”没有正式 Review 请求时，不因 look/review 类词汇自动升级。`ambiguityState=UNKNOWN` 只用于真实语义不确定，`CONFLICT` 用于仍未解决的请求冲突；缺授权、缺能力或 host 不可用本身不改变清楚的 intent。

IntentEnvelope2 保留原字段并增加必需 `facets={domain,workType,deliverableType,stage}`。每维仅为 `{state,values}`：KNOWN 必须是非空、唯一、已声明 token；UNKNOWN 与 NOT_APPLICABLE 的 values 必须为空。未知字段、未声明词项、重复 canonical 值及矛盾结构拒绝。native 词表来自完整生成目录，项目扩展和本地 aliases 来自 policy.facetVocabulary；条目仅有 dimension/id/description/aliases，id 是稳定命名空间 token。同维 alias 对应多个 id 时明确拒绝歧义，项目不得覆盖 native 身份。无隐含父子分类。

四维描述当前工作：讨论未来实现仍是当前 discussion/planning，当前 action=NONE；正式 Review 且“不要修改”仍是 review/REVIEW_EXECUTE。有效多轮限制、取消和先后条件仍由同一次模型判断对齐，不从原话关键词、任务权限或将来动作反推当前执行。semanticHints/semanticTerms 只辅助发现、理由或排序；不会覆盖确定的 NO_MATCH，也不作为 substring 执行动作触发。path/capability/mutation/external hints 仍受实际范围、已观察能力和当前 action 约束。任何分类或 hint 都不授予权限。

本合同继续使用当前 schema、单一 composer 与 resolver。说明性示例只证明字段可表达这些关系；在受控原始多轮回放实际观察主会话模型的输出前，不得声称自然意图识别准确率或语义 PASS，也不新增 intent-generation operation、provider/model 配置或服务。

selector 的 profile/role/phase/action/result/path/capability 已知边界先全部匹配；已知不相容立即 NO_MATCH。再消费 facets：维内 OR、维间 AND；未声明某维不增加该维限制。KNOWN 精确相交，UNKNOWN 只在已知边界内保守保留，NOT_APPLICABLE 排除确实限制该维的规则。分类 UNKNOWN 不等于请求本身不清楚；ambiguityState 仍独立约束受治理动作准入。

### 调用字段来源与路径

显示使用版本内ProcessRequirementDisplay.Get-AiwProcessDisplay的单一 `text`，保模式、真实fallback/限制、短来源、每规则有序短引用、当前及anticipated义务与一次完整必要正文。先[A]后[B,A]只显示正文[A,B]，引用分别[1]与[2,1]；独立反向链不构成全局环，不要求blockIds递增。相同文字的不同来源、条件或规范身份不混同。Input5 MODEL只输出FULL/DELTA本次必需正文，REUSED只复用coverage指明且当前模型确有的完整正文。机器原件、compact、coverage及严格身份仍由程序消费，不打印重复目录、长身份和覆盖数组，也不把整个display对象送入模型。显式-AsJson保完整MACHINE载体，处理后只显示模型text。主动分页参数、分片器和页票据已退役；真实宿主截断时从同一结果补读实际缺失的完整单元及义务，不重跑选择。末尾标记只帮助观察截断，不证明模型持有或attention；失败、未知和缺项保持可见。

当前TASK DISCOVER input5（兼容明确Input4分支） 使用绝对 projectRoot/frameworkRoot/taskPath 与 readOnlyContext=NOT_APPLICABLE；无任务只读使用 PROJECT_READ_ONLY。Maintenance CONTROL 与 TARGET 都沿根前门提交当前 pin 声明的输入；compact4/authority3 的binding.projectRoot 保持 CONTROL 项目根，TARGET 仓库由独立 topology/package 校验，不从包存储位置推断 CONTROL。旧固定 TC2 包继续其原 schema2 SOURCE / schema1 compact 限制，不重写旧包。checker 的 TaskPath 是相对已绑定项目/CONTROL 根的规范路径；同时对齐 shell cwd 与进程 cwd。ObservedIdentity 为 path=length|SHA256，新对象为 path=NEW。

有包时userDecision精确绑定仍有效的package.userConfirmation；无包只读为NOT_REQUIRED，不能由样例制造授权。boundary schema3只引用原compact并提交实际完成的preparation/result/delivery证据；publicDecisionIdentity为NOT_REQUIRED或length|SHA256，不是任意decision哈希；protectionState仅BOUND/NOT_APPLICABLE，须符合实际保护事实。不得把selected obligations自动当完成证据。输入使用严格UTF-8无BOM，接受CRLF和缺末尾LF等价格式；未知字段、重复键、错误类型、损坏文本与漂移仍拒绝。原始字节用于identity和事务前后像，不重写文件伪造原像。

### 选择条件与原采用准备

普通 SOURCE 跨一次已完成 FORMAT/refresh 的原 FINALIZE 由根 PROJECT_ADOPTION“普通 SOURCE 的跨采用原收口”定义有限输入和支持面。O 仍拥有原规则、授权、准入和结果消费者，T 拥有真实完成采用的核验，合格固定 X 只显式连接原件；原 version resolver 不透明重绑。原 SOURCE、采用成功原件、当前候选及仍有效的任务/Controller/保护/人类决定必须同时成立；不以新准入、改写旧收据或缺失证据推定完成。私有单次读取/准备复用不增加公开可信输入，公共边界及实际写入前仍复核真实字节和完整义务。

同pin、未发生采用且 AGENTS 在原 SOURCE 准入/写入后改变时，根 `upgrade-project.ps1` 和 `resolve-framework-maintenance-process-requirements.ps1` 的显式 `-CompleteOriginalSourceAfterAgentsChange` 沿根 PROJECT_ADOPTION“普通 SOURCE 的跨采用原收口”内的同pin分支消费原 FINALIZE、原 ADMIT input/result，以及 `OriginalAgentsPreimagePath/ExpectedOriginalAgentsPreimageIdentity`、`ExpectedCurrentAgentsIdentity`、`CurrentCompletionDecisionPath/ExpectedCurrentCompletionDecisionIdentity`、`CurrentCompletionPermission`。仅 `CURRENT_AND_COVERED` 可继续；调用者须亲读原/当前完整 AGENTS 与当前真实决定，判断为 INSTRUCTION_BOUND。固定来源及除 AGENTS 外的原任务、包、Controller、policy、配置、采用和保护绑定仍须成立；缺原前像、原准入或当前决定明确拒绝。该有限 SOURCE 收口不写产品或权威、不重授 SOURCE、不创建采用事务，也不把未完成动作当历史成功；不得混入跨采用参数。完整输入与拒绝边界取根 PROJECT_ADOPTION。

同pin的真实失败停止可在另存的原SOURCE FINALIZE输入显式带`continuationDisposition=STOP`：除单步SOURCE外，仅承接原`SOURCE_WRITE → REVIEW_ROUTE`批次的SOURCE，原repairReviewPlan不产生后继权。保原ADMIT、完整实际后像（可为MISSING）、全部准备/结果义务、当前许可与保护及真实typed SELF FAIL/INCOMPLETE；不放宽成功完成分支。必要TASK_MESSAGE尚为PREPARE时返回BLOCKED及未送达事实；实际OBSERVE通过后，actionOutcome仍为FAIL/INCOMPLETE、successorState=STOPPED且无continuationReceipt，不作为历史成功、审核或新写入许可。原件、已生成素材、真实次数/费用及UNKNOWN保留，后续依当前权限前向处理。

原有八个结构/辅助字段继续可表示；新增可选 facets 的每维是非空允许值数组。native 规则必须显式提供 facets（空对象表示仅结构限制），真实条件由结构和 facets 表达。旧 TOKEN/SUBSTRING/deterministicTriggers 元数据保留原始身份与采用差异，TC3 不用自由文本或触发词绕过当前分类。缺乏可靠分类的旧项目条目在已知结构内保守读取。

原采用 PREPARE 返回 selectorDifferences 及 selectorSemanticJudgmentRequired。目标义务仍须完整读取；存在差异时，在现有准备回执中明确提交 `ADOPTION_SELECTOR_SEMANTICS_CONFIRMED|<preparation identity>`，表示项目已判断当前精确差异及保守投影，之后才允许原动作 ADMIT/Apply。格式转换本身不证明新适用性已决定；该声明仍为 INSTRUCTION_BOUND，不是工具对语义或原始用户身份的证明。原 ADMIT/FINALIZE、typed evidence、独立审核、接受和事务前后像保持各自门禁。
`LOAD_PLAN_RESOLVE` 保持 compatibility/support operation，可定位 non-rule supporting artifacts、Framework-wide maintenance/explanation context 与 bounded affected-module fallback；它不是 pre-DISCOVER catalog filter，不能静默排除 requirement。STABLE 调用保持原参数兼容。对已完成本地试点的 CANDIDATE，caller 必须同时提供 `ProjectRoot`、`ExpectedProjectConfigIdentity` 与 `ExpectedCandidatePilotStateIdentity`；loader 通过 composer 导出的薄绑定入口复用现有 local-pilot 严格读取，验证项目 pin、候选 flags、完成状态、受管投影、payload canonical 与 manifest identity，并返回 `lifecycle=CANDIDATE`、`LOCAL_CANDIDATE_PILOT` evidence ceiling 及实际 state identity。缺少、部分提供或漂移的绑定全部拒绝。该 support 读取不运行完整 DISCOVER、不读取整个 project policy selected pack，也不授予 action。

当前操作按TOOLCHAIN及本节精确输入分派，Input4与Input5不互相改造执行意图。原采用/恢复仍用原固定来源，目标只读投影不授新准入。boundary3与旧typed证据保持；authority3新增controlRoot、objectRoot、repositoryId、executionContext，v1/v2保留独立历史schema，不静默丢字段。

机械 PASS 只证明 current identities 与 supplied structural receipts，不证明 semantic correctness、model attention、host invocation 或独立 authorization/Review/Git/external gate。

普通 TASK/PROJECT_READ_ONLY 的来源、授权与动作准入以当前项目根、配置、任务、精确对象和保护边界为准，`repositoryGitTop=NOT_APPLICABLE`；不调用 Git 程序。仅 GIT_STAGE/GIT_COMMIT/PUSH 或明确的多仓库拓扑核对 Git top；缺失或不符时停止相应 Git 动作。子目录项目、嵌套仓库和 worktree 的 Git 身份按实际动作目标分别验证，不能把项目根等同于任意父仓库。

## Target-before-pin adoption preflight

root project upgrade 从 ADOPTION_PROFILE 取得目标格式和能力合同；2.0跨版本入口另外限定未修改的固定 1.16.0-snapshot.12 → 已审固定2.0候选，不提供任意版本兼容服务。范围导航只返回声明路径；有原 DISCOVER 后，PREPARE 在隔离目录组合目标配置、Controller、当前任务、控制载体及真实标准来源，返回完整目标规则和精确前后像。

CurrentProcessInputPath 必须绑定真实旧 DISCOVER 的 ADMIT 输入。读取目标 fullText、完成两端准备后，根 ADMIT_ACTION 调用原健康 runtime 一次并保存原始成功证据。Apply 和原 FINALIZE 复证这一证据，不通过目标 resolver 或新准入追认历史。旧 resolver 的真实失败不能被预算调整或手改发行包掩盖。

AdoptionCorrectionsPlan schema2 的严格公开结构取根 PROJECT_ADOPTION 的“采用时处置旧纠正”。scope-only 仅声明路径；原 scope、保护、归属及依赖核对后，完整组计划与格式/模板成为一个投影。PREPARE 保存计划真实 bytes/identity 与原 history/installation 引用；ADMIT、Apply、恢复和原 FINALIZE 重算并核对同一效果、完整历史和最终 carrier，不把计划声明当权限或独立生命周期 Apply。项目源删除拒绝 live/cache 回填。公开前像 NEW、删除后像 ABSENT、内部投影 MISSING 分别使用；基础必需对象不得删除。旧流程来源为原 previousDistribution，不要求目标包携带旧版本。schema1 原行为保留，MajorAdoptionOverrides.corrections 与组计划互斥。

投影不授予权限。schema3包绑定原决定/主体/任务/范围、双方固定分发和目标后像；写入保持 task-last，原事务按可达状态 COMPLETE 或 ROLLBACK。恢复与原过程收口见 MIGRATION_MATRIX 和根 PROJECT_ADOPTION；Review、接受、宿主安装、项目采用及 Git/external 保持独立。

## 项目来源配置的受限普通采用

普通 CONTROL_WRITE 的归档删除仍逐对象校验唯一真实后像。缺失 active 卡只有在原授权存在前像、明确 MISSING 后像、同一精确范围的同名 archive 后像匹配、实际 task ID 一致且 CLOSED 时，才转由该 archive 执行既有完整 closure 校验。缺失 archive、NEW active、缺/重复/错误后像、非文件、reparse、错误 ID 或未关闭目标均拒绝。SUCCESS 与无 Closure outcome 的 legacy 继续验真实完整 acceptance plan，包括用户门及 CRITICAL 历史审核独立性；CANCELLED/SUPERSEDED 保留真实非成功关闭，不改称成功。普通证据材料必须存在。

已准入的固定 TC3 原归档动作因旧结果模块读已删 active 而失败时，仅可沿根 PROJECT_ADOPTION 的“原归档动作完成验证”显式使用新的合格固定校验工具。原 compact/ADMIT/failed FINALIZE 全部原字节保留；旧 pin、规则及实际实现来源仍由原 composer 复证，新子进程只使用两处已审结果模块差异，不重做准入或采用。该入口仅写新证据，不写原对象、历史或采用状态；来源/调用依赖、后像或真实接受证据不足则拒绝。

当前 project7/policy3 的日常来源采用使用原单步 `CONTROL_WRITE`。原包仅可为 repo-local schema1 或 Maintenance `CONTROL` schema2，候选保留两个现存文件 `.ai-workspace/process-policy.json`、`.ai-workspace/project.json` 的完整读上下文及前后像；精确授权写集只含实际 bytes 改变者，不能把未改变的 companion 放入写包，无实变不创建空动作。包不含 continuationPlan 或 transitionPlan。配置允许改变 `sourceBindings` 及已启用的 `frameworkCapabilities.KNOWLEDGE_REFERENCE.sources`。项目明确选择知识引用时，还可由当前 PROJECT_CONTROLLER 签发原精确包，将缺失声明或合法 `enabled=false` 变为 `enabled=true`；完整配置前后像和原决定绑定首次启用，目标仍须通过同一能力结构校验。除这项有界首次启用外，其余完整解析对象必须相等；pin/backend、项目身份、布局/根、policy locator、排除范围、其他能力变化、关闭或删除知识能力、任务/Controller 变化不属于本分支。知识引用可选，未采用也可完成项目接入和读取普通研究资料。

1. 对未写入的真实现场完成独立 checker 和 DISCOVER，保留原包、compact 与当前保护事实。根据原项目决定准备完整 config/policy 后像；preset 只是可选的候选生产者。
2. 从原固定版本的 `ProcessRequirementComposition.psm1` 调用 `New-AiwProjectSourceChangePreparation -DiscoverReceiptPath ... -ExpectedDiscoverReceiptIdentity ... -ConfigPostimagePath ... -PolicyPostimagePath ... -DecisionRef @{path=...;identity=...} -OutputDirectory ...`。后像和决定引用为本项目 `.ai-workspace` 内的绝对路径；输出是其 runtime 下尚不存在的目录，父目录须已存在。函数校验原静态事实、完整字段差异、保护与许可，再用同一 composer 投影最终组合。它只写调用者证据，返回 `authorityGranted=false/projectWritePerformed=false`，不改变两个控制载体。
3. 准备结果包含 `candidate={path,identity}`、`preparationReceipt`、重算的 `permissionChanges`、目标完整 `selectedRuleBlocks` 及准备/结果义务。调用者核对原决定确实覆盖来源 id/provider/root/allowedPaths/decisionLocator、revision、完整文档图与知识来源差异，读取目标命中全文，履行旧/新准备义务。在原 boundary3 ADMIT 的 preparationReceipts 加入返回的 `PROJECT_SOURCE_CHANGE|<candidate absolute path>|<identity>`，保留真实 ADMIT 输入与返回；不得只在写后补声明。
4. ADMIT 复证完整候选并绑定现有 decisionIdentity，成功返回 `projectSourcePreparation={candidateIdentity,targetIdentity,outcome:PREPARED}`。实际写序为 policy 在前、config 最后，逐文件原子写并读回；可以直接执行原精确动作，也可由下述恢复入口从全前像开始建立真实投影事务。
5. 原 FINALIZE 使用同一 compact，携原 candidate token、`PROJECT_SOURCE_ADMISSION|<admit input absolute path>|<identity>|<admit result absolute path>|<identity>`、每个实际写对象唯一的 OBJECT_POSTIMAGE 和正常 typed evidence/结果。共享校验先证明原包、准入、静态事实、完整前后像与受限差异，再允许读取目标来源；随后核对冻结的最终规则集合，并保留原/新义务并集。原准入保留旧配置能力集合，目标准备与成功收口由已验证目标配置重组能力和规则；回滚仍按旧集合收口，不把目标能力写回旧 receipt。Maintenance 前门使用同一证明后才替换 config 预期身份，再正常核对原固定 runtime 与双仓拓扑，不使用跨命名包采用例外。

候选 JSON 精确为 `schemaVersion=1, kind=PROJECT_SOURCE_CHANGE, discoverReceiptIdentity, authorizationIdentity, userDecision, decisionRef, objects, permissionChanges, rootToolDependencies, target`。objects 按 policy→config 排序，每项为 `{path,preimage:{path,identity},postimage:{path,identity}}`，保留完整原始字节。permissionChanges 为重算的 `{sourceBindings,knowledgeSources}`，每项 `{id,before:[],after:[]}`。rootToolDependencies 固定根入口依赖的路径和字节身份。target 为 `{projectConfigIdentity,policyIdentity,projectStandardsIdentity,contentSnapshotIdentity,effectiveSetIdentity,selectedRulesIdentity}`。后像、许可、正文、依赖、工具或原准入变化使候选失效，不得重新 hash 后追认已执行动作。知识方法保持参考用途，不因声明被遍历或变为规范义务。

中断复用根 `upgrade-project.ps1 -ProjectId <id> -ToVersion 2.0.0 -RepositoryPath <project> -ProjectRuleRecoveryPlanPath <plan> -ExpectedProjectRuleRecoveryPlanIdentity <identity> -ProjectRuleRecoveryDirection COMPLETE|ROLLBACK -ActorRouteActor <original actor> -Apply`。plan schema2 精确字段为 `schemaVersion,discoverReceiptPath,discoverReceiptIdentity,admitInputPath,admitInputIdentity,admitResultPath,admitResultIdentity,preparationReceipts,resultReceipts,evidenceRefs,transactionRelativePath`。preparationReceipts 包含 candidate token 和已履行义务，不重复放 admission/rollback 保留 token；入口从原件生成它们。evidenceRefs 绑定本次完成或回滚的实际整组结果。transactionRelativePath 位于 `.ai-workspace/upgrade-recovery/project-rules/<taskId>/<caller-selected-directory>/state.json`。

恢复只接受全前像、policy 后像/config 前像、全后像；两者都实际变化时的 config 新/policy 旧组合拒绝。所有对象与原事实先验证，第三方字节零写拒绝。COMPLETE 重证冻结目标，再按原动作 FINALIZE；ROLLBACK 不读取目标来源，以 config→policy 还原原字节，加入 `PROJECT_SOURCE_ROLLBACK`，由原规则收口撤销结果。来源离线不阻止有完整原件的回滚，原工具/包失效仍拒绝。全后像且无 journal 直接验证原收口，不补造事务；恢复时新建的 journal 明示 `RECOVERY_CREATED_NOW_FROM_ORIGINAL_ADMISSION`，再次中断复用实际 journal。已关闭恢复事务不得反向覆盖后来工作。原 Bootstrap→policy 的 schema1 恢复保持原支持面。

这些候选、准入和恢复材料均为 `INSTRUCTION_BOUND`：绑定字节及真实过程关联，不证明原始用户语义、模型阅读或恶意伪造防护，不形成新授权/账本。原动作完成后，后续独立动作才按当前配置正常准入；新 DISCOVER 不替代原动作收口。

无安装效果的纠正记录变更沿普通 CONTROL_WRITE、完整目标组合和原后像收口；已有历史/安装归属证据先保存，carrier 最后原子替换并读回，不取得项目 WRITE、不创建事务 journal。中断留下未引用历史可保留，不能因其存在覆盖第三方；实际安装/修订/暂停/卸载效果继续使用原投影、片段归属、依赖与恢复。

### 同项目专业正文的联合发布

此分支只接单一项目拥有的有限 LOCAL_DIRECTORY 专业规范：普通 UTF-8 Markdown 文件替换或 NEW，属于旧或目标完整专业来源闭包；NEW 必须被目标引用。先校验保护、排除、所有权、reparse 和路径别名，再读正文。脚本、测试、产品源码、根宿主入口/Skill、`.ai-workspace` 中的 docs、Framework/固定分发载荷、项目外 LOCAL/Git/HTTPS 写目标、删除及搬移拒绝。目录名、扩展名与新增 policy 引用不独自证明专业语义；原决定逐文件明确用途、写入及完成前恢复，作者与适用独审核对真实专业要求。外部供给方先在自身边界发布，消费项目随后独立采用；Maintenance TARGET 与 CONTROL 不合组。

先冻结计划，再签同 task/Owner/actor/决定/固定运行根的两份包。严格可选 `sourcePublicationBinding={planRef:{path,identity},member:SOURCE|CONTROL}` 仅用于 schema1 或 CONTROL schema2 的纯 SOURCE_WRITE/SOURCE、纯 CONTROL_WRITE/CONTROL，不含 continuationPlan、selfCheckRepairLimit、repairReviewPlan/Binding、transitionPlan、升级/接受/外部绑定。SOURCE 写集恰为计划中实际改变的 docs，CONTROL 恰为实际改变的 policy/config；两成员均须非空，未变对象只保留在完整候选读绑定中。Maintenance 例外要求当前 PROJECT_CONTROLLER 签两包并通过真实拓扑，`RootRepositoryBindingValidated` 不代替共同 eligibility。无 binding 的旧 CONTROL SOURCE_WRITE 禁令不变，其他被禁动作不获例外。

计划严格字段为 `schemaVersion=1,kind=PROJECT_SOURCE_PUBLICATION_PLAN,projectRoot,repositoryId,frameworkRoot,taskPath,taskId,taskIdentity,owner,actor,controllerIdentity,projectConfigIdentity,userDecision,decisionRef,assuranceEvidence,objects,writeOrder,permissionChanges,selectorChanges,sourceClosure,rootToolDependencies`。根为已验证的物理绝对根；repositoryId 为 REPO_LOCAL 或 CONTROL。计划不引用两包、DISCOVER、ADMIT 或共同候选，避免循环。objects 顺序为明确的 docs、policy、config，各项 `{path,ownerMember:SOURCE|CONTROL,preimage:{path,identity},postimage:{path,identity}}`；引用在本项目 `.ai-workspace` 内，绑定完整原始字节。NEW 前像仅用 `{path:<正式相对路径>,identity:NEW}`。writeOrder 是真正改变项的同序子集，noop 留在完整 objects。

decisionRef 指向严格 `{schemaVersion:1,kind:PROJECT_SOURCE_PUBLICATION_DECISION,projectRoot,taskId,owner,actor,userDecision,documents:[{path,write:true,recoverBeforeCommit:true,purpose}],forwardRecovery:true,inverseRecoveryBeforeCommit:true}`。它绑定原决定，不另造授权；userDecision 与两包一致。assuranceEvidence 使用现有 typed `{kind,path,identity}` 引用，实际验证精确完整候选、原要求、结果和独立性；CRITICAL 必须有对应 APPROVED/ACCEPTED。候选不是现行规范，准备成功不代替适用审核/接受。

sourceClosure的旧/目标两项各保存identity及完整documents列表，由同一编译器在真实专业发布准备边界重算全部有效采用项，包括未选章节。它属于该次完整目标校验，不把普通当前选择的scoped身份当全库证明。permissionChanges取原sourceBindings/knowledgeSources；selectorChanges逐ruleId保存除source外的前后rule对象，包含选择、义务及语义差异。config仅接原来源字段差异，本发布不首次启用或切换能力；旧单步Controller首次知识启用例外保留。单元、whole-file identity、依赖、采用、完整有效集合与实际工具共同绑定本次发布。

计划可选严格 `reviewScope=[{path,identity}]`，以正式项目相对路径及对应 objects 后像身份冻结实质审查集合 A。实际写集 M=writeOrder，完整对象读绑定 R=objects，并始终保完整 sourceClosure；必须 M⊆A⊆R。未提供时沿旧合同 A=R。assuranceEvidence 的精确候选仅匹配 A 的冻结后像文件；完整 R 的字节、路径、许可、保护、相容性及完整来源闭包继续核验，两成员准备、准入、执行、恢复和原收口使用同一冻结计划。Owner与适用审核者判断只读对象是否影响专业要求、权限、selector或依赖语义；有影响者进入 A，不能以 noop 自动免审。仅补列未变且不改变既有判断的只读对象不重做模型审验，原证据和裁决不改写。

同次私有调用可共享已实际核验的旧/目标闭包和两成员目标；各公共请求重新观察所需当前成员字节、路径、权限、任务和原工具，真正写前继续复证原前像、保护与两份原准入。同次共享不接受调用者可信缓存，也不延长写锁或取消部分成功恢复。

原 `New-AiwProjectSourceChangePreparation` 增加成组 `PublicationPlanRef,PublicationSourceReceiptRef,SourcePostimages`。主 DiscoverReceipt 为 CONTROL，另一个为 SOURCE；SourcePostimages 是 docs 的有序 `{path,identity}` 后像列表，必须等于计划。缺省仍走原 schema1，半组拒绝。各自先以旧来源独立 checker/DISCOVER；准备投影新完整 docs 和最终 config/policy，用各原 action/intent 返回两目标全文与义务。两成员实际读完目标全文并履行各自原/新义务后，以同一 candidate token 准入。既有单成员入口保持；受限联合入口可一次提交两份原输入，各自真实 checker/权限、当前绑定和准备义务仍独立核对。单成员 PREPARED 不允许普通执行者裸写；实际整组写入由原根编排复证完整两成员准入后执行。

受限联合准入由既有 resolver 的 `-PublicationSourceInputPath <absolute-path> -ExpectedPublicationSourceInputIdentity <length|SHA256>` 成组参数选择，`-InputPath` 仍为 CONTROL 的原 schema3 ADMIT_ACTION，另一个为 SOURCE 的原 schema3 ADMIT_ACTION。两输入须绑定同计划、同候选、同方向及各自原收据；不接受普通动作、混合项目、半组或自报可信 facts/targets。必须 `-AsJson`，不与 `DeleteInputOnExit`、`CompactReceiptPath` 或 runtime 消费/空目录/保留清理参数混用；原件按最后消费者管理，既有单输入清理行为保持。返回 `{kind:PROJECT_SOURCE_PUBLICATION_BOUNDARY_PAIR,status,mode,reason,members,failedMember,authorityGranted:false,semanticCorrectnessProven:false}`，成员顺序 SOURCE、CONTROL，各项 `{member,inputRef,response:{exitCode,output}}` 保存实际原边界响应。仅两成员均成功时整体 PASS；失败只列实际到达的成员，不补造未执行结果。恢复材料继续保存各成员真实原准入结果，不以联合包络代替它们。

联合调用仅在本次私有生命周期复用已实际核验的不可变目标结构；进入第二成员前仍重新观察当前完整成员、路径、原件和权限，两个原边界分别核当前绑定、各自选择和准备义务。失败和调用结束释放上下文，不接受公共可信校验参数，不持久化跨请求缓存。准入合并不合并两类权限，不授予其他动作。公开联合参数仅服务 ADMIT；收口由原根恢复调用组织，既有单成员 FINALIZE 仍可消费完整原组。

共同候选严格为 `schemaVersion=2,kind=PROJECT_SOURCE_PUBLICATION,planRef,userDecision,decisionRef,members,objects,writeOrder,permissionChanges,rootToolDependencies,targets`。members 固定 SOURCE、CONTROL，各为 `{member,discoverReceiptRef,authorizationRef}`；targets 同序，各为 `{member,binding:<原六项目标身份>}`。沿用 `PROJECT_SOURCE_CHANGE|<absolute candidate>|<identity>`。三个私有共同模块纳入 implementationIdentity、rootToolDependencies 和分发闭包；CLI 与同进程调用共用原 checker/boundary，不复制 resolver/composer。

根 `ProjectRuleRecoveryPlanPath` schema3 严格为 `{schemaVersion:3,kind:PROJECT_SOURCE_PUBLICATION_RECOVERY,projectRoot,planRef,candidateRef,members}`；members 固定 SOURCE、CONTROL，各项 `{member,discoverReceiptRef,admitInputRef,admitResultRef,finalizeInputRef}` 保存真实原准入和已准备的最终输入/typed evidence。沿原 COMPLETE/ROLLBACK 参数调用。新批次从这两份原准入、完整候选及实际前后像复证 actor、任务/Controller、原工具、审验与全组状态，不创建全局 journal、completedWrites、previousJournalRef 或完成提交层。公开 FINALIZE 以 `PROJECT_SOURCE_PUBLICATION_ADMISSIONS|<schema3 plan absolute path>|<identity>` 引用这组原件；它不授予写权，消费者独立重验两份准入。旧已存在真实 journal 仍由原固定工具按原方向恢复，不改造、删除或迁移其历史。

真正改变项只接受后像前缀 N 加前像后缀 O。按 docs→实际改变的 policy→实际改变的 config 逐文件原子写并读回；原件与该有序前后像足以识别 allOld、已知 prefix 和 allNew，无 journal 的已知前缀可以沿原许可继续。第三方 bytes、不可能组合、原工具或 actor/task 漂移拒绝且保留现场。回退只在原决定许可内逆序还原本批已写的精确后像；NEW 仅删除本批 exact NEW 后像。任一成员已正式完成后不自动反向恢复，后续撤回须新决定及候选。

实际 allNew 后，原根调用组织两个成员的真实原 FINALIZE；两者都待完成时在本次私有调用中共享目标构造，第一份真实成功结果立即保存并读回，再开始第二成员。真正写入的同次调用可复用刚在实际 PUBLICATION 保护内验证的目标结构，仍重新观察当前成员、路径、权限及各自 live binding；写句柄不延长至收口。只有一方待完成时沿原单成员边界补齐，两方已有成功结果时先完成当前完整验证再复用；不重复无写入的目标构造。正常 `projectSourcePreparation.outcome=COMPLETED/actionOutcome=OBSERVED`；原许可内精确回退则为 `ROLLED_BACK/OBSERVED`。每个结果均消费原 compact、双 ADMIT、全组后像、typed evidence 与原/新义务。只有两份成功结果齐全才报告整批 COMPLETE/ROLLED_BACK。一份成功而另一份失败或未知时保留已成功原件，整批仍未闭合，重启只补未完成的收口，不重写已完成对象或撤销第一份真实事实。保存的结果仍核原输入、decision/selection identity 与当前全组，不能凭 PASS 字符串补成功。

普通读取不取得应用级项目/source协调句柄，不创建或打开source-publication.lock，不自动深读publication journal而全局阻断。中央Enter的OBSERVE返回null，Invoke的OBSERVE直接执行观察体；直接消费者自行验证真实根、当前对象与各自所需事实，不从null lease推导根或伪造Owned/Handle。普通当前任务卡单对象更新按原责任、精确包及当前前像执行完整原子替换，再收口实际后像，不默认项目WRITE锁，也不声称CAS。

真实多对象采用、发布、责任转换及恢复保留原有必要写保护。Windows/PowerShell7本地文件系统的同步键仍为canonical物理项目根下的source-publication.lock，实际WRITE/PUBLICATION使用原零字节OpenOrCreate/ReadWrite与FileShare.None，项目锁先于局部锁；句柄只覆盖实际联合写入/恢复的保护段；日常批次 allNew 的纯收口不取写锁。真正采用/安装效果/责任事务的 journal 与完成证明仍按其原合同保护，不覆盖普通读取。纯FINALIZE不默认取得WRITE；仅首次保存FORMAT事务的originalFinalize时，在真实写保护内重新核对原件、journal和逐对象后像再保存。

真实写者冲突返回非零SOURCE_PUBLICATION_BUSY，holder=UNKNOWN，收起本次竞争；不轮询、自动重试、超时抢锁或等待。显式读取相关publication journal仍验证它的完整事务，真实未闭合状态按原入口恢复，不把它当普通观察前门。恢复预览零写，只返回已核对原决定与当前组的WHAT_IF上限；实际Apply在原排他保护内完整复证原双ADMIT、计划、候选和可达状态。不得从预览、null观察scope或caller标志获得恢复资格。不删、替换、重命名同步文件；非空、reparse、权限及其他IO故障分别拒绝。

只有当前调用栈、同一runspace中真实注册的live写句柄可借用，恢复还须复证原双ADMIT及精确计划/候选。公共JSON/CLI/环境/全局对象不能跳过检查；普通OBSERVE没有可借用句柄。旧包按自己的原固定合同执行，不增加外层读桥或向HEAD补载。写保护只协调参与协议的事务，不提供跨文件瞬时读取保证；外部编辑器、裸写、掉电和磁盘损坏不获得物理事务保证，未知字节仍保留原件并拒绝。

## Project selection

project authority field 是 `.ai-workspace/project.json.frameworkToolBackend`。`2.0.0` 只接受 `powershell7`；registration/upgrade deterministic 写入该值。所有 task/operation 继承它。authorization package 不重复该字段；既有 `projectConfigIdentity` 会在 selection 或其他 config byte 改变时使 package 失效。

host 先读 project pin，再读 pinned `TOOLCHAIN.json`。backend ID、`OFFICIAL` status、platform、runtime edition/version 与 exact entrypoint 都必须匹配。unknown field/backend、missing entrypoint、path escape、unavailable runtime 或 contract drift 在 operation 前 fail closed。Framework 不 install/download runtime。

## Project Bootstrap navigation

本目标Tool Contract4使用navigationContractVersion3；TOOLCHAIN声明PROJECT_BOOTSTRAP导航类型及其locator，具体字段取已冻结的目标schema。项目AGENTS直接导航自己的固定BOOTSTRAP；从原采用记录及project pin解析实际TOOLCHAIN，不声明或安装新Router Skill，也不提供nav3通用Skill转发层。AGENTS/Bootstrap的生成、用户授权原文承接及原过程切换取根PROJECT_ADOPTION。

旧nav1/nav2固定来源继续按自己的Skill及过程格式运行，原动作收口后才切换新入口；旧完整材料不降格解释为新格式。健康正文复用、压缩/换主体FULL及实际补差取RECOVERY_CORE；导航不证明模型attention或授予任何动作。

## Invocation

operation name 与 entrypoint path 只来自 `TOOLCHAIN.json`。path 是 version-root-relative、NFC-normalized、forward-slash locator，不得 absolute、drive、empty component、`.` 或 `..`。host 直接调用 selected entrypoint，不提供 user-facing launcher 或 generated wrapper。

official backend 使用 `pwsh -NoProfile -NonInteractive -File <entrypoint> ...`。每个 `2.0.0` entrypoint 独立拒绝 non-Core runtime 或 PowerShell major < 7。

## Results 与 evidence

exit code `0` 表示 operation 返回 documented accepted result；nonzero 使 requested boundary 失败，caller 保留 explicit reason，不从 prose 猜测成功。支持时优先用 structured `-AsJson`。human-readable output 只是同一 result 的 projection，不是 authority object。

file identity 为 exact bytes 上的 `byteLength|UPPER_SHA256`。JSON/Markdown 使用 strict UTF-8 no BOM，接受语义等价的 CRLF 和缺末尾 LF；解析时的等价处理不改变原始字节 identity。security-relevant JSON 在 escape decoding 后递归拒绝 duplicate members。repository-relative evidence 使用 forward slashes。

`2.0.0` 只列 Windows。未来 platform 只有在实际 conformance run PASS 后才受支持；missing CI/host evidence 是 capability ceiling，不得推断 compatibility。

## Backend lifecycle

backend selection 只在 released Framework 已提供 target backend 的 project adoption/switch boundary 改变。项目必须没有 active writer/reviewer lease，通过 project config drift 使 outstanding package 失效，transactionally 投影 config，并完成 fresh recovery/conformance。`2.0.0` 只有一个 backend，因此不提供 switch command。

本 contract 不增加 backend registry、service、ledger、plugin market、runtime code generation、task-level choice 或 global Framework default。

## 有限责任转换

Tool Contract 3的CONTROL_TRANSITION只接受原纯CONTROL_WRITE包，operation为PREVIEW/APPLY/FINALIZE/COMPLETE/RECOVER。输入为{operation,projectRoot,planPath,expectedPlanIdentity,recoveryMode}；非恢复的recoveryMode为NOT_APPLICABLE，RECOVER为CONTINUE或ROLLBACK。真实恢复主体取宿主CODEX_THREAD_ID并匹配原计划，不由输入自报。

plan1 结构取CONTROL_TRANSITION_SCHEMA.json，仅允许现存Controller与active任务对象；Controller只改ID并将epoch加一，任务只改明确列出的Owner/actor/role/phase/profile和已有唯一AIW-HANDOFF标记区内事实。TaskId、pin、项目身份、规则来源及无关正文不得改变。全部原始前像和最终后像保存完整identity/base64；步骤必须是Controller先设标记、其余任务设标记、任务实质字段更新、Controller身份最后更新，再任务清标记、Controller最后清标记。

标记指向planPath/planIdentity。为避免计划与自己标记的哈希循环，计划不嵌入带该标记的完整字节；PREVIEW从冻结的前/后像和最终planIdentity确定性派生全部标记像并返回真实identity，后续每个边界复算。task使用唯一aiw-transition代码块；Controller使用transitionRef属性。无需可变计划、占位哈希或第二权威。

originalProcessLocators预先固定原package、DISCOVER输入/compact、ADMIT输入/实际结果、FINALIZE输入和completionProof的同一runtime目录路径，不写未来身份。PREVIEW消费已准备的原DISCOVER输入，返回目标责任组合的完整规则供当前模型加载；实际准入随后通过原规则流程，APPLY再次复跑原ADMIT。每次恢复复核原材料、未变来源以及整组可达状态，不能以“每个对象分别属于某个已知像”放过不可达组合。

标记仍齐全时，原FINALIZE验证实际后像、未变来源和原/目标全部适用义务，通过后原子持久保存并回读完成证明。COMPLETE只据该证明精确去标记；最后标记消失前已有原过程完成点。每步复查全组状态并持有原事务排他文件锁。证明前可按原计划续完或回滚；证明后只能幂等完成清理，逆向变更须新动作。完成证明保存原准入的真实身份、核验过的标记后像、最终后像与剩余清理步骤，不是新授权或全局登记。

## 普通任务关闭归档

CONTROL_TRANSITION仅保留schema1真实责任转换。当前卡关闭可继续原单对象CONTROL_WRITE；物理归档是普通纯CONTROL_WRITE的窄两对象动作，恰为原active及同basename archive，不含Controller、route变更、其他卡或规则。先在active存在时核原包/前像并准入；taskId来自原receipt及正文，允许不同于basename。不新建归档plan、locator、marker、冻结卡reader、journal或完成proof，也不阻断无关任务。

当前卡归档后像明列Closure outcome=SUCCESS/CANCELLED/SUPERSEDED、Closure basis、Output disposition、Git disposition及依据、Unresolved obligations=NONE或TRANSFERRED:真实承接说明，Writer/Reviewer/Authorization为RELEASED。原正文ID、Owner、Work route、profile和Execution target引用保持。SUCCESS按实际acceptance plan消费全部必需阶段；取消/替代保留Unfinished work、Closure decision原件与未解承接，不冒充成功。先完整保存archive并读回、用既有Assert-AiwTaskClosure的RequireExplicitClosure核闭合与真实验收，再复核active仍为原前像后删除。每个对象完整原子替换；这一顺序不承诺跨进程CAS或跨文件原子提交。

相同完整archive可以复用；不同现存archive仅按明确原像和精确范围处理，不因同ID或CLOSED默默覆盖。active原像加archive后像可沿原动作继续；active已删且archive完整则补原FINALIZE，不补造事务。缺失/不完整archive或第三方字节不删除active、不覆盖第三方。其他已闭合卡的普通物理归档以完整原像逐字节转移，保留正文真实ID及完整接受要求，不从文件名猜ID。

原FINALIZE在任何当前任务读取之前，核原包/receipt的上述精确形状、active非NEW原像与唯一MISSING后像、实际archive完整后像及原逻辑任务/Owner/actor/route/profile。只将已验证archive作为实际读取路径传给Snapshot、ExecutionTargetContext、task binding和ResultEvidence，原receipt/sourceLocators与逻辑任务不改。不提供通用missing回退或公开skip；成功验收及第三方边界照常生效。原件和实际失败保到最后消费者，关闭、宿主归档与Git分别核对。

这些字节与关联校验保持INSTRUCTION_BOUND，不证明材料不可恶意伪造、模型实际注意力或跨项目原子性。普通单卡现有后像路径能闭合时继续使用原路径；临时grantee/Reviewer变化不使用控制转换。

## 既有领域外部资源的有限使用

Owner direct domain 仍为纯 EXTERNAL，issuer=当前Owner；externalBinding2可在原许可确实允许委派时，将grantee绑定同成果的具名原专业执行者，不提升其为Owner。Owner自用仍要求主路线TASK_OWNER/EXTERNAL；仅externalBinding2中原许可覆盖的异Owner具名委派，允许Owner保有当前有效的其他主phase，其唯一TASK_OWNER主路线actor仍须为该Owner。临时grantee沿原任务EXECUTOR/EXTERNAL路线消费，不修改Owner或Work route；外部观察本身不证明独立审核或接受资格。externalBinding1保持Owner自用的严格FREE/0。ZERO_PROJECT_DATA仅PROVIDER_PUBLIC_METADATA_READ/PROVIDER_PUBLIC_STATUS_READ/PROVIDER_CAPABILITY_DISCOVERY，EXACT_PAYLOADS逐项绑定payloadKind/normalizedIdentity/canonicalizationVersion，不混用。

externalBinding2 共同必需字段为 schemaVersion、route=TASK_OWNER_DIRECT_DOMAIN_EXTERNAL、provider、orderedOperations、outputUse、perOperationRetryCeiling、totalRetryCeiling、stopConditions、batchExecutionMode=ONE_LOGICAL_ATOMIC_EXECUTION、reissuable=false、ambiguousConsumptionPolicy=BLOCK、escalationFlags，加 grantRefs、grantAssessment。operation 仍为 operationId/operationKind/declaredInputClass/payloads，ID 唯一。有限 orderedOperations 自身限定数量；totalQuantity 可省，提供时恰等于初始操作数。总重试不超操作数乘单操作重试上限。

grantRefs为非空{path,identity}数组，指向本控制项目内真实用户决定/已批资源政策完整原件，逐次核当前原文、撤回/替代事实和语义适用。grantAssessment严格必需字段为{status:CURRENT_AND_COVERED,withdrawalOrReplacementObserved:false,provider,operationIds,outputUse,paidResourceUse,sharedResourceUse}，仅可额外带delegationPermitted:boolean；grantee不等于Owner时必须明确true，缺失、false或未知拒绝。原许可禁止转授时不能填true，也不能通过Owner纯转签改变其含义。provider/operationIds/outputUse恰等于本批，use为boolean，sharedResourceUse与escalationFlags.sharedQuotaOrResource一致。判断仍为INSTRUCTION_BOUND，执行者须核原许可是否覆盖具名接收者、原账号、费用/共享条件、已审payload及最坏重试；字段不是新许可、用户认证、实时账户余额或机械语义证明。

原许可实际规定且本次依赖时才带 grantConditions：operationCeiling 比较含最坏重试的调用数；costCeiling={value,requestedValue,currency,unit} 用可表示的十进制字符串和明确三位币种/计量单位，requestedValue 不超原 value；deadlineUtc 为实际 UTC 期限；sharedQuota={resource,quantity,requestedQuantity,unit} 是原共享条件及此次非负整数需求，需求不超限定值。原文无金额、币种、期限则省略，不填 UNKNOWN/无限/伪造 0。Framework 不算余额、并发占用或项目账本，执行者仍核实际条件与供应商结果。

escalationFlags 保留 paymentOrSubscription/commercialLicensing/accountOrCredentialChange/publicPublication/installation/protectedOrSecretUpload/crossDomain/formalAssetActivation/projectPhaseChange/gitOrPush/sharedQuotaOrResource/unknownScope。schema2 仅 sharedQuotaOrResource 可由既有 grant 覆盖；paidResourceUse 指已批付费资源使用，paymentOrSubscription 仍指本次新购买/订阅，不可置 true 进入此路。其他类别仍走原独立门，付费不推出上传许可。未知消费阻止不可安全重发的后续，保留失败和供应商恢复依据，本地准备继续。不调用服务的夹具不报真实费用、账户动作或服务成功。


宿主输出可能受限时，普通与Maintenance入口可在同次DISCOVER显式指定 `-DisplayPath <absolute-new-txt>`，由现有官方renderer将该次完整结构化结果的同一 `text` 写为严格UTF-8无BOM；默认不存正文，默认stdout仍一次完整text。文件限定当前 `.ai-workspace/runtime/<task-or-request>/<actor-storage>/` 的新安全 `.txt`，目录必须已存在，保护/排除和reparse检查先于目标访问，CreateNew拒绝覆盖。仅成功DISCOVER可保存；写失败整个调用失败，部分文件不能消费。它不是新规则来源、收据、缓存或永久结果台账，不扩授权或改变JSON/schema。

跨原生进程时用 `-AsJson -DisplayPath $bodyPath`：程序捕获完整ASCII转义JSON，检查真实exit/status，机器载体不进入模型；宿主以明确UTF-8读取同次官方txt给模型。没有输出限制时一次读完整text；仅在真实截断后，从同一保留字符串或txt的已观察截断处有序补缺，可适当回到被截断完整单元/义务起点，保完整引用与结束标记。使用现有文本/文件读取能力，不再DISCOVER、不从compact当正文、不读policy/doc标记重拼，不主动固定小页或建页票据。副本保留至本次最后消费者完成后按既有runtime生命周期精确释放；保存/字节等价不证明模型attention。旧固定版本不接受新参数时，程序保留一次 `-AsJson` 的完整结果，同进程调用其官方renderer，再以明确UTF-8传给宿主，不热改旧包。

## Typed evidence and acceptance (Tool Contract 3)

ADMIT_ACTION / FINALIZE_OUTPUT 的 boundary schemaVersion=3 在 schema2 字段上增加可选 `evidenceRefs: []`，实际证据门要求时必须提供相应引用。每项严格为 `{kind,path,identity}`，kind 仅 SELF_CHECK、REVIEW_VERDICT、RESULT_ACCEPTANCE；旧 boundary 格式不能绕过新动作所需的 typed evidence。UNKNOWN/重复字段、引用或候选、错误阶段、任务、主体、候选身份及要求身份均拒绝。decisionIdentity 绑定完整 evidenceRefs。要求与原始记录只在自然使用边界按需读，不在每次 task-card 结构检查中追读历史。

同根记录用 typed1，隔离目标用上述 typed2；共同字段和严格分支见 EVIDENCE_RECORD_SCHEMA.json。成功值分别 PASS / APPROVED / ACCEPTED；真实失败记录可完成“实际结果已观察”的输出，但不能满足成功前置。checks 至少一项，包含 id/method/outcome/reason/evidenceLocators。COMMAND 的唯一原始引用指向 `{command,exitCode,output:{path,identity}}`，必须读取实际输出且成功需要 exitCode=0；MODEL_JUDGMENT 引用实际判断依据并记录理由，不能填虚构退出码。命令记录只是实际观察，不在读取时执行命令。

REVIEW_VERDICT 与 RESULT_ACCEPTANCE 额外必需 `authorizationRef:{path,identity}` 反向绑定原纯动作包。SELF_CHECK 无该字段。仅 RESULT_ACCEPTANCE 可选 `acceptedCommit`，实际 push 必须与 localCommit 一致；非 Git 成果省略它。记录引用既有来源，不建立证据状态台账。包的当前 task identity 仍在动作前校验；成果证据的 requirementsRef 绑定不可变要求正文，日常进度卡改写不使所有历史证据循环失效。section 如使用，是既有唯一 `<!-- <section>:BEGIN --> ... <!-- <section>:END -->` 区块，仍绑定整文件。

所有普通 ref 为 `{path,identity}`。候选 path 相对绑定的 repository root，其他相对 control/project root；绝对路径仅限已绑定项目、精确 target 或 Framework root。读取之前拒绝 routineExcludedPaths/forbiddenScope、路径逃逸、ADS、非文件对象和 reparse。存在的候选身份用原始字节 length|SHA256；真实不存在的候选使用 MISSING，并保留在完整候选集合中。原授权包的 NEW 仅在比较该不存在前像时映射为 MISSING，不改写原包。SELF_CHECK、交审、独立审核及接受均复核实际存在状态，意外重现或伪报不存在拒绝。证据记录、原包、requirements、命令输出及原始用户决定引用仍必须存在且有字节身份，不能使用 MISSING；不正规化旧文件冒充原像。

普通locator允许已绑定根内的安全等价拼写，不改写原文件或放松路径边界；drive-relative、逃逸、ADS、设备名及reparse仍拒绝。成功证据按实际用途显式消费：Read-AiwResultEvidence的EvidencePurpose缺省CURRENT_CANDIDATE，继续核当前候选、当前权限/目标状态及原要求；HISTORICAL_SUCCESS仅在调用者给出有限OriginalFinalize=[{inputRef,resultRef}]、原成功记录确实列在相应真实FINALIZE evidenceRefs且原compact/包/决定/要求/结果/后像链均成立时成立。原记录不回填完成字段，不搜索新证据或制造成功证书；仅-Historical不放松当前成功门。Assert-AiwAcceptanceBinding的PrerequisiteEvidencePurpose可使前置证据按历史用途递归消费，自身候选始终CURRENT；Assert-AiwAcceptanceStages及递归接受沿同一用途和原件集合，不因普通locator或递归入口而丢失。历史worktree证据可脱离后来HEAD/产品状态核原成功，但保留原已验证executionContext用于当前绝对保护的control→execution映射，保护先于任何目标IO。

正常消费者在现有原件引用旁传递用途：纯接受包可选 `acceptanceBinding.prerequisiteConsumption`，验收计划的 typed stage 可选 `evidenceConsumption`，专业发布计划可选 `assuranceConsumption`。三者严格形状均为 `{purpose,originalFinalize}`；purpose 仅 `CURRENT_CANDIDATE` / `HISTORICAL_SUCCESS`，originalFinalize 为有限 `[{inputRef:{path,identity},resultRef:{path,identity}}]`。缺省为当前用途及空数组；当前用途带非空历史引用拒绝，历史用途缺原件拒绝。DESIGN / USER_DECISION 阶段不接受 evidenceConsumption。实际 RESULT_ACCEPT、SUCCESS 关闭的阶段预读/完整验证、递归接受及发布 assurance 均传同一已验证用途与有限原件；接受自身候选及发布当前 A/R/M 继续严格核当前字节。声明属于当前消费者，不回填旧证据，不从 live 漂移自动推断历史成功。

exactScope、forbiddenScope、protectedScope及boundary准备/结果/交付receipt集合无统一256项上限；仍逐项校验形状、长度、唯一性、真实成员与义务，不取消其他有语义依据的字段限制。当前Input5生产及continuation1/2/3消费共同支持规范绝对或相对的literal保护scope；绝对排除可在仓外，只校验字符串，不读取其目标。反斜线、ADS、非规范/逃逸分量、通配/控制字符、设备名等拒绝，原scope绑定和当前保护并集保持。

`acceptanceBinding={candidateObjects,requirementsRef,prerequisiteEvidenceRefs,reservedUserDecisionRefs}` 只用于纯 RESULT_ACCEPT，可选上述 `prerequisiteConsumption`，不与 continuation/repair/receiver/transition 混用。非 Owner 接受须原 Owner 签发；例外的真实用户授予以原始用户来源 ref 绑定，package.userConfirmation 与 boundary.publicDecisionIdentity 同为该来源身份，reservedUserDecisionRefs 中包含该 ref。字段绑定不独立证明用户来源/含义，执行者必须核对真实宿主用户输入；模型自填“已确认”及其他 agent 委派不是用户决定。保留事项引用实际用户来源，不新增用户决定服务。

任务唯一 `aiw-acceptance-plan` 结构见 ACCEPTANCE_PLAN_SCHEMA.json。stage.candidateRef 是已有产物 `{path,identity}` 数组，不另建产物 manifest；requiredBy 使用 requirementsRef 形状；evidenceRefs 使用上述 typed refs。stage.kind 限 DESIGN/DESIGN_REVIEW/SELF_CHECK/RESULT_REVIEW/RESULT_ACCEPT/USER_DECISION。每个列入阶段都有实际 requiredBy，无单独 PASS 状态。DESIGN 读实际产物；两种 REVIEW 读对应候选裁决；SELF_CHECK / RESULT_ACCEPT 读各自记录。USER_DECISION 的 candidateRef 引用真实原始用户决定，evidenceRefs 留空，不能造第四种证据；当前边界的 publicDecisionIdentity 或已合法接受包保留的用户来源须与之相符。未发生的用户门保留空 candidateRef。

RESULT_ACCEPT 的候选与要求定位唯一接受阶段，只校验其传递前置闭包；最终 SUCCESS 再核验全部必需阶段。task checker 仅做结构、重复与环检查，实际关闭的原 CONTROL_WRITE FINALIZE 读取本次精确写集内所有关闭任务的证据，包括主控在管理任务下关闭另一张卡；删掉 Closure outcome 也不能绕过其既有验收计划。接受之后的用户最终门不能阻塞前面的内部接受；未满足它仍不能 SUCCESS。多阶段发布需单独满足实际发布前置，不从内部接受推导发布权。

continuation的最终REVIEW_ROUTE需真实成功生产FINALIZE后像和同一质量选择的准备；LEGACY/选SELF仍需成功SELF_CHECK，C无SELF按下述productionFinalizeRef，实际TEST_RUN失败不产生成功后继；continuation receipt增加evidenceRefs并在生成和使用时复核，不无条件要求前一步TEST_RUN。正式REVIEW_ROUTE的ADMIT消费同一共享作者/适用SELF或原成功生产F检查，作者来自原repairReviewPlan.writer或当前纯Review包candidateWriter；未知Reviewer创建前先核已知作者、适用成功SELF或原生产F和当前完整候选，Owner代组织也不能替换作者SELF。实际发送FINALIZE复用此检查并另验真实接收者/宿主结果；后续独立REVIEW_EXECUTE的FINALIZE才要求真实verdict。原接收者恢复须对齐人类目标、当前合同、分派正文与实际包；缺后继权限只停相应链，保已授安全工作，不从正文扩权。可执行同源组织示例取PROMPTS，不新增公共父包工厂或组织服务。

以上结构与身份验证的上限为 INSTRUCTION_BOUND；不声称证明模型 attention、主观判断、用户来源或恶意篡改全部本地文件的不可伪造性。
### 项目显式质量阶段与一次准备

policy3可选`qualityAssurance={schemaVersion:1,defaultStages:[...]}`。整个对象缺省为LEGACY，保留原schema1计划、无计划和CRITICAL语义；存在则拒null、未知字段/版本、未知或重复阶段。阶段只有SELF_CHECK、RESULT_REVIEW、RESULT_ACCEPT；显式空数组是真零选择。rules中的可选`qualityStages`须非空、唯一并与合法qualityAssurance1同时存在，孤立扩展拒绝。

带qualityStages的规则沿原完整ruleId/理由/正文或来源/decisionLocator/selectors，不建立另一权威。只允许稳定profiles/pathPrefixes及facets.domain/deliverableType；roles/phases/actionKinds/resultKinds/capabilities须为空或无约束`*`，semanticTerms为空，不得有deterministicTriggers或workType/stage条件。唯一选择为defaultStages与全部原Test-AiwRuleMatch命中规则阶段的并集，固定顺序SELF_CHECK、RESULT_REVIEW、RESULT_ACCEPT，无减法、优先级或原生ID开关。

包schema1/2/4的普通成果可带严格`qualityBinding={schemaVersion:1,policyRef:{path:".ai-workspace/process-policy.json",identity},subject:{repositoryId,exactPaths,facets:{domain:{state:"KNOWN",values:[...]},deliverableType:{state:"KNOWN",values:[...]}}},effectiveStages:[...]}`。repo-local使用REPO_LOCAL，Maintenance为CONTROL或配置TARGET ID，已绑定隔离目标为PROJECT；subject是完整有限成果单仓候选，生产M/审收A均不得越出，M可为子集。沿原路径规范、排除、保护及目标绑定；未知必要分类、空或不完整范围不产生可执行零选择。profile取任务，历史取原包，不另造profile权威。

当前验收计划保schema1原形；schema2严格为`{schemaVersion:2,qualityBinding,stages:[原阶段结构]}`。选中阶段不得遗漏；仍有效用户/专业DESIGN、DESIGN_REVIEW、USER_DECISION等阶段及真实依赖由Owner保留。SELF、Review、接受不自动相互蕴含。plan2可在真正零阶段时为空，实际未验证成果如实说明用途、限制和已知结果，不造SELF/VERDICT/ACCEPTED。pending candidateRef/evidenceRefs不满足交审、接受或SUCCESS。

subject全部路径按所选实际仓库执行原候选保护，不能只保护M。实际交审、接受及PUSH的A，以及已填写的选中通用质量阶段candidateRef，均完整覆盖该subject。C原生产包声明完整A时，原成功F证明实际M后像，当前fresh审包冻结并核对全部A；只读未改成员不由此取得写权。既有显式repairReviewPlan的M/A身份关系仍严格保留，不以此抹去原冻结成员漂移。

既有WORKFLOW_ROUTE_RESOLVE dispatcher的只读`QUALITY_PLAN_PREPARE`严格输入为`{operation,schemaVersion:1,projectRoot,taskPath,expectedTaskIdentity,projectConfigRef,policyRef,subject,requirementsRef}`；refs沿原`{path,identity}`，requirementsRef可带原section。它核当前已采用来源、活动卡、配置/策略原件、保护及完整声明，调用同一稳定选择，返回authorityGranted=false、LEGACY或qualityBinding/effectiveStages/schema2计划候选及限制；不写卡、调模型或授执行权。requirementsRef须为已存在且长期保留的本成果要求原件，不能以可变任务卡或活动policy冒充。生成阶段引用该原件，candidateRef/evidenceRefs为空；缺分类、冲突或未知返回具体未就绪原因，不给可执行空模板。

Owner以原单卡CONTROL一次绑定策略/阶段和必要额外要求，包从该原plan投影qualityBinding；实际冻结、自查、审收后补真实candidate/evidence并fresh绑定受影响当前包。显式启用而缺合法plan2或绑定时，普通生产、交审、接受、成功关闭和PUSH报QUALITY_PLAN_REQUIRED/对应绑定错误，不退LEGACY。安全只读、只读准备、原单卡管理及原严格来源维护/责任转换/采用保各自入口，不能靠自填management标志免门；普通CONTROL成果报告仍是普通成果。SOURCE出版、schema3采用、发行资格、external及用户保留等专门包不携普通qualityBinding，不降低其显式独审/assurance/许可要求。

选择SELF时，交审仍需当前成功作者SELF；C未选SELF且没有额外必需SELF阶段时，boundary3的REVIEW_ROUTE准备可携`productionFinalizeRef={inputRef:{path,identity},resultRef:{path,identity}}`。它绑定decisionIdentity，核真实PASS/OBSERVED（TEST_RUN为PASS）、原DISCOVER/包/决定/主体/任务/仓库、完整候选和实际后像；只有重hash、缺原F、失败/不完整、错作者/候选均拒绝。自动continuation在真实成功生产FINALIZE内生成；到达当前REVIEW_ROUTE时同样消费其原成功input/result，不能用continuation本身代准备或伪造未来引用。实际TEST_RUN始终消费真实SELF/COMMAND、退出码和输出；删SELF阶段不重写原FAIL/INCOMPLETE或产生成功后继。REVIEW_PREPARATION_BOUND由真实共享准备生成，复制义务名称不成立。

实际独立Review在所有profile完整绑定并排除Owner、issuer、candidateWriter及全部materialContributors。普通C接受的RequireReview取同一有效RESULT_REVIEW加显式专门要求，原acceptanceBinding、当前候选、要求、真实传递前置及有权接受者保持。SUCCESS按同一计划消费全部真实阶段；取消/替代保未完成和承接，归档写序/前后像不变。未选择RESULT_ACCEPT不强造接受动作；进入PUSH通道仍需真实typed接受和exact acceptedCommit，这是通道前置。C的PUSH通过当前plan的接受stage.evidenceConsumption显式携原成功FINALIZE集合，递归使用同一历史选择并叠加今日通道实际要求，不重新按CRITICAL偷偷加回普通Review。

CURRENT核当前policy原始字节和同一选择。HISTORICAL_SUCCESS先核原typed记录/authorizationRef、原成功FINALIZE/DISCOVER、候选、要求和独立性，再解释原包qualityBinding；其canonical policyRef身份必须恰等原DISCOVER.policyIdentity，原包身份必须仍等原授权绑定。旧无绑定包保持LEGACY；历史不读取今日policy重算旧接受，不增加每轮policy快照。合法后来卡/策略变化不重写旧成功，坏/删除要求原件、缺原成功或篡改绑定仍拒绝。

启用/调整在无相关活跃效果或不可分中间态的安全点，由项目原来源维护PREPARE→真实checker/ADMIT→写入/读回→原FINALIZE生效；config/sourceBindings未变不写project.json。先实际采用支持此能力的新固定包，源码或方案通过不等采用。下一新动作prepare并重绑原卡，不批量迁历史；旧在途沿原来源/准入恢复并尊重当前撤回。停用后新动作fresh回LEGACY，旧C历史保留；未解决活跃及历史消费者前，不降级到不识别plan2/C证据的旧包。通用ObjectFormats只对声明的验收plan1/2严格按原格式、原字节只读，不适配/迁移/写回或泛化其它对象的转换豁免；旧runtime对新字段/operation仍严格拒绝。


## Knowledge index3 接口

入口仍为TOOLCHAIN中的KNOWLEDGE_QUERY和KNOWLEDGE_IMPACT_CHECK，共用版本私有KnowledgeSources模块。当前目标项目配置为schema7，sourceBindings保存获准的provider、locator与allowedPaths；KNOWLEDGE_REFERENCE.sources引用bindingId并保存索引选择、PINNED/FOLLOW策略及所需revision/identity。索引使用KNOWLEDGE_SCHEMA的schema3；旧格式只通过根采用事务的明确纯数据转换进入当前版。

QUERY入口参数为ProjectRoot、ExpectedProjectConfigIdentity、Operation=DISCOVER|QUERY、SourceId[]、EntryId[]、FacetQueryJson、ContentMode=LOCATOR_ONLY|FULLTEXT、ForbiddenPaths[]、AsJson。省略Operation时，显式提供EntryId或FacetQueryJson即QUERY，否则DISCOVER。DISCOVER无SourceId只给配置元信息，提供SourceId才读取所选索引；DISCOVER不接受EntryId、facets或FULLTEXT。非facets QUERY必须有非空、无重复的sourceId:entryId，不能同时给SourceId。facets QUERY必须给显式非空SourceId，FacetQueryJson为四维state/values对象；EntryId可省略以在这些来源内筛选，也可给所选来源内的限定条目。空facets、越出SourceId的EntryId或未知/重复来源均拒绝；不能隐式查询全库。PINNED索引身份和revision逐来源绑定，不使用单个全局ExpectedIndexIdentity。

以下以已配置的PROJECT_METHODS来源和METHOD_001条目示意；调用者替换为自己当前配置中的ID，绑定当前project.json的字节身份：

```powershell
pwsh -NoProfile -File <FW>/scripts/check-knowledge-entry.ps1 -ProjectRoot <PROJECT> -ExpectedProjectConfigIdentity <length|SHA256> -EntryId PROJECT_METHODS:METHOD_001 -AsJson
$facets = '{"domain":{"state":"KNOWN","values":["aiw:software"]},"workType":{"state":"KNOWN","values":["aiw:verification"]},"deliverableType":{"state":"NOT_APPLICABLE","values":[]},"stage":{"state":"NOT_APPLICABLE","values":[]}}'
pwsh -NoProfile -File <FW>/scripts/check-knowledge-entry.ps1 -ProjectRoot <PROJECT> -ExpectedProjectConfigIdentity <length|SHA256> -SourceId PROJECT_METHODS -FacetQueryJson $facets -AsJson
pwsh -NoProfile -File <FW>/scripts/check-knowledge-entry.ps1 -ProjectRoot <PROJECT> -ExpectedProjectConfigIdentity <length|SHA256> -EntryId PROJECT_METHODS:METHOD_001 -ContentMode FULLTEXT -AsJson
```

一次QUERY对每个显式来源只打开一个固定索引快照；条目、分类及依赖沿该快照读取，FOLLOW不会在同次查询切换到新的Git ref、HTTP索引或条目。默认LOCATOR_ONLY返回定位与精确身份，只有显式FULLTEXT返回完整参考正文。

结果保留referenceOnly=true、authority=false与projectConfigIdentity。sources逐项给sourceId、libraryId、实际索引identity及状态/原因；未读索引的默认来源发现只返回配置元信息。QUERY条目在CURRENT时提供精确正文/依赖身份与locator；ContentMode=FULLTEXT才给完整fullText。STALE或UNAVAILABLE不返回正文，不替换请求的来源；未知/重复请求结构、未知source或失效项目配置整体拒绝。合法批量请求中个别来源/条目失效保留其他逐项结果，退出码0表示请求已处理，不能等同全部CURRENT；整体请求拒绝退出3，runtime不支持退出4。

IMPACT入口参数为ProjectRoot、ExpectedProjectConfigIdentity、ChangedAuthorityPath[]、可选SourceId[]、ForbiddenPaths[]、AsJson；默认只读取PROJECT来源，返回来源状态和逐项DIRECT_AFFECTED/NONE_DIRECT/UNKNOWN，不写索引。实际读取的来源经ContentSources消费LOCAL_DIRECTORY、GIT_REVISION或HTTPS_RESOURCE；因此指定来源的发现、QUERY及IMPACT可能执行获准的Git或HTTPS读取，并遵守revision、凭据、传输上限、禁读边界及PINNED精确缓存验证。PINNED仅在当前许可/采用仍成立且缓存字节身份匹配时复用；FOLLOW按本次快照固定内容。默认来源元信息发现不读取索引或访问provider。相对禁读路径按当前项目根解析，绝对路径仍须合法本机路径。所有结果referenceOnly=true/authority=false；查询、缓存和分类不自动采用规范或改变动作权限。SOURCE来源、内容维护、影响采用与证据限制取KNOWLEDGE_AND_REFERENCE的唯一正文。
