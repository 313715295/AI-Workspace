# Framework 1.16.0 变更记录

当前开发候选：跨机制使用减负 B1。在已完成的精确选择、纠正生命周期与职责分离基础上，统一 AGENTS 具体决定授权正文，按当前决定准入并在升级时保留管理区外原始字节；允许正常文本格式、临时限域只读、不同职责的双规则载体及无完整安装历史的纠正退出。移除 objective、authority context、标准文档、纠正效果、Knowledge 查询、连续步骤及修复轮数的统一使用上限，保留任务有限计划、真实身份、事务及质量边界。独立审核使用新建可见任务，同项修复复审复用原审核者；首次交审与修复复审沿现有机制直接衔接，资源显式落实，等待和收尾集中处理。当前验证/审核资格以 RELEASE_MANIFEST 为准；本条不代表发行或项目采用。

## 历史候选演进（不作为本批通过证据）

此前候选曾完成调用边界减负、纠正整组生命周期、默认委托来源统一及字节观测改动，并有其当时的 Review/复审与发行准备记录。以下保留历史变化；旧快照的通过结果不覆盖当前新字节，已发行 ZIP 和固定运行包保持不可变。

- 交付时序：可选 `deliveryContext` 由同一校验函数解释。原生回复和任务消息发送前 `PREPARE` 只返回 `READY_TO_SEND`；任务消息 `OBSERVE` 按实际传入结果区分 `DELIVERED`、`NOT_DELIVERED` 与 `UNKNOWN`，不预填未来送达、不自动重试。复审、普通／Maintenance 采用、自更新和 runtime relocation 同步消费阶段义务、上下文身份及返回结果；旧无字段输入继续兼容，当前来源、原授权、固定包、后像和独立性校验保留。
- 有界修复／复审：Owner 可在原包预绑定 writer、独立 reviewer 和有限轮数；工厂只准备 exact 包，真实 checker、DISCOVER、ADMIT 和修复 FINALIZE 分别核验 verdict、当前对象、决策及独立性。未受影响的审核和测试证据按原范围复用，最终接受、Git、发行和项目采用仍各有独立边界。
- 纠正生命周期：根升级入口支持有证据的整组安装、历史登记、暂停、恢复与卸载，撤销安装拥有的文件或唯一上下文区块并保留后来独立修改。显式依赖、重叠冲突、Windows 大小写别名、完整三源重组和失败回滚均受校验；无原始归属证据的旧记录不能凭空补造安装前像。暂停／卸载与 Framework 吸收分开，非生效记录不参与当前规则选择。
- 委托及设计：默认持续委托静态正文只在版本 AGENTS 模板用户决定区，注册及升级按区块消费，保留自定义限制和已经撤回的决定。轻量设计标记只定位现有权威，不复制规范或自动证明实现一致。
- 字节观测：移除人工 32/64/96KiB 数字对选择、准入、写后重组、采用及自更新的阻断。保留完整必要规则、实际 bytes／估算 tokens、选择及来源身份；legacy budget／ceiling 字段仅兼容，不增加软硬模式、自动调额或新确认。旧 runtime 的真实失败沿原授权兼容路径处理，不热改旧包或伪造原成功。

此前同候选的目录取得、分派 selector 消歧、协议示例、方案验证依据及正常状态／归档责任等改动继续保留：

- 目录直接复用现有generated catalog和有效项目规则元数据，健康复用，composer仍选择完整索引；裸assignment/launch改为明确任务概念，旧schema1显式裸词不再保证命中任务规则，现有输入格式与matcher保持。协议样例覆盖schema3 TASK、schema2 boundary、根TARGET既有限制及严格LF/字段来源，不自动填完成证据。
- 同范围执行与OpenSpec式当前行为/增量/关键场景沿原任务；方案同时核对消费者、验证依据、失败及未解假设。局部修复保留未受影响审查/测试证据，真正扩面才扩审，权限与当前对象仍重绑。普通结果按实际影响维护已有入口，健康续作/长期Owner保留；送达依宿主真实信号，拒绝与未知不盲重发。

- 普通输入清理一致性：版本 process 入口与 Maintenance 自更新收尾入口的 `DeleteInputOnExit` 使用非强制精确删除，保持原路径/绑定、最后消费者与异常边界；属性或权限阻止删除时不自动清属性或升级 Force。现有示例补充 caller 到期 receipt 的独立删除调用与后续只读核验。

