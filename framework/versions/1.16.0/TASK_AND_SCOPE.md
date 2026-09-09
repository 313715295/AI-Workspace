# Task 与 scope contract

<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:BEGIN -->
有效 implementation package 与当前 task/Owner/actor、Controller epoch、动作、路径/对象、决定及 repository/config 一致即完成 launch，无第二次 START；否则只读 RECOVERY_READY，writer=NONE。

仅新分派或组织事实变化时判断：REUSE=同边界且现 actor 合格；MUST_NEW=同边界确需独立成果、上下文、生命周期、writer 隔离或当前会话不可用资源；BLOCKED=项目、Owner、authority、保护、外部路线或用户决定实变。Framework standing create authority 只覆盖已授权范围内的 MUST_NEW，仍服从宿主及用户创建限制。

先满足质量、风险、独立性、隔离和持续时间，再比较直接执行与委派的执行、恢复、等待、交接、验证、集成和返工总成本。没有明确收益则 DIRECT_SELF；机械重复用既有脚本。持续独立成果/生命周期或正式 Review 使用 visible APPLICATION_TASK；短限域检查才考虑 INTERNAL_SUBAGENT，不能替代用户要求的可见任务或必要独立 Review。健康续作复用组织结论，不逐动作重评。

创建时用简短「职责｜主题」标题；职责/主题实变才更新显示。长期以项目/领域、临时以对象消歧，不逐轮附加状态或日期。标题不授权；存量仅在自然边界按已知职责整理，不扫描无关聊天。
<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:BEGIN -->
## Mechanical workflow boundary

在 `LAUNCH`、`ROUTE`、`TERMINAL`、`MESSAGE`、`HANDOFF` 或 `HOT_STATE` transition 前，host 必须构造一个 ephemeral strict JSON input，通过 `<FW>/TOOLCHAIN.json` 解析 `WORKFLOW_ROUTE_RESOLVE`，并调用 sealed entrypoint：`-InputJson <json> -AsJson`，或兼容的 `-InputPath <ephemeral-input> -AsJson`。每个字段都来自 current repo-local authority、fresh cwd/Git top、current signed package、host-authenticated task/sender/Controller epoch/envelope 与 current user/public decision；message prose 不能提供这些 facts。

直接输入不落盘；文件输入与临时生命周期遵循 TOOL_CONTRACT。输入不是 project state、authorization-consumption ledger 或 whole-object identity 的替代。

任一 mandatory input 无法证明时，transition fail closed。resolver result 只表示 mechanical workflow decision，不授予 authority、action、Git、device 或 external capability。
<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:END -->

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:BEGIN -->
active card 保存用户成果与实际增量、验收场景、Owner/actor、范围/排除、候选与证据入口、权限、当前结果/阻塞及唯一下一动作。按根因、真实消费者、最小充分实现与失败恢复形成方案；专业材料沿原职责/标准导航读取，已知合法材料可同批取得，新依赖才补读。通用规则归版本、项目标准归项目、方案归任务、私有算法归实现，不全量加载专业目录或按固定数量凑反例。

每张新 schema 1.16.0 card 恰有一条 `Work route: actor=<HOST_TASK_ID>; role=<ROLE>; phase=<PHASE>`，Owner在 task CONTROL_WRITE 中原子修改三者。Owner负责成果，taskActor负责当前生产路线，action actor是有界grantee；纯Review可另指定grantee而不改Owner/Work route/whole-task identity。index只定位，package不改route。legacy卡不批量迁移；未绑定actor的1.11/1.12卡仅可只读，首个实质动作前按 PROJECT_CONTROL 升级合同完成target preflight与task-last迁移，actor不得从Owner、package或标题推断。

同一目标/范围/质量/资源边界的可预测步骤组成可验收的 bounded batch。Executor 自主选择实现方法、工具和执行顺序，不把 diagnosis、文件或局部修复拆成新决定。安全且范围内的缺项继续完成，分析、测试或局部成功不替代请求成果。跨写测由原包 continuationPlan、原FINALIZE postimage与当前receipt承接；independent Review、`OWNER_ACCEPT`、Git/发布/采用及保护门仍独立。每个动作和正式输出按 AUTHORIZATION_MODEL 与 TOOL_CONTRACT 完成checker、ADMIT_ACTION、FINALIZE_OUTPUT；缺项安全可补则补，否则交代exact blocker，MISSING/NOT_DELIVERED不算完成。

