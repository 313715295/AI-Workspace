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

## 本地候选试点

需要自然 project use 时，保持 direct version directory，并标记 `CANDIDATE / consumable=false / projectPinEligible=false`。`ADOPTION_PROFILE.json.localCandidatePilotEligible=true`。实现期 manifest 保持 `CANDIDATE / sourceReview=PENDING / releaseIntegration=PENDING`；进入试点前，manifest 必须把最终 payload、一次完整套件及独立 Source Review 绑定为同一候选证据，`sourceReview` 才投影为 `APPROVED`，而 `releaseIntegration` 仍为 `PENDING`。

local candidate 按四个阶段推进：

1. `CANDIDATE_IMPLEMENTATION`：只实现冻结范围并运行 affected tests。
2. `PRE_PILOT_VERIFICATION`：冻结一份 pilot snapshot，运行一次 complete current-version suite，并取得一次 independent CRITICAL Source Review。
3. `LOCAL_PILOT`：显式选择的 project 按顺序使用同一份已测试、已 Review 的 snapshot。先由 Maintenance，再由选定 consumer；finding 先报告，不自动修复。
4. `RELEASE_CLOSURE`：snapshot 未变化时复用 identity-bound full-suite 与 Review evidence；发生修正时只按实际 delta 运行 affected validation 与 proportionate rereview。然后才分别进入 `OWNER_ACCEPT`、seal、Git/push、publication 与 adoption。

显式选择的 existing project 可在 `LOCAL_PILOT` 运行 root upgrader `-LocalCandidatePilot`。这是 project-owned pilot decision，不是 stable adoption。upgrader 必须在 project boundary 前重算 payload 并与 manifest 的 file count、bytes、canonical、完整套件及 Source Review evidence 一致；实际写入使用的 schema3 project authorization 还必须携带 `targetFrameworkSnapshot={canonical,manifestIdentity}`，逐次绑定最终 manifest。preview 只读，不以自身授予项目写入。工具复用普通 actor-bound transaction，不注册新项目、不发布、不创建第二 candidate tree，也不把 finding 自动转成 project correction。

同一 project 已 pin 该 candidate version、但 pilot snapshot 后续发生变化时，仍使用 `-LocalCandidatePilot`。工具先根据旧 pilot state 证明 live 托管对象确实来自上一候选投影，再生成当前 snapshot 的 Bootstrap/AGENTS 管理区、process policy、Maintenance overlay 与 runtime ignore；完全一致时只重绑 `upgrade-recovery/<version>/state.json`，存在可证明的旧候选托管差异时则输出一次 fresh schema3 exact pre/postimage 写集并按“托管对象在前、state 在后”刷新。刷新后的 state 明确分离原始跨版本 `objects` 恢复材料与当前 `projectionObjects`，不会把未同步的 old/new material 冒充当前候选恢复材料；普通异常会反向回滚，进程被强制终止造成的未知 live/state 组合则停止并要求精确恢复，不宣称跨进程原子性。项目自定义区、corrections 内容、任务正文和未知字节不被改写；任一来源无法证明仍 fail closed。该路线不复跑发布门，也不允许 stable 同版本重绑。

candidate 自身 Bootstrap/resolver/checks 必须支持 declared lifecycle；target projection preflight 在任何 pin write 前 PASS。candidate bytes 变化使旧 source context 失效，需要 fresh project recovery；不自动重写已选 pin。finding 在正常 Framework source authority 下修复同一 candidate。

pilot 不接受 raw、未完整测试或未 Review 的 candidate，不让 candidate generally consumable，也不授予 Git/push。project 仍独立决定是否采用 sealed release。

## 候选与测试

payload 是 version 内除 `RELEASE_MANIFEST.json` 外的全部文件，按 ordinal relative path 排序。每行 `path|byteLength|UPPER_SHA256`，以 UTF-8 LF 连接且无 trailing LF；payload identity 是这些行的 SHA256。

实现期只跑 affected tests。final candidate freeze 只跑一次 complete current-version suite。始终证明 immutable baseline payload identity。只有 shared root tools、upgrade compatibility、Tool Contract 或 baseline execution boundary 受影响时，才重跑 baseline executable suite。

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

## 项目纠正与平台证据

coverage metadata 本身不能证明 correction incorporated。suppression 需要 original reason/boundary 已由 applicable native requirements 实现、behavior tests 覆盖，并在 Source Review 中以 exact mapping evidence 接受。

platform support 由 evidence 限定。release 只声称 sealed Tool Contract 声明且实际 conformance 已证明的平台。

本流程不增加 release service、registry、queue、ledger、persistent receipt、第二 authority 或 automatic consumer operation。

## 试点项目规则与安装快照

本地候选获准试点后，安装历史不是项目规则的永久冻结清单。项目规则按项目任务授权、Review 和接受流程演进；runtime 重新绑定当前规则，安装历史保留不改。candidate 刷新使用当前规则的完整 preimage，并保留已接受的项目规则。schema4 的 Bootstrap managedIdentity 排除 PROJECT-CUSTOM 正文，但不排除框架管理区；旧 state 只经既有候选刷新转换，不允许手工改 state 绕过漂移。schema4 先保存 `transactionComplete=false`，在全部 live postimages（task 最后）匹配后，仅原子登记现有 state 的完成标记并结束原授权事务；未完成不得进入试点，原恢复可续完。日常恢复只读完成证明，不要求历史升级任务留在 active 或 archive。这一元数据收口不许可额外业务写入。此约束不改变既有 CANDIDATE_IMPLEMENTATION / PRE_PILOT_VERIFICATION / LOCAL_PILOT / RELEASE_CLOSURE 四阶段。
