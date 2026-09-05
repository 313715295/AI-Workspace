# Tool Contract v1

Framework operation 是 language-independent contract。backend 是 adopting project 一次选择的 immutable implementation，不是 task role、action、resource route 或 authorization capability。

## PROCESS_REQUIREMENTS_RESOLVE

一个 source composer 提供三个 logical mode：

- `DISCOVER` 严格绑定 project、当前 task 或显式 `PROJECT_READ_ONLY` request context、host-authenticated actor、effective role/phase、profile、project-declared capabilities、objective/action/result kind 与 normalized exact scope。task context 继续绑定 whole task、Owner 与 Work route actor；只读 context 必须绑定 session/request 且只能使用 `NONE + PLAN/USER_RESPONSE`，不能伪造任务或绕过已知冲突。`pathHints` 必须位于 scope 内，`capabilityHints` 必须已观察，mutation/external hints 必须匹配 requested action。CLEAR contradiction 失败；UNKNOWN 保留 conservative-load ceiling，不能 admit governed action。resolver 对完整 generated metadata catalog 选择，校验 selected locator 与 owning Markdown module，一次返回每个 exact complete block，并另给 compact receipt。still-effective corrections 与 permanent project rules 保持独立 source。
- package grantee 可以作为当前一次 action 的临时 actor，而不改变 task Owner、Work route 或 task identity。resolver 只接受 package 中唯一且与请求相同的 action，并按 action 形成 `EXECUTOR/IMPLEMENT`、`EXECUTOR/VERIFY`、`REVIEWER/REVIEW`、`EXECUTOR/GIT` 或 `EXECUTOR/EXTERNAL` context；`REVIEW_ROUTE` 与 `OWNER_ACCEPT` 不走临时 actor。权限、独立性、Git 与 external gate 仍分别校验。
- `ADMIT_ACTION` 只消费 exact compact DISCOVER receipt，复检 task/Framework/catalog/coverage/project/correction/policy/custom identities，按 current exact object bytes 重跑 authorization observation，并校验 selected preparation；它不授予 action。
- `FINALIZE_OUTPUT` 做同样 source revalidation，并在实际 final output 前校验 observable result/delivery。每个 authorized exact path 必须恰有一个 `OBJECT_POSTIMAGE|<relative-path>|<byteLength|UPPER_SHA256>`，且匹配 current repository object。

UNKNOWN semantic applicability 保守加载规则。schema1 free-text correction 与 legacy PROJECT-CUSTOM 使用 full-source compatibility loading 和 unchanged-context reuse，并报告 `LEGACY_PROGRESSIVE_SELECTION_UNPROVEN`。

runtime selected-pack ceiling 只来自 `.ai-workspace/process-policy.json.selectedRulePackBytes`。该值必须是 `1..98304` 的 integer；Framework absolute cap 固定为 `98304`。pack 超过项目值即 `SELECTED_RULE_PACK_BUDGET_EXCEEDED`。不再设置 ordinary/absolute/legacy runtime tier 或 correction exception。

source composition、progressive selection 与 boundary decision identity 分离，并拥有各自 invalidators。selection 绑定完整 intent envelope，boundary decision 也绑定 discovered context identity。backend 可以重读 unchanged bytes，但 host 未观察时不得声称 physical cache hit。receipt 是 ephemeral、non-authoritative artifact，不是 repository ledger。

`-DeleteInputOnExit` 只删除经过安全验证的 exact input：

- 首选 project-local `.ai-workspace/runtime/<task>/<actor>/<safe-name>.json`，其中 task/actor 必须匹配 input binding，路径不得是 reparse；
- 只有 project runtime 不可用时，才接受 operating-system temp 下的 exact non-reparse `aiw-*.json`，并公开 fallback evidence ceiling；
- success 或 failure 都只删除该 exact file；unsafe cleanup request 在删除前失败。

caller 在 `FINALIZE_OUTPUT`、invalidation 或 abort 后立即删除 compact receipt。

schema3 DISCOVER 产生 schema2 compact receipt：authority/context 只保留在一个 `binding`，intent 只保留在一个 `intentEnvelope`，来源、义务、预算、证据与计数各自只有一个结构。schema2 ADMIT/FINALIZE input 只提交 receipt locator/identity 与新增 preparation/result/delivery evidence，不再复制 objective、action、scope 或 authorization identity。schema1/2 DISCOVER 与 schema1 boundary 只作为兼容输入保留。

