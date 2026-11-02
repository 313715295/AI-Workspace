# Framework 发布流程

本 root-owned 流程管理跨版本 Framework release。它不属于 sealed version payload、consumer runtime rule pack、project task 或第二 authority。Maintenance control repo 提供 current task、authorization、Review 与 evidence；本文只提供可复用顺序。

## 开发与维护职责

开发仓承载源码、通用合同和交付模板；Maintenance 治理项目承载真实任务、授权、责任、Review 和证据。维护前恢复该项目自己的 Bootstrap，缺失或冲突时不得在源码仓推断原任务身份或另建替代控制面。另一个环境开展新维护可以建立自己的治理项目；本合同不依赖某个本机路径或会话。

STABLE 封存版本、已发行 ZIP 和固定运行目录不可原地修改。开发 CANDIDATE 可按精确授权在原目录实现和修复；源码变化撤回受影响的旧资格，实现期 manifest 保持 PENDING，再按本文验证。schema2 的 completeSuite 语义保持；2.0 的 schema3 按下述 S0–S5 分离源码机制、源码资格与实际分发验证。候选冻结、版本发行、根工具整合、Git 发布与项目采用是独立动作。真实消费者身份、路径、任务和采用状态不写入通用源码。

开发根不设 AGENTS/CLAUDE；README 面向使用者；本文提供维护阅读地图，版本模块持有通用规则。`framework/user-package/AGENTS.md` 只导航发行包与接入说明，不作为用户项目控制面。版本 project-starter 和 maintenance-overlay 分别提供普通项目与治理项目入口，AGENTS托管导航与用户约定分区；迁移、刷新和升级须验证当前约定、收窄/撤回、幂等及原事务恢复，不以标签存在代替语义保留。构建/采用继续验证独立交付模板的正确性。

## 维护阅读地图

从源码仓理解框架的职责、行为和验证方式，沿以下现有文档与实现阅读，无需依赖旧聊天或原维护项目。概览与链接用于导航；规则以对应模块正文为准，实现和测试分别用于核对行为与验证范围。

| 维护内容 | 文档与实现入口 |
|---|---|
| 版本能力与发行资格 | [版本说明](versions/1.16.0/README.md)、[版本元数据](versions/1.16.0/VERSION.json)、[发布资格](versions/1.16.0/RELEASE_MANIFEST.json) |
| 任务、授权、审查与恢复 | [任务与范围](versions/1.16.0/TASK_AND_SCOPE.md)、[授权](versions/1.16.0/AUTHORIZATION_MODEL.md)、[审核与证据](versions/1.16.0/REVIEW_AND_EVIDENCE.md)、[恢复](versions/1.16.0/RECOVERY_CORE.md) |
| 规则组合、纠正与材料 | [工具合同](versions/1.16.0/TOOL_CONTRACT.md)、[项目控制](versions/1.16.0/PROJECT_CONTROL.md)、[组合实现](versions/1.16.0/scripts/ProcessRequirementComposition.psm1)、[纠正生命周期实现](../scripts/ProjectCorrectionLifecycle.psm1) |
| 宿主接入与项目采用 | [Codex 接入](versions/1.16.0/HOST_CODEX.md)、[项目接入与升级](PROJECT_ADOPTION.md) |
| 行为变更与验证场景 | [变更记录](versions/1.16.0/CHANGELOG.md)、[运行合同测试](versions/1.16.0/tests/process-runtime-v2-tests.ps1)、[选择与存储回归](versions/1.16.0/tests/efficiency-regression-tests.ps1)、[纠正测试](../scripts/tests/project-correction-lifecycle-tests.ps1)、[采用与恢复测试](../scripts/tests/upgrade-project-bridge-tests.ps1) |

Framework 负责项目治理与协作规则，复用现有模块约束任务、行动、证据、协作、材料和资源选择。宿主提供模型调用、上下文压缩、缓存、工具调度、并发、通知和计费；具体接入由宿主适配文档说明。业务标准和产物由项目维护。当前实现与验证主要覆盖 Windows、PowerShell 7 和 Codex。

维护取舍依据质量要求、实际消费者、现有能力和完整交付成本，沿现有方案与验证处理，不额外增加必填表或检查阶段。宿主能力缺口只限制实际受影响的动作；责任、授权、独立性与证据边界仍按对应规则处理。

测试源码用于了解验证场景，实际通过结论取对应执行证据；开发候选的当前状态与已审发行快照分别核对，旧快照证据不证明新字节。继续原维护任务须恢复原维护项目；在新环境开展维护则建立自己的治理项目，不从本仓库推断原会话的身份和权限。

## 发布分类

- `ROOT_MAINTENANCE`：不改变 sealed payload 的 root docs、license、checkout policy、release procedure 或 integration tooling；使用 exact-path validation 与 affected tests，但不是 version release。
- `PATCH`：兼容且边界明确的修正，不新增 public capability、authority action、schema migration、role、backend 或 consumer requirement。
- `MINOR`：新增 Framework capability 或 public process/schema behavior，并保留兼容 adoption。
- `MAJOR`：改变既有公开责任、授权动作或不兼容的项目/schema合同；先冻结迁移边界，保留旧健康来源，经目标专项、完整套件和独立审核接受后，使用显式采用事务迁移。新版本不自动授予旧项目采用权，也不要求建立永久历史兼容层。

unknown impact、新 authority boundary 或 migration requirement 不能归为 PATCH。candidate freeze 前 classification change 会重开 scope/authorization。

## 直接版本候选

直接在 `framework/versions/<version>/` 开发，不需要 parallel draft tree。目录存在不代表 consumable。stable registration/upgrade 只接受 lifecycle stable、canonical `RELEASE_MANIFEST.json`、`sourceReview=APPROVED` 与 non-pending integration。

payload 只含 version-owned runtime rules、schemas、compatibility/adoption facts、tests 与 explanation；不复制本文，也不复制完整 Framework Maintenance starter。root `framework/maintenance-overlay/` 与 `scripts/MaintenanceOverlay.psm1` 是可变 integration input，由 root tools 在 registration/upgrade 时叠加到通用 `project-starter`；它们不进入 version manifest，也不是 live project authority。version-specific identity/evidence 位于 `VERSION.json`、`RELEASE_MANIFEST.json`、`CHANGELOG.md` 与 Maintenance task。

## 分发命名与用户包

对外分发标识使用 `<version>-snapshot.N` 或 `<version>-release`，例如 `1.16.0-snapshot.1` 和 `1.16.0-release`。它只标识一次用户包分发；内部 Framework version、项目 pin、版本目录、payload canonical 算法和 CANDIDATE/STABLE 资格保持原合同。序号 N 是无前导零的正整数，由发行 Owner 从已有包/交付记录选定；不自动发现、递增或建立注册表，不把同号不同内容当同一快照。既有输出文件拒绝覆盖，交付绑定实际包 identity。

根级 [build-user-package.ps1](../scripts/build-user-package.ps1) 增加可选 `-Distribution`：

