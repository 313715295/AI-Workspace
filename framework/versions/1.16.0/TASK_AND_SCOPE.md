# Task 与 scope contract

<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:BEGIN -->
Recovery只读。signed implementation package绑定task/Owner/actor、Controller epoch、action、path/object、user decision、repository/config即闭合launch；无第二次START；否则RECOVERY_READY/writer=NONE。

按current authority/governance facts一次三态：REUSE=边界未变且actor合格（profile/resource rebind不授权）；MUST_NEW=边界未变但需新visible outcome|独立context/lifecycle|writer isolation|不可用same-session resource；BLOCKED=project|未授权Owner rebind|actor/authority/protection/external route|public decision变化。Framework standing create authority仅及same-scope MUST_NEW。

每个bounded action先按quality/risk/evidence/independence/isolation/duration筛合法topology，再比较Owner、temporary context、handoff、recovery、validation、integration、rework的全成本；无清晰净收益=>DIRECT_SELF，机械重复=>既有script/tool。持续实现、独立lifecycle或正式Review=>visible APPLICATION_TASK；同turn短检查=>INTERNAL_SUBAGENT且不替requested visibility；成本不取消required independent Review。

抽象route：OWNER_FRONTIER=ownership/architecture/full CRITICAL Review；FOCUSED_HIGH=困难限域实现/focused Review；ROUTINE_BALANCED=常规实现/分析；MECHANICAL_LOW=script-first、直接可验的PROBATIONARY机械投影。合法topology内先选足够model，再选其支持的足够effort。Profile/route/model/effort正交，不一一绑定、无配额/固定流水线/最低档失败升级阶梯；CRITICAL不自动升档。

标题=简短「职责｜主题」：role仅显示；长期=project/domain，临时=object；model/effort仅当主题，version/round仅消歧，默认无date/epoch/ID/status。创建即命名；职责/主题实变才host-update；接任去candidate；完成/阻塞用lifecycle/archive，非逐turn改名。存量仅正常边界按已知职责整理，不猜无关chat；普通chat留用户名。标题不授权；失败仅显示差异；无title checker/ledger/sync/approval。
<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:BEGIN -->
## Mechanical workflow boundary

在 `LAUNCH`、`ROUTE`、`TERMINAL`、`MESSAGE`、`HANDOFF` 或 `HOT_STATE` transition 前，host 必须物化一个 ephemeral strict UTF-8/LF JSON input，通过 `<FW>/TOOLCHAIN.json` 解析 `WORKFLOW_ROUTE_RESOLVE`，并调用 sealed entrypoint：`-InputPath <ephemeral-input> -AsJson`。每个字段都来自 current repo-local authority、fresh cwd/Git top、current signed package、host-authenticated task/sender/Controller epoch/envelope 与 current user/public decision；message prose 不能提供这些 facts。

input 默认位于 `.ai-workspace/runtime/<task>/<actor>/`；文件名必须受限，目录由项目 `.gitignore` 排除。只有该目录不可用时，才使用 system temp `aiw-*.json`。调用结束后删除 input；它不是 project state、authorization-consumption ledger 或 whole-object identity 的替代。

任一 mandatory input 无法证明时，transition fail closed。resolver result 只表示 mechanical workflow decision，不授予 authority、action、Git、device 或 external capability。
<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:END -->

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:BEGIN -->
## Task contents

active card 只包含 current contract、owner/actor roles、exact boundary、stable candidate locator、authorization state、evidence ceiling 与 next action。superseded narrative 通过既有 archive/Git route 处理。

每张新 schema `1.16.0` card 必须恰有一条 `Work route: actor=<HOST_TASK_ID>; role=<ROLE>; phase=<PHASE>`。current Owner 在正常 task `CONTROL_WRITE` boundary 下原子修改三者。task index 只做 locator。actor/role/phase 选择 context；action authorization 独立，不能创建或覆盖 task route。