project policy rule 的正文可以继续内联为 `effectiveRule`，也可以二选一声明 `source={rootSourceId,documents}`。每个 source document 绑定 project-relative locator、whole-file identity、`FULL_FILE` 或唯一 marked section、直接 dependency IDs 与 decision locator；dependency graph 必须闭合、无重复、无孤儿、无环。composer 在 selector 前验证全部 source bindings，模型只接收命中的当前正文。身份漂移时旧 selector/section 不再用于排除，当前全文保守加载并公开 `PROJECT_STANDARD_SOURCE_DRIFT_CONSERVATIVE_LOAD`；它不自动改写 policy，也不扩展扫描到全项目。

`requirements/fragments/*.json` 拥有 native requirement ID、deterministic selectors、exact Markdown locator 与 preparation/result gates。marked Markdown block 是唯一 native rule body。`PROCESS_REQUIREMENTS.json` 是 deterministic sealed metadata projection，只作为 internal operation input，不独立编辑，也不把 native rule body 加载进 model。host 只读取 DISCOVER 返回的 selected complete rules。

### 选择条件：结构边界、确定性触发与内容判断

selectors 原有八字段保持兼容：profile、role、phase、action、result、path、capability 先全部匹配，semanticTerms 才判断内容；空 terms 表示本条在结构边界内已确定适用。没有元数据依据，不得仅因动作非 NONE 就加载整组规则。

可选 `deterministicTriggers={actionKinds:[],resultKinds:[]}` 表示同一规则的另一条充分触发路径。只有上述结构条件全部通过，且当前已绑定 action 或 result 在所列集合内，才不再让关键词否决本条义务。两组至少一组非空；禁止 NONE、通配符、未知值、重复值及越出本条 action/result 边界的值。它不绕过授权、角色、范围或 UNKNOWN 拒绝，不创建第二份动作映射表。正式 Review 的视角选择由 REVIEW_EXECUTE 触发；普通讨论仍按本条内容条件，不能因此加载所有视角或全部 Review 流程。

可选 `semanticMatch=TOKEN` 对英文/数字/下划线词边界作大小写不敏感的字面匹配，阻止 preview 命中 review；不执行 regex、项目代码或否定句推理。省略它保留旧 SUBSTRING 解释。未声明新字段的项目 selectors 不静默改变，也不自动重写。三源使用同一匹配器但保留各自权威与身份；纠正记录新增字段会进入既有 canonical identity，不能复用旧吸收映射。

内容条件仍由 objective 与既有 semanticHints 表达；title/description 是供模型理解的索引说明，不是后端自然语言分类器。模型按原始要求理解并映射，不能拼接动作名来骗过匹配；有真实不确定性按既有 UNKNOWN 保守加载，UNKNOWN 不允许执行受治理动作。含“不要修改”等否定措辞的真实 Review 仍需 Review 义务；不能一律排除包含否定词的规则。结构 PASS 不证明模型的理解或任意自然语言的选取完整性。

项目不必为本次 Framework 原生修正迁移 selectors。只有项目希望启用新增触发表达/词边界模式时，才按原有显式修改与 Review 边界改变自己的记录；不新增迁移步骤、审批或 ledger。

`LOAD_PLAN_RESOLVE` 保持 compatibility/support operation，可定位 non-rule supporting artifacts、Framework-wide maintenance/explanation context 与 bounded affected-module fallback；它不是 pre-DISCOVER catalog filter，不能静默排除 requirement。

legacy schema1 process input 只用于 discovery/evaluation compatibility。它没有 bound authorization package 或 complete AuthorityContext，因此 categorical governed action 不能通过 ADMIT/FINALIZE，并返回 `LEGACY_AUTHORITY_CONTEXT_UNBOUND`。governed action boundary 必须使用 schema2。

机械 PASS 只证明 current identities 与 supplied structural receipts，不证明 semantic correctness、model attention、host invocation 或独立 authorization/Review/Git/external gate。

## Target-before-pin adoption preflight

