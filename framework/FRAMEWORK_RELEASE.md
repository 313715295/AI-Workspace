# Framework 发布流程

本 root-owned 流程管理跨版本 Framework release。它不属于 sealed version payload、consumer runtime rule pack、project task 或第二 authority。Maintenance control repo 提供 current task、authorization、Review 与 evidence；本文只提供可复用顺序。

## 发布分类

- `ROOT_MAINTENANCE`：不改变 sealed payload 的 root docs、license、checkout policy、release procedure 或 integration tooling；使用 exact-path validation 与 affected tests，但不是 version release。
- `PATCH`：兼容且边界明确的修正，不新增 public capability、authority action、schema migration、role、backend 或 consumer requirement。
- `MINOR`：新增 Framework capability 或 public process/schema behavior，并保留兼容 adoption。

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

显式分发模式下，用户包文件名精确为 `AI-Workspace-<分发标识>.zip`；启用 `-InternalMaintenance` 则精确为 `AI-Workspace-Maintenance-<分发标识>.zip`，两种名称不可混用。前缀区分包用途，不改变包内 README 及 PACKAGE_MANIFEST 的 `distributionId`。命名包使用 package manifest schema2；不传参数的既有用户包调用继续使用 schema1及原 OutputPath 行为，其文件名不能用于推断资格。两种模式均保留完整 payload、completeSuite、Source Review 和 releaseIntegration 校验；snapshot 需要 `-Provisional` 且只能用于候选，release 只能用于 stable。预览/打包不修改版本元数据、不发布、不改变项目 pin，也不授予项目采用权限。

发布 Owner 在本次任务中明确最终 ZIP 交付位置，并通过 `-OutputPath` 指定；用户包与内部包分别定位，不把会话 runtime 的中间产物路径直接作为最终交付入口。位置由发布者选择，不规定消费者的解压目录。整理已有交付副本只复制已验证字节并核验原 identity，保留原审计材料，不重建同号不同内容的包，也不改变项目已绑定的运行目录；旧内部包不因旧文件名失去采用资格。

命名包可显式接入固定解压目录；distribution/content/manifest/runtime 绑定保存在原采用记录，开发目录变化不改变项目运行来源。snapshot 序号不意味着已采用“完整基线 + 累计差异”的验证合同。根级变更运行受影响专项并独立审查；未变版本证据按真实身份复用，不修改旧 completeSuite 的 payload hash 冒充重跑。用户包只包含所选版本消费内容、必要接入工具和用户入口，不含源码仓 Git/维护状态、其他版本或独立评估工具。

## 本地候选试点

需要自然 project use 时，保持 direct version directory，并标记 `CANDIDATE / consumable=false / projectPinEligible=false`。`ADOPTION_PROFILE.json.localCandidatePilotEligible=true`。实现期 manifest 保持 `CANDIDATE / sourceReview=PENDING / releaseIntegration=PENDING`；进入试点前，manifest 必须把最终 payload、一次完整套件及独立 Source Review 绑定为同一候选证据，`sourceReview` 才投影为 `APPROVED`，而 `releaseIntegration` 仍为 `PENDING`。

local candidate 按四个阶段推进：

1. `CANDIDATE_IMPLEMENTATION`：只实现冻结范围并运行 affected tests。
2. `PRE_PILOT_VERIFICATION`：冻结一份 pilot snapshot，运行一次 complete current-version suite，并取得一次 independent CRITICAL Source Review。
3. `LOCAL_PILOT`：显式选择的 project 按顺序使用同一份已测试、已 Review 的 snapshot。先由 Maintenance，再由选定 consumer；finding 先报告，不自动修复。
4. `RELEASE_CLOSURE`：snapshot 未变化时复用 identity-bound full-suite 与 Review evidence；发生修正时只按实际 delta 运行 affected validation 与 proportionate rereview。实现包可用受限 `continuationPlan` 承接写后真实 postimage 到已预授予测试/局部修复，但不承接 independent Review、`OWNER_ACCEPT`、seal、Git/push、publication 或 adoption；这些仍分别进入自己的 gate。

