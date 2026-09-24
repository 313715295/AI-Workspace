# Task 与 scope contract

<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:BEGIN -->
有效 implementation package 与当前 task/Owner/actor、Controller epoch、动作、路径/对象、决定及 repository/config 一致即完成 launch，无第二次 START；否则只读 RECOVERY_READY，writer=NONE。

仅新分派或组织事实变化时判断：REUSE=同边界且现 actor 合格；MUST_NEW=同边界确需独立成果、上下文、生命周期、writer 隔离或当前会话不可用资源；BLOCKED=项目、Owner、authority、保护、外部路线或用户决定实变。复用项目 AGENTS 中用户已确认且仍有效的持续委托，不逐任务或逐步骤重复确认。委托来源、后续决定及保留事项遵循 AUTHORIZATION_MODEL；规则本身不制造用户授权。为取得签包便利不把临时 writer 升为 Owner；原 Owner 在完整委派中预授权有界写测、交审、修复和局部复审，临时主体沿原决定直接续接，实质范围或决定变化才回 Owner。

先满足质量、风险、独立性、隔离和持续时间，再比较直接执行与委派中Owner及执行者双方的模型往返、上下文、执行、工具、澄清、交接、验证、集成、返工及用户介入总成本；可依据任务和同类证据定性估计，不要求事前证明节省或新增实验/审批。没有明确收益则 DIRECT_SELF；机械重复用既有脚本。需要独立成果、审核或持续独立生命周期时使用可见 APPLICATION_TASK。框架不支持内部子 agent，包括内部 Reviewer，不因停用内部载体把普通工作全部委派。正式 Review 按 REVIEW_AND_EVIDENCE 核对真实主体、材料和结果追溯。一次安排同时决定组织、能力足够的模型与支持的 effort；创建时传入所选配置及按当前基线/隔离结论选定且宿主支持的环境和精确起点，核对实际接受。新建时一次提供完整任务/候选/验收/消费者材料和限域待绑定授权的路径、身份及委派编号；接收者从实际初始委派取得这三项，并用宿主真实自身 ID 经 AUTHORIZATION_RECEIVER_BIND 在自身过程目录派生精确包，随后走原 checker、DISCOVER、ADMIT。待绑定材料不可执行；不修改原件、Owner、issuer、决定、范围、候选和独立性。已知 ID 的新委派直接绑定新 scope，有效健康续作复用原绑定；宿主身份缺失或实际初始委派不符时停在只读，报告具体阻塞，不向接收者交空白权限。clientThreadId 不是正式主体。用户指定的环境/起点优先，不把某项目的 LOCAL/WORKTREE 默认推广为通用规则。健康续作复用组织结论，不逐动作重评。

创建时用简短「职责｜主题」标题；职责/主题实变才更新显示。长期以项目/领域、临时以对象消歧，不逐轮附加状态或日期。标题不授权；存量仅在自然边界按已知职责整理，不扫描无关聊天。
<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:BEGIN -->
## Mechanical workflow boundary

在 `LAUNCH`、`ROUTE`、`TERMINAL`、`MESSAGE`、`HANDOFF` 或 `HOT_STATE` transition 前，host 必须构造一个 ephemeral strict JSON input，通过 `<FW>/TOOLCHAIN.json` 解析 `WORKFLOW_ROUTE_RESOLVE`，并调用 sealed entrypoint：`-InputJson <json> -AsJson`，或兼容的 `-InputPath <ephemeral-input> -AsJson`。每个字段都来自 current repo-local authority、fresh cwd/Git top、current signed package、host-authenticated task/sender/Controller epoch/envelope 与 current user/public decision；message prose 不能提供这些 facts。

直接输入不落盘；文件输入与临时生命周期遵循 TOOL_CONTRACT。输入不是 project state、authorization-consumption ledger 或 whole-object identity 的替代。

任一 mandatory input 无法证明时，transition fail closed。resolver result 只表示 mechanical workflow decision，不授予 authority、action、Git、device 或 external capability。
<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:END -->

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:BEGIN -->
active card 保存用户成果与实际增量、验收场景、Owner/actor、范围/排除、候选与证据入口、权限、当前结果/阻塞及唯一下一动作。方案同时核对根因、当前机制与直接消费者、可推翻错误方案的验证依据、重要失败恢复及未解重大假设；已有充分结论直接引用。实现取舍遵循同次加载的PR_TASK_IMPLEMENTATION_JUDGMENT，不另建方案判断。专业材料沿原职责/标准导航读取，已知合法材料可同批取得，新依赖才补读；不全量加载专业目录或按固定数量凑反例。