```powershell
# 已审 CANDIDATE；先预览，-Apply 才写 ZIP
pwsh -File scripts/build-user-package.ps1 -FrameworkVersion 1.16.0 -Provisional -Distribution snapshot.1 -OutputPath AI-Workspace-1.16.0-snapshot.1.zip
# 内部 Maintenance 包；不作为普通用户下载附件
pwsh -File scripts/build-user-package.ps1 -FrameworkVersion 1.16.0 -Provisional -Distribution snapshot.1 -InternalMaintenance -OutputPath AI-Workspace-Maintenance-1.16.0-snapshot.1.zip
# 已封存且满足现有完整证据门的 STABLE
pwsh -File scripts/build-user-package.ps1 -FrameworkVersion 1.16.0 -Distribution release -OutputPath AI-Workspace-1.16.0-release.zip
```

显式分发模式下，用户包文件名精确为 `AI-Workspace-<分发标识>.zip`；启用 `-InternalMaintenance` 则精确为 `AI-Workspace-Maintenance-<分发标识>.zip`，两种名称不可混用。前缀区分包用途，不改变包内 README 及 PACKAGE_MANIFEST 的 `distributionId`。命名包使用 package manifest schema2；不传参数的既有用户包调用继续使用 schema1及原 OutputPath 行为，其文件名不能用于推断资格。两种模式都验证完整载荷及当前源码资格：release manifest schema2 校验 completeSuite、Source Review 与原 releaseIntegration；schema3 校验 Qpre、Mreview→Msealed 投影及 PREPACKAGE_PASS。snapshot 需要 `-Provisional` 且只能用于候选，release 只能用于 stable。schema3 构建成功返回 BUILT_UNVERIFIED，分发资格仍待实际包后验证和接受。预览/打包不修改版本元数据、不发布、不改变项目 pin，也不授予项目采用权限。

发布 Owner 在本次任务中明确最终 ZIP 交付位置，并通过 `-OutputPath` 指定；用户包与内部包分别定位，不把会话 runtime 的中间产物路径直接作为最终交付入口。位置由发布者选择，不规定消费者的解压目录。整理已有交付副本只复制已验证字节并核验原 identity，保留原审计材料，不重建同号不同内容的包，也不改变项目已绑定的运行目录；旧内部包不因旧文件名失去采用资格。

命名包可显式接入固定解压目录；distribution/content/manifest/runtime 绑定保存在原采用记录，开发目录变化不改变项目运行来源。snapshot 序号不授予验证复用：schema2 保持原合同；schema3 proof v1 的 VERIFIED_GROUP_COVERAGE 仍要求真实已接受的 FULL_RUN 基线，proof v2 的 CURRENT_GROUP_COVERAGE 按下述当前平面组覆盖合同复证，不把此前 S5 接受作为开发续跑前置。根级变更运行受影响专项并独立审查；未变版本证据按真实身份复用，不修改旧证明的 payload hash 冒充重跑。用户包只包含所选版本消费内容、必要接入工具和用户入口，不含源码仓 Git/维护状态、其他版本或独立评估工具。

### 2.0 开发候选的加载与专业发布收敛

实际规则加载按当前意图取得完整适用条件与依赖，同次去重后返回完整正文。健康同动作仅普通文件/包改变时，原 checker/ADMIT 重绑当前范围而不装配或显示正文；额外要求、实际动作或恢复变化要求完整加载。旧 REUSE 兼容完整返回，coverage 差集和未来预载退出；完整文本与同结果截断恢复保留。

专业发布保留普通批量读取、一次完整 targets 及两侧不同选择、真实双权限与结果、首侧成功后只补缺侧的恢复。同一目标对的完整本地规范只构造一次，第二侧直接消费；诊断区分 SOURCE_BODY_READ 与 SOURCE_BODY_SHARED，不把共享结果记为又一次物理读取。selected→closure 与 closure 复核仍跨独立投影、当前权限/成员及恢复入口，本轮未重写这些耦合，也不以旧样本宣称各层净提速。

路径保护保留既有通用检查和普通/投影原路径/投影成员中能检出读前遗漏的最小回归，不再扩成入口×链接形式的矩阵。文件符号链接创建、Windows 提权或开发者模式不是升级前置；本批不宣称实际文件 symlink 覆盖或消除所有并发竞态。旧 NOT_RUN/PARTIAL 仍是历史事实，新候选按当前必要用例的真实结果及原一次共同 Source Review 核对；不增加通用遗漏豁免或额外审核层。

这些是开发候选行为，固定运行包和真实项目采用不随源码变化。定向作者验证不替代整版资格、独审、构包、分发接受或显式采用。

## 本地候选试点

需要自然 project use 时，保持 direct version directory，并标记 `CANDIDATE / consumable=false / projectPinEligible=false`。`ADOPTION_PROFILE.json.localCandidatePilotEligible=true`。实现期 manifest 保持 `CANDIDATE / sourceReview=PENDING / releaseIntegration=PENDING`。schema2 进入试点前仍须绑定最终 payload、一次完整套件及独立 Source Review，审核后 releaseIntegration 保持 PENDING；schema3 则必须先完成 S1/S2 源码资格，再以实际不可变包完成 S3–S5，不能用源码资格直接宣称分发已验收。

local candidate 按四个阶段推进：

1. `CANDIDATE_IMPLEMENTATION`：只实现冻结范围并运行 affected tests。
2. `PRE_PILOT_VERIFICATION`：冻结一份 pilot snapshot，按其 manifest 合同完成验证，并取得一次 independent CRITICAL Source Review。schema2 保持一次 complete current-version suite；schema3 首次执行全部 Gpre，并在实际构包后执行全部 Gpost 和分发接受。
3. `LOCAL_PILOT`：显式选择的 project 按顺序使用同一份已测试、已 Review 的 snapshot。先由 Maintenance，再由选定 consumer；finding 先报告，不自动修复。
4. `RELEASE_CLOSURE`：snapshot 未变化时复用 identity-bound full-suite 与 Review evidence；发生修正时只按实际 delta 运行 affected validation 与 proportionate rereview。实现包可用受限 `continuationPlan` 承接写后真实 postimage 到已预授予测试/局部修复，但不承接 independent Review、`OWNER_ACCEPT`、seal、Git/push、publication 或 adoption；这些仍分别进入自己的 gate。

显式选择的 existing project 可在 `LOCAL_PILOT` 运行 root upgrader `-LocalCandidatePilot`；新项目可按 PROJECT_ADOPTION 使用支持首次注册的固定 root registrar `-LocalCandidatePilot`。两入口复用同一候选源码资格 reader，首次注册额外要求 registrationEligible、同一命名运行包及真实有限接入任务。这是 project-owned pilot decision，不是 stable adoption。upgrader 必须在 project boundary 前重算 payload，并验证 file count、bytes、canonical、当前证明和 Source Review；实际写入使用的 schema3 project authorization 还必须携带 `targetFrameworkSnapshot={canonical,manifestIdentity}`，逐次绑定最终 manifest。reader 的 SOURCE_QUALIFIED 不替代发行 Owner 对 Z/Qpost 的分发接受；S4 仅在独立测试授权的隔离消费者执行真实入口。preview 只读，不以自身授予项目写入。upgrader 复用普通 actor-bound transaction；registrar 只在控制面缺失时完成首次初始化。两者均不发布、不创建第二 candidate tree，也不把 finding 自动转成 project correction。

