# AI Workspace 初始化与采用

## 1. 现有项目恢复

1. 证明实际 cwd、project Git top 与 `.ai-workspace/` root。
2. 严格读取 `.ai-workspace/project.json`、`controller.json` 与 `BOOTSTRAP.md`。
3. 只解析 `framework/versions/<project pin>/`；不得从 HEAD、tag、network state 或其他 project 推断 version。
4. 校验 pinned version inventory/toolchain，再恢复 project facts、relationships、status、active tasks 与 Review profile。
5. recovery 保持 read-only，直到 current project authority 授予 next action。Maintenance sibling layout 还必须分别证明 CONTROL/TARGET Git top、dedicated parent 与 target 无 `.ai-workspace`。

现有项目的本地 pin 是唯一版本选择 authority。

## 2. 新项目接入

新项目必须显式选择 exact stable Framework version；省略即错误，没有 default selector。

1. 校验 selected `VERSION.json` 为 stable/consumable/pin-eligible，`RELEASE_MANIFEST.json` canonical 且 approved，并验证 `project-starter/` 与可选 `ADOPTION_PROFILE.json.registrationEligible=true`。
2. 先运行 root `scripts/register-project.ps1` preview。
3. Review exact destination、starter inventory、project-selected `SelectedRulePackBytes` 与 root `.gitignore` runtime rule。
4. 获得 project write authority 后用 `-Apply`。
5. 填写 project-owned `PROJECT.md`、`RELATIONSHIPS.md`、`REVIEW_PROFILE.md`、`STATUS.md` 与 tasks；不改 Framework release。
6. 从 materialized `BOOTSTRAP.md` 做 fresh FULL_COLD。

registration 始终要求 exact `FrameworkVersion` 与 `ControllerId`。`repo-local` 只物化该 version 的通用 starter。显式 `framework-maintenance-sibling` 模式要求 target repository ID、单一 sibling directory 与 target routine exclusions；工具先验证 dedicated parent、两个不同 Git top、target 无 `.ai-workspace`，再用通用 starter 加 root `framework/maintenance-overlay/` 生成 CONTROL。profile 可以细化 project-control/toolchain projection，但不能让 candidate consumable 或授予写权限。

## 3. 现有项目升级

upgrade 由项目发起，不由 Framework release 自动触发。

1. 按 target version 的 `REUSE / MUST_NEW / BLOCKED` contract 创建或复用 project task。
2. 冻结 source/target pin、Controller、managed objects、custom regions、protection、exact sorted capabilities 与 Git state。
3. preview root `scripts/upgrade-project.ps1 -ToVersion <exact-version> -SelectedRulePackBytes <bytes>`。
4. 要求 target profile 明确声明当前 Project Format/capability 可直接采用；未声明即停止。1.16 基线不为已退出的 1.14/1.15 格式保留专用直升分支。
5. 工具在 isolated target projection 中先迁移 current task route、target policy/corrections/budget，再运行 target resolver。Maintenance what-if 会建立真实临时 CONTROL/TARGET sibling Git tops；PASS 前不写 project pin。
6. apply recoverable managed-object transaction；non-task objects 先写，active adoption task 最后写，之后零写入。
7. 在 new pin 下 fresh FULL_COLD，并执行 project-owned acceptance。

工具只操作 supplied `RepositoryPath`，不发现、注册或修改其他 consumer。

`DISCOVER` 一次返回完整 selected rule blocks 与 reusable compact receipt。`ADMIT_ACTION`/`FINALIZE_OUTPUT` 只在 source/context binding current 时消费 receipt；uncertainty/drift 要求新 DISCOVER。ephemeral input 默认位于 project `.ai-workspace/runtime/<task>/<actor>/`，system temp 仅作 fallback。

## 4. 独立动作

Framework candidate creation、Source Review、`OWNER_ACCEPT`、stable seal、root-tool integration、Git commit、push/publication 与 project adoption 是独立 actions；其中一个成功不授权另一个。

后续自然 project task 可以验证 released workflow。evidence 留在来源项目，不复制成 Framework consumer state。
