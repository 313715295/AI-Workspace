# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
资源选择及调整只遵循 TASK 的 PR_TASK_RESOURCE_SELECTION；HOST负责核对当前可用 model、各自支持的 effort 与实际接受结果。同名 effort 不证明跨模型等价，角色/profile 不决定档位。当前 Codex 指引只从 GPT-6 Astra、Sol、Luna 中选择：Sol 覆盖多数完整任务的分析、方案设计、复杂实现、定位、验证与独立审核；Luna 适合范围集中、模式成熟、结果容易核验的完整任务。这是能力匹配方向，不是模型使用配额。需要更强探索、设计或综合能力时，可选 Astra 承担分析、方案、实现或审核；结合具体难点、探索深度、成果质量对后续工作的影响及同类表现判断，不能只凭任务名称或笼统的高质量要求升档。先选模型再按推理工作量选 effort；Sol、Luna 以 High 为通用起点，新增 Astra 任务按推理工作量选 effort，不套用长期 Owner 档位。初始即可直接采用适合配置；影响原选择的实质证据才调整，能力足够但推演或检查工作量显著增加时考虑 effort，问题识别、约束综合或证据解释能力不足时考虑模型。健康配置持续复用，长期主控与领域 Owner 保持各自已批准的稳定配置；GPT-5.6 只退出现行推荐、默认配置与新任务示例；历史 ID、冻结试验、当时费率、失败/用量及必要读取计价兼容保留，缺失费率记为未知，不套当前费率。

健康 identity/model/effort 复用。新任务显式落实当次选定的 model/effort，并核对实际接受结果；按当次工具合同传参，不能用“保持默认”代替选型，也不能把调用前主动省略说成工具拒绝。omitted/rejected/normalized/ignored、接受不明、host move 或能力变化才复查。prompt 不能证明物理切档，不要求健康 peer 额外握手。长期主控/Owner保持原绑定。

用户持续委托的来源与复用遵循 AUTHORIZATION_MODEL。HOST 只映射当前调用参数、实际配置和结果，不新增泛化宿主限制预检、安装守卫或授权台账；实际拒绝仍按真实原因处理。新建临时实现、调查或独立 Reviewer 时，创建提示一次携完整正式委派、待绑定授权路径与原始字节身份、唯一 delegationId；不要先发空任务等其反向索包。接收者在初始委派中核对这些字段和材料，用当前宿主 `CODEX_THREAD_ID` 经 `AUTHORIZATION_RECEIVER_BIND` 派生自身精确包；工具读取该宿主变量，不接受模型自填 grantee。`CODEX_THREAD_ID` 只证明本地自身事实，初始委派编号和原件身份是 INSTRUCTION_BOUND 的对应依据，不能宣称密码学宿主认证。已知 ID 仍直接签精确包；健康续作复用有效绑定。后建 Reviewer 可在原 `repairReviewPlan` 下用 `HOST_INITIAL_DELEGATION` 的待绑定 assignment 承接既有生产证据；旧 `HOST_CREATE_THREAD_RESULT` 已绑定路径保留。身份或初始委派事实缺失时保持只读并报告具体条件。

不可满足任务能力时报告 RESOURCE_CAPABILITY_REQUIRED；不静默降质、不擅自切换长期 Owner。资源计量复用原日志、实际执行及交付/验收记录；执行者提供必要定位，任务最后消费者在原收尾复用有效汇总，必要时用既有工具一次提取可确认的配置、用量、首交/返工、耗时与费用覆盖，并分别记录请求配置和实际接受配置。未知项及覆盖限制明确标注，不计为零，不为补齐增加模型回合；正常成果、验证证据和终态仍按原合同交付，更上层汇总消费已有结果。不得用 pack bytes 或 resolver 延迟代替模型收益。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
Codex 的协作等待取 TASK 的 `PR_TASK_SCOPE_AND_FORBIDDEN`，终态、routing identity 与 Controller escalation 取 `PR_FINAL_OUTPUT_CURRENT_RESULT`；本块只映射宿主投递信号。

