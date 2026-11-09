# Task 与 scope contract

<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:BEGIN -->
当前任务、主体、决定、对象和适用配置/仓库与有效包一致，且独立checker及ADMIT通过，即可开始已授权动作，无第二次START；缺失时只保持已知安全读取并报告具体条件。

仅在新分派或组织事实变化时判断：同一原未完成成果或同一审核的有界修复复审，边界未变且原actor仍合格、上下文健康时可REUSE；新有限成果、新独立审核默认新建可见会话，分别以outcomeMatch=false或requiresDistinctOutcome=true、requiresIndependentContext=true表达真实情况，沿现有ROUTE取得MUST_NEW。其他确需独立上下文、生命周期、写入隔离或原会话不可用资源时同样MUST_NEW；项目、责任、授权、保护、外部路线或用户决定实变则处理相应BLOCKED。已关闭/归档的有限会话不默认恢复改名承接新成果；原事必要补正可回原会话，历史参与者可另承担其他工作，但不能审核自己的贡献成果。健康续作复用原组织决定；长期保留须有真实持续职责。临时writer不能为签包便利升为Owner；原Owner可一次预授权有界写测、交审及修复复审，实质扩面或决定变化才回Owner。

先满足质量、风险、独立性、隔离和持续时间，再比较直接执行与委派双方的上下文、模型往返、工具、交接、验证、集成、返工和用户介入总成本。可依据任务和同类证据定性判断，不要求新增实验或事前证明节省；无明确收益则DIRECT_SELF，机械重复优先现有脚本。需要独立成果、审核或持续独立生命周期时使用可见APPLICATION_TASK；当前Framework不支持内部子agent，包括内部Reviewer，不因此把普通工作全部委派。

同次组织决定选足够的资源及适当环境/起点，分别遵循PR_TASK_RESOURCE_SELECTION和HOST_CODEX。委派一次给齐目标、范围、候选、验收、原始用户来源、权限材料和直接消费者；不得交空任务等接收者反向索包。新任务标题用简短“职责｜主题”，职责/主题实变才更新显示；标题只描述已成立职责，不改变权限、Owner、任务范围或贡献历史，不扫描无关聊天或逐轮附加状态。
<!-- AIW-REQUIREMENT:PR_TASK_LAUNCH_AND_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:BEGIN -->
实际LAUNCH、ROUTE、TERMINAL、MESSAGE、HANDOFF或HOT_STATE转换前，按TOOLCHAIN的WORKFLOW_ROUTE_RESOLVE核对当前项目/任务、包、用户决定和宿主真实身份包络；与FINALIZE共用的转换消费其绑定结果，不重复全链。普通项目以明确controlRoot绑定权威，实际Git或GIT_WORKTREE动作另核所需仓库/执行目标事实，不为纯非Git转换虚构Git top。

消息正文、历史摘要和自填身份不能替代机械事实。必需输入缺失或冲突时停止该转换；返回值只证明机械路由检查，不授予动作或外部权限。精确字段、直接JSON/文件调用及临时生命周期唯一取TOOL_CONTRACT，临时输入不是项目状态或授权消费台账。
<!-- AIW-REQUIREMENT:PR_WORKFLOW_TRANSITION_MECHANICAL_BOUNDARY:END -->

<!-- AIW-REQUIREMENT:PR_TASK_COLLABORATION_BOUNDARY:BEGIN -->
协作期间不以wait_threads、wait_agent或反复读取聊天、状态、日志等待其他会话。有安全工作就继续，没有就结束当前轮，真实结果送达后续作。宿主要求新建后首次取得进度时，按HOST的一次有界观察执行，未就绪不转为持续等待。已启动的当前命令/测试可等待自身必要结果；用户主动查询可单次读取现状。

