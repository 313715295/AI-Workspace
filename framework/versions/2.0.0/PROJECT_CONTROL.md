# Project control

<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:BEGIN -->
项目自身project.json.frameworkVersion是唯一版本选择权威；Framework不设全局默认或消费者登记。首次注册按人类明确采用目标，指定真实项目目录、版本、项目及Controller身份，验证目标资格、固定来源、starter、运行条件和安全控制面。默认只接受合格STABLE；首次CANDIDATE试点仅沿目标明确支持且实际合格的注册分支。

原始用户授权与后续收窄取AUTHORIZATION_MODEL。导航模板不独自授权；新注册在明确采用决定下生成已批准工作约定，升级保留项目用户拥有的授权原文及区外内容，不重复确认有效决定。

注册只物化所选项目必要控制入口及已准备的真实有限首卡，不发明持续Root占位任务或后续无限写权。普通项目不要求Git、不自动git init；真实本地Git的runtime忽略投影及Maintenance特殊拓扑分别按根PROJECT_ADOPTION验证。具体schema、预览/Apply、REGISTER origin、完成证明和失败恢复唯一取该根合同及ADOPTION_PROFILE。预览和基础控制面成功分别如实报告，不等同后续业务、宿主加载或所有要求承接完成。
<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:END -->

<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:BEGIN -->
升级绑定明确目标项目/版本、当前责任与受支持起点，双方固定来源及实际兼容接入工具分别核对；不按版本名称猜兼容。保留项目身份、布局、保护、能力和用户自定要求，只有声明且获授权的对象进入写集。旧语义无法可靠投影时在原准备边界解决真实差异，不把旧请求变为新执行意图。

按根PROJECT_ADOPTION先有限scope导航，再原健康runtime DISCOVER、目标完整投影PREPARE与全文读取、真实原ADMIT、精确升级包Apply、实际完成证明及原FINALIZE。目标预检不能代替旧准入、项目语义判断或写许可；配置变化不让无关旧动作续权。原规则和旧/目标义务按该事务完整承接。

中断沿原授权、原前后像和仍健康的兼容工具继续或回退，第三方字节拒绝覆盖；部分文件变化、transactionComplete字符串或新DISCOVER不代替真实完成。原过程收口后才使用新入口开展工作，仍被当前state引用的恢复材料保留；已完成历史任务可正常更新/归档。

精确schema、旧起点、REGISTER/REFRESH/major-origin、旧预算repair及中央纠正映射转换只取MIGRATION_MATRIX与根PROJECT_ADOPTION相应分支。当前规则大小不设配额，真实旧失败不改写。升级不搜索或改其他消费者，不修改产品来源，不执行Git或宿主全局安装。
<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:BEGIN -->
PROCESS_REQUIREMENTS_RESOLVE是唯一过程组合入口：组合当前固定原生规则、仍有效项目纠正及永久项目规则，各自保留来源权威；DISCOVER不授权，ADMIT与FINALIZE分别消费实际准备/结果。项目policy及规范custom按真实职责可并存，但同一义务只有一份有效完整正文，重复/冲突不能静默覆盖。

先验证完整有效集合、来源许可与保护，再选择本次命中正文。项目可直接采用使用者维护的完整文档、唯一章节或已声明规范单元及其完整有序依赖；不得以摘要代规范、扫描普通链接扩依赖、越过来源许可或因未命中就忽略缺失的有效成员。SOURCE读取不授写权。

R2规范单元模式将物理raw观察与完整规范身份分开，绑定公共条件、例外、selector、义务及有序依赖；旧整文件模式仍严格。正文、采用、许可或完整闭包实变须重绑，不切最新来源救旧动作；同文件无关位置变化不冒充规范变化。精确字段/算法及FULL/REUSE显示取TOOL_CONTRACT和RECOVERY，固定运行包、授权对象与写入前像的整文件校验不放松。

AI根据项目原决定准备policy/sourceBindings，用户无需手写JSON；直接引用已经可用，精炼、拆分和重排均为可选。替换规范须同次退出旧项、加入完整新项并完成原修改/验证门。随包standard/preset只提供来源，展开后不构成第四权威，也不自动抑制原生治理或更新其他项目。固定/跟随边界由原项目决定表达，不新增后台同步或中央采用登记。