显式选择的 existing project 可在 `LOCAL_PILOT` 运行 root upgrader `-LocalCandidatePilot`。这是 project-owned pilot decision，不是 stable adoption。upgrader 必须在 project boundary 前重算 payload 并与 manifest 的 file count、bytes、canonical、完整套件及 Source Review evidence 一致；实际写入使用的 schema3 project authorization 还必须携带 `targetFrameworkSnapshot={canonical,manifestIdentity}`，逐次绑定最终 manifest。preview 只读，不以自身授予项目写入。工具复用普通 actor-bound transaction，不注册新项目、不发布、不创建第二 candidate tree，也不把 finding 自动转成 project correction。

同一 project 已 pin 该 candidate version、但 pilot snapshot 后续发生变化时，仍使用 `-LocalCandidatePilot`。工具先根据旧 pilot state 证明 live 托管对象确实来自上一候选投影，再生成当前 snapshot 的 Bootstrap/AGENTS 管理区、process policy、Maintenance overlay 与 runtime ignore；完全一致时只重绑 `upgrade-recovery/<version>/state.json`，存在可证明的旧候选托管差异时则输出一次 fresh schema3 exact pre/postimage 写集并按“托管对象在前、state 在后”刷新。刷新后的 state 明确分离原始跨版本 `objects` 恢复材料与当前 `projectionObjects`，不会把未同步的 old/new material 冒充当前候选恢复材料；普通异常会反向回滚，进程被强制终止造成的未知 live/state 组合则停止并要求精确恢复，不宣称跨进程原子性。项目自定义区、corrections 内容、任务正文和未知字节不被改写；任一来源无法证明仍 fail closed。该路线不复跑发布门，也不允许 stable 同版本重绑。

candidate 自身 Bootstrap/resolver/checks 必须支持 declared lifecycle；target projection preflight 在任何 pin write 前 PASS。候选项目调用 `LOAD_PLAN_RESOLVE` 的 supporting/fallback 路线时，必须提供当前 project config identity 与 local-pilot recovery state identity，由 loader 复用 composer 的候选绑定读取；它返回 CANDIDATE evidence，不把候选伪装成 STABLE，也不把完整规则组合或授权变成 support 前置。candidate bytes 变化使旧 source context 失效，需要 fresh project recovery；不自动重写已选 pin。finding 在正常 Framework source authority 下修复同一 candidate。

pilot 不接受 raw、未完整测试或未 Review 的 candidate，不让 candidate generally consumable，也不授予 Git/push。project 仍独立决定是否采用 sealed release。

## 候选与测试

payload 是 version 内除 `RELEASE_MANIFEST.json` 外的全部文件，按 ordinal relative path 排序。每行 `path|byteLength|UPPER_SHA256`，以 UTF-8 LF 连接且无 trailing LF；payload identity 是这些行的 SHA256。

实现期先跑 dependency-closed affected entrypoint：canonical identity/PowerShell 5.1 compatibility 变化运行 `tests/canonical-identity-tests.ps1`，recovery、batching、root release wording、catalog/budget/coverage binding 或其薄入口变化运行 `tests/governance-contract-tests.ps1`；selector、Tool Contract、process runtime 与 authorization 继续使用既有 focused entrypoint。`tests/run-framework-tests.ps1` 调用这些相同实现并传播失败，affected PASS 不替代候选冻结、一次 complete current-version suite、independent Source Review 或 `OWNER_ACCEPT`。

