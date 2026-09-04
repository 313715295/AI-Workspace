# Framework 1.16.0 change log

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

- immutable Framework `1.14.1`、`1.15.0`、`1.15.1` payload；
- 一个 composer、canonical Markdown blocks、actor-bound authorization、task-last recovery、project-owned corrections/policy、independent Review、独立 `OWNER_ACCEPT`、Git/external gate 与 protected-path boundary；
- Windows PowerShell 7 是本 release 唯一 official/evidenced backend。

## Not added

不增加第二 schema/resolver、service、registry、ledger、cache、poller、automatic consumer discovery/adoption、automatic host Skill installation、新 backend 或更宽 platform claim。
