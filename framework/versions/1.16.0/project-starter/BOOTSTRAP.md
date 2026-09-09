<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI 入口

Project ID=`{{PROJECT_ID}}`；repo-local control plane=`.ai-workspace/`；pinned Framework=`{{FRAMEWORK_VERSION}}`。这是唯一入口。chat、legacy summary、memory、root HEAD、tag 与 network state 只作 locator，不是 authority。

## 1. 定位与校验

1. 严格读取 `.ai-workspace/project.json`：要求 schema4、repo-local、`repositoryRoot=..`、expected project ID/pin、`frameworkToolBackend=powershell7`、array `routineExcludedPaths`、closed `frameworkCapabilities` 与 exact process-policy locator。
2. 严格读取 `.ai-workspace/controller.json`：project ID 相同、controller ID 非空、epoch integer >= 1、`state=CURRENT`。
3. 先从原采用记录定位已绑定的固定 runtimeRoot 并验证 distribution/content/manifest 身份；有绑定时只使用该目录。尚无固定包绑定的旧项目，才在 mounted workspace 中唯一定位包含所选版本的 AI-Workspace；零个或多个候选均 fail closed。显式升级完成后退出该旧定位方式。
4. 普通采用的 pinned stable version 必须完整且 canonical sealed。若项目由 root `-LocalCandidatePilot` 显式进入本地候选试点，则只接受 `.ai-workspace/upgrade-recovery/<version>/state.json` 绑定的 exact candidate canonical 与 manifest identity；后续 recovery 不重跑准入时的完整测试、Source Review 或 schema3 授权，也不把升级时 task postimage 当长期条件。两种模式都严格读取 exact `TOOLCHAIN.json`，要求 backend、当前 platform 与 `pwsh` Core >= 7，并只从 exact manifest entrypoint 解析；不得从其他 version/tag/HEAD/network repair。
5. 严格校验 `.ai-workspace/corrections.json` 与 `.ai-workspace/process-policy.json`。policy 必须含 `selectedRulePackBytes`，范围 `1..98304`；两者保持独立 project authority。标准正文只从 policy 明确绑定的项目内相对文件或本机绝对文件读取；外部文件仍由使用者维护，读取不授予修改权限。
6. root `.gitignore` 必须有且只有一个等价 `/.ai-workspace/runtime/` exclusion，不能有对应 negation。完整 repo-local plane 是唯一 live project authority；partial、reparse、identity conflict 或 unknown control bytes fail closed。

`<FW>` 指上述唯一通过 stable seal 或 bounded `LOCAL_PILOT` snapshot 校验的 `framework/versions/{{FRAMEWORK_VERSION}}`。下列 operation name 都通过 `<FW>/TOOLCHAIN.json` 解析。

## 2. Recovery 与规则加载