root project upgrade 从 `ADOPTION_PROFILE.json` 取得 Project Format/capability 兼容声明与 target behavior，不按旧发行号列表放行。1.16作为新基线不声明跨pin direct source；新项目安装和同pin幂等修复仍可用。未来版本只有显式声明兼容结构时，才可创建隔离target projection，写入 target project、Bootstrap、corrections、process policy、project-selected budget 与 migrated current task route，再调用 target `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。只有 complete selected pack 在项目 ceiling 内 PASS 才可准备 actual transaction。

旧 current-process input 若提供，只作为 exact-bound user decision 来源，不执行 current-pin resolver；因此旧 budget 或 1.11/1.12 two-field task schema 不会形成 target-before-pin deadlock。

该 preflight 是 compatibility observation，不是 alternate resolver、authority 或 consumer fast path。schema3 actor-bound upgrade package、exact pre/postimages、protected paths、project decision、task-last write、forward recovery 与后续 Review/acceptance/Git/external gate 保持独立。

## Project selection

project authority field 是 `.ai-workspace/project.json.frameworkToolBackend`。`1.16.0` 只接受 `powershell7`；registration/upgrade deterministic 写入该值。所有 task/operation 继承它。authorization package 不重复该字段；既有 `projectConfigIdentity` 会在 selection 或其他 config byte 改变时使 package 失效。

host 先读 project pin，再读 pinned `TOOLCHAIN.json`。backend ID、`OFFICIAL` status、platform、runtime edition/version 与 exact entrypoint 都必须匹配。unknown field/backend、missing entrypoint、path escape、unavailable runtime 或 contract drift 在 operation 前 fail closed。Framework 不 install/download runtime。

## Router compatibility

唯一 canonical `ai-workspace-router` Skill 位于 repository root `skills/ai-workspace-router/SKILL.md`，只负责 navigation。`TOOLCHAIN.json.routerCompatibility.canonicalSkillPath` 绑定该路径，`versionContractPath` 指向 version 内的 `REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE` history file。

当前受支持版本通过 sealed `TOOLCHAIN.json` 声明 exact operations、process-catalog schema/version 与 native rule-body source。Router 不按发行号内置兼容白名单；declaration 缺失、冲突或 unknown 时，回到 pinned project Bootstrap 并报告 `INCOMPATIBLE_OR_UNKNOWN`。

install/update host-global Skill 是独立 explicit host-write action。registration/upgrade 不执行安装，也不创建 installation registry/ledger。

## Invocation

operation name 与 entrypoint path 只来自 `TOOLCHAIN.json`。path 是 version-root-relative、NFC-normalized、forward-slash locator，不得 absolute、drive、empty component、`.` 或 `..`。host 直接调用 selected entrypoint，不提供 user-facing launcher 或 generated wrapper。

official backend 使用 `pwsh -NoProfile -NonInteractive -File <entrypoint> ...`。每个 `1.16.0` entrypoint 独立拒绝 non-Core runtime 或 PowerShell major < 7。

## Results 与 evidence

exit code `0` 表示 operation 返回 documented accepted result；nonzero 使 requested boundary 失败，caller 保留 explicit reason，不从 prose 猜测成功。支持时优先用 structured `-AsJson`。human-readable output 只是同一 result 的 projection，不是 authority object。

file identity 为 exact bytes 上的 `byteLength|UPPER_SHA256`。JSON/Markdown 使用 strict UTF-8 no BOM 与 LF。security-relevant JSON 在 escape decoding 后递归拒绝 duplicate members。repository-relative evidence 使用 forward slashes。

`1.16.0` 只列 Windows。未来 platform 只有在实际 conformance run PASS 后才受支持；missing CI/host evidence 是 capability ceiling，不得推断 compatibility。

## Backend lifecycle

backend selection 只在 released Framework 已提供 target backend 的 project adoption/switch boundary 改变。项目必须没有 active writer/reviewer lease，通过 project config drift 使 outstanding package 失效，transactionally 投影 config，并完成 fresh recovery/conformance。`1.16.0` 只有一个 backend，因此不提供 switch command。

本 contract 不增加 backend registry、service、ledger、plugin market、runtime code generation、task-level choice 或 global Framework default。