生产/自测转入新的交审分派是组织事实变化，按PR_REVIEW_ROUTE_PREPARATION处理真实新意图、选择及准入。相同目标的健康正文和证据可复用；没有新分派不重复组织选择，不重做完整恢复或制造纯记账回合。
<!-- AIW-REQUIREMENT:PR_TASK_COLLABORATION_BOUNDARY:END -->

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:BEGIN -->
TASK_OWNER是当前有限成果唯一负责人，负责目标明确、实施组织、验证、接受和产物处置；成果闭合释放活跃责任，历史签认及明确移交的未解义务保留。父任务只在确有持续成果及协调责任时保存范围、下级入口、资源界限和升级条件；父子关系只导航，不授跨Owner签发权。真实跨任务依赖由责任人直接协调，项目级决定才路由Controller。角色整理须把未解工作交给实际成果、规范、知识或协调责任，不能丢回主控。

项目预授权直接模式下，普通工具调用本身不单独创建任务卡；已有有限成果时归入原任务，无适用任务的有界用户工具请求可用TOOL_CONTRACT的PROJECT_EXTERNAL取得当前必要规则后直接调用。该加载上下文不建立Owner、writer或逐次执行许可，不为省卡冒用已关闭任务。真正的源码、控制面、审核、接受、发布或其他有限成果责任仍按各自任务合同处理。

当前任务保存目标与实际增量、验收场景、Owner/actor、精确范围/排除、候选与证据、权限、当前结果/阻塞和唯一下一动作。方案核对根因、当前机制、直接消费者、能推翻错误方案的验证、重要失败恢复及重大假设；已有充分结论直接引用。实现取舍取PR_TASK_IMPLEMENTATION_JUDGMENT，专业材料按实际要求读取，不全量加载目录或凑反例。

Owner负责成果，Work route actor负责当前生产路线，action grantee只承担有界动作；纯Review不改变Owner/Work route。卡片的唯一route语法、原子修改及旧格式迁移取TOOL_CONTRACT、任务模板与MIGRATION_MATRIX，不能从Owner、包或标题猜actor。普通任务默认SAME_ROOT；确需已授权隔离时，以原任务绑定的不可变descriptor选择GIT_WORKTREE。唯一controlRoot保有任务、pin、采用及恢复，executionRoot承载指定候选；复制的旧控制目录不成为新权威。目标缺失、根关系/HEAD/保护漂移只停止受影响动作，重新绑定须先完成原动作并取得当前明确范围；不自动移除worktree。

同一目标、范围、质量及资源边界内的可预测步骤组成可验收有界批次。Executor自主选择方法、工具和顺序；必需诊断、依赖和局部修复不拆成新决定。Owner按完整成果及实际不确定性预授足够的有限写测续作；次数用于防失控，不以固定小轮数代替任务判断，刻意只授线性计划时保留其实际理由。Executor依据原始失败、实际后像和最短验证判断进展：范围内、许可有效且下一修正有可检验依据时直接续作；重复同根因而无新证据时先诊断或停止，方案/能力/资源及权限边界改变时交实际责任者。进展判断不扩权，不为每轮新增审核或模型请求。停止后由Owner消费已有失败、候选和未完成项，只重绑失效或新授部分，不重建健康任务或清零历史。具体分支、计数和收据只取TOOL_CONTRACT。分析、原型、自测或局部成功不能替代用户请求成果。明确扩展更新实际范围和授权，可独立交付的新成果取得自己的目标、验收和关闭责任；紧密相关且可共同验收的工作可合批，不要求一功能一卡。同一未完成成果的健康聊天可续作；新有限成果及新独审默认新会话，不能靠复用聊天扩大旧目标和权限。原事必要补正、同审有界修复复审及真实持续职责按PR_TASK_LAUNCH_AND_ROUTE处理。并行/隔离按真实收益选择，共享冲突只限制冲突写集。

Controller和Owner可因质量、能力缺口或有据总成本收益安排有界专家，不以任务类别、profile、耗时或先失败作门槛。设计给结论、依据、取舍、适用条件及实施/验收；调查给根因、证据、修正和验证；困难实现可由足够能力者直接完成。Owner必须理解并消费结论，按需组织执行、合格专业审核或明确受托接受。设计/实现贡献者不能充任同成果独立Reviewer；普通简单任务不强制专家。仅实质新事实重新咨询。

