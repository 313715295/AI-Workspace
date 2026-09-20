# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
资源选择及调整只遵循 TASK 的 PR_TASK_RESOURCE_SELECTION；HOST负责核对当前可用 model、各自支持的 effort 与实际接受结果。同名 effort 不证明跨模型等价，角色/profile 不决定档位。

健康 identity/model/effort 复用。新分派或实际调整时，宿主支持则显式传参并消费接受结果；omitted/rejected/normalized/ignored、接受不明、host move 或能力变化才复查。prompt 不能证明物理切档，也不要求健康 peer 额外握手。

用户持续委托的来源与复用遵循 AUTHORIZATION_MODEL。HOST 只映射当前调用参数、实际配置和结果，不新增泛化宿主限制预检、安装守卫或授权台账；实际拒绝仍按真实原因处理。

不可满足任务能力时报告 RESOURCE_CAPABILITY_REQUIRED；不静默降质、不擅自切换长期 Owner。保存当前任务的实际配置和必要观察；自然任务证据比较首次达标、漏项、返工、总消耗及耗时，不用 pack bytes 或 resolver 延迟代替模型收益。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
Codex 遵循 `PR_FINAL_OUTPUT_CURRENT_RESULT` 通用合同：终态、routing identity、Controller escalation、wait。

任务 turn boundary 优先投递；安全例外可立即 steer。缺 host authenticity/delivery signal=>capability ceiling 或 `REPORT_CHANNEL_UNAVAILABLE`。禁 heartbeat、delivery ledger。

temporary actor/Reviewer 一次 terminal 后即无写职责；不向 Owner 索要反向 task 写权、package 删除或释放确认。Owner 更新唯一 task facts；STATUS/index 仅随 lifecycle/routing 变化投影。

宿主实际成功/拒绝/未知/明确可重试信号按 PR_FINAL_OUTPUT_CURRENT_RESULT 消费；没有送达证明不称 DELIVERED，不能把未知结果当作可重试。

原生 final 在发送前按 TOOL_CONTRACT 的 PREPARE 核定，只报告 READY_TO_SEND。任务间发送完成后，在原工具编排把真实返回映射为 OBSERVE 并连续调用同一 DELIVERY 校验；未知和失败停止依赖发送。宿主无法提供细分状态时保留 UNKNOWN，不生成未来证据、ACK 或额外记账回合。
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
首次解析、来源变化或正文实际缺失时读取项目backend与pinned TOOLCHAIN.json，校验runtime/platform并取得exact entrypoint；健康调用复用。不得从shell推断backend、另造后端或让用户逐任务选择。已知独立读查同批执行；有依赖且无需新语义判断的机械步骤按结果连续编排，各门保留独立结果，失败停止依赖链。按预期耗时合理首次等待；新事实、语义取舍或真实失败才返回模型，不能自动填授权、Review或接受PASS。

TASK定义的workflow transition使用fresh repo-local authority、cwd/Git top、package、用户决定和host-authenticated envelope，按 TOOLCHAIN 的 WORKFLOW_ROUTE_RESOLVE 提交 ephemeral input；缺事实 fail closed，具体字段及输入生命周期仅见TOOL_CONTRACT。任务显示名遵循TASK命名合同；创建时使用宿主title参数，主题实变时按authenticated task ID调用宿主标题操作，只改显示、不发指令或改authority。

创建环境/起点按TASK的当前基线与隔离结论及宿主合同传参，消费实际接受结果；不支持时报告具体能力限制，不静默换环境/起点。用户已有授权与宿主不支持是不同事实，不能把后者误报为用户未授权；不维护第二份参数表。

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
项目通过已接入且兼容采用版本的 `ai-workspace-router` Skill 导航治理工作。适用条件由根 canonical Skill 统一维护；接入收尾及异常处理见根 PROJECT_ADOPTION，version host 文件只保存兼容合同。

加载、复用和重建遵循 `RECOVERY_CORE.md`。健康上下文继续使用已加载 Skill 与有效规则；使用 Skill 不等于 FULL_COLD，action/final boundary call 不自行推导全文重载。

输入、compact 保存与清理遵循 TOOL_CONTRACT；当前动作仍完成 DISCOVER、ADMIT_ACTION 与 FINALIZE_OUTPUT。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
