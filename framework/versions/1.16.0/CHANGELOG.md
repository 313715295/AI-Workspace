# Framework 1.16.0 变更记录

- 项目标准渐进接入：`process-policy.json` 可在不复制正文的前提下绑定项目自有文档全文或唯一标记区块，并声明有界依赖；只把命中的当前正文送入模型。来源漂移改为保守加载当前全文，相关来源不可读或区块无效时只阻止依赖它的动作，无关来源不阻断当前工作。

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
