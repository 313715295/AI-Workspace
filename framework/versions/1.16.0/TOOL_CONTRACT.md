# Tool Contract v1

Framework operation 是 language-independent contract。backend 是 adopting project 一次选择的 immutable implementation，不是 task role、action、resource route 或 authorization capability。

## PROCESS_REQUIREMENTS_RESOLVE

一个 source composer 提供三个 logical mode：

- `DISCOVER` 严格绑定 project、当前 task 或显式 `PROJECT_READ_ONLY` request context、host-authenticated actor、effective role/phase、profile、project-declared capabilities、objective/action/result kind 与 normalized exact scope。task context 继续绑定 whole task、Owner 与 Work route actor；只读 context 必须绑定 session/request 且只能使用 `NONE + PLAN/USER_RESPONSE`，不能伪造任务或绕过已知冲突。`pathHints` 必须位于 scope 内，`capabilityHints` 必须已观察，mutation/external hints 必须匹配 requested action。CLEAR contradiction 失败；UNKNOWN 保留 conservative-load ceiling，不能 admit governed action。resolver 对完整 generated metadata catalog 选择，校验 selected locator 与 owning Markdown module，一次返回每个 exact complete block，并另给 compact receipt。still-effective corrections 与 permanent project rules 保持独立 source。
- package grantee 可执行当前 action 或 `continuationPlan` 中预授予的写/测与最后一步组织 `REVIEW_ROUTE`，不改变 Owner/Work route/task identity。该路由只在写入及紧接的 `TEST_RUN` 后续接，计划绑定顺序与整组 exact scope；独立 `REVIEW_EXECUTE`、`OWNER_ACCEPT`、Git、browser/device 与 external 不进入计划。
- `ADMIT_ACTION` 只消费 exact compact DISCOVER receipt，复检 task/Framework/catalog/project/correction/policy/custom identities，按 current exact object bytes 重跑 authorization observation，并校验 selected preparation；它不授予 action。
- `FINALIZE_OUTPUT` 重验 sources 与 observable result/delivery；每个 exact path 必须有唯一且匹配 current object 的 `OBJECT_POSTIMAGE`。有未完成计划时才返回 `INSTRUCTION_BOUND`、`authorityGranted=false` 的 `AUTHORIZED_ACTION_CONTINUATION`，绑定原 package、source Discover identity/action/step、task/actor/repository/config/Controller/decision/protection、下一步骤与整组 postimage；不保存无法由 checker 复验的 finalize hash。

后续 `DISCOVER` 可选成对携带 `continuationReceiptPath + expectedContinuationReceiptIdentity`。resolver/checker 复证 receipt bytes、原 package、source action/step、next step 与 current objects；未知字段、错链、第三方/越界、错包、虚假或 stale postimage 均 fail closed。普通项目与 Maintenance root authorization/process adapter 共用实现，root 只补 topology/repository 验证和透传。

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

compact/continuation 留到最后消费者完成。上一步 compact 与 continuation 可能在下一 DISCOVER、ADMIT、FINALIZE 全部复验；先保存新的 successor continuation 再释放前序。失效/中止后在自然收尾释放已无消费者的 artifact；不用持久收据注册表。

PROCESS_REQUIREMENTS_RESOLVE 可显式指定 `-CompactReceiptPath <absolute-path>`：仅 DISCOVER，保存既有 compactReceipt。成功响应的 `selectedRuleBlocks[*].fullText` 是本次须读取的完整选中正文；`compactReceipt` 只承接后续 ADMIT/FINALIZE，不含正文，也不能用其中的 selectedObligations 冒充已完成证据。指定路径时输出另有 `savedCompactReceipt={path,identity}`，供后续边界引用所存收据；未指定时原响应形状不变，不另存全文。目录须已存在且精确为当前项目 `.ai-workspace/runtime/<task-or-request>/<actor-storage>/`，文件名安全、全部祖先非 reparse；CreateNew 拒绝任何已有对象，包括输入、旧收据及权威。保存失败整个调用失败，不报告保存成功；中途失败留下的部分文件不得消费。普通 evaluation 无后续边界时不要求保存。Maintenance 前门透传该参数，仍保留其 schema/repository 限制。