首次候选注册与既有升级是不同 origin。注册的 schema7 state 必须由真实 COMPLETE REGISTER 的投影后像证明，原 REGISTER journal 作为在用恢复依赖保留。同 pin 7→7 刷新保持该 origin 和 registrationId，以当前任务/原 ADMIT/目标 PREPARE/精确 schema3 包闭合；refresh journal 不覆盖原 REGISTER。schema6 升级、project5→6 格式迁移及 major origin 的支持边界不扩大。新增源码字节撤回受影响资格，最终冻结载荷按当前 schema 验证并独立审核接受；旧计数只支持原输入和 canonical。

首次或新来源仍完整验证源码资格。同一根动作、同一 reader 实例和 runspace 内，可私有复用已完整验证的结果；每次消费重新校验有限实际成员集合、全部相关字节及路径/reparse 边界，返回独立对象。证明成员从已验原始 bytes 按成员、kind 和解析模式严格解析一次，保持比较器、时间 token、引用可达性和 unused 检查。失败、异常、取消、动作结束或模块重载丢弃上下文，弱结果不能满足强请求；来源、运行根和 Maintenance 模式分别绑定。该上下文不持久化，不形成资格或权限。

已完成采用的同一固定命名来源，可在独立期望 distribution binding、真实 COMPLETE 事务、原准入和当前实际 state 后像核对后，验证 PACKAGE_MANIFEST 原字节、完整包成员及全部字节、VERSION/manifest 身份和当前形状，返回 FIXED_ADOPTED_SOURCE。它不重放历史深读图，不返回 Proof 或新 SOURCE_QUALIFIED。schema6 核对最新 UPGRADE/REFRESH 及原 major origin；schema7 核对原 REGISTER 与当前 refresh；stable REGISTER 使用自身 journal、投影、root/pin/tools，不构造候选 state。prospective 注册不得使用此层。缺失或不支持原凭据时保留原完整资格/恢复路径，实际漂移拒绝；当前 task、policy、corrections、AGENTS 与权限仍由当前过程独立核对。这里的资格消费细化了上段的逐次复验，不改变发行、Review、接受或采用门。

同一 project 已 pin 该 candidate version、但 pilot snapshot 后续发生变化时，仍使用 `-LocalCandidatePilot`。工具先根据旧 pilot state 证明 live 托管对象确实来自上一候选投影，再生成当前 snapshot 的 Bootstrap/AGENTS 管理区、process policy、Maintenance overlay 与 runtime ignore；完全一致时只重绑 `upgrade-recovery/<version>/state.json`，存在可证明的旧候选托管差异时则输出一次 fresh schema3 exact pre/postimage 写集并按“托管对象在前、state 在后”刷新。刷新后的 state 明确分离原始跨版本 `objects` 恢复材料与当前 `projectionObjects`，不会把未同步的 old/new material 冒充当前候选恢复材料；普通异常会反向回滚，进程被强制终止造成的未知 live/state 组合则停止并要求精确恢复，不宣称跨进程原子性。项目自定义区、corrections 内容、任务正文和未知字节不被改写；任一来源无法证明仍 fail closed。该路线不复跑发布门，也不允许 stable 同版本重绑。

candidate 自身 Bootstrap/resolver/checks 必须支持 declared lifecycle；target projection preflight 在任何 pin write 前 PASS。候选项目调用 `LOAD_PLAN_RESOLVE` 的 supporting/fallback 路线时，必须提供当前 project config identity 与 local-pilot recovery state identity，由 loader 复用 composer 的候选绑定读取；它返回 CANDIDATE evidence，不把候选伪装成 STABLE，也不把完整规则组合或授权变成 support 前置。candidate bytes 变化使旧 source context 失效，需要 fresh project recovery；不自动重写已选 pin。finding 在正常 Framework source authority 下修复同一 candidate。

pilot 不接受 raw、未完整测试或未 Review 的 candidate，不让 candidate generally consumable，也不授予 Git/push。project 仍独立决定是否采用 sealed release。

## 候选与测试

schema2 payload 是 version 内除 `RELEASE_MANIFEST.json` 外的全部文件；schema3 P 还精确排除已声明且完整验算的 Qpre 附件，不能按后缀或目录通配隐藏源码。P 必须等于 NORMATIVE_SURFACE_INVENTORY 声明的当前完整文件集合。每行 `path|byteLength|UPPER_SHA256`，按 ordinal relative path 排序，以 UTF-8 LF 连接且无 trailing LF；payload identity 是这些行的 SHA256。Qpre 有自己的 index+成员 canonical，PACKAGE_MANIFEST 则绑定实际完整包内成员，包含 Msealed 和全部 Qpre。

实现期先跑 dependency-closed affected entrypoint：canonical identity/PowerShell 5.1 compatibility 变化运行 `tests/canonical-identity-tests.ps1`，recovery、batching、root release wording、catalog/budget/coverage binding 或其薄入口变化运行 `tests/governance-contract-tests.ps1`；selector、Tool Contract、process runtime 与 authorization 继续使用既有 focused entrypoint。`tests/run-framework-tests.ps1` 调用这些相同实现并传播失败，affected PASS 不替代候选冻结、一次 complete current-version suite、independent Source Review 或 `OWNER_ACCEPT`。

维护受影响测试时，先将变化的行为和风险对应到现有用例，区分复用、更新、参数化、合并、增加与退役。新增说明未覆盖的风险，合并或退役说明保留覆盖；本次回归未选择不表示永久删除。核对用例是否到达目标机制，其他条件提前拒绝不证明目标行为。具体软件方法可参考项目显式采用的[软件验证与回归](versions/2.0.0/standards/software/VALIDATION.md)，该可选标准不因本导航自动成为所有项目的核心门禁。

开发阶段按实际改动选择已有专项；成本观察优先使用主 runner 已有专项调用边界的起止、耗时及退出状态，保留原始输出和失败传播。测试计数与组耗时分别解释，重叠组耗时不能相加冒充总耗时。最终稳定候选仍执行下文现行完整验证和独立审核；局部通过、旧候选证据或耗时改善均不替代这些要求。