通用规则归版本、项目标准归项目、方案归任务、私有算法归实现。只有真实外部消费者、兼容、安全、确定性或外部性能承诺需要，才把实现机制提升为公共合同；测试方便不是理由，引用不形成第二权威。声称实现已接受契约时，在原任务绑定当前权威、负责接点、直接消费者/测试与证据；来源实质变化先重绑。允许轻量 @design-contract <locator> 定位原设计并保留项目已有合理标记；不复制语义、哈希或通过状态，不声称标记证明实现一致，不要求全仓补标、台账或扫描。技术事实先有界查证，只把实质目标、范围、权限或风险取舍交用户；中间回答不是整案授权，仍有效决定不重复确认。重大冲突与必要用户取舍已解决、剩余假设有界且可验证和恢复时，方案足够就绪，沿现有授权推进；未处理重大冲突只停受影响链。按实际 Review profile 保留必要审核，普通低影响修复不新增写前审核阶段。

每张新 schema 1.16.0 card 恰有一条 `Work route: actor=<HOST_TASK_ID>; role=<ROLE>; phase=<PHASE>`，Owner在 task CONTROL_WRITE 中原子修改三者。Owner负责成果，taskActor负责当前生产路线，action actor是有界grantee；纯Review可另指定grantee而不改Owner/Work route/whole-task identity。index只定位，package不改route。legacy卡不批量迁移；未绑定actor的1.11/1.12卡仅可只读，首个实质动作前按 PROJECT_CONTROL 升级合同完成target preflight与task-last迁移，actor不得从Owner、package或标题推断。

同一目标/范围/质量/资源边界的可预测步骤组成可验收的 bounded batch。Executor 自主选择实现方法、工具和执行顺序，不把 diagnosis、文件或局部修复拆成新决定。安全且范围内的缺项继续完成，分析、测试或局部成功不替代请求成果。跨写测由原包 continuationPlan、原FINALIZE postimage与当前receipt承接；independent Review、`OWNER_ACCEPT`、Git/发布/采用及保护门仍独立。每个动作和正式输出按 AUTHORIZATION_MODEL 与 TOOL_CONTRACT 完成checker、ADMIT_ACTION、FINALIZE_OUTPUT；缺项安全可补则补，否则交代exact blocker，MISSING/NOT_DELIVERED不算完成。

协作期间的等待与组织切换统一在此约束：所有角色均不以 wait_threads、wait_agent 或反复读取任务状态、聊天、日志等待其他会话；有安全工作就继续，没有就结束当前轮，实际结果送达后续作。宿主明确要求新建后的首次进度取得时，按 HOST_CODEX 的一次有界观察执行，未就绪不转为持续等待。当前已启动命令/测试为取得自身结果所需的等待仍可进行；用户主动查询进度可单次读取现状。生产/自测转入**新的交审分派**属于组织事实变化，不能把旧 SOURCE_WRITE/TEST_RUN 的选择结果当成该委派的规则；按 REVIEW_AND_EVIDENCE 的唯一交审顺序，以真实交审目标完成一次增量 DISCOVER、读取必要正文并复用仍健康的既有正文与生产证据。若同一真实交审目标的当前选择与正文已经取得且仍健康，直接复用，不为形式再调用或重做整套恢复。没有新分派时不为常规续作重复组织选择。

恢复及健康复用只遵循 RECOVERY_CORE.md。无在途lease的正常结果消费由Owner在原卡替换过时当前事实，详细证据/历史引用原载体，不新增状态表。实际影响已有恢复、交接或用户说明时，同步并读回可宣称的当前事实；候选不投为已接受，未解义务与失败证据保留，无受影响载体不额外写。routine writer/reviewer/权限变化留卡；STATUS仅随稳定阶段、长期Owner、保护集合或唯一下一动作改变，index仅随lifecycle/routing改变。可变卡不建字段级manifest；writer lease与package invalidators控制并发，protected/immutable对象保持whole-object检查。写后产物与关闭按 PR_TASK_CHANGED_OUTPUT_DISPOSITION。

自然维护受影响的当前材料时，精简重复或过时文字，同时保留责任、条件、范围、例外、失效和证据；健康续作只报告实际变化及影响，无变化不另写卡或重复恢复。
<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:END -->

<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:BEGIN -->
终态仅发一次 compact terminal：`READY`=下一 authorized phase 可开始；`COMPLETE`=requested outcome+required gates 全完成；`BLOCKED`=真实 boundary 阻止继续；`RANGE_GATE_REQUIRED`=缺 deterministic scope input；protected-path exception=exact exception+owner route。发送前绑定实际授权、精确消费者与允许内容；结果含裁决、必要 finding/原因/影响/最小修正及证据定位与上限、精确阻塞和 unique next action。认证 identity/Controller epoch 留实际工具包络，普通正文仅披露消费者判断或行动必需的事实，不复制常规成功控制证明或无关敏感资料。authoritative task 不可达=>`REPORT_CHANNEL_UNAVAILABLE`，不得称已交付。协议本身不授予通信权。

无 ACK。协作期间的等待与组织切换只取本模块 PR_TASK_SCOPE_AND_FORBIDDEN；本块只处理终态交付。未知结果不自行转成成功或重试许可。