actor-storage 仅用于保存和清理的目录定位，不改变认证 actor：匹配小写 `[a-z0-9][a-z0-9._-]*` 、不以点结尾、不是 Windows 保留设备名（含扩展名），且不以保留前缀 `actor-sha256-` 开始的身份沿用原段；其他身份使用 `actor-sha256-` 加真实身份精确 UTF-8 字节的完整 SHA-256 小写十六进制。大小写、斜杠和反斜杠不归一化、不替换字符，不创建身份注册表。输入创建、compact 保存、根采用/恢复收口和 Maintenance 专用清理共用实际绑定 runtime 的映射，authority/package 中始终保留原身份。原过程边界以原 receipt 的 runtime 为准，不因采用后当前 pin 来源变化而移动旧材料；原恢复 FINALIZE 也调用该 runtime 的 resolver。旧固定包仍使用其旧目录合同，不热改包、不将旧收据迁成新布局。

schema3 DISCOVER 产生 schema2 compact receipt：authority/context 只保留在一个 `binding`，intent 只保留在一个 `intentEnvelope`，来源、义务、预算、证据与计数各自只有一个结构。schema2 ADMIT/FINALIZE input 只提交 receipt locator/identity 与新增 preparation/result/delivery evidence，不再复制 objective、action、scope 或 authorization identity。schema1/2 DISCOVER 与 schema1 boundary 只作为兼容输入保留。

project policy rule 的正文可以继续内联为 `effectiveRule`，也可以二选一声明 `source={rootSourceId,documents}`。每个 source document 绑定可选 `locatorKind`、locator、whole-file identity、`FULL_FILE` 或唯一 marked section、直接 dependency IDs 与 decision locator；省略 kind 保持旧 `PROJECT_RELATIVE` 语义，`ABSOLUTE_FILE` 只接受显式、本机、非 reparse 的绝对文件路径。dependency graph 必须闭合、无重复、无孤儿、无环。composer 在正文读取或 identity 计算前消费当前明确的 `forbiddenPaths`，对 project-relative locator 及指向同一项目文件的 absolute alias 使用同一拒绝语义；`routineExcludedPaths` 与只约束写入的 `protectedPaths` 不自动成为标准来源禁读边界，项目外已显式指定的共享来源继续可读。composer 在 selector 前验证全部显式 source bindings，模型只接收命中的当前正文；不扫描目录、不跟随普通超链接、不抓取网络，也不获得来源写权限。路径/kind/identity/section/dependency 漂移会使旧 receipt 失效；正文 identity 漂移时旧 selector/section 不再用于排除，当前全文保守加载并公开 `PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD`。同一选中响应内，物理来源、当前身份和完整正文相同的块只返回一次；后续规则引用同响应中的首个完整块，原规则ID、preparation/result义务、来源及依赖身份全部保留。不同来源的相似文本不能合并；普通加载与UNKNOWN/漂移分别观测真实大小；不以数字截断正文或阻断准入。

来源位置和组织方式由使用者决定。多个项目引用同一个 `ABSOLUTE_FILE` 即共享同一来源，各项目仍可通过自己的 rule/dependency 补充本地要求。target-before-pin 预检只把 `PROJECT_RELATIVE` 来源快照复制到隔离投影；`ABSOLUTE_FILE` 始终从原只读路径复核，不搬迁、不写入临时项目，也不把它纳入采用写集。

`requirements/fragments/*.json` 拥有 native requirement ID、deterministic selectors、exact Markdown locator 与 preparation/result gates。marked Markdown block 是唯一 native rule body。`PROCESS_REQUIREMENTS.json` 是 deterministic sealed metadata projection，不独立编辑；首次构造可读取其 id/title/description/selectors 元数据，正文仍只消费 DISCOVER 返回的 selected complete rules。元数据不成为第二权威或预先筛选器，composer 始终校验完整规则集合。