实现期 `-SkipManifest` 只接受 `CANDIDATE + PENDING/PENDING/PENDING`，允许最终 manifest 尚未冻结。final candidate freeze 运行一次 complete current-version suite。默认完整校验直接接受两种真实状态：已封存 STABLE，或 payload/manifest/完整 suite/独立 Source Review 全部严格绑定且 `releaseIntegration=PENDING` 的已审 CANDIDATE；混合状态拒绝，候选结果仍报告 `lifecycle=CANDIDATE`，且前后 manifest bytes 必须不变。若 Review 后确需复证同一已审快照，可按必要性重跑默认完整校验，不新增 replay mode、不重置 Review metadata，也不预设连续重复完整套件。始终证明 immutable baseline payload identity。baseline executable regression 只适用于仍声明支持且确被 shared root tools、upgrade compatibility、Tool Contract 或 execution boundary 变更影响的基线；已退出版本只保留历史 identity 与 recovery evidence，不恢复退役套件。

Source Review 前冻结 README/ROADMAP 等 current-facing wording。deterministic sealing 期间不得修改 free-form 或 executable bytes。

## Review、接受与封存

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

涉及宿主 Router 的交付按[宿主接入收尾](PROJECT_ADOPTION.md#宿主接入收尾)核对实际安装副本；正文只由接入流程维护。

## 项目纠正与平台证据

coverage metadata 本身不能证明 correction incorporated。suppression 需要 original reason/boundary 已由 applicable native requirements 实现、behavior tests 覆盖，并在 Source Review 中以 exact mapping evidence 接受。

platform support 由 evidence 限定。release 只声称 sealed Tool Contract 声明且实际 conformance 已证明的平台。

本流程不增加 release service、registry、queue、ledger、persistent receipt、第二 authority 或 automatic consumer operation。

## Maintenance 根来源自更新

当 Maintenance 已采用的候选需要把同一已审 Framework 根来源写回 configured target 时，先在旧的健康 pin 下安装本节所需的 root-only integration tool；首次安装仍使用普通 schema2 DISCOVER、ADMIT、exact SOURCE_WRITE 与 FINALIZE，不以待安装工具追认自身。版本 payload 与 manifest 均不因 root-only 修复而变化。

后续根来源整合是一个有界恢复事务。`scripts/integrate-framework-source.ps1` 的 PREVIEW/APPLY 绑定原 DISCOVER、ADMIT input/result、SOURCE_WRITE package、CONTROL/TARGET、config/controller/task、target Git parent及已接受候选冻结；APPLY 写前真实复跑原 ADMIT（含既有 checker），保存双方恢复字节。候选自身必须匹配完整 freeze；TARGET 只按授权路径映射到该候选，另绑定受影响脚本/版本依赖。TARGET 的 Git 元数据、独立 tools 与范围外项目文件既不要求等同候选，也不进入写集。

写后由 REFRESH_PREVIEW 调用既有 same-pin local-candidate upgrader 的真实 preview；Owner 依其计划签发独立 schema3。REFRESH 在原事务内调用真实 upgrader apply、消费完整授权和实际后像，记录执行结果；VERIFY_REFRESH 只复核这个已完成结果，不接受外部 PASS 或人工 pilot state。FINALIZE_CHECK 使用同一版本 composer 重组当前完整规则，验证只发生本次授权来源/采用状态转换，合并原义务与当前适用义务并检查提交证据。root adapter 的原 SOURCE_WRITE FINALIZE 委托 COMPLETE 重做上述检查后登记结果，不另造收据或接受 caller 自报 decision hash；fresh receipt 不能追认旧写入。结果明示原 DISCOVER/ADMIT、当前 composition 与完成事务身份，保留 INSTRUCTION_BOUND 上限，不声称签名认证或 single consumption。

写入异常自动恢复；进程中断用同一事务 RECOVER。恢复前一次检查双方全部受管对象和依赖，拒绝第三方字节；再复用 adoption projection 的恢复能力，先还原 Maintenance 受管对象和原 recovery state，后还原 TARGET，最后复跑旧健康源下原准入。未证明组合恢复则不能完成事务或进入 Git。其他 consumer（包括 Pocket）始终独立，不由此自动写入，也不承诺跨项目原子性。

本次整个根级 self-update 部署路线（包括首次安装、原 TARGET SOURCE_WRITE 的 DISCOVER/ADMIT、来源替换及原 FINALIZE）只支持已验证的 schema2 DISCOVER / schema1 compact receipt，source actor 与刷新 grantee 为同一 Controller。schema3 DISCOVER / schema2 compact 的 TARGET 路线不受支持：根入口在 DISCOVER 或消费已有 TARGET compact 时明确返回 `MAINTENANCE_TARGET_RECEIPT_SCHEMA_UNSUPPORTED`，不改写 receipt 的 authority root，不转入版本 resolver 或误清理输入。此限制针对 TARGET 来源动作的 process 收据组合，不是授权包 schema 限制；独立 schema3 CONTROL 升级授权包、schema3 CONTROL DISCOVER 及其正常边界仍按既有合同运行。

## 试点项目规则与安装快照

本地候选获准试点后，安装历史不是项目规则的永久冻结清单。项目规则按项目任务授权、Review 和接受流程演进；runtime 重新绑定当前规则，安装历史保留不改。candidate 刷新使用当前规则的完整 preimage，并保留已接受的项目规则。schema4 的 Bootstrap managedIdentity 排除 PROJECT-CUSTOM 正文，但不排除框架管理区；旧 state 只经既有候选刷新转换，不允许手工改 state 绕过漂移。schema4 先保存 `transactionComplete=false`，在全部 live postimages（task 最后）匹配后，仅原子登记现有 state 的完成标记并结束原授权事务；未完成不得进入试点，原恢复可续完。日常恢复只读完成证明，不要求历史升级任务留在 active 或 archive。这一元数据收口不许可额外业务写入。此约束不改变既有 CANDIDATE_IMPLEMENTATION / PRE_PILOT_VERIFICATION / LOCAL_PILOT / RELEASE_CLOSURE 四阶段。

内部 Maintenance 包使用同一构建入口的 -InternalMaintenance，仅增加内部根适配器与 overlay；普通用户包不启用此选项。两者独立绑定实际内容身份，均不可覆盖。旧健康包及原事务材料保留至新包接入和恢复验证完成。

固定运行包的首次接入不需要先修改仍在运行的开发源。Owner 接受整批候选后，使用已验证的接入工具、原健康项目来源及独立 schema3 升级包，把既有采用状态和管理入口接入固定解压包；旧开发源和旧包保持可用。固定运行包接入后，开发仓 SOURCE_WRITE 的规则来源仍在固定包，直接经原 DISCOVER/ADMIT/FINALIZE 闭合，不走会替换运行来源的旧 self-update 刷新。此时每次切换包仍是显式采用动作。旧耦合项目继续使用已有 self-update 路线，直到显式接入固定包。

固定包 same-pin 刷新复用 ProjectAdoptionTransaction 的升级事务，管理对象与原 state 最后写入；进程中断后，使用仍健康的接入工具执行 upgrade-project -RecoverRuntimeAdoption，并提供原包身份、实际事务身份及原 actor。COMPLETE 先验证目标包身份，ROLLBACK 只用已绑定前像；未知第三方对象拒绝且不发生部分恢复。原项目版本 state 是唯一采用记录，runtime/project-adoption 中的文件只保存本次事务与恢复材料。

项目 Bootstrap custom 到 process-policy 的来源迁移由原 CONTROL_WRITE FINALIZE 处理；旧 receipt 可提供原包绑定的 Bootstrap 前像，仍须证明管理区未变。已授权动作中断时，upgrade-project 的 ProjectRuleRecoveryPlanPath 入口消费原 DISCOVER、原 ADMIT 输入与结果、原授权包及精确前后像。恢复事务明确在现在创建，不声称历史上已存在；COMPLETE 与 ROLLBACK 均复核所有对象和未授权来源后执行，并以原动作 FINALIZE 收口。缺失原 admission、前像或未知混合字节时拒绝，fresh DISCOVER 不替代原 action。