Owner在正常结果消费时替换唯一任务卡的过时当前事实，候选不投为已接受，详细历史/失败引用原件。writer/reviewer/授权变化留卡；STATUS仅随稳定阶段、长期责任、保护或唯一下一动作变化，index仅随lifecycle/routing变化。无新结果不写卡，不为可变卡建字段manifest；并发沿原lease/package约束，保护/不可变对象仍整体验证。涉及身份组合转换先按RECOVERY恢复原事务；收尾取PR_TASK_CHANGED_OUTPUT_DISPOSITION。
项目显式qualityAssurance1按完整稳定成果subject并集选择SELF_CHECK/RESULT_REVIEW/RESULT_ACCEPT，规则/格式和准备唯一取TOOL_CONTRACT。缺省LEGACY，启用缺plan2不得降为无门；真零不伪造证据，用户/专业阶段和真实失败保留。qualityBinding是当前选择投影，不授动作、跨仓、专门门或接受权。

已采用支持C的来源后，Owner通过只读QUALITY_PLAN_PREPARE核稳定subject与已有持久要求，在原单卡CONTROL绑定plan2并保额外用户/专业阶段；真实冻结和结果消费补实际候选/证据。按当前policy变化只重绑下一实际动作，不批量迁关闭卡；SUCCESS消费同一计划全部真实阶段，取消/替代保实际未完成，原归档写序及责任释放保持。

<!-- AIW-REQUIREMENT:PR_TASK_SCOPE_AND_FORBIDDEN:END -->

<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:BEGIN -->
终态仅发一次 compact terminal：`READY`=下一 authorized phase 可开始；`COMPLETE`=requested outcome+required gates 全完成；`BLOCKED`=真实 boundary 阻止继续；`RANGE_GATE_REQUIRED`=缺 deterministic scope input；protected-path exception=exact exception+owner route。发送前绑定实际授权、精确消费者与允许内容；结果含裁决、必要 finding/原因/影响/最小修正及证据定位与上限、精确阻塞和 unique next action。认证 identity/Controller epoch 留实际工具包络，普通正文仅披露消费者判断或行动必需的事实，不复制常规成功控制证明或无关敏感资料。authoritative task 不可达=>`REPORT_CHANNEL_UNAVAILABLE`，不得称已交付。协议本身不授予通信权。

无 ACK。协作期间的等待与组织切换只取本模块 PR_TASK_COLLABORATION_BOUNDARY；本块只处理终态交付。未知结果不自行转成成功或重试许可。

交付与环境/起点选择服从当前用户决定和宿主实际合同。仅宿主成功信号证明送达。明确策略拒绝不得绕行；超时、未知或模糊结果停止受影响发送，不盲查重发。仅宿主明确可重试且当前授权/身份仍有效时，按其有界合同重送同一结果，不重做 Review、建 ACK 链或投递台账。

`TERMINAL` 绑定 proposed consumer 与真实 Controller escalation。仅 Controller-owned unique next action 或 `PR_DYNAMIC_ROLE_DIRECT_ISSUANCE` 全部 explicit exceptions 可设 `controllerEscalationRequired=true`；否则 `UNNECESSARY_CONTROLLER_RELAY`。fresh package、temporary role/resource change 不是升级理由。

routing message 须带 host-authenticated task/sender identity+Controller epoch/envelope，拒 stale epoch；authenticity 不可证时仅是 untrusted locator，identity-dependent transition fail closed。
成功控制证明保留在对应证据，普通正文只呈现决策所需结果；失败、未知、跳过和中断仍明确报告，不因精简而吞掉。自检失败按原有限许可与当前候选续作，具体分支与证据合同取 TOOL_CONTRACT；无许可、耗尽、不完整或停止只结束该动作，Owner 保留未完成成果责任。安全原动作重跑不制造空写入、虚假成功或审核 finding；历史失败保留，成功自查不替代独立审核。
<!-- AIW-REQUIREMENT:PR_FINAL_OUTPUT_CURRENT_RESULT:END -->