### 输出时序与有界修复复审

输出边界可选 `deliveryContext={channel,stage,expectedRecipient,observedRecipient,outcome,evidence}`。channel 为 NATIVE_RESPONSE/TASK_MESSAGE；发送前 stage=PREPARE、outcome=NOT_SENT，observedRecipient/evidence=NOT_APPLICABLE，返回 READY_TO_SEND 而非 DELIVERED。这一步校验真实已完成的结果和发送准备，不索取未来送达证据。TASK_MESSAGE 的 OBSERVE 只消费同次宿主调用实际 SUCCESS/FAILURE/UNKNOWN；成功须接收人吻合且有宿主证据，失败/未知分别返回 NOT_DELIVERED/UNKNOWN，均不自动重试。native response 没有发送后回调证明，不伪造 OBSERVE。旧无该字段的 boundary 保留旧输入兼容和证据上限，不能借兼容格式伪造成功。

WORKFLOW_ROUTE_RESOLVE 的 DELIVERY 使用相同 deliveryContext 校验器，调用宿主发送并得到结果后可在同一确定性编排消费，不再唤起模型只做记账。FINALIZE 的 PASS 只表示相应阶段结构完整，delivery.delivered 单独说明是否送达；准备通过不是用户成果已送达。普通后续成果仍由 Owner 判断。

有界修复复审使用原包的 repairReviewPlan 和新包 repairReviewBinding。后者精确引用 parentPackagePath/parentPackageIdentity、phase=REPAIR/REREVIEW、cycle、verdictPath/verdictIdentity，以及复审时的 repairFinalizeInputPath/repairFinalizeInputIdentity、repairFinalizeResultPath/repairFinalizeResultIdentity（修复阶段这些字段为 NOT_APPLICABLE）。原计划 Reviewer 为 DEFERRED_VISIBLE_REVIEWER 时，binding 另含 reviewerAssignment，绑定 `HOST_CREATE_THREAD_RESULT` 的已知threadId，或 `HOST_INITIAL_DELEGATION` 首审前的待绑定接收者及修复／复审时已自绑定的同一接收者，以及hostId、创建者、taskId和原包身份；已知 Reviewer 不携该字段。verdict 保存 taskId、owner、reviewer、writer、cycle、CHANGES_REQUESTED、exactPaths/objectIdentities、findingPaths、scopeChanged/decisionChanged；后两者只能为 false 才可沿计划续作。WORKFLOW_ROUTE_RESOLVE 的 REPAIR_REVIEW 接收 repositoryRoot/binding，读取当前候选生成标准新包数据；派生子包不继承原包的 receiverBinding，仍用 repairReviewBinding 锚定原包；checker 验计划、关系独立性、原 verdict/修复后像、当前任务和当前候选，原 DISCOVER/ADMIT 继续不可省略。证据仍为 INSTRUCTION_BOUND，不声称签名、语义证明、单次消费或物理撤权。

同一 REPAIR_REVIEW 入口承接首次交审：binding.phase=INITIAL_REVIEW、cycle=0，verdictPath/verdictIdentity=NOT_APPLICABLE；原 repairFinalize 四字段绑定生产动作的实际 FINALIZE 输入/结果，生产包必须是 parentPackage 自身。当前候选必须等于该 FINALIZE 的完整后像，Reviewer仍按计划绑定且独立。REPAIR/REREVIEW从真实finding开始，cycle不得超出任务自定maxCycles；首次交审不伪造finding或修复历史。交审材料与必要卡更新的先后依赖只取 REVIEW_AND_EVIDENCE，不在包工厂重复定义。适用任务默认由原 Owner 在生产包配置计划；Reviewer 可稍后创建。若当时真实ID未知，writer 用 `HOST_INITIAL_DELEGATION`、`threadId=UNBOUND_RECEIVER` 准备当前候选的待绑定 Reviewer 模板及完整材料，在创建提示一次交付；Reviewer 从宿主身份自绑定，保留原 Owner/issuer 和生产后像。真实finding后的修复和复审沿同一 assignment 填入已绑定的 Reviewer ID，不重发待绑定包。旧 `HOST_CREATE_THREAD_RESULT` 精确已绑定路径仍有效，临时 writer 不取得 Owner/issuer 身份。