schema2 旧调用中，实现期 `-SkipManifest` 只接受 `CANDIDATE + PENDING/PENDING/PENDING`，允许最终 manifest 尚未冻结；final candidate freeze 运行一次 complete current-version suite。默认完整校验仍接受已封存 STABLE，或 payload/manifest/完整 suite/独立 Source Review 全部严格绑定且 `releaseIntegration=PENDING` 的已审 CANDIDATE；混合状态拒绝，manifest 前后不变。schema3 的 PREPACKAGE 调用则使用 SOURCE_PAYLOAD_V1：冻结完整 P/T/D，真正从该视图读取源码和明确构造的 synthetic manifest，不读本次未来 Qpre、Msealed 或 ZIP；partial/focused 结果不生成完整资格。全局 reader、schema 或定义变化撤回依赖它们的旧组记录；受影响或无法闭合的组必须 fresh，不追认旧记录为新输入通过。未受影响且满足当前 proof 合同的原记录才可严格复证。始终证明 immutable baseline payload identity。baseline executable regression 只适用于仍声明支持且确被 shared root tools、upgrade compatibility、Tool Contract 或 execution boundary 变更影响的基线；已退出版本只保留历史 identity 与 recovery evidence，不恢复退役套件。

Source Review 前冻结 README/ROADMAP 等 current-facing wording。deterministic sealing 期间不得修改 free-form 或 executable bytes。

四类协议夹具（current coverage、efficiency、governance measurement、non-git transactions）按声明成员构造：coverage 用十二个版本输入及三个 child、两个 sentinel 的私有 inventory；efficiency 和 measurement 各自用机制清单一次构造完整合成资格，governance 直接调用 measurement；旧 1.16 runtime 只复制已声明的八十项，历史 manifest 在隔离夹具内单独处理。完整默认用例与失败出口保留，私有 FixtureContractOnly 仅产生 PARTIAL 构造/消费者证据，不产生正式组 completion。

这四组采用 MECHANISM 闭包，可在原 EXECUTED/native/raw/CLEAN、当前定义、实际工具/父环境、root/options 及完整输入均匹配时严格复证。具名真实 snapshot 反例验证相关改动失效、无关独立测试字节不进入闭包；反例不是四组的新执行证明。旧格式保持原严格读取。新定义只在原记录具有足够的行为事实、当前严格验证通过时复证；事实不足给出具体原因并鲜测，不重签旧记录。当前完整 suite/export、integration.full-source、未闭合动态依赖及 POSTBUILD 实际包检查仍承担各自鲜测义务；部分构造与映射通过不构成整版、Source Review、性能或发行通过。

### 本轮常驻引导补做的验证边界

本轮 2.0 常驻引导与旧 nav3 刷新是在完整冻结技术基线完成后的有限后继。范围仅为普通及 Maintenance 两份 AGENTS 模板、根 ProjectAdoptionState.psm1、upgrade-project.ps1、project-adoption-tests.ps1，以及本文、test-groups.json、governance-contract-tests.ps1，共八文件。原 45 组结果保留其完整原件、失败和过程限制，只证明原 P/T/D，供一次共同独立 Source Review 判断本次影响；不得将旧 PASS 改贴到新输入，不将该技术基线当作 S5 接受基线，也不建立派生或证据继承链。

本轮 D 保留全部旧组定义及原 POSTBUILD 必需集，明确本轮 PREPACKAGE 的全部必需 Gpre 为 `adoption.entry-templates`、`governance-contract`、`integration.full-source`。新增组直接调用原 `scripts/tests/project-adoption-tests.ps1 -EntryTemplatesOnly`，在默认分支实际触达普通/维护旧 nav3 的 upgrader→投影器接点，保留当前用户编辑、收窄/撤回、旧 grant 迁移、CRLF、幂等、未知内容拒绝及原事务检错。其终标必须由真实原生输出验证，不能以手填可信事实或仅有文案断言代替接线。四个真实 authorization 消费者及其原行为继续保留，本轮未选不等于删除测试、永久退役或放松权限。

八文件稳定后，只以原 public runner 执行一次显式三组的 `PREPACKAGE / proof3` 批次：`-Groups adoption.entry-templates,governance-contract,integration.full-source`，使用经当前授权的新 EvidenceDirectory 和 SourceViewPath，不传 ResumeEvidence，不先单独重复运行 EntryTemplatesOnly。新三组均须为当前 `EXECUTED`，真实 native 退出 0、原生记录完整、收尾 CLEAN，无未运行、失败或未知；suite 为 COMPLETE、Qpre3 为 PASS，并绑定完整新 P/T/D 和当前 D 的全部必需集。完整源码、载荷、运行工具及输入闭包校验保持，原 45 组不计作新三组的执行或复证。失败保留原结果，只在原许可及有限额度内按实际影响修正和重验，首充分成功即停。

本轮有限选择不作为未来未知变更、扩大范围或其他发行永久缩减 FULL 的通则；新增实质影响须重新确定必要覆盖。当前完整源码、三组新证据、原冻结基线和本次八文件共同进入原一次独立 Source Review，全部贡献者排除于独审。上述安排不替代 S0–S5 的其余门：源码接受/封存后，用户包与内部包仍分别对实际未改 ZIP 完成 fresh POSTBUILD、首次注册/同版升级检查、分发接受及项目显式采用。


## schema3 的源码与分发阶段

P 包含当前 VERSION、测试实现及定义；T 包含实际根工具、构建器、验证器与运行环境；D 明确区分 PREPACKAGE 的 Gpre 和 POSTBUILD 的 Gpost。阶段不是新 action 或状态数据库，各写测、审核、接受和发行门保持独立。

| 阶段 | 已存在输入与真实输出 | 可以宣称的结果 |
|---|---|---|
| S0 | 冻结 P/T/D、参数及夹具定义；没有最终 ZIP | 准备完成，尚无验证结论 |
| S1 | Gpre 读取完整源码视图与独立合成夹具；真实 command/raw/组结果先存包外，全部组成功后组装有限 Qpre | PREPACKAGE_PASS，尚无实际包通过 |
| S2 | 独立 Source Review 消费 P/T/D/Qpre 和 Source Review=PENDING 的 Mreview；实际审核完成后按精确权限投影 Msealed | SOURCE_QUALIFIED、DISTRIBUTION_NOT_BUILT |
| S3 | builder 复验已有源码资格，生成 PACKAGE_MANIFEST 和新 ZIP Z；全部包内字节与原构建命令冻结，输出拒绝覆盖 | BUILT_UNVERIFIED |
| S4 | Gpost fresh 读取实际 Z、校验解压树、构建命令和 runtime；在隔离消费者执行真实注册及同版本升级 smoke，跨版本迁移仍由 Gpre bridge 覆盖；Qpost 只存包外 | 全部必需组成功才 PACKAGE_VALIDATED |
| S5 | 原 Reviewer/Owner 消费源码审核、Z/Qpost 与完整绑定；接受记录留包外并引用同一未改 ZIP | 适用审核、RESULT_ACCEPT 和发行权限齐备才 DISTRIBUTION_READY |