- 来源写后承接：已授权 `CONTROL_WRITE` 可在验证 exact source postimage 后，以同一 composer 重组 corrections/process-policy 当前来源并继续核验；旧授权与旧结果义务保持，越界来源、独立 drift 和无效 source binding 拒绝；规则包大小仅记录真实观测。临时 resolver input 的 `-DeleteInputOnExit` 与 continuation receipt 最后消费者边界同步写入工具/宿主合同。

- 有界授权续作：可选 `continuationPlan` 让同一临时 actor 在原 package 预授予的写→测→局部修复顺序中继续；每步由 `FINALIZE_OUTPUT` 绑定真实 postimage，下一 `DISCOVER/ADMIT` 重验原包、source action/step、任务/actor、repository/config/Controller、decision/protection 与 current bytes。普通项目与 Maintenance 根适配器复用同一 checker/resolver；receipt 保持 `INSTRUCTION_BOUND`，不保存 checker 无法复验的 finalize hash，也不新增 ledger、签名或调度服务。

- 项目标准渐进接入：`process-policy.json` 可在不复制正文的前提下绑定项目自有文档全文或唯一标记区块，并声明有界依赖；只把命中的当前正文送入模型。来源漂移改为保守加载当前全文，相关来源不可读或区块无效时只阻止依赖它的动作，无关来源不阻断当前工作。

- 初始化与标准来源补强：默认注册只创建必要控制入口和薄项目/Review 指针，`RELATIONSHIPS.md` 改为按需模板；旧项目资料无需搬迁或精炼即可采用。project policy source 新增可选 `locatorKind`，兼容旧项目相对路径，并可只读绑定本机项目外文件或独立仓库 checkout。多个项目可直接引用同一来源，各自保留本地补充；target preflight 不复制或改写外部标准。README/Prompts 增加用户与 AI 的直接引用、可选精炼和可选文档改造指引。

- 运行边界精简：新增 schema3 `DISCOVER` 与 schema2 compact receipt/boundary input。正式 task 保持完整 Owner/actor/authority 绑定；没有任务卡的项目只读讨论使用 `PROJECT_READ_ONLY`，不伪造 task 或授权。后续 ADMIT/FINALIZE 只补实际 evidence，不重复 objective、scope 与 authorization facts。

- 临时角色统一：Owner 可在原任务直接执行，也可把单次 source、test、Review、Git、browser/device 或 external action 授予 temporary actor；task Owner 与 Work route 不因此变化。正常 Review 只需一次完整分派和一次可用终态，Reviewer 不反向申请控制写、不维护三份状态、不删除 package 或等待释放 ACK。

- 根级采用能力：注册、跨 pin 升级、同 pin repair 与明确选择的永久规则迁移复用状态读取、内存投影和可恢复 transaction 模块；结果绑定 `Framework Pin + Project Format + Root Tool Revision`。捕获失败恢复旧 pin、旧受管对象与旧有效三源行为，入口保持幂等且不合并成新的 God Script。

- 用户分发：root builder 只打包一个目标版本、必要接入工具/依赖、canonical Router 与中文入口；构建前重算 release payload 并绑定完整套件和 Source Review 证据，不包含 Git、runtime、项目状态或历史版本集合。

- 规则选择修正：复用现有 IntentEnvelope 和唯一 composer，为混合用途 selector 增加可选 deterministicTriggers；正式 Review、直接角色交接和终态义务不再被关键词二次否决。原生内容条件采用可选 TOKEN 字面词边界，避免 preview/review 子串误选。三源权威独立，旧 selector 保持原解释；不自动迁移项目记录，不把 UNKNOWN 变成执行许可。

- Owner 接受准入修复：授权检查器与流程解析器统一支持已有 `OWNER_ACCEPT` 动作，并校验接受者为当前任务 Owner；接受证据规则由动作直接触发，不依赖阶段标签。`OWNER_ACCEPTANCE` 不得通过 `NONE` 或写入动作绕过接受门。复用现有 package 与回执，不新增脚本、状态或权限。

- 本地候选试点恢复闭环：普通项目仍只接受 sealed stable pin；已经由 root `-LocalCandidatePilot` 完成准入的项目，可依据既有 upgrade recovery state 与未漂移 candidate snapshot 继续恢复。准入证据不在每次恢复重跑，升级时 task postimage 也不成为长期硬门。

baseline：immutable Framework `1.15.1`。release class：`MINOR`。

