# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
资源选择及调整只遵循 TASK 的 PR_TASK_RESOURCE_SELECTION；HOST负责核对当前可用 model、各自支持的 effort 与实际接受结果。同名 effort 不证明跨模型等价，角色/profile 不决定档位。

健康 identity/model/effort 复用。新分派或实际调整时，宿主支持则显式传参并消费接受结果；omitted/rejected/normalized/ignored、接受不明、host move 或能力变化才复查。prompt 不能证明物理切档，也不要求健康 peer 额外握手。

不可满足任务能力时报告 RESOURCE_CAPABILITY_REQUIRED；不静默降质、不擅自切换长期 Owner。保存当前任务的实际配置和必要观察；自然任务证据比较首次达标、漏项、返工、总消耗及耗时，不用 pack bytes 或 resolver 延迟代替模型收益。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
Codex 遵循 `PR_FINAL_OUTPUT_CURRENT_RESULT` 通用合同：终态、routing identity、Controller escalation、wait。

任务 turn boundary 优先投递；安全例外可立即 steer。缺 host authenticity/delivery signal=>capability ceiling 或 `REPORT_CHANNEL_UNAVAILABLE`。禁 heartbeat、delivery ledger。

temporary actor/Reviewer 一次 terminal 后即无写职责；不向 Owner 索要反向 task 写权、package 删除或释放确认。Owner 更新唯一 task facts；STATUS/index 仅随 lifecycle/routing 变化投影。

宿主实际成功/拒绝/未知/明确可重试信号按 PR_FINAL_OUTPUT_CURRENT_RESULT 消费；没有送达证明不称 DELIVERED，不能把未知结果当作可重试。
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
首次解析、来源变化或正文实际缺失时读取项目backend与pinned TOOLCHAIN.json，校验runtime/platform并取得exact entrypoint；健康调用复用。不得从shell推断backend、另造后端或让用户逐任务选择。已知独立读查同批执行；有依赖且无需新语义判断的机械步骤按结果连续编排，各门保留独立结果，失败停止依赖链。按预期耗时合理首次等待；新事实、语义取舍或真实失败才返回模型，不能自动填授权、Review或接受PASS。

TASK定义的workflow transition使用fresh repo-local authority、cwd/Git top、package、用户决定和host-authenticated envelope，按 TOOLCHAIN 的 WORKFLOW_ROUTE_RESOLVE 提交 ephemeral input；缺事实 fail closed，具体字段及输入生命周期仅见TOOL_CONTRACT。任务显示名遵循TASK命名合同；创建时使用宿主title参数，主题实变时按authenticated task ID调用宿主标题操作，只改显示、不发指令或改authority。

创建环境/起点按TASK的当前基线与隔离结论及宿主合同传参，消费实际接受结果；不支持时报告具体能力限制，不静默换环境/起点。用户已有授权与宿主不支持是不同事实，不能把后者误报为用户未授权；不维护第二份参数表。

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
非简单受治理工作在 pinned release 兼容时使用仓库根唯一 canonical `ai-workspace-router` Skill：绑定 explicit/current project、调用 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`、加载 selected complete blocks，并引导 `ADMIT_ACTION`/`FINALIZE_OUTPUT`。它不授权；registration/upgrade 不安装；version host 文件仅为 `VERSION_CONTRACT / REFERENCE_ONLY`。

激活、复用、重建及 compaction 后正文恢复只遵循 `RECOVERY_CORE.md`；本 host profile 不复制失效清单。`LOAD_PLAN_RESOLVE` 仅作 support/fallback，action/final boundary call 不自行推导全文重载。

输入、compact 保存与清理仅遵循 TOOL_CONTRACT 的调用和生命周期合同；此处不复制步骤。终态文本不能替代当前动作的 DISCOVER。

Skill 缺失/不兼容/调用不可证时走 repo-local `BOOTSTRAP.md` 并报告 `INVOCATION_UNPROVEN`；不得声称机械证明 current `fullText` 已读、attention/memory retention 或物理免重读。

`INSTRUCTION_BOUND` 无法机械阻止漏调，须暴露 `INVOCATION_UNPROVEN`。只有直接测试才可称 `HOST_ENFORCED/FRAMEWORK_GATED`；tool preflight/message authentication 都不等于 OS enforcement，Framework 不安装/模拟 per-tool hook 或 host adapter。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
