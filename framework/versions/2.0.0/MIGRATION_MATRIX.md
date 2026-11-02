# Framework 2.0.0 migration matrix

这是目标版本的迁移合同，不是项目采用记录。开发候选仍须完成整版验证、独立 Source Review 和接受；目录存在、隔离测试或本文不能授予采用资格。

| Source | Target | 必需行为 |
|---|---|---|
| new project | explicit stable 2.0.0 或合格固定候选的显式首次试点 | 由目标 ADOPTION_PROFILE 创建当前 project7、corrections3 和 process-policy3；候选首次注册同时写入真实有限首卡和 schema7 REGISTER origin；普通项目无需 Git，Maintenance 双仓拓扑与真实 Git 动作另验；只投影 managed AGENTS，不安装宿主 Skill |
| 健康 project4 / 1.16.0-snapshot.12 | 已审、固定命名的 2.0.0 local candidate | 使用下述唯一有界根桥；普通和 Maintenance 均由真实旧 runtime 准入，目标投影校验后以原过程收口 |
| 其他旧来源或未固定候选 | 2.0.0 | 不支持该跨版本入口；不猜测兼容性、不热改旧包、不建立任意版本迁移矩阵 |
| 健康 project5 / 2.0.0-snapshot.3 | 已审固定的当前 2.0.0 格式 | 使用兼容固定根工具完成原准入及格式迁移至目标 project7；不变任务只读绑定、不进入写集，采用 state 最后写入 |
| 健康 project6 / 2.0.0-snapshot.15 | 已审固定的当前 2.0.0 格式 | 按目标 ADOPTION_PROFILE 的精确 runtimeStarts 经原过程迁移至 project7；真实 REGISTER / UPGRADE / REFRESH 起源和原完成证明分别验证，不把采用 state schema 当作 project format |
| 健康 project6 / snapshot.16 的真实 REGISTER，或 project7 / snapshot.17 已完成采用 | 已审固定的后续 2.0.0 分发 | 16 按真实配置6经 FORMAT 迁移至7，保原 REGISTER journal 及原 state 前像；17 沿实际起源同 pin 刷新。两者均须原准入及原 FINALIZE，采用 state schema7 不代表 project format7；运行源、目标源和执行工具分别绑定 |
| 健康 project7 / 2.0.0 | 相同目标 | 按当前配置、任务和发行绑定复核；不得把历史安装内容当作当前项目规则的永久锁 |
| managed AGENTS 模板更新 | 2.0.0 | 精确绑定当前整文件前像，管理区只投影目标导航；承接当前真实授权原文、项目限制及区外字节，未知混合 custom 在原准备中解决，不猜删或扩大授权 |
| 缺 current actor-bound active task | 2.0.0 | 拒绝实施；不从 Owner 或聊天推断 actor，不批量重写其他任务 |
| 有效规则、纠正覆盖或阶段接受无法自动映射 | 2.0.0 | 项目 Owner 提供当前任务/规则的明确映射并独立审收；不删除记录、伪造完成或以 Framework 中央登记代替项目决定 |
| 未知对象、第三方字节、保护范围或来源漂移 | 2.0.0 | 写入前拒绝；中断后仅处置原授权精确前后像，保留第三方对象 |
| unavailable backend/runtime/platform | 2.0.0 | 拒绝依赖动作，不自动下载、安装或切换 backend |
| downgrade | older release | 无自动降级；已完成事务不能通过恢复入口反向切换 |

项目拥有配置、标准采用、知识来源及升级决定。当前 nav3/TC4 由项目 AGENTS 直接导航固定 Bootstrap，不要求 Router Skill；旧 nav1/nav2 固定项目及在途事务仍使用原入口，版本 host 文件只作历史不可安装说明。旧 Skill 的有条件退役仍需独立宿主权限。

## snapshot.12 → 2.0 原过程桥