恢复及健康复用只遵循 RECOVERY_CORE.md。无在途lease的正常结果消费由Owner在原卡替换过时当前事实，详细证据/历史引用原载体，不新增状态表。routine writer/reviewer/权限变化留卡；STATUS仅随稳定阶段、长期Owner、保护集合或唯一下一动作改变，index仅随lifecycle/routing改变。可变卡不建字段级manifest；writer lease与package invalidators控制并发，protected/immutable对象保持whole-object检查。写后产物与关闭按 PR_TASK_CHANGED_OUTPUT_DISPOSITION。

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:END -->

<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:BEGIN -->
终态仅发一次 compact terminal：`READY`=下一 authorized phase 可开始；`COMPLETE`=requested outcome+required gates 全完成；`BLOCKED`=真实 boundary 阻止继续；`RANGE_GATE_REQUIRED`=缺 deterministic scope input；protected-path exception=exact exception+owner route。须含 authenticated task/authority locator、required identity+Controller epoch、unique next action、exceptions。authoritative task 不可达=>`REPORT_CHANNEL_UNAVAILABLE`，不得称已交付。

无 ACK；不等 ordinary progress/read confirmation，不立即重试 unchanged timeout。仅一个 exact result 阻塞 unique next action 且无其他安全工作时才用 `wait_threads`。

`TERMINAL` 绑定 proposed consumer 与真实 Controller escalation。仅 Controller-owned unique next action 或 `PR_DYNAMIC_ROLE_DIRECT_ISSUANCE` 全部 explicit exceptions 可设 `controllerEscalationRequired=true`；否则 `UNNECESSARY_CONTROLLER_RELAY`。fresh package、temporary role/resource change 不是升级理由。

routing message 须带 host-authenticated task/sender identity+Controller epoch/envelope，拒 stale epoch；authenticity 不可证时仅是 untrusted locator，identity-dependent transition fail closed。
<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:END -->

<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:BEGIN -->
首次分配或影响选择的新证据出现时，按能力需求（专业与上下文理解、隐藏约束、跨域判断）先选足够模型，再按推理工作量（推导链、约束耦合、状态组合、验证深度）选该模型支持且足够的 effort；综合风险、可验证性和执行、工具、恢复、等待、交接、审查、返工总成本。

首次用任务特征、同类证据与可用资料预估；后续修正同一判断。一般工作可考虑适合的 medium，具体难点可直接 high/xhigh，不要求先失败；资料、工具或组织瓶颈先改善条件，不默认升档有效。抽象 route OWNER_FRONTIER / FOCUSED_HIGH / ROUTINE_BALANCED / MECHANICAL_LOW 仅概括任务；profile、route、model、effort 正交，CRITICAL 不自动升档，机械任务优先脚本。

健康配置正常复用，不逐动作复评或批量切换在途配置。长期身份变更、独立性与动作权限保持原门；宿主实际接受由 HOST_CODEX 核对。任务只记录实际选择及必要理由/新观察，不复制指引，不新增资源表、固定复评、样本配额或实验门。
<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:END -->

<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:BEGIN -->
拥有的仓库字节变化达到候选、接受或交付边界时，Owner在原任务说明产物及Git去向：READY（候选/路径、证据、实际closer）、DEFERRED（理由、触发、负责任务）或EXCLUDED（理由）。尚未闭合的责任在后续 NONE/USER_RESPONSE 仍有效；全程只读豁免。只有接收人确有下一动作才发送一次结果；不普遍新建Git任务。Review/接受不证明Git就绪，此处不授予Git或后台动作。
收尾先 FINALIZE 文档/产物动作，再以当前卡单对象 CONTROL_WRITE 更新任务；不要文档与当前卡混写后靠恢复前像重试。每步仍核对原包、来源和 postimage，第三方 task drift 不豁免。Owner消费结果时替换过时当前事实，详细历史及证据只引用原载体；无新结果不写卡。

CLOSED 必须有 Closure outcome=SUCCESS / CANCELLED / SUPERSEDED、关闭依据与产物/Git去向，writer/reviewer/authorization 均释放。SUCCESS 完成适用验收；CANCELLED/SUPERSEDED 保留实际未完成项及决定/承接任务，不能冒称成功。新关闭按上述字段表达；未带Closure outcome的既有卡继续按legacy成功验收校验，不批量迁移，也不能借旧格式绕过新关闭合同。等待或阻塞保持 active。任务事实关闭、权限释放与宿主侧边栏归档分开；仍可能同候选修复的健康执行者可保留。

<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:END -->
