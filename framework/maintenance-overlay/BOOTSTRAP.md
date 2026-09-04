<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI 入口

Project ID=`{{PROJECT_ID}}`；layout=`framework-maintenance-sibling`；control plane=`.ai-workspace/`；pinned Framework=`{{FRAMEWORK_VERSION}}`。这是唯一 dynamic authority entry。chat、sibling state、memory、root HEAD、tag 与 network state 只作 locator。

## 1. 定位与校验

1. 从 supplied cwd 解析 Maintenance control Git top。严格读取 `.ai-workspace/project.json`：要求 schema4、`repositoryRoot=..`、expected project ID/pin、`frameworkToolBackend=powershell7`、empty `frameworkCapabilities`，以及一个 non-CONTROL repository ID、安全 sibling directory 与 literal routine exclusions。
2. 严格读取 `.ai-workspace/controller.json`：相同 project ID、controller ID 非空、epoch >= 1、`state=CURRENT`。
3. 不跟随 reparse 解析 control Git root parent；parent 不得含 `.git` 或 `.ai-workspace`。只连接已校验的单一 target directory component，不搜索其他目录，也不接受 absolute/`..` locator。
4. 通过 target 根级 `scripts/resolve-framework-maintenance-target.ps1` 绑定 control/target Git tops，再在 target 内定位完整 pinned `framework/versions/{{FRAMEWORK_VERSION}}`。版本 `TOOLCHAIN.json` 只声明通用项目运行时工具，不拥有 Maintenance 拓扑。
5. 严格校验 CONTROL corrections 与 process policy，包括 `selectedRulePackBytes`。Maintenance 调用根级 `scripts/resolve-framework-maintenance-process-requirements.ps1`；该前门复用 pinned version 的唯一 composer，不建立第二 composer。
6. resolver 必须返回 `controllerState=CURRENT`，target 不得有 canonical `.ai-workspace`。target control entry、missing component、intermediate reparse、parent authority、pin/config/controller drift 或 Git-top conflict 都 fail closed。

`<FW>`、`<CONTROL>`、`<TARGET>` 只使用 resolver 的 exact 结果。

## 2. Recovery 与 load

1. 轻读 Maintenance `STATUS.md` 与 `tasks/README.md` 只定位 assigned task；绑定 Owner、authenticated Work route、profile、objective/action/result、selected repository、exact scope 与 protection。
2. normative module 前执行 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`；一次读取所有 returned exact complete blocks，后续只保留 compact receipt。
3. 只读 selected rules/task 要求的 Maintenance facts、target evidence、schemas、templates 与 action artifacts。target work 在 scope 时显式读取 `<TARGET>/AGENTS.md`；sibling instruction 不自动继承。
4. `LOAD_PLAN_RESOLVE` 只用于 compatibility、non-rule support、Framework-wide explanation/maintenance 或 bounded fallback，不是 pre-DISCOVER gate。
5. 分别重证 control/target HEAD、index、dirty。safe-Git 每次只绑定一个 repository ID 与 bounded literal paths；一个 repo 的 VERIFIED 不能填补另一个 repo 的 UNVERIFIED。
6. 复检 current package。Maintenance 通过根级 `scripts/check-framework-maintenance-authorization.ps1` 绑定 `repositoryId + projectConfigIdentity`；schema3 只用于 closed actor-bound project upgrade。

WARM 仅在 config、resolver result、repository IDs、Git tops、owner、impact 与 manifest 均未变化的同一 session 使用。drift 时 FULL_COLD。

task/taskActor/actionActor/role/phase/profile/capability 或 rule-source drift 重跑 DISCOVER；objective/action/result/scope drift 只使 boundary decision 失效。不得 per-tool-call reload。

ephemeral input/receipt 默认位于 `.ai-workspace/runtime/<task>/<actor>/`；project runtime 不可用时才用 system temp `aiw-*.json`。调用后删除 exact input；它不是 authority、project state 或 ledger。

执行 action，或声称 `TERMINAL`、`MESSAGE`、`HANDOFF`、`HOT_STATE` transition 前，必须从 current authority、分别验证的 CONTROL/TARGET Git tops、current package、public decision 与 authenticated host envelope 生成 strict `ephemeral` input；任一 mandatory fact 缺失或冲突都 `fail closed`。通用 `WORKFLOW_ROUTE_RESOLVE` 仍从 pinned `<FW>/TOOLCHAIN.json` 解析；Maintenance process requirements 使用 target 根级前门。调用后删除 exact input；它不是 authority、project state 或 ledger。

## 3. Action 前

报告 recovery mode、control/target Git tops、repository ID、baseline、Owner、taskActor/actionActor、objective、exact/forbidden paths、validation、两个 dirty boundary、Controller ID/epoch、authorization 与 single next action。

没有 valid package 时两个 repo 都 read-only。`CONTROL_WRITE` 只对 `CONTROL`；Framework source/test action 只对 configured target repository ID。control/target 写入分别建 package，Git 观察使用根级 `scripts/invoke-framework-maintenance-safe-git.ps1`。Review、Git、push、external 保持独立。

纯 `REVIEW_EXECUTE` package 可把 independent Reviewer 设为临时 grantee，但不改 task Owner/Work route/candidate。fresh authorization 不自动要求 Controller relay 或 FULL_COLD。DOMAIN_OWNER 直接选择 temporary actor/Reviewer 并接收 terminal result；只有 Controller-owned next action 或明确 exception 才路由 PROJECT_CONTROLLER。

本 Bootstrap 是 steady-state recovery contract，不是 directory migration procedure。创建/移动两个 repo 与退役旧 control plane 是另行授权的 project-specific offline task；该任务完成并由 fresh FULL_COLD 接受前，previous authority 不变。
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
此 legacy region 当前没有 permanent project process rule。structured rules 位于 `.ai-workspace/process-policy.json`。
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

CONTROL execution authority 包含 pinned Framework、still-effective corrections 与 permanent project policy rules。current process resolver 是唯一 composer；correction command 只是 legacy report view。

本 block 在采用 older/alternate Framework 时保留，不引入 target control plane、role、task、ledger、background service 或第二 state object。
<!-- PROJECT-CORRECTIONS:END -->