任务 turn boundary 优先投递；安全例外可立即 steer。缺 host authenticity/delivery signal=>capability ceiling 或 `REPORT_CHANNEL_UNAVAILABLE`。禁 heartbeat、delivery ledger。

temporary actor/Reviewer 的 terminal 只结束本轮交付，不改变原任务范围内已定的职责。writer 交齐审核材料后结束当前轮，若 Reviewer 返回真实 finding，仍可按原计划在当前修复包重新准入后续作；Reviewer 不因此取得候选写职责。无 Owner 下一动作时不另发中间终态，不向 Owner 索要反向 task 写权、package 删除或释放确认。Owner 更新唯一 task facts；STATUS/index 仅随 lifecycle/routing 变化投影。

宿主实际成功/拒绝/未知/明确可重试信号按 PR_FINAL_OUTPUT_CURRENT_RESULT 消费；没有送达证明不称 DELIVERED，不能把未知结果当作可重试。

原生 final 在发送前按 TOOL_CONTRACT 的 PREPARE 核定，只报告 READY_TO_SEND。任务间发送完成后，在原工具编排把真实返回映射为 OBSERVE 并连续调用同一 DELIVERY 校验；未知和失败停止依赖发送。宿主无法提供细分状态时保留 UNKNOWN，不生成未来证据、ACK 或额外记账回合。
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
首次解析、来源变化或正文实际缺失时读取项目backend与pinned TOOLCHAIN.json，校验runtime/platform并取得exact entrypoint；健康调用复用。不得从shell推断backend、另造后端或让用户逐任务选择。已知独立读查同批执行；有依赖且无需新语义判断的机械步骤按结果连续编排，各门保留独立结果，失败停止依赖链。当前命令/测试的必要结果获取可按预期耗时等待；跨会话结果遵循 TASK 的无等待规则。新事实、语义取舍或真实失败才返回模型，不能自动填授权、Review或接受PASS。记录、交付和必要归档在原任务收尾集中完成，不另起清理或统计回合。

TASK定义的workflow transition使用fresh project authority、cwd/project root、package、用户决定和host-authenticated envelope；实际 Git 动作另核对 Git top。按 TOOLCHAIN 的 WORKFLOW_ROUTE_RESOLVE 提交 ephemeral input；缺事实 fail closed，具体字段及输入生命周期仅见TOOL_CONTRACT。任务显示名遵循TASK命名合同；创建时使用宿主title参数，主题实变时按authenticated task ID调用宿主标题操作，只改显示、不发指令或改authority。

创建时在同一次调用落实已选 model、effort、环境及宿主支持的精确起点，并核对返回的真实任务 ID、配置与读取基线；当前未提交材料和明确隔离需求影响环境选择，但独立审核或 Git 名称自身不强制某环境。宿主工具合同若要求创建后首次取得进度，仅在取得可用真实任务 ID 后做一次立即快照；未就绪即结束当前轮，超时或 commentary 不构成再次等待依据，不把首次观察扩成循环。参数缺失、归一化、拒绝或不支持时按身份、保护、候选与证据影响处置，不静默换环境/起点。交审依赖顺序只取 REVIEW_AND_EVIDENCE；HOST在已有主体的新工作中使用已知真实 ID，在新建且 ID 未知时将限域待绑定原件随完整初始委派一次交付，由接收者自绑定，不默认改走创建后补包。健康续作复用仍有效绑定；任何分支包未准入前只读。用户已有授权与宿主不支持是不同事实，不能把后者误报为用户未授权；不维护第二份参数表。

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
项目通过已接入且兼容采用版本的 `ai-workspace-router` Skill 导航治理工作。适用条件由根 canonical Skill 统一维护；接入收尾及异常处理见根 PROJECT_ADOPTION，version host 文件只保存兼容合同。

加载、复用和重建遵循 `RECOVERY_CORE.md`。健康上下文继续使用已加载 Skill 与有效规则；使用 Skill 不等于 FULL_COLD，action/final boundary call 不自行推导全文重载。

输入、compact 保存与清理遵循 TOOL_CONTRACT；当前动作仍完成 DISCOVER、ADMIT_ACTION 与 FINALIZE_OUTPUT。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