task Owner 表示责任归属，Work route actor 表示当前生产路线，action package grantee 表示一次临时 action 的执行者。纯 `REVIEW_EXECUTE` 可以让独立 Reviewer 成为 grantee，同时保持 Owner、Work route、task identity 与 candidate 不变；authority context 必须同时报告 `taskActor` 与 action `actor`。

Recovery 复用/失效只指向 `RECOVERY_CORE.md`。同一 goal/scope/quality/resource boundary 的可预测步骤组成一个可验收的 bounded batch；Executor 自主选择实现方法、工具和执行顺序，闭合 routine issue，不把 diagnosis、文件或局部修复拆成新决定。跨写/测仅由原 package 的 `continuationPlan`、上一 `FINALIZE_OUTPUT` 真实 postimage 和 current receipt 承接，不改 Owner/Work route；tool call、progress、authorized postimage、fresh package 或 compaction 不单独创建 task/handoff/`FULL_COLD`。independent Review、`OWNER_ACCEPT`、Git/publication/adoption 与 protection gate保持独立。

独立 governed action 前必须立即调用 `ADMIT_ACTION`；实际 final user/consumer output 前必须调用 `FINALIZE_OUTPUT`。缺少 preparation/result evidence 时，安全则补齐，否则返回 exact blocker。`MISSING` 或 `NOT_DELIVERED` 不算完成。authorization、Review、OWNER_ACCEPT、Git、push、browser、device、external 与 protection gate 保持独立。

adoption 不批量重写 legacy card。1.11/1.12 两字段 card 可带 `LEGACY_ACTOR_CONTEXT_UNBOUND` 只读恢复，但首个 substantive actor action 前必须原子绑定 schema 与 authenticated `actor/role/phase`。official upgrade tool 先在 target projection 中迁移精确 current active task 并完成 target resolver preflight，再把 target pin 和全部 non-task objects 写入可恢复 transaction，最后原子写 task；stable/schema2 随即结束，本地候选/schema4 仅按 `PROJECT_CONTROL.md` 登记原事务完成后结束，不追加其他项目工作；然后在 target pin 下停住等待 fresh FULL_COLD。actor 绝不从 owner、package、prompt 或 host label 推断。

routine writer、reviewer 与 authorization change 留在 task 内。一个正常 bounded batch 完成且没有 in-flight lease 时，更新既有 current result/evidence locator/unique next action，不增设平行状态表。只有 stable project phase、long-lived owner、protected set 或 unique next action 变化时更新 STATUS；task index只在lifecycle或routing change时更新。

mutable card 不建立 semantic-field manifest。protected 或 immutable object 继续使用 whole-object identity 严格停止；current task concurrency 由 writer lease 与 package invalidators 控制。
<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:END -->

<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:BEGIN -->
终态仅发一次 compact terminal：`READY`=下一 authorized phase 可开始；`COMPLETE`=requested outcome+required gates 全完成；`BLOCKED`=真实 boundary 阻止继续；`RANGE_GATE_REQUIRED`=缺 deterministic scope input；protected-path exception=exact exception+owner route。须含 authenticated task/authority locator、required identity+Controller epoch、unique next action、exceptions。authoritative task 不可达=>`REPORT_CHANNEL_UNAVAILABLE`，不得称已交付。

无 ACK；不等 ordinary progress/read confirmation，不立即重试 unchanged timeout。仅一个 exact result 阻塞 unique next action 且无其他安全工作时才用 `wait_threads`。

`TERMINAL` 绑定 proposed consumer 与真实 Controller escalation。仅 Controller-owned unique next action 或 `PR_DYNAMIC_ROLE_DIRECT_ISSUANCE` 全部 explicit exceptions 可设 `controllerEscalationRequired=true`；否则 `UNNECESSARY_CONTROLLER_RELAY`。fresh package、temporary role/resource change 不是升级理由。

routing message 须带 host-authenticated task/sender identity+Controller epoch/envelope，拒 stale epoch；authenticity 不可证时仅是 untrusted locator，identity-dependent transition fail closed。
<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:END -->