首次候选注册采用目标 ADOPTION_PROFILE 声明的 project7 / corrections3 / policy3；旧 project4 / snapshot.12、project5 / snapshot.3 及 project6 / snapshot.15 只沿各自精确声明的起点迁移。首次 root REGISTER 使用原始采用目标形成的有限首卡，并产生 schema7 REGISTER-origin state；不伪造升级 actor/task/旧 objects。正常加载校验原 REGISTER journal 的 COMPLETE、项目根、registrationId、原投影 state 后像及分发绑定；SELF_PROJECTION_BOUND 避免 journal/state 双向哈希循环。后续 same-pin 7→7 刷新保持 REGISTER origin，绑定真实原 journal identity，使用独立 refresh journal 和当前任务。完整 PREPARE、原 ADMIT、schema3 Apply、原 FINALIZE 及逐点恢复复用既有根过程链；原 schema6 采用起源与 schema7 REGISTER 起源继续分别验证，配置格式6→7不按采用 state 的schema泛化。任务归档与当前规则合法演进不改写历史起源。

入口仍为根 scripts/upgrade-project.ps1。先取得经独立审核的根工具及固定目标分发；保持旧 runtime 原字节和可恢复性。操作参数与同命名包流程见根 PROJECT_ADOPTION.md。

1. **范围导航。** 提供项目、Controller、目标和当前 actor-bound task，但不提供 CurrentProcessInputPath 时，只读返回 UPGRADE_SCOPE_ONLY 和 OLD_DISCOVER_REQUIRED。这一步仅声明路径，不生成后像、不读取可选知识索引正文、不授予写入。项目按声明范围和真实保护集合构造旧 CONTROL_WRITE 包。
2. **旧 DISCOVER 与目标准备。** 在未修改的 snapshot.12 执行真实 DISCOVER，读取规则，保存原 ADMIT 输入。根入口 PREPARE 绑定该输入，在隔离目录组合目标 project7、Controller、任务、Bootstrap/AGENTS、policy3、corrections3 和实际标准来源；返回精确前后像、两端分发身份及目标 fullText。范围或来源不合法即停止。
3. **真实旧 ADMIT。** 读取目标完整规则并满足两端准备义务，提交 preparation identity。根 ADMIT_ACTION 只调用原健康入口完成一次真实旧准入，保存原输入和目标准备；不能由新 DISCOVER、目标预检或自报 PASS 补造它。
4. **schema3 Apply。** 原批准包只作受限结构投影：保留决定、主体、任务、范围和前像，增加目标 canonical/manifest 与全部后像。Apply 重验原准入和当前投影，不扩大权限。先写旧 state 的恢复链接，随后写受控对象、目标 state，当前任务最后；完整读回后只登记事务 COMPLETE。
5. **原 FINALIZE 与新恢复。** 原 FINALIZE 核对原准入、两端固定包、原/目标义务、全量后像、未变化来源和已完成事务；之后读取新 AGENTS / Bootstrap 和目标命中规则的完整正文，再做正常目标版本恢复。同一会话不能继续沿旧正文工作，也不能仅因 pin 或 AGENTS 已写入便提前切换。采用成功、原动作收口、独立 Review、接受、宿主接入和发布各自记录，互不替代。

基本写集为旧 state、project.json、BOOTSTRAP.md、AGENTS.md、process-policy.json、corrections.json、目标 state、当前任务，以及确有旧声明时的单个知识 indexLocator。显式 AdoptionCorrectionsPlan 可按根 PROJECT_ADOPTION 的严格结构加入纠正 history/installation 及 effectPaths；创建、删除和二进制效果与基础迁移使用同一最终投影及原事务。Controller 参与绑定但不被替换。保留项目 ID、名称、拓扑、backend、排除集合、Owner/actor 和任务目标；DOMAIN_OWNER 迁为 TASK_OWNER，只转换有效 selector 的角色/接受词汇，不替换历史文字或旧证据。

MajorAdoptionOverridesPath 与 ExpectedMajorAdoptionOverridesIdentity 可提供 schema1 的项目映射：绑定当前 projectConfigIdentity/taskIdentity，仅允许 taskText、policy、corrections。Phase gate=TRUE 的当前任务须映射目标 acceptance-plan；旧 runtime 曾抑制的纠正必须由项目显式说明保留或退出，不自动复活或删除。旧索引纯转换为 index3，保留原验证时间和依赖，来源配置归项目。其他在途任务和责任由项目安排衔接，本桥不批量迁移。

