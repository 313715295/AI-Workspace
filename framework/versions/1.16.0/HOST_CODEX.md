# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
Framework quality route 是抽象合同；host mapping 只是轻量建议，不是项目证据或强制矩阵。

| Route | Codex model | Effort | 用途 |
|---|---|---:|---|
| `OWNER_FRONTIER` | `gpt-5.6-sol` | `xhigh` | Controller、架构、critical Review |
| `FOCUSED_HIGH` | `gpt-5.6-sol` | `high` | 边界明确的困难实现或 Review |
| `ROUTINE_BALANCED` | `gpt-5.6-terra` | `xhigh` | 常规限域实现与分析 |
| `MECHANICAL_LOW` | `gpt-5.6-luna` | `xhigh` | 机械投影；`PROBATIONARY` |

host 可以替换该 mapping。resource change 不授予权限；Framework 不保存项目 task name、measurement、cost claim 或 model-effect record。

只有 host capacity 与 task authority 都允许时，才可用 internal subagent 处理边界清晰且独立的工作。user-visible task 由 `REUSE / MUST_NEW / BLOCKED` 管理，不能只为并行而创建。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
host task routing 应使用 host-authenticated task ID、sender 与可用的 Controller epoch/envelope；message body 不能自证身份。Codex 未提供所需真实性或 delivery signal 时，返回已记录的 capability ceiling 或 `REPORT_CHANNEL_UNAVAILABLE`。

优先在接收任务 turn boundary 进行一次 compact terminal delivery；安全例外可以立即 steer。terminal input 要命名 proposed consumer；除非 Controller 拥有唯一 next action，或存在显式 owner/public-decision、cross-domain-contract、protected-path、project-phase、Git/device/external 或 resource-conflict boundary，否则拒绝 `CONTROLLER`。只有一个精确 task result 阻塞当前唯一 next action 且没有其他安全工作时，才调用 `wait_threads`；不得增加 ACK、heartbeat、polling 或 delivery ledger。

临时 actor/Reviewer 在发送一次已收尾的 terminal 后不保留后续写入职责，也不向 Owner 申请反向任务卡写权、package 删除或“释放确认”。Owner 接收 terminal 后更新唯一任务事实；STATUS/index 只在 lifecycle/routing 变化时投影。发送失败只重送同一终态，不重复 Review 或创建 ACK 链。
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
调用任何 Framework operation 前，Codex 读取项目级 backend 与 pinned `<FW>/TOOLCHAIN.json`，校验 official backend/runtime/platform contract，并解析 exact entrypoint。不得从 host shell 推断 backend、生成 wrapper，或让用户逐任务选择。

在 `TASK_AND_SCOPE.md` 指定的每个 workflow transition，Codex 必须从已加载的 repo-local facts、重新证明的 cwd/Git top、当前 package、当前 public decision 与 host-authenticated envelope 生成新的 ephemeral input，然后解析 `WORKFLOW_ROUTE_RESOLVE` 并调用其 sealed entrypoint。缺失或不可用 fact 必须 fail closed；resolver output 只是 decision boundary，不能增加权限。
<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
非简单受治理工作在当前 pinned release 满足 sealed compatibility predicate 时，使用仓库根目录唯一 canonical `ai-workspace-router` Skill。该 Skill 只负责导航：绑定一个 explicit/current project root、取得最小 facts、调用 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`、一次加载全部选中的完整 Markdown blocks，并引导 `ADMIT_ACTION` 与 `FINALIZE_OUTPUT`。它不是 project authority；registration 或 project upgrade 不安装它。version 内的 host 文件只保存 `VERSION_CONTRACT / REFERENCE_ONLY` 历史。

在相关 user prompt、首次 task/context binding、authority/source change、compaction/resume/handoff uncertainty、独立 governed action 和最终输出前激活。source context 未变化时复用已加载规则与 compact receipt；不得按每次 tool call 重跑，也不得只因 authorization package 刷新而重跑。`LOAD_PLAN_RESOLVE` 是 support/fallback，不是 DISCOVER 前置过滤器。

task、task actor、action grantee、role/phase/profile、capabilities、exact scope、source binding 或 receipt identity 变化时重新 DISCOVER；无法判断是否变化时同样重新加载。

ephemeral input 与 receipt 默认写入 `.ai-workspace/runtime/<task>/<actor>/`，并由项目 `.gitignore` 排除。仅当 project runtime 不可用时使用 system temp `aiw-*.json`，并公开对应 evidence ceiling。完成、失效或中止后清理。

Skill 缺失、未发现、不兼容或无法证明已调用时，使用 repo-local `BOOTSTRAP.md` 路线并如实报告 `INVOCATION_UNPROVEN`。不得声称 Framework 机械证明 attention、memory retention，或在 host 未观察时声称避免了物理重读。

在 `INSTRUCTION_BOUND` 下，Framework 无法机械阻止漏调，结果必须暴露 `INVOCATION_UNPROVEN`。host hook 只有经过直接测试后才能声称 `HOST_ENFORCED` 或 `FRAMEWORK_GATED`。Framework 不安装、模拟或要求 per-tool hook。

tool preflight 是机械 gate，不是 operating-system enforcement。无法配置或直接测试 host hook 时不得声称其存在。message authentication 也是 capability ceiling，不能成为安装或模拟 Framework-managed host adapter 的理由。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