`AUTHORIZATION_RECEIVER_BIND` 使用 CONTROL 根、待绑定材料绝对路径、初始委派给出的原件 `length|SHA256` 和 delegationId；仅从宿主进程 `CODEX_THREAD_ID` 取实际主体，在 `.ai-workspace/runtime/<task>/<actor>/` 写精确包。原件为 `schemaVersion/delegationId/receiverRole/authorizationTemplate` 四字段；角色仅限 IMPLEMENTER 的写测、INVESTIGATOR 的 TEST_RUN 或独立 REVIEWER 的纯 REVIEW_EXECUTE。IMPLEMENTER 模板预先配置 repairReviewPlan 时，writer 必须明确为 UNBOUND_RECEIVER；binder 只把它和 grantee 同步派生为同一宿主真实 ID，其他角色不得借此携计划。checker 的 `receiverBinding` 逐字段核验原件身份与派生差异，拒绝原始 `UNBOUND_RECEIVER` 包、其他宿主主体、原件漂移、额外权限或不合格 Reviewer。接收者必须先核对实际收到的初始委派；此对应关系保持 INSTRUCTION_BOUND，上述工具结果不证明消息来源或实际模型执行。派生后仍需原 checker、DISCOVER/ADMIT 和实际结果 FINALIZE。

PROJECT_READ_ONLY可使用当前真实的管理、执行或观察审核角色；临时观察者可按EXECUTOR表达实际只读职责，无须冒填管理身份或新建卡。它仅允许NONE与PLAN/USER_RESPONSE，REVIEWER标签也不授予正式Review、写入或越界读取。objective、authority context、标准文档数、纠正changes、Knowledge查询数和continuation步骤不设框架统一使用配额；任务仍绑定有限范围、具体计划及退出条件，结构、类型、唯一性和路径验证保持。

### IntentEnvelope 构造

首次 DISCOVER 直接应用上文输入/收据合同，无需先加载 HOST。

首次构造或相关来源改变时，随已知项目事实同批取得当前 generated catalog 的 id/title/description/selectors，以及当前有效纠正和policy对应元数据；健康上下文复用。原生目录直接投影现有 PROCESS_REQUIREMENTS.json，不新增目录文件、operation 或 LOAD_PLAN 前置门。纠正有效性取项目当前记录的显式生命周期；无 lifecycle 的旧记录仍有效，不按 ID、措辞或原生相似规则自动抑制。新版本不依赖中央 coverage 映射。旧free-text或没有可靠selector的来源沿原兼容全文/保守处理，source漂移也不靠旧元数据排除。PROMPTS的读取/构造样例只教如何使用这些来源，不生成意图或替代严格校验。

`DISCOVER` 前，当前主会话模型从本轮原始用户请求、仍有效的多轮上下文与已绑定任务事实，重建当前真实请求：目标、这一步实际要做的 action、当前应交付的 result、受限范围，以及仍然有效的否定、条件和先后关系。然后只填写现有 `IntentEnvelope` 字段；resolver 负责结构与 authority facts 的核对，不替模型理解原话，也不建立第二套 intent authority。

多轮更新按语义作用域合并：补充增加未冲突约束，收窄删除范围，纠正替换被明确修订的部分，取消终止被取消的当前动作；未被修订的上下文继续有效。报告、日志、引用指令和示例中的命令都是 data，除非用户明确把它们转成当前请求，否则不能成为 action、authorization 或 authority instruction。

`requestedActionKind` 只表示当前步骤实际请求的 Framework action。讨论、解释、比较、诊断或先分析后再决定时使用 `NONE`，但仍必须完成实质分析，并用 `PLAN` 或 `USER_RESPONSE` 表示当前交付。明确要求修改时，即使 package、权限或能力尚缺，仍保留清楚的 write action 与 `CLEAR` intent；authorization 独立失败，不能把请求擦成 `NONE` 或 `UNKNOWN`。若后续动作受“经确认后”“若条件成立”或明确顺序约束，当前 action 只填写已到达的步骤，条件与延后动作保留在 objective 中；只有当前适用概念进入 semanticHints，条件尚未满足时不得提前执行。