schema3 manifest 用 validationProof 替代 completeSuite。proof v1 只允许 PREPACKAGE/PASS 的 FULL_RUN 或 VERIFIED_GROUP_COVERAGE；显式 proof schemaVersion=2 只允许 PREPACKAGE/PASS 的 CURRENT_GROUP_COVERAGE，baselineRef 必须为 null，并且必需 currentSuiteRef 引用 Export 之前生成的原 suite。两者均绑定当前 P canonical、D identity、精确 Gpre、原 EXECUTED 组引用及 root integration；releaseIntegration=PREPACKAGE_PASS 只表示已完成的源码集成。实现期 CANDIDATE/PENDING 的未来 refs（含 v2 currentSuiteRef）为 null、数组为空，v1 使用 FULL_RUN，v2 使用 CURRENT_GROUP_COVERAGE，不能预填 POSTBUILD/接受结果。v1 的字段及既有接受语义保持，v2 的新时间、文案和归属要求仅用于 v2；旧 v1 reader 必须拒绝显式 v2，不能降格解释。

Qpre index 列举有限 typed members、alias 和逐输入角色映射。原 EXECUTED/native command/launch/stdout/stderr/phase 字节原样携带，alias 将原引用绑定到包内成员；旧绝对路径和 cleanup root 只作不访问的来源标签。CURRENT_PAYLOAD、CURRENT_RUNTIME_TOOL、SOURCE_ONLY_BUILD_OR_TEST_INPUT 和 SYNTHETIC_FIXTURE_INPUT 分别处理，源码与运行工具不能降为历史材料。reader 在源码端核对完整实际读集合，在运行包端核对完整 P 和所需根工具；移动包可验证便携证明，但不据此复用 root-sensitive 的旧执行。

v2 将原 suite 字节作为 CURRENT_SUITE 携带。suite 必须为当前 PREPACKAGE/PASS/COMPLETE，绑定 D、完整必需组集、options、sourceInputsRef 和原记录；现有 alias 逐项映射 suite 的记录与复证。proof.groupRecordRefs 与 suite 记录一一对应，proof.revalidationRefs 恰等于 suite 的 REVALIDATED 分区，EXECUTED 与 REVALIDATED 完整、唯一且无冲突。原 suite 只引用记录、复证和输入，不回指 proof 或 manifest。标注 fresh 的 EXECUTED 仍核对原 process/launch/raw、前后像、validator、角色闭包及 CLEAN，并且实际开始、创建、退出、完成时间位于本轮 suite 的有效窗口，root/options 与 suite 一致。unknown/alwaysFresh 仅在此确证 fresh 分支允许；复证仍拒绝二者。不能删除复证或重标历史 EXECUTED 冒充本轮执行。

用于 v2 归属及 phase collector 的固定顶层时间字段显式保留原 JSON string token，再用含时区 ISO 格式与 invariant culture 解析比较值。实际 nullable 元数据单独校验；PASS 执行仍需要完整归属时间。严格解析器的该选项默认关闭，通用数组、默认日期物化和嵌套 facts/canonical 不改变，历史原件不回写。时间窗、alias 和 hash 是 INSTRUCTION_BOUND 的一致性证据，真实命令、Source Review 与接受各门继续独立，不由本地自报材料推断密码学宿主真实性。

Msealed 的 sourceReviewEvidence 携带被审 Mreview 的原字节身份及 reviewedManifestBase64。解码前像须为 schema3、审核 PENDING、证明 PASS 且非递归。只允许顶层 /sourceReview 与 /sourceReviewEvidence 改变；P、Qpre、D、T、lifecycle、sourceCandidate、releaseIntegration 及其他字段必须一致。VERSION 等 P 字节变化回到 S0/S1，不能当作资格投影。Qpre 不包含 Mreview 或后来的审核附件，不形成自引用。

proof v1 首次没有可用基线时全部 Gpre fresh；后续 VERIFIED_GROUP_COVERAGE 只引用一份实际完成 S5 接受的 FULL_RUN 基线及真实本地 revalidation，其语义保持。proof v2 CURRENT_GROUP_COVERAGE 直接引用有限、平面的原 EXECUTED 记录；每个复用组另有当前严格 REVALIDATED，原记录仍保留其实际命令、时间、原始 stdout/stderr、launch、phase、环境、闭包前后像、validator 与 cleanup。原记录失败、缺失、partial、未知依赖、alwaysFresh、字节/输入/命令/环境/validator 漂移时执行该组，不能把 REVALIDATED 当成可递归复用的原执行。所有 required Gpre 及 root integration 必须完整，未运行组不能补 PASS；来源角色、source-only 与 synthetic 输入的字节、P/T/D 和 root-sensitive 身份继续严格校验。v2 不引用或伪造 S5 基线，不嵌套差异证明。acceptance 原件及 Z/Qpost 绑定由 Source Review 和宿主接受门复证，文件 hash 不独自证明审核者身份或独立接受。新 ZIP 的全部 Gpost 始终 fresh。

公开 PREPACKAGE runner 对 D3 默认导出显式 proof v3；未显式选版本的旧 D1/D2 分别保留 v1/v2 默认，已有显式基线调用保留 v1。Export 的既有调用默认 v1，可显式选择版本而不能混用基线参数；D3 只配 suite3/index2/proof3，旧 D1/D2 不生成新格式，显式不兼容组合拒绝。每次使用独立 EvidenceDirectory，执行视图用现有 owned SourceViewPath、原 owner receipt 与独占 lease；owner 保留 Windows SID|creator 形状，完整当前 SID 是资源归属，creator 仅作创建来源，同 SID 的已授权顺序调用不要求相同聊天。省略 resume 路径时只从唯一原 EXECUTED root 推断，缺失、歧义、异主、active、reparse 或未知内容拒绝；显式新根仍按真实环境、位置和记录严格选择，不消去 root-sensitive 身份或静默换根。当前源重建后先保存全组 EXECUTE/REVALIDATED 计划和原因；缺少终态 proof 路线在子进程启动前拒绝。固定优先仅为实测廉价的 `publication.phase-evidence` 与 `non-git.preflight-ast`；focused 选择不自动增加组，其余按显式请求顺序稳定执行。默认 D 将四个独立集成领域及跨层 flow 放在昂贵 current-coverage、proof-schema 和真实恢复组之前，所有必需覆盖与原生失败停止保留。current-coverage、proof-schema、五崩溃恢复均为真实完整验证，不作为廉价元数据入口。最终 suite 验证失败时，已写 suite、summary 和 native 退出均表示失败/不完整，保留原始失败，不留下相矛盾的 PASS suite。阶段 collector 对所有混合记录分类，父阶段绑定 START/REACHED/END、原始检查记录绑定具体生产者、原件身份及真实输出/退出码；未知或不完整记录拒绝。短链通过不代替真实完整 Gpre、独立 Source Review 或 S2–S5；计时和启动数分别报告实际总成本、重建、规划、复证与原生执行，反事实避免时间不能称实测总提速。

W1 新格式采用 D3、EXECUTED2、REVALIDATED2、suite3、index2、proof3 和 source-input closure2。D3 每组声明 groupContractVersion、behaviorInputs、fixtureRecipe、environmentPolicy 与 locationPolicy。原生执行由 TestExecutionRuntime 唯一持有进程句柄、流任务和取消资格，TestHarness 保留公开 facade 与夹具/reset 职责；只读 TestEvidenceValidation 统一校验本地、Source 和便携证据，不启动进程、不访问历史绝对路径，也不形成新的规则加载器。LOAD_MANIFEST 的规范加载职责保持。