Review-1 rework：local candidate pilot 现在会在 project preflight 前校验 manifest 声明、完整套件与独立 Source Review evidence，并由 schema3 pilot authorization 绑定 exact candidate canonical 和 manifest identity；旧 runtime 的 `selectedRulePackBytes` 失败保留原兼容修复路径及 exact 授权；新 runtime 不再因该数字自锁，原调额修复返回 NO_CHANGE，不增加事务或第二 authority。

Pocket 试点 finding rework：payload resolver 现在同时接受 official root upgrader 生成的 schema2 初次采用 state 与 schema3 `LOCAL_CANDIDATE_MANAGED` refresh state；schema3 严格验证 projection 字段、原对象覆盖、task-last 及全部非 task managed object 的当前身份，同时继续由 current DISCOVER task identity 绑定可变任务卡，不把升级时 task postimage 变成长期硬门。

日常 runtime cleanup finding rework：`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 的 project-runtime 输入不再重复要求 boundary JSON 携带 `projectRoot`；resolver 只在 exact DISCOVER receipt identity 与严格结构通过后，从 receipt 派生 project/task/actor 绑定，再删除该次精确输入。receipt 漂移、不同项目 runtime 或 task/actor 不匹配时继续 fail closed 并保留输入供诊断。

## Added

- 保留 `selectedRulePackBytes` 等 legacy 元数据及原默认数字以兼容已有载体；它们不再作为规则包字节上限；
- target-before-pin upgrade projection，支持 legacy 1.11/1.12 two-field task card 的原子 route migration；
- authority context 的 `taskActor`，使 task route 与临时 `REVIEW_EXECUTE` grantee 分离；
- project-local `.ai-workspace/runtime/<task>/<actor>/` ephemeral artifact 路线与幂等 `.gitignore` projection；
- compact ADMIT/FINALIZE JSON result；
- root canonical Router Skill 与 version contract/history 分离。
- root Framework Maintenance overlay 与确定性共享投影 helper；version payload 不再携带重复的完整 Maintenance starter。

## Changed

- 所选规则包大小仅观测，完整规则及真实来源／授权义务决定边界结果，不以预算分档放行或阻断；
- source/context 不变时复用 compact receipt；uncertainty 或 source binding drift 时重新 DISCOVER；
- direct adoption 由 profile 投影，不重复 target-version literal branch；
- root Maintenance adapter对其schema3 upgrade authorization保持closed；version checker只复用通用repository-bound package语义，不再解析Maintenance专属layout或调用root target resolver；
- human/AI-facing guidance 使用中文，machine field、ID、parameter 与 diagnostic token 保持 English。

## Preserved

- Framework `1.14.1`、`1.15.0`、`1.15.1` 的 immutable 历史 identity 与恢复材料仅保留在任务隔离区和 Git 历史中，不随当前交付树发布；
- 一个 composer、canonical Markdown blocks、actor-bound authorization、task-last recovery、project-owned corrections/policy、independent Review、独立 `OWNER_ACCEPT`、Git/external gate 与 protected-path boundary；
- Windows PowerShell 7 是本 release 唯一 official/evidenced backend。

## Not added

不增加第二 schema/resolver、service、registry、ledger、cache、poller、automatic consumer discovery/adoption、automatic host Skill installation、新 backend 或更宽 platform claim。

## 本地试点规则演进修正

- 分离历史安装投影与当前项目规则，允许已准入试点在合法任务内迁移 PROJECT-CUSTOM、更新 process-policy/corrections。
- 保留候选快照、框架管理区、当前全文授权与收据失效检查；后续候选刷新保留项目规则，不回写历史版本。
- 补充 schema2/3 兼容、schema4 规则演进/拒绝场景及再次刷新回归；Router 自测断言改为已采用的协议声明，不依赖发行号文案。
- 独立审查回修：把安装完成证明保存在既有恢复记录，任务归档不阻断新任务；未完成/完成标记写入中断仍走原授权恢复；同步桥前置完整来源与义务检查，大小只观测。

## snapshot.7 入口与模板增量

项目 AGENTS 的持续委托纳入 FRAMEWORK 管理模板，注册生成、升级替换并保留区外扩展；旧默认 USER-DECISION 声明随采用迁入。Router 接入包含安装、宿主发现和兼容性收尾，统一按需导航与健康复用；包内入口收敛为使用/接入说明。采用绑定、未完成事务、历史及临时材料按用途保留，不按目录名称清理。