交付与环境/起点选择服从当前用户决定和宿主实际合同。仅宿主成功信号证明送达。明确策略拒绝不得绕行；超时、未知或模糊结果停止受影响发送，不盲查重发。仅宿主明确可重试且当前授权/身份仍有效时，按其有界合同重送同一结果，不重做 Review、建 ACK 链或投递台账。

`TERMINAL` 绑定 proposed consumer 与真实 Controller escalation。仅 Controller-owned unique next action 或 `PR_DYNAMIC_ROLE_DIRECT_ISSUANCE` 全部 explicit exceptions 可设 `controllerEscalationRequired=true`；否则 `UNNECESSARY_CONTROLLER_RELAY`。fresh package、temporary role/resource change 不是升级理由。

routing message 须带 host-authenticated task/sender identity+Controller epoch/envelope，拒 stale epoch；authenticity 不可证时仅是 untrusted locator，identity-dependent transition fail closed。
成功控制证明保留在对应证据，普通正文只呈现决策所需结果；失败、未知、跳过和中断仍明确报告，不因精简而吞掉。
<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:END -->

<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:BEGIN -->
首次安排或影响选择的新证据出现时，在同一次组织决定中按能力需求（专业与上下文理解、隐藏约束、跨域判断）先选足够模型，再按推理工作量（推导链、约束耦合、状态组合、验证深度）选该模型支持且足够的 effort；综合风险、可验证性和执行、工具、恢复、交接、审查、返工总成本。

首次用任务特征、同类证据与可用资料预估；后续修正同一判断。具体难点可直接选较高 effort，不要求先失败；资料、工具或组织瓶颈先改善条件，不默认升档有效。profile、model、effort 与责任独立，CRITICAL 不自动升档，机械任务优先脚本。通用判断不指定供应商模型或档位。

健康配置正常复用，不逐动作复评或批量切换在途配置。长期身份变更、独立性与动作权限保持原门；宿主实际接受由 HOST_CODEX 核对。任务只记录实际选择及必要理由/新观察，不复制指引，不新增资源表、固定复评、样本配额或实验门。
<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:END -->

<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:BEGIN -->
拥有的仓库字节变化达到候选、接受或交付边界时，Owner在原任务说明产物及Git去向：READY（候选/路径、证据、实际closer）、DEFERRED（理由、触发、负责任务）或EXCLUDED（理由）。尚未闭合的责任在后续 NONE/USER_RESPONSE 仍有效；全程只读豁免。只有接收人确有下一动作才发送一次结果；不普遍新建Git任务。Review/接受不证明Git就绪，此处不授予Git或后台动作。
收尾先 FINALIZE 文档/产物动作，再以当前卡单对象 CONTROL_WRITE 更新任务；不要文档与当前卡混写后靠恢复前像重试。每步仍核对原包、来源和 postimage，第三方 task drift 不豁免。Owner消费结果时替换过时当前事实，详细历史及证据只引用原载体；无新结果不写卡。

CLOSED 必须有 Closure outcome=SUCCESS / CANCELLED / SUPERSEDED、关闭依据与产物/Git去向，writer/reviewer/authorization 均释放。SUCCESS 完成适用验收；CANCELLED/SUPERSEDED 保留实际未完成项及决定/承接任务，不能冒称成功。新关闭按上述字段表达；未带Closure outcome的既有卡继续按legacy成功验收校验，不批量迁移，也不能借旧格式绕过新关闭合同。等待或阻塞保持 active。任务事实关闭、权限释放与宿主侧边栏归档分开；仍可能同候选修复的健康执行者可保留。正常消费时由实际消费方按已有授权归档无后续的临时任务，未授权则列可归档项；长期Owner与明确续作保留，不为归档往返恢复或新增清理回合。

原任务自然收尾一次交代材料保留、归档、清理及未解依赖，复用产物去向；执行者按 TOOL_CONTRACT 的统一材料生命周期处理已知临时集合和正式证据归属，不逐文件新建状态或另开清理回合。最后消费者可同批提取已有请求、工具、加载、统筹、返工和用户介入观察；缺数据保留限制，不另设费用证明门。

<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TASK_IMPLEMENTATION_JUDGMENT:BEGIN -->
在已接受目标、精确授权与保护范围内，先理解真实机制、直接消费者及失败恢复；有多条实质可行路线时比较现有实现、标准库/平台、已授权依赖和必要新代码的正确性及总成本，选择最小充分方案。复用不安全或适配代价更高时可有据换用，不为假设未来新增机器。成果类别及验收以用户目标为准，分析、测试或原型不替代请求的正式产物。普通低影响修复不新增写前审查或表单；重大契约/风险/范围冲突只停止受影响链。健康已审结论复用，实际新增证据才重开。MICRO同样遵守这些原则，不因此加载完整任务维护程序。
<!-- AIW-REQUIREMENT:PR_TASK_IMPLEMENTATION_JUDGMENT:END -->