EXECUTED2 原件分别保存 producer 的模块来源、实际 native 命令/argv/cwd/环境/退出/双流/phase/cleanup、前后 snapshot 和 executionContext。snapshot 的 definitionIdentity、原生产者 identity 与当前 verifierIdentity 属于各自来源；复用比较 group contract、完整声明行为输入、显式依赖的其他组/全 D、真实 fixture recipe、options、有效环境及位置事实。定义/解析器/验证器的无关变化可触发当前复证；被测验证器、解析器或定义本身仍必须声明为行为输入。WHOLE_VERSION、unknownDependencies、alwaysFresh、必需组集和完整 P/T/D 资格校验保持保守。默认定义仍包含宽闭包，不声称所有组均已获得复用收益。

REVALIDATED2 直接引用一份未改 EXECUTED2，记录当前 snapshot、当前 verifierRef、原记录 schema、当前 verifiedBehaviorIdentity、checkedUtc 和明确 derivations。当前实现不接受非空派生链；旧记录缺少新环境/位置/上下文事实时，以 LEGACY_BEHAVIOR_FACTS_UNPROVEN 鲜测，不能仅改 schema 或补造缺失事实。原生产者与当前 verifier 不要求相同；当前 verifier 必须匹配本次实际执行的验证代码及当前 P，当前 suite/proof 同时绑定它。原失败、partial、缺 raw、命令/行为输入变化、fresh 要求或校验失败均不复用。旧 EXECUTED1/REVALIDATED1/suite1/2/index1/proof1/2 保持原分支与严格字段；各 reader 显式拒绝混合或未知格式。

环境默认 EXACT，保留实际父环境和子进程启动环境。显式 EFFECTIVE_TOOLS 只可忽略未声明为影响行为的环境差异，仍比较实际工具路径、版本与字节、模块、负向工具查找、locale、COMSPEC、PSModulePath 及声明变量；全部 raw 环境事实保留。每组按实际入口选择依赖：只依赖工具解析的组不因无关 PATH 文本变化失效；读取 PATH 文本、查找顺序、内部替换搜索路径或未闭合动态依赖的组保留对应声明或鲜测，廉价负向查找组可使用既有 alwaysFresh。声明的 ambient TMP/TEMP 仍是依赖；组内私有分配的 TMP/TEMP/raw 等六个受控键仅可沿已验证历史上下文比较，不能据此复制旧 PATH、COMSPEC、PSModulePath 或改变实际新启动环境。策略变化产生新身份，须先取得新策略的真实原执行，不能重贴旧记录或推定实际总提速。

公开 runner 在当前分配、原为空的精确私有临时根与实际完成 native 环境相符、输入稳定、全部已跟踪进程记录完整且物理已结束时，可非递归处置该根下直接自有空目录，实际删除后重新观察条目，再按现有 CLEAN 字段与验证器判断。已知空目录先由创建者收尾；非空数据、未知归属、reparse/逃逸、活动或未知 worker、漂移与处置失败仍阻断相应链，功能/native 结论另行保留。不遍历任意临时根，不递归清理、忽略 DIRTY 或引入普遍继续执行策略。位置默认 EXACT；显式 LOGICAL_ROOT 仅服务 SAME_ROOT 的 SOURCE_VIEW 映射，条件声明使用 OBSERVE，由 snapshot 实际观察 Windows volume、目录大小写标志、路径长度类别、ACL、owner 和全部声明路径无 reparse。任一条件无法观察或变化都不能宣称等价。逻辑比较不改写原生 argv/cwd 或历史原件。

executionContext 使用 schema1 的 SAME_ROOT/GIT_WORKTREE 判别结构。SAME_ROOT 的 canonical controlRoot=executionRoot，target ref/observation 必须为 null。GIT_WORKTREE 需要原 descriptor bytes、描述符 identity、control/target roots、common/worktree Git dirs、Git top、branch/head、观察时间及 overridesAbsent，并携带 typed descriptor member/alias；便携验证只读已绑定字节。此处是 W1 的证据形状基础；目标选择、准入、真实工作树执行和 Pocket/其他消费者能力须由后续 W2/W4 的实际证据证明，不能以结构通过宣称已支持。

closure2 的 recipeIdentity 绑定完整 source input 集、constructor identity、synthetic inputs 与 location policy；正式当前资格继续验证完整 P/T/D 和原角色集合。owned view 仅在原 receipt 的完整当前 Windows SID、精确来源/目标与内容、独占 lease、当前 owned handles、无 reparse/未知内容、完整输入及同一 recipe 全部复证后复用准备；creator 不授予动作权限，同 recipe 保留原 receipt/closure 字节，必要重建沿原保护执行。锁和进程内句柄知识不证明未知遗留进程的清理，原未知证据仍保持未知；它不缓存测试 PASS。Release qualification 的同动作私有 scope 可复用一次深验证，逐次消费仍验证实际字节，结果隔离拷贝，失败、异常和动作结束清空。性能结论只能取真实计时与启动数；有限协议夹具通过不等于完整 Gpre、Source Review、性能目标或 S2–S5 通过，新 ZIP 的全部 Gpost 始终 fresh。

POSTBUILD runner/summary 必须提供已存在的 PackagePath 和 BuildCommandPath，不读取将来输出。Qpost schema1 记录 phase、Z 整文件 ref、PACKAGE_MANIFEST ref、解压 canonical、source manifest/Qpre/build command refs、D identity、必需 Gpost、真实组记录、runtime/options、outcome 与原输出 refs；不包含自身输入身份，不回填或重打 ZIP。失败、中断、缺组、漂移和 dirty 不能成为 PASS。S4 失败后原 Z/Qpre/Msealed 和失败证据保留，无 DISTRIBUTION_READY；真实修复回到受影响 S0/S1，重新审核并以新分发标识构包。仅进程中断且输入均未变时，可在原权限与额度内续跑必要 Gpost。

## Review、接受与封存

下列既有 schema2 封存顺序保持。schema3 使用上述 S2 投影及 S5 接受；生命周期字节已属于被审 P，资格投影不能修改它。Git、推送与项目采用继续各自准入。

1. 冻结 exact non-consumable candidate，并 release writer。
2. 一个 independent CRITICAL Source Review 检查全部 changed normative/executable bytes、exact payload、root projection、tests 与 immutable baseline。
3. same-scope repair 返回同一个仍 independent Reviewer 做 focused rereview；broadened impact 需要 full rereview。
4. Maintenance `OWNER_ACCEPT` 独立接受 exact approved candidate。
5. bounded sealing writer 只改 enumerated lifecycle fields 与 excluded manifest；reviewed/generated root projection 已是 final wording。
6. deterministic checks 重算 payload，校验 seal allowlist、manifest 与 staged diff。没有未 Review 的 free-form/executable change 时，不需要第二次 semantic post-seal Review。
7. `GIT_STAGE` 只 stage exact sealed allowlist。commit 前 deterministic publication preflight 证明 index pathset/staged identities、authorized parent、无 unauthorized/unstaged release delta 与 remote preconditions。
8. preflight 全部证明后才可 `GIT_COMMIT`。任何 path/byte/parent/repository/integration ambiguity 都停止；若 candidate bytes 变则重开 Source Review。
9. publication 顺序为 `github/main` 后 `origin/main`。首 push 前两端 refs 必须等于 authorized parent；每次 push 后回读 exact release commit。失败即停止，不 implicit retry、force、tag 或 compensate。

