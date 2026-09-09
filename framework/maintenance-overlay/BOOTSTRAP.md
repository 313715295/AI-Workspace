<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI 入口

Project ID=`{{PROJECT_ID}}`；layout=`framework-maintenance-sibling`；control plane=`.ai-workspace/`；pinned Framework=`{{FRAMEWORK_VERSION}}`。这是唯一 dynamic authority entry。chat、sibling state、memory、root HEAD、tag 与 network state 只作 locator。

## 1. 定位与校验

1. 从 supplied cwd 解析 Maintenance control Git top。严格读取 `.ai-workspace/project.json`：要求 schema4、`repositoryRoot=..`、expected project ID/pin、`frameworkToolBackend=powershell7`、empty `frameworkCapabilities`，以及一个 non-CONTROL repository ID、安全 sibling directory 与 literal routine exclusions。
2. 严格读取 `.ai-workspace/controller.json`：相同 project ID、controller ID 非空、epoch >= 1、`state=CURRENT`。
3. 不跟随 reparse 解析 control Git root parent；parent 不得含 `.git` 或 `.ai-workspace`。只连接已校验的单一 target directory component，不搜索其他目录，也不接受 absolute/`..` locator。
4. 固定包采用后，从原采用记录的 runtimeRoot 调用内部根级 resolve-framework-maintenance-target.ps1；返回 controlRoot、开发 targetRoot 与运行 runtimeRoot。尚无固定包绑定时沿 target 根级旧入口恢复。版本规则和根适配器从已验证的 runtimeRoot 解析；target 只保持开发仓与 Git 拓扑，不是固定包的执行来源。
5. 严格校验 CONTROL corrections 与 process policy，包括 `selectedRulePackBytes`。Maintenance 调用根级 `scripts/resolve-framework-maintenance-process-requirements.ps1`；该前门复用 pinned version 的唯一 composer，不建立第二 composer。显式标准来源可位于 CONTROL 内或本机其他用户维护目录；只读引用不改变 repository ownership，也不授权写来源。
6. resolver 必须返回 `controllerState=CURRENT`，target 不得有 canonical `.ai-workspace`。target control entry、missing component、intermediate reparse、parent authority、pin/config/controller drift 或 Git-top conflict 都 fail closed。

`<FW>`、`<CONTROL>`、`<TARGET>` 只使用 resolver 的 exact 结果。

固定包采用后，先读取既有 .ai-workspace/upgrade-recovery/<pin>/state.json 的 distributionBinding（新注册使用既有 registration transaction 的 metadata）。runtimeRoot 是唯一实际运行来源，distributionId/contentIdentity/manifestIdentity 必须与该目录的 PACKAGE_MANIFEST 及全部文件一致；不从开发目录、HEAD或最新ZIP回退。未完成事务先通过保留的旧健康入口恢复，不运行未知新目标。尚无固定包绑定的旧项目保持原入口，仅由显式升级接入固定包。Maintenance 的 target repository 仍是开发对象，内部运行包只提供工具与规则，不持有控制面。
## 2. Recovery 与 load

