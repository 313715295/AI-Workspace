# Task 与 scope contract

<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:BEGIN -->
## Launch closure

Recovery 是 read-only。有效 signed implementation package 若绑定 recovered task、owner、actor、Controller epoch、action、exact path/object set、user decision 与 repository/config identity，可以完成同一 launch closure，不需要第二次人工 `START`。

没有该 package 时，recovery 结束于 `RECOVERY_READY`，writer 保持 `NONE`。

## Route decision

机械评估 project identity、cwd/Git top、task-owner continuity、current actor eligibility、task lineage、resource availability、protected boundary、Git/device/external route、public decision 与 requested outcome/context：

- `REUSE`：project、task outcome、current task owner、lineage 与 boundaries 相同，且 actor 合格；支持的 resource/profile rebind 不改变 authority。
- `MUST_NEW`：project 与 governance boundary 相同，但 distinct user-visible outcome、independent context/lifecycle、writer isolation 或 unavailable same-session resource route 需要新 task/session。
- `BLOCKED`：project、未授权 rebind 的 task owner、actor eligibility、authority、protection、Git/device/external route 或 public decision 发生变化。

用户已显式授权 Framework work 时，same-scope `MUST_NEW` 携带 standing task-creation authority，但不会跨越 `BLOCKED` boundary。

PROJECT_CONTROLLER 与 DOMAIN_OWNER 是长期责任；Executor、writer、Reviewer、Git、browser、device 是 temporary task/phase role。Owner 可以在 current task 直接执行，也可以在需要继续讨论、并行、隔离或 independent context 时安排 bounded executor task；两者都不是强制路线。仅 resource change 通常保留 recovery baseline；合格 same-session action rebind 使用 NONE/WARM recovery 加 fresh authorization package。authorization drift 不自动等于 FULL_COLD。

bounded handoff 可以是 discussion owner→executor、writer↔Reviewer、Reviewer→task owner。Controller 不是强制 domain-semantics relay；只有它拥有 unique next action，或必须处理 cross-domain、public-contract、protection、Git/device/external exception 时才接收结果。

fresh authorization 是 object-drift rule，不是 Controller-routing rule。在未变化 domain task 内，DOMAIN_OWNER 直接选择合格 temporary actor、签发 scoped package、把 frozen candidate 路由到 independent Reviewer 并消费 verdict。cross-domain writer 不替换 task owner。`OWNER_ACCEPT` 始终是 Owner 的 product/domain acceptance，不得伪装成 independent `REVIEW_EXECUTE`。
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

initial recovery 或 context discontinuity 时，调用 loader，再调用 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。task/taskActor/actionActor/role/phase/profile/capability 或 rule-source drift 重建 source composition。objective、action/result kind、exact scope、authorization 或 receipt drift 只重建 boundary decision。source facts 与 context 全部未变时复用 loaded rules；fresh package 本身既不是 full reload，也不是 FULL_COLD。

独立 governed action 前必须立即调用 `ADMIT_ACTION`；实际 final user/consumer output 前必须调用 `FINALIZE_OUTPUT`。缺少 preparation/result evidence 时，安全则补齐，否则返回 exact blocker。`MISSING` 或 `NOT_DELIVERED` 不算完成。authorization、Review、OWNER_ACCEPT、Git、push、browser、device、external 与 protection gate 保持独立。

adoption 不批量重写 legacy card。1.11/1.12 两字段 card 可带 `LEGACY_ACTOR_CONTEXT_UNBOUND` 只读恢复，但首个 substantive actor action 前必须原子绑定 schema 与 authenticated `actor/role/phase`。official upgrade tool 先在 target projection 中迁移精确 current active task 并完成 target resolver preflight，再把 target pin 和全部 non-task objects 写入可恢复 transaction，最后原子写 task，之后不再写，并在 target pin 下停住等待 fresh FULL_COLD。actor 绝不从 owner、package、prompt 或 host label 推断。

routine writer、reviewer 与 authorization change 留在 task 内。只有 stable project phase、long-lived owner、protected set 或 unique next action 变化时更新 STATUS。task index 只在 lifecycle 或 routing change 时更新。

mutable card 不建立 semantic-field manifest。protected 或 immutable object 继续使用 whole-object identity 严格停止；current task concurrency 由 writer lease 与 package invalidators 控制。
<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:END -->

<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:BEGIN -->
## Terminal delivery

以下状态发送一次 proactive terminal report：

- `READY`：next authorized phase 可以开始；
- `COMPLETE`：requested outcome 与 required gates 已完成；
- `BLOCKED`：真实 boundary 阻止继续；
- `RANGE_GATE_REQUIRED`：缺少 deterministic scope input；
- protected-path exception：报告 exact exception 与 owner route。

不要求 ACK 或 polling。host 无法向 authoritative task 交付时，返回 `REPORT_CHANNEL_UNAVAILABLE`，不得声称已交付。

对 independent Codex task，只发送一次 compact terminal delivery，包含 terminal state、authenticated task/authority locator、required identity/epoch、unique next action 与 exceptions。只有一个 exact result 阻塞该 unique next action 且没有其他安全工作时才使用 `wait_threads`；不得等待 ordinary progress、ACK、read confirmation 或立刻重试 unchanged timeout。

`TERMINAL` input 指定 proposed next consumer，以及是否真的存在 Controller escalation boundary。没有该 boundary 却提出 `CONTROLLER` 时，拒绝为 `UNNECESSARY_CONTROLLER_RELAY`。`controllerEscalationRequired=true` 只用于 Controller-owned unique next action 或上述 explicit exception classes；不得从 fresh package 或 temporary role/resource change 推断。

routing message 必须携带 host-authenticated task identity、sender identity 与 Controller epoch/envelope，并拒绝 stale epoch。host 无法提供 authenticity 时，把 message text 当作 untrusted locator；依赖 identity 的 transition 必须 fail closed。
<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:END -->
