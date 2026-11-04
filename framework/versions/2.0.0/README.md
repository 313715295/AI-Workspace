# Framework 2.0.0

本版本是开发候选，尚不具备普通正式采用资格。发行状态与当前载荷资格取 VERSION.json 与 RELEASE_MANIFEST.json。当前 schema3 实现清单保持 CANDIDATE/PENDING：源码机制 Gpre、独立源码审核、实际包 Gpost 与包外接受分别核对真实绑定。实现字节改变时撤回受影响资格，历史通过计数不证明新载荷。局部测试与局部审核只证明各自绑定的对象。

Framework 面向通用项目治理：在保障交付质量的前提下，降低沟通、执行、验证和返工总成本。目标与验收、事实与连续性、规则、责任协作、资源选择、受控自动化、真实证据、操作范围和中断恢复共同服务这一目标；行业标准、专业方法与知识可按项目需要采用。

## 当前源码能力

沿用单一 composer、IntentEnvelope、任务和动作包，实现可恢复的责任转换、TASK_OWNER 与临时执行者的责任分离、有类型结果证据，以及按实际依赖接受的阶段计划。控制转换见 CONTROL_TRANSITION_SCHEMA.json；结果与阶段验收见 EVIDENCE_RECORD_SCHEMA.json 和 ACCEPTANCE_PLAN_SCHEMA.json。权限与证据仍是 INSTRUCTION_BOUND，不声称宿主强制执行或模型行为保证。

Tool Contract 为 **4**，导航为 **PROJECT_BOOTSTRAP / navigationContractVersion 3**。当前输入是 IntentEnvelope2 / DISCOVER5（含ruleLoad），输出 compact4，边界输入仍为3；精确合同取 TOOLCHAIN.json 与 TOOL_CONTRACT.md。先核必要全局声明和当前权威，以同一四维/结构选择器选择，再完整验证命中规则的公共条件、依赖和正文；未命中的独立外部正文不访问。真实采用与规则变更保留完整目标集合验证；语义提示不增加权限。规则显示、依赖正文闭包和 typed delivery 共用现有过程边界。

当前项目AGENTS直接导航本项目固定Bootstrap，用户约定独立分区；旧托管约定、无标签约定及已有用户区保持原文与次序，刷新现有入口不补默认授权，收窄/撤回继续有效。未知混合定制在写前报告具体冲突。导航不依赖目标Router Skill，也不提供nav3 Skill转发层；版本内host文件只作旧nav2历史不可安装说明。旧navigation1/2项目及在途事务继续使用各自原Skill、TOOLCHAIN和过程格式，不转换旧执行意图。原动作先恢复并收口，再读取新AGENTS/Bootstrap与当前命中规则全文。源码、项目投影、宿主可见入口和实际正文读取分别取证；仍需旧Skill的宿主不自动卸载。

模型显示使用单一text：模式、真实fallback与限制、短来源、有序短引用、当前义务和一次完整必要正文。机器来源索引保留程序侧，主动分页接口已退役；真实截断只补实际缺失的完整单元。显示量变化不单独证明脚本提速、宿主token费用或自然任务效果。