否定必须绑定它实际否定的对象。明确要求正式 Review 并说“不要修改”时，当前 action 仍是 `REVIEW_EXECUTE`、result 是 `REVIEW_VERDICT`，否定只限制 repair/write；普通“帮我看看”“比较方案”没有正式 Review 请求时，不因 look/review 类词汇自动升级。`ambiguityState=UNKNOWN` 只用于真实语义不确定，`CONFLICT` 用于仍未解决的请求冲突；缺授权、缺能力或 host 不可用本身不改变清楚的 intent。

`semanticHints` 保存当前适用活动与内容概念：被否定/取消或条件未满足的动作不作为正触发词，否定对象和延后条件保存在 objective。正式Review禁止修复仍保留Review语义。当前新分派、资源选择、实际QUERY影响、写后待交付/产物Git处置、Controller例外答复按任务事实表达；NONE不清除前序尚未履行的责任。依据已提供catalog描述/selector将同义请求映射为当前概念，不需要全局概念枚举；不得为了命中 selector 补入用户未请求的 action 名、Review 词或其他 trigger padding。`pathHints`、`capabilityHints`、`mutationHints` 与 `externalHints` 仍受当前 scope、已观察能力和实际 action 约束。任何 hint 都不授予写入、测试、Review、Git 或 external 权限。

本合同继续使用当前 schema、单一 composer 与 resolver。说明性示例只证明字段可表达这些关系；在受控原始多轮回放实际观察主会话模型的输出前，不得声称自然意图识别准确率或语义 PASS，也不新增 intent-generation operation、provider/model 配置或服务。

### 调用字段来源与路径

process schema3 TASK DISCOVER 使用绝对 projectRoot/frameworkRoot/taskPath；其readOnlyContext为NOT_APPLICABLE，不伪造无任务上下文。Maintenance TARGET动作继续使用schema2 DISCOVER/schema1 compact，不能把CONTROL示例的schema3复制过去；根前门不改写不支持的receipt。独立authorization checker的TaskPath则是相对已绑定CONTROL/项目根的规范路径；调用时同时对齐PowerShell工作目录与进程当前目录，避免.NET相对文件API指向旧cwd。ObservedIdentity为path=length|SHA256（新对象为path=NEW），不是裸hash数组。

有包时userDecision精确绑定仍有效的package.userConfirmation；无包只读为NOT_REQUIRED，不能由样例制造授权。boundary schema2只引用原compact并提交实际完成的preparation/result/delivery证据；publicDecisionIdentity为NOT_REQUIRED或length|SHA256，不是任意decision哈希；protectionState仅BOUND/NOT_APPLICABLE，须符合实际保护事实。不得把selected obligations自动当完成证据。输入使用严格UTF-8无BOM，接受CRLF和缺末尾LF等价格式；未知字段、重复键、错误类型、损坏文本与漂移仍拒绝。原始字节用于identity和事务前后像，不重写文件伪造原像。

### 选择条件：结构边界、确定性触发与内容判断

selectors 原有八字段保持兼容：profile、role、phase、action、result、path、capability 先全部匹配，semanticTerms 才判断内容；空 terms 表示本条在结构边界内已确定适用。没有元数据依据，不得仅因动作非 NONE 就加载整组规则。

可选 `deterministicTriggers={actionKinds:[],resultKinds:[]}` 表示同一规则的另一条充分触发路径。只有上述结构条件全部通过，且当前已绑定 action 或 result 在所列集合内，才不再让关键词否决本条义务。两组至少一组非空；禁止 NONE、通配符、未知值、重复值及越出本条 action/result 边界的值。它不绕过授权、角色、范围或 UNKNOWN 拒绝，不创建第二份动作映射表。正式 Review 的视角选择由 REVIEW_EXECUTE 触发；普通讨论仍按本条内容条件，不能因此加载所有视角或全部 Review 流程。