一次 explicit user authorization 可以预授权同一 exact ordered Git sequence，但不合并 action package、evidence 或 failure boundary。

Review approval、`OWNER_ACCEPT`、seal、Git publication 与 consumer adoption 是不同 outcome。stable release 不设置 global default，也不改 project pin。

入口交付按PROJECT_ADOPTION“宿主接入收尾”核对目标导航及实际加载；nav3使用项目Bootstrap，旧Skill只为实际旧依赖保留。源码、项目投影、宿主可见和当前正文读取分别取证，不以其中一项替代其余。

普通和Maintenance过程入口可按实际宿主编码/输出边界显式使用DisplayPath，保存同次DISCOVER结果经官方renderer生成的UTF-8无BOM完整text，截断后补读同一输出，不再次解析或扫描项目标记。默认仍一次完整正文且不保存副本，AsJson机器载体由程序捕获；副本只在需要时新建于当前任务/actor合法runtime，遵守原保护和最后消费者生命周期，不作为权限或模型attention证明。该能力仅在新运行包取得资格并由项目显式采用后生效；旧固定包不热改。

## 项目纠正与平台证据

原固定 TC3 归档动作已实际准入、全部成果及删除后像已经完成，但旧 ResultEvidence 因 active 缺失而无法 FINALIZE 时，可使用 PROJECT_ADOPTION 的完成专用入口。先由本维护流程实现、验证、独立审查和接受两处结果模块及根集成，再另行形成全新合格固定分发；原固定目录保持完整原字节。新工具只是项目明确选择的完成校验工具，原规则/任务/配置/旧 pin 与准入仍为原来源。新旧 resolver、composer、运行 helper/schema 的实际依赖必须字节相同，仅 ResultEvidence/WorkflowDelivery 允许本次已审差异；来源、验收、后像或依赖不足即拒绝，不扩大到通用历史适配或修补旧包。原动作真实成功后，才可独立进行新分发采用。开发 SOURCE、散装模块、同版本名称和测试模拟资格均不能代替现场的完整合格分发。

原生吸收声明需要对照原始原因、义务和适用边界，由实际规则、行为测试及独立 Source Review 支持；不维护项目 ID 中央抑制表。项目显式采用时独立处置完整覆盖与项目增量，保留完整旧记录和决定。

platform support 由 evidence 限定。release 只声称 sealed Tool Contract 声明且实际 conformance 已证明的平台。

本流程不增加 release service、registry、queue、ledger、persistent receipt、第二 authority 或 automatic consumer operation。