项目可显式启用质量阶段策略：在 policy3 的 qualityAssurance 中选择默认的自查、独立审核、成果接受阶段，并由稳定适用规则的 qualityStages 补充所需阶段；未启用的项目继续原 LEGACY 行为。一次准备绑定完整成果和当前选择，当前任务、历史证据及接受、关闭等消费者沿同一选择核对。项目选择不豁免实际权限、保护、真实测试失败、独立性及专门的发行、采用和外部门禁。配置、准备和启用顺序见 [Tool Contract](TOOL_CONTRACT.md#项目显式质量阶段与一次准备)；本候选的实现、自查和整版资格仍分别取证。

历史结果由原对象根解释，今天的消费者继续应用当前保护；合法相对引用及JSON数组不再被当作错误对象拒绝。材料释放在零候选时退出，只处理已经验证且精确匹配的可释放集合；需要由当前有限维护任务接手旧集合时，显式RUNTIME_MAINTENANCE复用原准入、逐对象重核和remaining结果。它不扫描历史材料或根据年龄推定可删。

项目可在policy3中选择外部调用方式：缺省PER_ACTION保持原按次动作包和准入/收口；显式PROJECT_PREAUTHORIZED引用项目既有完整许可，在覆盖范围内直接使用原工具，省去逐次新卡、手工包和模型D/A/F。模式及适用许可由正常完整规则加载显示，无适用任务时保真实PROJECT_EXTERNAL上下文。宿主限制、用户保留事项、撤回、越界和UNKNOWN仍约束实际调用；配置通过不证明模型自然遵从。配置及行为见 [Tool Contract](TOOL_CONTRACT.md#项目外部授权模式与直接调用)，构造及配置例子见 [EXAMPLES](EXAMPLES.md)。原binding2和Owner合法主路线仍供按次路径使用。

已完成外部调用的历史事实与新执行权限分别处理。根升级工具的显式CompleteOriginalExternalResult只读入口可由新合格固定包核对旧原准入、冻结义务、真实工具结果及原来源漂移失败；原任务关闭和后续政策变化不自动抹去事实。它保留原FAIL，补充历史结果，不重放工具、不重开任务、不授未来调用。支持的单操作binding2及原件要求见[项目接入说明](../../PROJECT_ADOPTION.md#已完成外部调用的历史结果补充)。源码能力、实际验证和新分发资格仍分别成立。

## 来源、采用与知识

项目 schema7 的 `sourceBindings` 维护明确来源和读取许可，policy3 维护精确规范采用。已实现 LOCAL_DIRECTORY、GIT_REVISION、HTTPS_RESOURCE；按完整 revision、原始字节、采用项、依赖和实际实现绑定同一快照。规范采用绑定实际完整单元（FULL_FILE或唯一标记章节）及其完整有序依赖；同文件不同完整章节可组成依赖图，同一完整单元的别名重复拒绝，各章节共同绑定原始整文件身份。显示复用保留每条规则的依赖顺序、完整正文与义务，摘要不替代采用单元。PINNED 的合法精确本地事实可离线复用；FOLLOW 在本次读取固定实际 revision，不静默退回旧快照。读取来源不等于采用规则，采用规则也不等于本次命中；供给方不登记消费者，项目自行管理采用。

Git 支持明确的本地仓库或 HTTPS 仓库，解析到完整 commit 后读取对象，不检出工作树；引用查询隔离调用目录的 Git 配置，附注标签解析到 commit，非 commit 目标拒绝。HTTPS 按获准位置读取并逐次校验重定向与字节身份；传输有超时、大小及重定向限制。当前凭据引用返回 CREDENTIAL_UNAVAILABLE，不宣称私有凭据接入。实际公开来源取样及隔离夹具的证据有各自边界，不代表所有服务、平台或性能表现。

可选软件规范见 [standards](standards/README.md)，方法参考见 [knowledge](knowledge/README.md)。知识查询按明确 SourceId 选择范围，可用四维 FacetQueryJson 收窄，并可进一步指定条目；默认只返回定位信息，显式 FULLTEXT 才读正文。方法参考不会自动成为必须遵循的规范，未选中的知识来源不阻断普通治理。公共 Git 知识查询目前只有隔离夹具证据。

同项目拥有的专业 Markdown 正文可按 [双动作发布](TOOL_CONTRACT.md#同项目专业正文的双动作发布) 原位更新。两份纯 SOURCE/CONTROL 包各自准入，共同目标候选预读后由原根入口协调应用和恢复；普通读取不取项目/source协调锁；真实多对象发布和恢复保留必要写保护，两个成员分别执行各自真实的原 FINALIZE，两份均成功才完成整批；首份成功保持成立，后续失败只补未完成者，不另建联合提交层。普通当前卡单对象更新使用原授权、当前前像、完整原子替换与后像收口，不默认项目WRITE锁，不声称CAS或跨文件瞬时一致。Maintenance CONTROL 专业正文须当前 Controller 精确授权，TARGET、外部来源、产品、能力/pin 切换不在该分支。支持面限 Windows/PowerShell7 本地项目；源码能力与本候选的实际验证、整版审核及将来分发资格分别取证。

## 运行与剩余工作

当前验证环境为 Windows / PowerShell 7 / Codex。普通项目注册、升级和恢复使用明确项目目录，普通治理不要求 Git；实际 Git 动作和 Maintenance 双仓拓扑仍分别验证。维护开发源码由独立固定运行包治理，源码候选不自动成为当前执行权威。

根升级桥的支持起点及恢复合同取 MIGRATION_MATRIX.md 和根 FRAMEWORK_RELEASE.md；当前精确旧起点为project4 / 1.16.0-snapshot.12、project5 / 2.0.0-snapshot.3和project6 / 2.0.0-snapshot.15，按各自原格式及完成起源验证，不按版本名称放宽。旧源码耦合自更新已退役，旧固定包与原事务材料保留。支持起点的当前升级/恢复整合结论取绑定的真实专项及完整套件结果，不据局部恢复结果宣称整体通过。

首次新项目试点由根 PROJECT_ADOPTION 导航：支持本合同的合格固定命名候选可显式 LocalCandidatePilot 注册，生成当前 project7 / policy3、首张真实有限任务及 schema7 REGISTER origin。项目配置格式与采用state起源格式分别验证；默认STABLE注册和既有schema6采用起源、格式/跨版本路径保留各自严格分支。正常规则、support、首轮治理及 7→7 刷新共同复核真实完成事务，不用手填升级历史替代注册。此源码能力、隔离验证、Source Review、新分发、宿主接入和项目实际采用分别报告。

主控承担项目持续责任，Owner承担有限成果生命周期；双方按委派后本人职责选择资源并可安排专家。同一未完成成果和同审有界修复复审可续健康且合格的原聊天；新有限成果、新独审默认新会话，已关闭/归档有限会话不默认恢复改名接新成果。长期保留须有真实持续职责，原事必要补正可回原会话。有限成果已交付、原结果已消费且无后续职责时实际归档并核对，任务卡与会话归档分别确认；待验收/返修保留。资源指引取 HOST_CODEX.md 的六种宿主配置映射（包含Astra/high）；先能力、后推理工作量，并计入协调、审核和返工成本。角色或 profile 不固定模型与 effort，明确用户覆盖及健康在途配置继续有效。

问题驱动学习由实际任务承担责任，基本义务不依赖启用方法库。可选方法与正文通过原索引显式消费，内容可用不代表专业效果已证。当前规则加载按真实意图选择、同次去重并返回完整正文；旧Input5 REUSE兼容FULL，coverage差集及未来preload退役。健康同活动新增普通文件、更新包或本地配套操作沿原ADMIT_ACTION重绑定，完整核当前权限、范围、真实路线与来源；当前要求无新增且仅操作专属规则退场时，当前完整义务冻结到新compact及原F，正文装配/显示均为零。sourceObservation2保留原FULL加载ID及真实任务路线，旧格式保持严格分支。来源/要求变化、实际自测/自查/返修与恢复重新完整加载。C05仍为UNSUPPORTED_FULLTEXT_FALLBACK，机械来源核对不证明模型记忆、attention、自然触发或宿主费用改善。

发行验证按根 FRAMEWORK_RELEASE 的 S0–S5 单向推进。PREPACKAGE 读取冻结完整 P/T/D 的 SOURCE_PAYLOAD_V1 和明确合成的资格夹具；全部必需组完成后才生成有限 Qpre。独立 Source Review 消费审核仍 PENDING 的 Mreview，Msealed 只投影两项审核字段，并内置原 Mreview 字节供 reader 复验；Qpre、P、生命周期和其他字段不变。schema2 旧入口与资格语义保持，新 proof 不使用 completeSuite。

当前 reader 由 runner、builder、composer 及根注册/升级/采用状态共用，生产 reader 不依赖测试 helper。SOURCE_QUALIFIED 只证明已有源码资格；builder 输出 BUILT_UNVERIFIED，新 ZIP 原样冻结。POSTBUILD 使用已存在 ZIP、实际解压成员与原构建命令 fresh 验证完整性及隔离注册/同版本升级 smoke，Qpost 和接受记录均留包外，不改 ZIP 或内置 manifest。全部包后验证、适用独立审核与 Owner 接受齐备后才可声明 DISTRIBUTION_READY。

源码资格须覆盖全部必需 Gpre。proof v1 的 VERIFIED_GROUP_COVERAGE 仍使用实际已接受 FULL_RUN 基线；proof v2/v3 的 CURRENT_GROUP_COVERAGE 可按各自严格格式直接复证平面的原 EXECUTED 记录，不要求先有 S5 基线。声明必须鲜测、依赖未知或实际输入、环境、位置等条件失效时仍执行受影响组，原 command/raw/执行时间和失败记录保持。便携读取已审证明不等于跨 root 复用旧执行。源码审核、正式分发、宿主安装与各项目真实采用分别后置；发布候选不会自动修改任何消费者 pin，测试调用数不证明降本。

runner的原件解析复用仅在实际resume选择中建立单次私有索引，每次仍核全部显式成员的真实身份，并由原validator验证目标结果、raw、环境与cleanup；无resume及必需fresh路径不读取原件建索引。当前必要验证范围取D3，源码与实际包资格仍按既有出口判断；解析次数减少不自动证明整体提速。
