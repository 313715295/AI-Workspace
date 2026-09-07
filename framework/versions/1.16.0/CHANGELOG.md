# Framework 1.16.0 变更记录

- 来源写后承接：已授权 `CONTROL_WRITE` 可在验证 exact source postimage 后，以同一 composer 重组 corrections/process-policy 当前来源并继续核验；旧授权与旧结果义务保持，越界来源、独立 drift、无效 source binding 和新 pack 超预算拒绝。临时 resolver input 的 `-DeleteInputOnExit` 与 continuation receipt 最后消费者边界同步写入工具/宿主合同。

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

Review-1 rework：local candidate pilot 现在会在 project preflight 前校验 manifest 声明、完整套件与独立 Source Review evidence，并由 schema3 pilot authorization 绑定 exact candidate canonical 和 manifest identity；current-pin 项目若只因 `selectedRulePackBytes` 自锁，则由现有 root upgrader 提供隔离投影、exact package 约束的单字段修复，不增加新脚本或第二 authority。

Pocket 试点 finding rework：payload resolver 现在同时接受 official root upgrader 生成的 schema2 初次采用 state 与 schema3 `LOCAL_CANDIDATE_MANAGED` refresh state；schema3 严格验证 projection 字段、原对象覆盖、task-last 及全部非 task managed object 的当前身份，同时继续由 current DISCOVER task identity 绑定可变任务卡，不把升级时 task postimage 变成长期硬门。

日常 runtime cleanup finding rework：`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 的 project-runtime 输入不再重复要求 boundary JSON 携带 `projectRoot`；resolver 只在 exact DISCOVER receipt identity 与严格结构通过后，从 receipt 派生 project/task/actor 绑定，再删除该次精确输入。receipt 漂移、不同项目 runtime 或 task/actor 不匹配时继续 fail closed 并保留输入供诊断。

## Added

- project-selected `selectedRulePackBytes`，starter default `32768`，absolute cap `98304`；
- target-before-pin upgrade projection，支持 legacy 1.11/1.12 two-field task card 的原子 route migration；
- authority context 的 `taskActor`，使 task route 与临时 `REVIEW_EXECUTE` grantee 分离；
- project-local `.ai-workspace/runtime/<task>/<actor>/` ephemeral artifact 路线与幂等 `.gitignore` projection；
- compact ADMIT/FINALIZE JSON result；
- root canonical Router Skill 与 version contract/history 分离。
- root Framework Maintenance overlay 与确定性共享投影 helper；version payload 不再携带重复的完整 Maintenance starter。

## Changed

- runtime budget 只读取 project process policy，不再使用 ordinary/absolute/legacy tier exception；
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
- 独立审查回修：把安装完成证明保存在既有恢复记录，任务归档不阻断新任务；未完成/完成标记写入中断仍走原授权恢复；同步桥前置预算检查。
