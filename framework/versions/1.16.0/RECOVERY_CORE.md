# Framework 1.16.0 recovery core

<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:BEGIN -->
Recovery 只证明 authority 与 current facts；它不授予 write、test、Review、Git、browser/device 或 external capability。

## 必需顺序

1. 不信任 chat 或 memory，先证明实际 cwd 与 Git top。
2. 严格读取项目 repo-local `.ai-workspace/project.json`、`controller.json`、`corrections.json` 与 `BOOTSTRAP.md`，包括项目级 `frameworkToolBackend`。
3. 只解析 `framework/versions/<project.json.frameworkVersion>/`。普通采用必须校验 stable `VERSION.json`、`RELEASE_MANIFEST.json`、`TOOLCHAIN.json` 与生成的 process-requirement catalog；显式本地候选试点则必须由 root upgrader 的既有 `upgrade-recovery/<version>/state.json` 证明 `LOCAL_PILOT`，并让其中的 candidate canonical、manifest identity 与当前候选快照一致。
4. 绑定 current task、authenticated actor、`role + phase` Work route、profile、exact scope、protection boundary、capabilities 与 current Review profile。只读取证明这些输入所需的项目 facts。
5. 通过 sealed Tool Contract 解析 `PROCESS_REQUIREMENTS_RESOLVE`，对完整生成 catalog、仍有效 corrections 与当前 permanent project-rule carrier 执行 `DISCOVER`。
6. 一次加载 `DISCOVER` 返回的每个精确完整 Markdown rule block；后续只保存 compact receipt，再取得规则要求的 facts、evidence、schemas、templates 或其他 action artifacts。
7. `LOAD_PLAN_RESOLVE` 只用于 1.14 compatibility、Framework-wide explanation/maintenance、non-rule supporting artifact，或 affected module block mapping 无法证明时的 bounded fallback。它不筛选 catalog，也不创建第二个规则决策。
8. selected rule 或 intended action 要求时，用当前 version 的 safe-Git helper 重新证明 protected paths 与真实 Git state。
9. 报告 unique next action、writer/reviewer/authorization state 与 evidence ceiling。

project pin 是唯一 Framework-version authority。root HEAD、tag、network state 或其他项目 pin 都不是 fallback。`controller.json` 是当前 Controller ID/epoch 的唯一字面真相；历史 literal ID 只用于 audit。

普通 pin 不是 sealed stable release 时返回最窄 blocker。唯一例外是已经通过 root `-LocalCandidatePilot` 完成的一次性准入：后续 recovery 只复核 `LOCAL_PILOT` 绑定与候选快照未漂移，不重跑完整测试、Source Review 或旧 schema3 授权，也不要求 current task 保持升级时的 postimage。候选快照或试点绑定不一致时仍 fail closed。
<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:BEGIN -->
`DISCOVER` 在加载 normative module text 之前，对完整 sealed metadata catalog 进行选择。composer 校验每个 selected fragment locator 与 owning Markdown module，返回完整 block text 及 fragment 声明的 preparation/result requirements；它不授予权限。

每个独立 governed action boundary 调用 `ADMIT_ACTION`；向用户或 consumer 输出最终结果前立即调用 `FINALIZE_OUTPUT`。两者都消费同一 exact compact `DISCOVER` receipt，不再复制完整 rule blocks。finalization、invalidation 或 abort 后删除 receipt。semantic applicability 为 UNKNOWN 时保守选择受影响 blocks。mapping 缺失或冲突时先加载 affected module 中全部 mapped blocks；只有 module mapping 不完整时才 fallback 到该完整 module，绝不扩展到整个 Framework。

初次 recovery、compaction、pause/resume、handoff 或 context uncertainty 必须重建 current source composition 与 decision。task、task actor/action grantee、role、Work phase、profile、capability 或 source-authority change 也重建 composition。objective、exact-scope、action 或 result change 只重建 boundary decision；source identities 与 selected rule bodies 未变化时可以复用。不得按每次 tool call 或 authorization refresh 重载。

一次性 input/receipt 默认位于 `.ai-workspace/runtime/<task>/<actor>/`，并受项目 `.gitignore` 保护；仅在该目录不可用时使用 system temp `aiw-*.json`，同时暴露 evidence ceiling。

机械 PASS 从不证明 semantic correctness、model attention 或 host invocation。invocation 不可用或未观察时，只报告真实 evidence ceiling，不声称 enforcement。
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:END -->

<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:BEGIN -->
Recovery 分别报告 current task owner、任务 Work route actor 与临时 action grantee/Reviewer/resource route。健康的 same-task role/action rebind 可以使用 NONE/WARM recovery 加新 package；仅 package invalidation 不要求 FULL_COLD 或 Controller issuance。

1.11/1.12 两字段 route 可在 `LEGACY_ACTOR_CONTEXT_UNBOUND` 下只读恢复。升级到要求 `actor + role + phase` 的 release 时，先在 target projection 中迁移任务卡并完成 resolver preflight，再原子写入项目 pin；不得先让旧 resolver 因两字段格式或旧预算阻断升级。
<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:END -->

<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:BEGIN -->
backend selection 是 project-level Framework-use configuration，不是 task/action authority。调用 operation 前，必须让项目选择精确匹配 `TOOLCHAIN.json`，并满足 declared runtime/platform。selection change 通过 `projectConfigIdentity` 使未完成 package 失效，并要求安全 project adoption boundary 与 fresh recovery。unknown backend、missing entrypoint、unsupported platform 或 unavailable runtime 必须 fail closed；不得自动 fallback、install 或生成 adapter。
<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:END -->