可选 `semanticMatch=TOKEN` 对英文/数字/下划线词边界作大小写不敏感的字面匹配，阻止 preview 命中 review；不执行 regex、项目代码或否定句推理。省略它保留旧 SUBSTRING 解释。已有 selectors 的结构轴、TOKEN/SUBSTRING 与 deterministicTriggers 继续解释；内容输入统一取当前 semanticHints，不增模式字段。三源使用同一匹配器但保留各自权威与身份；纠正记录新增字段会进入既有 canonical identity，不能复用旧吸收映射。

1.16 的内容条件只匹配当前归一化 semanticHints；objective 保留目标、背景、否定及条件用于解释，不参加内容关键词匹配，externalHints 也不混入。schema1没有IntentEnvelope，其旧objective是显式选择文本，适配为semanticHints后进入同一匹配器；这保留旧输入格式而非新增模式。title/description 是供模型理解的索引说明，不是后端自然语言分类器。模型按原始要求理解并映射，不能拼接动作名来骗过匹配；有真实不确定性按既有 UNKNOWN 保守加载，UNKNOWN 不允许执行受治理动作。含“不要修改”等否定措辞的真实 Review 仍需 Review 义务；不能一律排除包含否定词的规则。结构 PASS 不证明模型的理解或任意自然语言的选取完整性。

同一 Framework 版本仅一套选择语义。验证已有项目声明与旧输入消费者；真实不兼容沿既有采用路径转换并做 target selection 预检，不另建解析器或默认新旧开关。没有新增采用能力声明时不扩大跨pin支持。

`LOAD_PLAN_RESOLVE` 保持 compatibility/support operation，可定位 non-rule supporting artifacts、Framework-wide maintenance/explanation context 与 bounded affected-module fallback；它不是 pre-DISCOVER catalog filter，不能静默排除 requirement。STABLE 调用保持原参数兼容。对已完成本地试点的 CANDIDATE，caller 必须同时提供 `ProjectRoot`、`ExpectedProjectConfigIdentity` 与 `ExpectedCandidatePilotStateIdentity`；loader 通过 composer 导出的薄绑定入口复用现有 local-pilot 严格读取，验证项目 pin、候选 flags、完成状态、受管投影、payload canonical 与 manifest identity，并返回 `lifecycle=CANDIDATE`、`LOCAL_CANDIDATE_PILOT` evidence ceiling 及实际 state identity。缺少、部分提供或漂移的绑定全部拒绝。该 support 读取不运行完整 DISCOVER、不读取整个 project policy selected pack，也不授予 action。

legacy schema1 process input 只用于 discovery/evaluation compatibility。它没有 bound authorization package 或 complete AuthorityContext，因此 categorical governed action 不能通过 ADMIT/FINALIZE，并返回 `LEGACY_AUTHORITY_CONTEXT_UNBOUND`。governed action boundary 必须使用 schema2。

机械 PASS 只证明 current identities 与 supplied structural receipts，不证明 semantic correctness、model attention、host invocation 或独立 authorization/Review/Git/external gate。

普通 TASK/PROJECT_READ_ONLY 的来源、授权与动作准入以当前项目根、配置、任务、精确对象和保护边界为准，`repositoryGitTop=NOT_APPLICABLE`；不调用 Git 程序。仅 GIT_STAGE/GIT_COMMIT/PUSH 或明确的多仓库拓扑核对 Git top；缺失或不符时停止相应 Git 动作。子目录项目、嵌套仓库和 worktree 的 Git 身份按实际动作目标分别验证，不能把项目根等同于任意父仓库。

## Target-before-pin adoption preflight