有归属的纠正退出或效果修订用 AdoptionCorrectionsPlan schema2；与 MajorAdoptionOverrides.corrections 互斥。旧 schema1 继续支持原记录/历史消费者。scope-only 不读取效果；计划、原 exact scope 和实际投影保持同一全集，保护先于存在性/hash/read。完整 priorRecord 与旧历史/installation 引用不改写；目标模板合成后继续证明修订安装归属，已退出纠正不可复活。目标只含 2.0 是正常布局，旧 snapshot.12、snapshot.3 或 snapshot.15 由 previousDistribution.runtimeRoot 取得。project4→7、project5→7、project6→7、major/state6 与真实 REGISTER/state7 的相邻刷新分别保留各自来源及任务合同，不扩大为任意历史版本适配。

## 中断与材料保留

旧/新采用 state 都指向同一原事务。目标 state 自带 true 标记并不单独证明完成，正常目标恢复还须核对所链接的真实事务 COMPLETE、其中原始 state 的字节身份和未变化的历史主体、授权及恢复对象。当前发行绑定与托管投影另按当前 state 校验；任一在途采用事务未完成时走 RecoverRuntimeAdoption。

COMPLETE 仅接受顺序写入形成的新像前缀，包括对象落盘但事务记录尚未更新的一步窗口；续写前重验目标完整包、原准入和当前标准来源，并使用目标 composer。ROLLBACK 校验保存的目标身份与原 ADMIT 一致，但不要求或执行损坏目标载荷；仍验证旧运行包、原授权/准入、Controller/任务、投影和前像，按逆序恢复原像，再恢复被替换的原 journal。回退中断后的缩短前缀只能继续回退。任一对象不等于原像或目标像、顺序不可达、Controller/授权/原准入漂移都拒绝；第三方字节不能由恢复覆盖。已关闭事务不可反向切换；原 journal 恢复后不以新事务的旧身份重放命令。

原授权/运行来源、实际固定兼容工具和目标运行来源分开保存。当前格式迁移使用本次 Apply 的固定兼容根入口 `scripts/upgrade-project.ps1 -RecoverRuntimeAdoption`；旧 snapshot.3 不认识 UPGRADE_FORMAT_TRANSITION。实际 Apply 与 major 恢复从自身工具目录核对原目标投影中的 rootToolRevision/rootToolDependencies，保持原准入绑定；独立完好工具副本可与目标目录分离，但依赖字节必须一致。工具本身损坏时先从精确信任的固定分发恢复可用工具，不退回不兼容旧脚本，也不新增恢复服务或项目。参数、原证据及实际工具位置沿根 PROJECT_ADOPTION 保留，目标损坏场景的测试必须报告真实调用来源。

原准入、投影、前后像及链接中的事务虽位于 runtime，也属于在用恢复依赖，不可按临时目录批量删除。后续同 pin 刷新必须先完成本次原收口，重新绑定当时项目状态；保留 majorTransition 和原 upgrade/state.json，刷新事务使用独立的 project-adoption/refresh/state.json。后续刷新只替换已完成的刷新事务，成功及回滚均不覆盖原跨版本恢复材料；恢复入口按调用者绑定的精确事务身份选取两处固定路径之一，不扫描或猜测历史。只有旧链接和其他实际消费者均已释放，才能按 TOOL_CONTRACT 的材料生命周期整理历史。项目当前规则可在完成后正常演进，历史安装身份不替代新任务授权。

## 规则加载与兼容边界

目标新调用使用 schema5 DISCOVER / ruleLoad、schema2 IntentEnvelope 四维 facets 和 schema4 compact；ADMIT/FINALIZE 使用 schema3，typed evidence 与既有授权格式保持。原 snapshot.12/snapshot.3/snapshot.15 的过程仍按各自原合同和原收据验证，不将历史输入批量改写为新格式，也不能用旧格式豁免新调用的证据门。具体 Maintenance TARGET 输入限制以 TOOL_CONTRACT 为准。

同一 composer 组合原生规则、有效纠正和项目标准；完整 selected blocks 供模型实际读取，compact 仅保留来源/边界/义务。旧 budget 字段只作兼容数据，不设置规则包额度。项目可以继续使用 inline 或 source-bound 标准，不自动搬迁正文。机械匹配、哈希和 PASS 不证明模型注意力、语义正确性或宿主实际调用。