<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:BEGIN -->
首次安排或影响选择的新证据出现时，在同一次组织决定中先按专业/上下文理解、问题识别、隐藏约束与综合判断需求选择足够模型，再按推导链、约束耦合、状态组合和验证深度选择其支持且足够的effort；同时比较执行、工具、恢复、专家协调、审核和返工总成本。角色/profile/model/effort与权限分别判断，通用核心不指定供应商型号。

初始依据任务特征、同类证据和已有材料预估，具体难点可直接选足够资源，不要求先失败。资料、工具和组织瓶颈先改善条件，升档不保证解决问题。机械重复优先脚本，CRITICAL不自动升档。

按委派后本人持续承担的职责评估：Controller负责项目统筹与公共/跨域/资源决定，Owner负责当前有限成果的规划、证据消费、整合和收尾。双方都须足以理解目标、冲突及专业证据，不能机械转抄专家结论。困难局部可委托有界专家；整项成果持续困难且拆分无净收益时，也可由足够能力Owner直接承担。Owner持续整合不足可在该成果有界调整；单个难题不自动永久提高Controller配置，其常态策略只随持续项目职责变化调整。

健康配置复用，不逐动作复评或批量切换在途资源。人类临时覆盖遵守原用途、期限/退出条件及后续决定，不静默变成长期默认。身份变更、独立性和动作权限各守原门，实际接受由HOST核对。原任务只记录实际选择、必要理由和新观察，不新增资源表、固定复评、样本配额或实验门。
<!-- AIW-REQUIREMENT:PR_TASK_RESOURCE_SELECTION:END -->

<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:BEGIN -->
拥有的仓库字节变化到候选、接受或交付边界时，Owner在原任务说明产物与Git去向：READY含候选/路径、证据和实际closer；DEFERRED含理由、触发和责任；EXCLUDED含理由。未闭合责任在后续NONE答复仍有效，全程只读豁免。Review/接受不证明Git就绪，不普遍新建Git任务；仅实际接收者有下一动作才发送结果。

先FINALIZE文档/产物动作，再以当前卡单对象CONTROL_WRITE更新任务。普通当前卡与其他对象混合写集仍拒绝；当前卡关闭并物理归档仅允许普通纯CONTROL_WRITE的精确active+同basename archive两对象：active存在时核原包及前像并准入，先完整保存、读回和实际验证闭合archive，再复核原active后删除，原FINALIZE消费已验证的实际archive路径，正文ID及原逻辑准入保持。已有相同archive可复用，不同历史仅按明确原像处理；中断留两张有效卡或完整archive可沿原动作补完，不造归档事务/全局locator。其他合法文档批次、schema1真实责任转换及专用根采用按自身合同；不泛化混合写、missing或第三方豁免。

CLOSED写明SUCCESS、CANCELLED或SUPERSEDED、关闭依据、产物/Git去向和未解义务承接，并释放writer/reviewer/动作授权。SUCCESS满足适用验收；取消/替代保留实际未完成项与决定，等待/阻塞保持active。当前ACTIVE维护任务移动另一张原已CLOSED卡时，精确active前像必须等于同basename archive实际后像，原正文ID、闭合/释放、当前纯CONTROL移动权限及保护成立；只证明原字节移存，不重新验收后来演进的产品。卡改字、原非CLOSED、未释放、目标冲突或原件不足仍拒绝该分支；当前任务新SUCCESS继续完整验收。旧closure decision/acceptance plan进入原retention，移存不追认真证明有效或令材料到期。旧卡按其原兼容检查，不批量伪补成功。任务卡关闭/物理归档、责任释放和宿主会话归档分别核对。有限成果已交付、原结果已被实际消费且会话无后续职责时，由实际收尾责任人在已有权限内调用宿主归档该会话，并核对真实返回；只写CLOSED、释放授权或改标题不算会话已归档。待验收、仍有同项返修或真实长期职责时保留。权限缺失、失败或UNKNOWN如实保留并交实际责任者，不宣称已完成，不批量扫描或操作历史会话。

