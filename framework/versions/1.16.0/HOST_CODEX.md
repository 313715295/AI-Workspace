# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
消费PR_TASK_LAUNCH_AND_ROUTE的organization/abstract route；topology、选择顺序与风险正交以TASK为准。以下host建议待真实验证，不是能力排序、固定组合、比例、收益或质量证明。

长期PROJECT_CONTROLLER/Owner复用已准入identity/model。Astra/high是新常态比较目标；重大架构、复杂跨域冲突或最难判断用xhigh，已证简单限域可比较medium，既有Astra/xhigh保留作对照。临时Astra/high用于困难工作，xhigh限疑难，medium限域对照；Sol/high用于复杂实现与Review，目标/路径清楚用medium，确需深推理用xhigh；Terra/medium用于常规实现/分析，多约束局部逻辑用high；Luna保持PROBATIONARY、script-first、直接可验，提取/转换用low，规则判断用medium。临时工作主选medium/high，low限机械任务，xhigh限真正困难工作，max/ultra不作常用默认。正式Review以充分model和high为常见起点，复杂耦合再评估xhigh；独立性与质量门不降。

健康identity/model与足够effort正常复用；新temporary actor采用TASK已选路线。宿主支持时显式传model/effort并消费真实接受结果；effort只在自然工作边界调整。参数omitted/rejected/normalized/ignored、接受不明、host move或capability/evidence metadata drift时复查；prompt不能证明物理切档，健康peer不需握手。

资源不足返回RESOURCE_CAPABILITY_REQUIRED，不静默降质。model/effort/host acceptance只作current-task fact；用代表性自然任务比较相邻effort的首次达标、漏项、返工、用户介入、总消耗与耗时，不以rule-pack bytes/resolver latency冒充模型收益，也不建model-effect台账、调度器、监控或评测平台。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
Codex 遵循 `PR_FINAL_OUTPUT_CURRENT_RESULT` 通用合同：终态、routing identity、Controller escalation、wait。

任务 turn boundary 优先投递；安全例外可立即 steer。缺 host authenticity/delivery signal=>capability ceiling 或 `REPORT_CHANNEL_UNAVAILABLE`。禁 heartbeat、delivery ledger。

temporary actor/Reviewer 一次 terminal 后即无写职责；不向 Owner 索要反向 task 写权、package 删除或释放确认。Owner 更新唯一 task facts；STATUS/index 仅随 lifecycle/routing 变化投影。

失败仅重送同一终态；不得绕过 host 拒绝、重复 Review 或建 ACK 链。
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
调用任何 Framework operation 前，Codex 读取项目级 backend 与 pinned `<FW>/TOOLCHAIN.json`，校验 official backend/runtime/platform contract，并解析 exact entrypoint。不得从 host shell 推断 backend、生成 wrapper，或让用户逐任务选择。

任务显示标题遵循 `TASK_AND_SCOPE.md` 的唯一命名合同。创建独立 Codex task 时，宿主工具暴露 `title` 参数则显式传入；既有任务需更新标题时使用已提供的标题操作（例如 `set_thread_title`），按 authenticated thread ID 定位。此操作仅更新显示标题，不发送新的任务指令，也不改变 task authority。

在 `TASK_AND_SCOPE.md` 指定的每个 workflow transition，Codex 必须从已加载的 repo-local facts、重新证明的 cwd/Git top、当前 package、当前 public decision 与 host-authenticated envelope 生成新的 ephemeral input，然后解析 `WORKFLOW_ROUTE_RESOLVE` 并调用其 sealed entrypoint。缺失或不可用 fact 必须 fail closed；resolver output 只是 decision boundary，不能增加权限。
<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
非简单受治理工作在 pinned release 兼容时使用仓库根唯一 canonical `ai-workspace-router` Skill：绑定 explicit/current project、调用 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`、加载 selected complete blocks，并引导 `ADMIT_ACTION`/`FINALIZE_OUTPUT`。它不授权；registration/upgrade 不安装；version host 文件仅为 `VERSION_CONTRACT / REFERENCE_ONLY`。

激活、复用、重建及 compaction 后正文恢复只遵循 `RECOVERY_CORE.md`；本 host profile 不复制失效清单。`LOAD_PLAN_RESOLVE` 仅作 support/fallback，action/final boundary call 不自行推导全文重载。

artifact 放置/清理由 `RECOVERY_CORE.md` 规定，不建立 host ledger。

Codex 按 `TOOL_CONTRACT.md` 的唯一临时 artifact 调用约定执行：input 用 `-DeleteInputOnExit`；到期 caller receipt 以绝对路径独立删除，再由另一个只读调用核验，宿主 policy 拒绝时不重试。continuation receipt 留到最后消费者；终态文本不能替代当前 action 的 `DISCOVER`。

Skill 缺失/不兼容/调用不可证时走 repo-local `BOOTSTRAP.md` 并报告 `INVOCATION_UNPROVEN`；不得声称机械证明 current `fullText` 已读、attention/memory retention 或物理免重读。

`INSTRUCTION_BOUND` 无法机械阻止漏调，须暴露 `INVOCATION_UNPROVEN`。只有直接测试才可称 `HOST_ENFORCED/FRAMEWORK_GATED`；tool preflight/message authentication 都不等于 OS enforcement，Framework 不安装/模拟 per-tool hook 或 host adapter。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