不同命名包的原 CONTROL_WRITE 采用过程收口，使用[项目接入的显式根边界](PROJECT_ADOPTION.md#原过程的跨命名包收口)。在真实 ADMIT 前通过既有升级投影取得并消费目标规则，成功结果保留原输入；采用后核对原准入、双方包和实际事务。原同包 state-only 迁址 helper 保留其严格包相同约束。此根级集成不改变 version resolver 或既有版本证据；没有原始准入材料的历史流程不能补造。根工具增量须经受影响测试及独立 Review 后以新分发号交付，不能覆盖旧包或已采用目录。

2.0跨版本根桥仅声明健康固定1.16.0-snapshot.12到已审固定2.0候选；实现和逐点恢复合同取目标2.0分发内的MIGRATION_MATRIX.md。旧runtime执行真实原准入，目标投影校验和schema3包不替代它；原FINALIZE完成后才进行新任务。根桥、版本正文及真实依赖一起进入最终Source Review，之后才具备交付条件。普通与Maintenance隔离fixture、测试构包、源码审核、正式打包、宿主安装和项目采用必须分别报告，不从任何单项推断后续已完成。

## Maintenance 固定运行来源

Maintenance 的规则与工具必须来自已验证的固定运行包；开发 TARGET 仅是源码对象。开发源码 SOURCE_WRITE 在固定运行来源下按原 DISCOVER、ADMIT 和 FINALIZE 收口。切换运行包是独立显式采用动作，继续保留固定包升级、same-pin 刷新、原准入/原收口及完整恢复合同。缺少固定包绑定时停止并说明接入条件，不回退开发源执行。

旧运行源 O、目标源 T 与实际执行工具 X 各自绑定所属实现。O 未提供后来轻观察接口时，仍由 O 自己的完整 reader 验证；T 的规则和投影不由 X 同名模块代替。同一私有调用可复用字节未变材料的严格解析，公共调用和真正写前仍重观当前路径、权限及实际字节；调用结束、失败或取消后不保留跨请求上下文，不接受调用者自报的可信校验结果。

旧源码耦合自更新已从当前有效实现、专属测试、打包清单及支持面退役，不继续增加 TC3 适配。已封存运行包和历史事务证据保持原样。未来版本间链式适配沿迁移规划推进，不要求保留这条旧部署路径。

## 试点项目规则与安装快照

本地候选获准试点后，安装历史不是项目规则的永久冻结清单。项目规则按项目任务授权、Review 和接受流程演进；runtime 重新绑定当前规则，安装历史保留不改。candidate 刷新使用当前规则的完整 preimage，并保留已接受的项目规则。schema4 的 Bootstrap managedIdentity 排除 PROJECT-CUSTOM 正文，但不排除框架管理区；旧 state 只经既有候选刷新转换，不允许手工改 state 绕过漂移。schema4 先保存 `transactionComplete=false`，在全部 live postimages（实际迁移任务时 task 最后）匹配后，仅原子登记现有 state 的完成标记并结束原授权事务；未完成不得进入试点，原恢复可续完。同版本格式迁移的任务卡保持原字节且不进入写集；其历史身份保留在 projectionObjects，并由原收据/原 FINALIZE 验证，不伪造 task 写对象。日常恢复只读完成证明，不要求历史升级任务留在 active 或 archive，也不永久锁定它的当前字节。这一元数据收口不许可额外业务写入。此约束不改变既有 CANDIDATE_IMPLEMENTATION / PRE_PILOT_VERIFICATION / LOCAL_PILOT / RELEASE_CLOSURE 四阶段。

内部 Maintenance 包使用同一构建入口的 -InternalMaintenance，仅增加内部根适配器与 overlay；普通用户包不启用此选项。两者独立绑定实际内容身份，均不可覆盖。旧健康包及原事务材料保留至新包接入和恢复验证完成。

Owner 接受整批候选后，使用已验证的接入工具、原健康固定包及独立 schema3 升级包，显式切换项目运行来源。开发仓 SOURCE_WRITE 继续由固定包治理，直接经原 DISCOVER/ADMIT/FINALIZE 闭合；源码改动不自动切换运行包。历史接入材料保留，但不构成当前对旧源码耦合部署的支持。

固定包 same-pin 刷新复用 ProjectAdoptionTransaction 的升级事务，管理对象与原 state 最后写入；进程中断后，使用与本次事务兼容且仍健康的固定接入工具执行 upgrade-project -RecoverRuntimeAdoption，并提供原包身份、实际事务身份及原 actor。旧运行/授权包、实际执行接入工具与目标运行包分别定位；旧 snapshot.3 不能恢复其尚不认识的 UPGRADE_FORMAT_TRANSITION。本次格式迁移复用原 ADMIT 投影中的 rootToolRevision/rootToolDependencies 核对实际 Apply/恢复工具；独立完好副本必须具有相同依赖字节，不引入新的项目配置或恢复服务。工具与目标同目录而不可用时，先从精确信任的固定分发恢复兼容工具，再调用原恢复入口。

已 COMPLETE 的 same-pin 原过程收口可使用新的合格修复工具 X，原准入仍由旧来源 O 验证，目标算法仍由原目标 T 的精确模块执行；使用 X 不等于采用 X。沿原公开边界执行 FINALIZE-only，原输入、授权、准入、事务及项目对象保持原字节。此零写结论不适用于 FORMAT/major 或未完成恢复；原工具依赖检查和 FORMAT originalFinalize 登记保持。源码修复、Source 资格、新分发接受及现场原动作收口分别取得真实证据。

COMPLETE 验证目标完整包及目标 composer；ROLLBACK 只验证原保存目标身份与原准入的一致性，不要求或执行损坏目标载荷。两方向仍保留原准入、授权、旧固定包、Controller/任务、前后像及第三方漂移校验，未知对象拒绝且不发生部分恢复。验证须明确实际调用的固定兼容工具路径和依赖身份，覆盖目标损坏时 COMPLETE 零写拒绝、ROLLBACK 后旧 resolver 实际通过，以及原授权、前像和第三方对象损坏的拒绝；不能在夹具中暗换工具却让文档指向不兼容旧入口。原项目版本 state 是唯一采用记录，runtime/project-adoption 中的文件只保存本次事务与恢复材料。

复用已有完成事务路径时，未完成事务保留被替换 journal 的原始字节及身份。异常和显式回滚恢复对象组后，最后原子恢复旧 journal，使旧安装状态引用的证明与旧运行包重新匹配；中途停止仍可沿待恢复事务继续。事务文件或前像漂移拒绝覆盖。成功完成时移除这份临时回滚前像，不把反复刷新变成嵌套历史链。验证须包含带合法旧 majorTransition 历史的隔离项目，并在回滚后实际调用未修改的旧 resolver；只比较投影对象不证明完整恢复。

项目 Bootstrap custom 到 process-policy 的来源迁移由原 CONTROL_WRITE FINALIZE 处理；旧 receipt 可提供原包绑定的 Bootstrap 前像，仍须证明管理区未变。已授权动作中断时，upgrade-project 的 ProjectRuleRecoveryPlanPath 入口消费原 DISCOVER、原 ADMIT 输入与结果、原授权包及精确前后像。恢复事务明确在现在创建，不声称历史上已存在；COMPLETE 与 ROLLBACK 均复核所有对象和未授权来源后执行，并以原动作 FINALIZE 收口。缺失原 admission、前像或未知混合字节时拒绝，fresh DISCOVER 不替代原 action。

本批整组纠正与调用减负的新增根 helper 属于接入工具；包构建清单必须包含其真实依赖，测试只在隔离 fixture 构包。新 capability 的开发验证不得更改已有 snapshot、ZIP、live corrections 或采用状态。AGENTS的FRAMEWORK管理区只承载目标导航；当前人类工作约定与必要项目限制位于用户拥有区。升级将旧管理区中已确认授权原文和需保留的自定文字按原投影完整承接，保留原区外字节、后续收窄及撤回；未知归属不猜删。新注册沿明确采用决定生成已批准约定。日常以当前人类正文为准，安装managedIdentity不永久冻结授权；实际事务仍绑定完整前后像并拒绝并发覆盖。封存前验证注册与升级消费者一致。纠正吸收仍需完整来源语义、行为和独立 Review，生命周期安装证据不能替代吸收依据。

## 内部接入职责

2.0 的受限 config+policy 来源维护复用原普通 CONTROL_WRITE、共享候选校验和规则恢复入口，支持原 boundary3/evidenceRefs；完整字段及读写顺序仅由 TOOL_CONTRACT“项目来源配置的受限普通采用”定义。普通消费者和 Maintenance 前门均须有真实原准入，不能通过重新 DISCOVER 或配置身份白名单追认。该实现、根接点、失败恢复和真实闭环测试一起进入新候选验证与 Source Review，只有新固定分发获得资格后才可使用；不得原地修补旧 ZIP 或已采用目录。

消费者注册、升级、恢复和纠正操作统一见 PROJECT_ADOPTION.md，随用户/内部包交付。Maintenance sibling 布局、CONTROL/TARGET 拓扑、maintenance-overlay、固定运行包适配与内部包构建只属根级维护工具。内部包以 build-user-package.ps1 -InternalMaintenance 构建；开发 TARGET 保留 Git 源码职责，固定 runtime 完成已授权源码动作收口，不随开发改动重绑运行来源。

Maintenance 跨命名包过程以根 process adapter 的 -AdoptionProcessBoundary 和准备材料执行 ADMIT/FINALIZE；后者还绑定原 AdmitResult、AdoptionAuthorizationPackagePath/ExpectedAdoptionAuthorizationIdentity 及实际采用事务。普通消费者使用 PROJECT_ADOPTION 的 root upgrader 入口，不承担 sibling 维护职责。根工具可独立修复，但固定包不可热改，交付变化使用新的分发身份并由项目显式采用。

集成测试由四个独立入口 surface、maintenance、authorization、process 和保留 ID 的 integration.full-source flow 组成。每个领域独占短临时根及原生句柄，私有 IntegrationFixture 只共享不变输入和构造方法；已有授权包与 COMPLETE journal 不跨域复用。原 -MainIntegrationOnly 选择四领域加 flow。短 Frontdoor/Schema1ControlPlane 与正式领域复用同一 Source case、夹具和判定，短选取标示 PARTIAL；真实 flow 消费 owned view、冷注册、当前 DISCOVER、checker/ADMIT、有限原生产物、FINALIZE 与后继消费者，不内部重跑四领域。各领域当前构造整版夹具，均保守 WHOLE_VERSION/alwaysFresh；六新文件进入 inventory、P、D 及实际读取闭包，定义/共同验证器变化使旧组资格失效，不重贴旧 PASS。局部结果不授予 Source Review、接受、发行或采用资格。
