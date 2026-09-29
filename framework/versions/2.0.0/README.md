# Framework 2.0.0

本版本处于分批实施阶段，尚不可采用。发行资格只取 VERSION.json 与 RELEASE_MANIFEST.json；测试、独立源码审核和发布整合均从 PENDING 开始，历史快照不证明新候选通过。

源码继承 1.16.0 已审快照，release class 为 MAJOR。旧版本与固定运行包保持原始字节；不要求现有项目立即升级。

## 本次实施

沿用单一 composer、IntentEnvelope、任务和动作包，实现可恢复的责任转换、TASK_OWNER替代原DOMAIN_OWNER角色，Owner/actor/grantee责任分离、有类型结果证据及可按实际依赖接受的阶段计划。Tool Contract 和 Router 导航合同升为2；具体接口取 TOOL_CONTRACT、TOOLCHAIN 与对应模块。

W1核心、W2规则链、W3可选规范/非Git、W4多来源Knowledge/project5已形成候选实现。W5在现有根入口实现snapshot.12到2.0的原准入、精确投影、原收口及中断续完/回退，正在完成整合验证。当前宿主使用UNSUPPORTED_FULLTEXT_FALLBACK，不提供alreadyLoaded跳过；机械测试不证明自然模型稳定消费。整版测试、独立源码审核、接受、宿主安装及项目采用尚未完成。

可安装入口源码位于根 skills/ai-workspace-router-v2/SKILL.md；本版本 host 文件只是 NON_INSTALLABLE 兼容说明。合同一致的Framework版本共享入口；封装、宿主安装/发现/实际加载与项目采用分别验证。

项目自管规则、规范采用和知识来源；Framework不建立消费者采用登记。普通项目的目标合同不强制Git，Git动作和Maintenance双仓拓扑仍独立验证。

当前验证环境为 Windows / PowerShell 7。最终完整套件、独立Source Review、成果接受、发行/Git和项目采用是独立结果，逐项保存实际证据。

## W1 核心实现入口

有限交接与恢复见 CONTROL_TRANSITION_SCHEMA.json 和 scripts/ControlTransition.psm1；任务责任、受托接受与阶段验收见 EVIDENCE_RECORD_SCHEMA.json、ACCEPTANCE_PLAN_SCHEMA.json 和 scripts/ResultEvidence.psm1。相应入口已接入 checker、process 边界及 typed push 接受链，仍须完成整个版本的回归、独立源码审核与采用验证。边界只宣称 INSTRUCTION_BOUND；单项测试不等于完整套件或真实项目验收。

W2显示入口为 scripts/ProcessRequirementDisplay.psm1，消费同一resolver结果；scripts/WorkflowDelivery.psm1由FINALIZE、TERMINAL和修复复审核验共用。用法、原始用户来源及证据上限取TOOL_CONTRACT与PROMPTS。新增 rule-chain、rule-display、workflow-delivery 专项保留历史反例和失败分支。

可选软件规范及声明式preset来源展开见[standards](standards/README.md)。采用只记录在项目policy，未采用不加载；专业方法从通用视角归位，原生治理继续适用。当前仍为未完成整版审收的开发候选。

可选方法入口见 [knowledge/README](knowledge/README.md)。项目 schema5 自管多个 PROJECT / LOCAL_DIRECTORY 来源，以 sourceId:entryId 精确选择，只有显式 FULLTEXT 才返回正文。库不可达会报告来源失败，不在未选中时阻断普通治理。