原任务自然收尾一次处理正式材料持久归属、有效引用、已知临时集合和未解依赖，生命周期取TOOL_CONTRACT；不按目录大小/年龄/关闭状态推定可删，不另开清理或统计回合。已有请求、工具、加载、协调、返工和用户介入数据可由最后消费者同批提取，缺数据保留限制，不设费用证明门。
<!-- AIW-REQUIREMENT:PR_TASK_CHANGED_OUTPUT_DISPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TASK_IMPLEMENTATION_JUDGMENT:BEGIN -->
在已接受目标、精确授权与保护范围内，先理解真实机制、直接消费者及失败恢复；有多条实质可行路线时比较现有实现、标准库/平台、已授权依赖和必要新代码的正确性及总成本，选择最小充分方案。复用不安全或适配代价更高时可有据换用，不为假设未来新增机器。成果类别及验收以用户目标为准，分析、测试或原型不替代请求的正式产物。普通低影响修复不新增写前审查或表单；重大契约/风险/范围冲突只停止受影响链。健康已审结论复用，实际新增证据才重开。MICRO同样遵守这些原则，不因此加载完整任务维护程序。

通用规则归版本、项目标准归项目、方案归任务、私有算法归实现。只有真实外部消费者、兼容、安全、确定性或外部性能承诺需要，才把实现机制提升为公共合同；测试方便不是理由，引用不形成第二权威。声称实现已接受契约时，在原任务绑定当前权威、负责接点、直接消费者/测试与证据；来源实质变化先重绑。允许轻量 @design-contract <locator> 定位原设计并保留项目已有合理标记；不复制语义、哈希或通过状态，不声称标记证明实现一致，不要求全仓补标、台账或扫描。技术事实先有界查证，只把实质目标、范围、权限或风险取舍交用户；中间回答不是整案授权，仍有效决定不重复确认。重大冲突与必要用户取舍已解决、剩余假设有界且可验证和恢复时，方案足够就绪，沿现有授权推进；未处理重大冲突只停受影响链。按实际 Review profile 保留必要审核，普通低影响修复不新增写前审核阶段。

变更实际影响现行契约或说明时，在原任务定位受影响完整正文、维护者、基线和直接依赖，保留条件、例外及并发有效变更，形成合并后候选；增量不代替原文，规格预期不代替实现证据。必要规范候选随成果在适用审核和接受前准备，Owner按原合同接受精确候选；后续必要写入、生效、发行或采用仍需对应授权。落地前复核基线，新增语义或冲突须重绑候选并复核受影响部分，不以“同步”发布未审变化。未完成本批承诺的规范维护不宣称该项完成；合法后置事项保留真实前置和原责任。按实际影响触发，不强制新建规格、加载方法或全库扫描；候选已在最终目录时不要求接受后再复制。可选软件表达见[软件行为规格与变更](knowledge/software/BEHAVIOR_SPEC_CHANGE.md)。

遇真实失败、专业不确定性或知识缺口时，原参与者在原任务先区分已知缺陷、使用偏差、资料/能力不足和规则冲突；已有知识充分则直接应用，基础不足可按目标系统补学。按欠缺的判断选择内容与来源，分清实际阅读、专业解释、待验建议和真实效果；关键冲突或能力缺口只限制受影响决定。将依据落实为具体判断/动作、事前预期及对应验证，由Owner消费结果，按需安排有界专家及具备专业/工具能力的验证者，独立审核仍满足原独立性。已有规则充分则留有价值案例，确有义务缺口才沿原规则变更门修订；沉淀保留条件、失败、未知、维护责任和下次入口。上述任务责任不依赖启用KNOWLEDGE_REFERENCE或加载METHOD；不增加普遍研究表单、常驻队伍、每题联网或额外模型请求。完整可选方法见[问题驱动改进](knowledge/cross-domain/PROBLEM_DRIVEN_IMPROVEMENT.md)，仅在实际需要时读取。

具体软件设计、实现和测试方法由项目选择的完整标准提供；Framework随包可选正文见standards/README.md，未采用不自动进入规则集合。生产和审核对同一成果消费同一适用专业要求，职责程序仍按各自角色选择。
<!-- AIW-REQUIREMENT:PR_TASK_IMPLEMENTATION_JUDGMENT:END -->