1. 轻读 Maintenance `STATUS.md` 与 `tasks/README.md` 只定位 assigned task；绑定 Owner、authenticated Work route、profile、objective/action/result、selected repository、exact scope 与 protection。
2. 先按已解析的 `<FW>/TOOL_CONTRACT.md` 中“IntentEnvelope 构造”唯一合同，由当前模型依据本次真实请求及仍有效上下文形成 DISCOVER 输入；再在 normative module 前执行 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`；一次读取所有 returned exact complete blocks，后续只保留 compact receipt。
3. 只读 selected rules/task 要求的 Maintenance facts、target evidence、schemas、templates 与 action artifacts。target work 在 scope 时显式读取 `<TARGET>/AGENTS.md`；sibling instruction 不自动继承。普通资料链接不自动成为规范依赖；外部标准只有经 process-policy 显式绑定后才进入当前来源快照。
4. `LOAD_PLAN_RESOLVE` 只用于 compatibility、non-rule support、Framework-wide explanation/maintenance 或 bounded fallback，不是 pre-DISCOVER gate。
5. 分别重证 control/target HEAD、index、dirty。safe-Git 每次只绑定一个 repository ID 与 bounded literal paths；一个 repo 的 VERIFIED 不能填补另一个 repo 的 UNVERIFIED。
6. 复检 current package。Maintenance 通过根级 `scripts/check-framework-maintenance-authorization.ps1` 绑定 `repositoryId + projectConfigIdentity`；可选 continuation receipt 由同一根级 authorization/process adapter 透传给 pinned version checker/resolver，仍重验 CONTROL/TARGET topology 与 current bytes。schema3只用于closed actor-bound project upgrade。

WARM、`FULL_COLD`、source composition、boundary decision 与 compaction 后当前模型正文恢复，全部按 `<FW>/RECOVERY_CORE.md` 的唯一规则判定；Maintenance Bootstrap 不复制失效清单。CONTROL/TARGET 拓扑事实仍分别复证，但 fresh authorization、tool call 或 routine progress 自身不推导全文重载。

ephemeral input/receipt 默认位于 `.ai-workspace/runtime/<task>/<actor>/`；project runtime 不可用时才用 system temp `aiw-*.json`。调用后删除 exact input；它不是 authority、project state 或 ledger。

执行 action，或声称 `TERMINAL`、`MESSAGE`、`HANDOFF`、`HOT_STATE` transition 前，必须从 current authority、分别验证的 CONTROL/TARGET Git tops、current package、public decision 与 authenticated host envelope 生成 strict `ephemeral` input；任一 mandatory fact 缺失或冲突都 `fail closed`。通用 `WORKFLOW_ROUTE_RESOLVE` 仍从 pinned `<FW>/TOOLCHAIN.json` 解析；Maintenance process requirements 使用 target 根级前门。调用后删除 exact input；它不是 authority、project state 或 ledger。

## 3. Action 前

报告 recovery mode、control/target Git tops、repository ID、baseline、Owner、taskActor/actionActor、objective、exact/forbidden paths、validation、两个 dirty boundary、Controller ID/epoch、authorization 与 single next action。

没有 valid package 时两个 repo 都 read-only。`CONTROL_WRITE` 只对 `CONTROL`；Framework source/test action 只对 configured target repository ID。control/target 写入分别建 package，Git 观察使用根级 `scripts/invoke-framework-maintenance-safe-git.ps1`。Review、Git、push、external 保持独立。

纯 `REVIEW_EXECUTE` package 可把 independent Reviewer 设为临时 grantee，但不改 task Owner/Work route/candidate。显式 `continuationPlan` 也只在原 package 已授予的本地写/测步骤间承接真实 postimage，不转移 Owner/Work route，不包含 Review/Git/external gate。fresh authorization 不自动要求 Controller relay 或 FULL_COLD。DOMAIN_OWNER直接选择temporary actor/Reviewer并接收terminal result；只有Controller-owned next action或明确exception才路由PROJECT_CONTROLLER。

Maintenance 自身的已审根来源整合只按 `<TARGET>/framework/FRAMEWORK_RELEASE.md` 的根来源自更新流程执行；Bootstrap 仅导航，不复制事务、恢复或收尾合同。

本 Bootstrap 是 steady-state recovery contract，不是 directory migration procedure。创建/移动两个 repo 与退役旧 control plane 是另行授权的 project-specific offline task；该任务完成并由 fresh FULL_COLD 接受前，previous authority 不变。
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

CONTROL execution authority 包含 pinned Framework、still-effective corrections 与 permanent project policy rules。current process resolver 是唯一 composer；correction command 只是 legacy report view。

本 block 在采用 older/alternate Framework 时保留，不引入 target control plane、role、task、ledger、background service 或第二 state object。
<!-- PROJECT-CORRECTIONS:END -->