三源使用同一结构轴和四维facets。确定事实不符先排除，UNKNOWN只在其他已知边界内保守选择；提示词不能推翻实际action/role/scope。详细选择和格式迁移由TOOL_CONTRACT统一定义，不另设自然语言意图服务。
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:BEGIN -->
## Controller lifecycle

machine truth 是 `controller.json`。handoff 冻结 old/new identity 与 epoch；有授权时先写 hot projections，最后写 Controller object，并以 `TAKEOVER_COMPLETE` 结束。old read-only grace 可以为 recovery 保留 bytes，但不保留长期 routing authority，也不授权 cleanup。

本块适用于此刻实际进行的 Controller 身份／epoch 移交及其 hot projections；规范语义提示应表达主控交接、接任、切换或任期变更。角色名、当前状态整理、普通任务交接和仅调整 effort 不形成 Controller 移交；取消或条件性未来交接仍按 IntentEnvelope 的当前动作归一化，语义未明则保守加载并核对。
<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:BEGIN -->
## Knowledge capability

Knowledge reference 仍为 optional、project-local、non-authoritative。`DISCOVER` 返回 compact metadata；`QUERY` 在 request scope 校验显式选择的 IDs，不设统一数量配额。只读 changed-authority impact check 帮助 owning task 在正常 acceptance boundary 刷新或标记 stale entry。不增加 background service 或 automatic write；Knowledge 不能改变 product facts、task authority 或 Framework pin。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:BEGIN -->
项目采用加载目标starter和任务合同，不批量重写已有任务或会话。当前成果的Owner、执行路线及临时主体按TASK_AND_SCOPE绑定；签发与真正Controller例外只取AUTHORIZATION_MODEL，不因新包或临时资源变化强制主控中转。

项目结果消费由当前有限成果责任人直接完成，项目持续事实由Controller维护。发现任务或Controller的在途转换标记时，先沿RECOVERY_CORE和TOOL_CONTRACT恢复原事务，不能用新的卡片或授权追认未闭合写入。
<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:BEGIN -->
项目纠正的安装、修订、暂停、恢复和卸载独立于Framework升级。corrections保存当前项目权威；效果、总成本、副作用或用户决定变化均可触发处置，不以Framework吸收为前提。ACTIVE或原兼容的未声明生命周期记录参与选择，PAUSED/UNINSTALLED作为不生效历史保留，不用不可能命中的selector假停用。

操作覆盖纠正实际引入的整组委托、导航、policy、配置、专属对象及正文，按真实安装归属处理，保留后续独立决定。共享/重叠/依赖或未知历史只阻断受影响对象；未知效果不能声称已逆转，也不维持已明确停用的旧正文有效。暂停可恢复，卸载不被注册/升级自动复活。

完整旧record及决定形成不可变历史；安装证据证明效果归属，history证明正文/状态演进，事务证明恢复，三者不混称。正文修订与效果替换同一投影完成，不能拆作先卸后装的两个事务或补造历史前像。无归属旧记录可独立修订/停用并如实保存未知；用户明确当前移除的效果记录本次真实前后像，不冒充历史安装。

按根PROJECT_ADOPTION“纠正整组生命周期”预览全部精确对象、检查保护、准入并Apply，完整三源不合法则整组回滚；中断按原事务及当前许可恢复，第三方混合字节拒绝。FILE/TEXT、history/installation路径和REGISTER_HISTORY等字段只取该唯一操作合同。原审核、接受和保护边界保持，正式历史与证据不按临时收据清理。
<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:BEGIN -->
通用吸收须对照原始问题、完整有效义务和适用边界，以实际规范、行为验证及独立Review支持；规则ID、近似文案、changelog或对象hash本身不证明覆盖。Framework发布通用行为、边界、验证和迁移说明，不登记消费者纠正ID或hash来抑制项目规则；项目材料默认不外传。

项目采用时自行判断：完整覆盖退出重复，部分覆盖保留增量，未覆盖保留，冲突明确解决，证据不足如实保留未知。旧有效、旧抑制及停用历史都要承接；需要新版本才能成立的退出与目标运行绑定同一采用事务，失败回到匹配旧包及完整前像，不覆盖后续独立修改。工具只检查精确投影，不能替代语义判断。

新运行只按当前记录及生命周期选择，不建中央/本地吸收台账。旧中央映射退出的受支持转换取MIGRATION_MATRIX与根PROJECT_ADOPTION，原完整记录和决定保留。暂停/卸载与原生吸收分别判断，不以停用证明Framework已经覆盖。
<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:END -->