1. 轻读 `STATUS.md` 与 `tasks/README.md` 只为定位 assigned task；随后绑定 current header、Owner、authenticated Work route actor/role/phase、profile、objective/action/result、capabilities、exact scope 与 protection boundary。task card 是 authority，index 只是 projection。
2. 先按已解析的 `<FW>/TOOL_CONTRACT.md` 中“IntentEnvelope 构造”唯一合同，由当前模型依据本次真实请求及仍有效上下文形成 DISCOVER 输入；再在加载 normative module 前运行 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`，输入完整 sealed catalog、current corrections 与 project policy。存在任务时使用 task context；没有适用任务且仅做解释/方案/用户答复时使用 `PROJECT_READ_ONLY`，不得伪造 task。一次读取全部 returned exact complete Markdown blocks，后续只保留 compact receipt。
3. 只读取 selected rules 与 current task 要求的 project facts、evidence、schemas、templates 或 action artifacts。`PROJECT.md` 与 `REVIEW_PROFILE.md` 是薄入口；`RELATIONSHIPS.md` 仅在项目确有稳定关系图时存在。不得要求用户补齐与当前项目无关的模板，也不得把普通 Markdown 链接自动升级为规则依赖。
4. `LOAD_PLAN_RESOLVE` 只用于 1.14 compatibility、non-rule artifact 与 bounded affected-module fallback，不是 catalog filter 或 protected-path bypass。
5. selected rule/action 要求时，用 `PROTECTED_SAFE_GIT` 和 frozen project config identity 重证 Git top、object identity 与 read/hash/diff/index/write boundary。`UNVERIFIED` 不能触发 broad fallback。

WARM、`FULL_COLD`、source composition、boundary decision 与 compaction 后当前模型正文恢复，全部按 `<FW>/RECOVERY_CORE.md` 的唯一规则判定；本 Bootstrap 不复制失效清单。连续健康上下文可复用仍有效部分，fresh authorization、tool call 或 routine progress 自身不推导全文重载。

输入、紧凑收据保存和临时产物生命周期只取 `<FW>/TOOL_CONTRACT.md`。WORKFLOW_ROUTE_RESOLVE 支持直接 InputJson 或文件 InputPath，不重复维护保存/删除步骤。

执行 `TERMINAL`、`MESSAGE`、`HANDOFF`、`HOT_STATE` 等真实 transition 前，从 current authority、Git top、package、public decision 与 authenticated host envelope 构造 strict `ephemeral` input，按 `<FW>/TOOLCHAIN.json` 解析 WORKFLOW_ROUTE_RESOLVE；任一 mandatory fact 缺失/冲突都 fail closed。健康机械步骤可以同批编排，各门仍单独验证。

## 3. Action 前

报告 recovery mode、baseline、owner、taskActor/actionActor、objective、profile、exact/forbidden paths、validation、Git/external、protection、Controller ID/epoch、authorization 与 single next action。

没有 valid package 时保持 read-only。每个 package 绑定 current whole-task identity；一次纯临时 action，或显式 `continuationPlan` 的本地写/测批次，可让 grantee 不同于 task Work route actor，同时保持 task Owner、Work route 与 identity 不变，并按当前 action 形成临时执行/测试 context。Review/Git/browser/device/external 仍使用独立 gate；`REVIEW_ROUTE` 与 `OWNER_ACCEPT` 不走临时 actor。DOMAIN_OWNER package留在domain且省略Controller fields；PROJECT_CONTROLLER package绑定current controller object。schema3 authorization只用于closed actor-bound project-upgrade bundle。

每个独立 action 前调用 `ADMIT_ACTION`，并让 independent action checker 单独 PASS。最终输出前以 actual result/delivery receipts 调用 `FINALIZE_OUTPUT`。优先使用 schema3 DISCOVER 的 schema2 compact receipt 与 schema2 boundary input，后者不重复 objective/action/scope/authorization。原 package 若有可选 `continuationPlan`，只可用 FINALIZE 返回并绑定真实 postimage 的 continuation receipt 进入其下一已授予本地写/测步骤；下一边界继续重验 package、receipt 与 current bytes，且不改变 Owner/Work route。receipt保留至最后消费者，清理遵循TOOL_CONTRACT。`MISSING`/`NOT_DELIVERED` 不算完成；structural PASS 不证明 semantic correctness 或 host enforcement。

同一 domain task 中，DOMAIN_OWNER 直接选择 temporary actor/Reviewer、签发 package 并接收 terminal result。Controller 只接 owner/public-decision、cross-domain-contract、protected-path、project-phase、Git/device/external、resource-conflict、routine-exclusion 或 object-drift exception。不得建立 ACK chain。

`frameworkCapabilities={}` 或 `KNOWLEDGE_REFERENCE.enabled=false` 表示 optional capability 未启用。显式启用时，DISCOVER metadata 后最多 QUERY 三个 ID；Knowledge 不授予 authority/action，也没有 background polling/write。
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

project execution authority 由 pinned Framework、still-effective corrections 与 permanent project rules 共同组成，但 source ownership 不合并。`PROCESS_REQUIREMENTS_RESOLVE` 是唯一 composer；`check-project-corrections.ps1` 只是同一 composer 的 compatibility view。

采用 older/alternate Framework 时保留本 block，使相同 correction records 被重新评估而不是删除。它不增加 role、task、ledger、background service 或 authority。
<!-- PROJECT-CORRECTIONS:END -->