root project upgrade 从 `ADOPTION_PROFILE.json` 取得 Project Format/capability 兼容声明与 target behavior，不按旧发行号列表放行。1.16作为新基线不声明跨pin direct source；新项目安装和同pin幂等修复仍可用。未来版本只有显式声明兼容结构时，才可创建隔离target projection，写入 target project、Bootstrap、corrections、process policy、project-selected budget 与 migrated current task route，再调用 target `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。完整三源、身份及授权校验PASS后才可准备actual transaction，旧预算数字不阻断。

旧 current-process input 若提供，只作为 exact-bound user decision 来源，不执行 current-pin resolver；因此旧 budget 或 1.11/1.12 two-field task schema 不会形成 target-before-pin deadlock。

该 preflight 是 compatibility observation，不是 alternate resolver、authority 或 consumer fast path。schema3 actor-bound upgrade package、exact pre/postimages、protected paths、project decision、task-last write、forward recovery 与后续 Review/acceptance/Git/external gate 保持独立。

## Project selection

project authority field 是 `.ai-workspace/project.json.frameworkToolBackend`。`1.16.0` 只接受 `powershell7`；registration/upgrade deterministic 写入该值。所有 task/operation 继承它。authorization package 不重复该字段；既有 `projectConfigIdentity` 会在 selection 或其他 config byte 改变时使 package 失效。

host 先读 project pin，再读 pinned `TOOLCHAIN.json`。backend ID、`OFFICIAL` status、platform、runtime edition/version 与 exact entrypoint 都必须匹配。unknown field/backend、missing entrypoint、path escape、unavailable runtime 或 contract drift 在 operation 前 fail closed。Framework 不 install/download runtime。

## Router compatibility

唯一 canonical `ai-workspace-router` Skill 位于 repository root `skills/ai-workspace-router/SKILL.md`，只负责 navigation。`TOOLCHAIN.json.routerCompatibility.canonicalSkillPath` 绑定该路径，`versionContractPath` 指向 version 内的 `REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE` history file。

当前受支持版本通过 sealed `TOOLCHAIN.json` 声明 exact operations、process-catalog schema/version 与 native rule-body source。Router 不按发行号内置兼容白名单；安装、宿主发现及 declaration 缺失或不兼容的处理统一见随包 PROJECT_ADOPTION 的宿主接入收尾。

install/update host-global Skill 是独立 explicit host-write action。registration/upgrade 不执行安装，也不创建 installation registry/ledger。

## Invocation

operation name 与 entrypoint path 只来自 `TOOLCHAIN.json`。path 是 version-root-relative、NFC-normalized、forward-slash locator，不得 absolute、drive、empty component、`.` 或 `..`。host 直接调用 selected entrypoint，不提供 user-facing launcher 或 generated wrapper。

official backend 使用 `pwsh -NoProfile -NonInteractive -File <entrypoint> ...`。每个 `1.16.0` entrypoint 独立拒绝 non-Core runtime 或 PowerShell major < 7。

## Results 与 evidence

exit code `0` 表示 operation 返回 documented accepted result；nonzero 使 requested boundary 失败，caller 保留 explicit reason，不从 prose 猜测成功。支持时优先用 structured `-AsJson`。human-readable output 只是同一 result 的 projection，不是 authority object。

file identity 为 exact bytes 上的 `byteLength|UPPER_SHA256`。JSON/Markdown 使用 strict UTF-8 no BOM，接受语义等价的 CRLF 和缺末尾 LF；解析时的等价处理不改变原始字节 identity。security-relevant JSON 在 escape decoding 后递归拒绝 duplicate members。repository-relative evidence 使用 forward slashes。

`1.16.0` 只列 Windows。未来 platform 只有在实际 conformance run PASS 后才受支持；missing CI/host evidence 是 capability ceiling，不得推断 compatibility。

## Backend lifecycle

backend selection 只在 released Framework 已提供 target backend 的 project adoption/switch boundary 改变。项目必须没有 active writer/reviewer lease，通过 project config drift 使 outstanding package 失效，transactionally 投影 config，并完成 fresh recovery/conformance。`1.16.0` 只有一个 backend，因此不提供 switch command。

本 contract 不增加 backend registry、service、ledger、plugin market、runtime code generation、task-level choice 或 global Framework default。
