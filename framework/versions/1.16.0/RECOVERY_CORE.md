# Framework 1.16.0 recovery core

<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:BEGIN -->
Recovery 只证明 authority 与 current facts；它不授予 write、test、Review、Git、browser/device 或 external capability。

## 必需顺序

1. 不信任 chat 或 memory，先证明实际 cwd 与 Git top。
2. 严格读取项目 repo-local `.ai-workspace/project.json`、`controller.json`、`corrections.json` 与 `BOOTSTRAP.md`，包括项目级 `frameworkToolBackend`。
3. 只解析 `framework/versions/<project.json.frameworkVersion>/`。普通采用必须校验 stable `VERSION.json`、`RELEASE_MANIFEST.json`、`TOOLCHAIN.json` 与生成的 process-requirement catalog；显式本地候选试点则必须由 root upgrader 的既有 `upgrade-recovery/<version>/state.json` 证明 `LOCAL_PILOT`，并让其中的 candidate canonical、manifest identity 与当前候选快照一致。
4. 绑定 current task、authenticated actor、`role + phase` Work route、profile、exact scope、protection boundary、capabilities 与 current Review profile。只读取证明这些输入所需的项目 facts。
5. 在 `DISCOVER` 前，由当前主会话模型按 sealed `TOOL_CONTRACT.md` 的唯一 IntentEnvelope 构造段，从原始请求与仍有效上下文重建当前 objective/action/result/scope；authority 与授权另行核对。再解析 `PROCESS_REQUIREMENTS_RESOLVE`，对完整生成 catalog、仍有效 corrections 与当前 permanent project-rule carrier 执行 `DISCOVER`。
6. 一次加载 `DISCOVER` 返回的每个精确完整 Markdown rule block；后续仅保留 compact receipt。已知合法的 facts、evidence、schemas、templates 与专业材料可同批取得，发现新依赖才补读。
7. `LOAD_PLAN_RESOLVE` 只用于 1.14 compatibility、Framework-wide explanation/maintenance、non-rule supporting artifact，或 affected module block mapping 无法证明时的 bounded fallback。它不筛选 catalog，也不创建第二个规则决策。
8. selected rule 或 intended action 要求时，用当前 version 的 safe-Git helper 重新证明 protected paths 与真实 Git state。
9. 报告 unique next action、writer/reviewer/authorization state 与 evidence ceiling。

project pin 是唯一版本 authority；root HEAD/tag/network/其他项目 pin 均非 fallback。命名包另由既有 adoption state 的 distributionId/contentIdentity/manifestIdentity/runtimeRoot 固定完整来源；漂移或事务未完拒绝运行，按原授权恢复，不转回开发根。controller.json 唯一确定当前 Controller ID/epoch，历史 literal 只作 audit。

普通 pin 非 sealed stable 则阻断。已完成 root -LocalCandidatePilot 准入后，仅复核 LOCAL_PILOT 与当前 candidate 快照，不重跑完整测试、Source Review 或旧 schema3 授权。schema4+ 的 transactionComplete=true 证明完成，false 须原授权续完；快照或绑定漂移拒绝。完成态不读取历史升级任务，允许其更新/归档；当前 task 仍由 DISCOVER 独立校验。

<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:BEGIN -->
`DISCOVER` 从完整 sealed catalog 选择并校验 fragment/Markdown locator，返回完整 `fullText` 与 obligations，不授予权限。每个独立 action 用 `ADMIT_ACTION`，最终输出前用 `FINALIZE_OUTPUT`；二者复用 compact receipt，UNKNOWN 或 mapping 缺口只保守扩到 affected block/module。无适用 task 的解释/现状/方案使用 `PROJECT_READ_ONLY`，仅允许 `NONE + PLAN/USER_RESPONSE`。

Recovery 分开维护：`source composition`=来源身份及 task/task actor/action grantee/role/phase/profile/capability；`boundary decision`=objective/exact scope/action/result/authorization/receipt；`current model fullText availability`=当前模型实际持有的 selected blocks。standard locator/path/whole identity/section/dependency 属于 source binding。事实变化只重建受影响项；actual authority、task route 或 phase drift 不得沿用。健康来源、选择和正文可复用；fresh authorization、tool call、progress、authorized postimage 或 continuation receipt 只失效相关 decision，不自动全文重载、`FULL_COLD` 或复活已解决问题。

compaction、pause/resume、handoff 或正文不确定时，对齐最新请求、已观察结果与 next action；下一 substantive action 前读取 current `DISCOVER` 的每个 `fullText`。summary、cache、source hash、compact/continuation receipt、旧 receipt 或“机械校验通过”不能证明正文已在当前模型上下文：正文丢失只恢复正文，composition/decision 漂移才重建。

input/receipt 默认进被忽略的 `.ai-workspace/runtime/<task>/<actor>/`，不可用才用 system temp 并暴露 ceiling；清理遵循 `TOOL_CONTRACT.md` 的 receipt lifecycle，尤其 continuation 引用的原 compact 必须留到最后消费者完成。机械 PASS 不证明 semantic correctness、模型 attention 或 host invocation。
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:END -->

<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:BEGIN -->
Recovery 分别报告 current task owner、任务 Work route actor 与临时 action grantee/Reviewer/resource route。健康的 same-task role/action rebind 可以使用 NONE/WARM recovery 加新 package；仅 package invalidation 不要求 FULL_COLD 或 Controller issuance。

1.11/1.12 两字段 route 可在 `LEGACY_ACTOR_CONTEXT_UNBOUND` 下只读恢复。升级到要求 `actor + role + phase` 的 release 时，先在 target projection 中迁移任务卡并完成 resolver preflight，再原子写入项目 pin；不得先让旧 resolver 因两字段格式或旧预算阻断升级。
<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:END -->

<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:BEGIN -->
backend selection 是 project-level Framework-use configuration，不是 task/action authority。调用 operation 前，必须让项目选择精确匹配 `TOOLCHAIN.json`，并满足 declared runtime/platform。selection change 通过 `projectConfigIdentity` 使未完成 package 失效，并要求安全 project adoption boundary 与 fresh recovery。unknown backend、missing entrypoint、unsupported platform 或 unavailable runtime 必须 fail closed；不得自动 fallback、install 或生成 adapter。
<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:END -->
