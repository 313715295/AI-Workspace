# Tool Contract v1

Framework operation 是 language-independent contract。backend 是 adopting project 一次选择的 immutable implementation，不是 task role、action、resource route 或 authorization capability。

## PROCESS_REQUIREMENTS_RESOLVE

一个 source composer 提供三个 logical mode：

- `DISCOVER` 严格绑定 project、task whole identity、task Owner、task Work route actor、host-authenticated action actor、effective role/phase、profile、project-declared capabilities、objective/action/result kind 与 normalized exact scope。`pathHints` 必须位于 scope 内，`capabilityHints` 必须已观察，mutation/external hints 必须匹配 requested action。CLEAR contradiction 失败；UNKNOWN 保留 conservative-load ceiling，不能 admit governed action。resolver 对完整 generated metadata catalog 选择，校验 selected locator 与 owning Markdown module，一次返回每个 exact complete block，并另给只含 identities/obligations 的 compact receipt。still-effective corrections 与 permanent project rules 保持独立 source。
- 对纯 `REVIEW_EXECUTE`，package grantee 可以不同于 task Work route actor，但 task Owner、task identity 与 candidate 不变。receipt/AuthorityContext 同时绑定 `taskActor` 与 action `actor`，effective role/phase 为 `REVIEWER/REVIEW`。其他 action 仍要求 grantee、observed actor 与 task route 一致。
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

`requirements/fragments/*.json` 拥有 native requirement ID、deterministic selectors、exact Markdown locator 与 preparation/result gates。marked Markdown block 是唯一 native rule body。`PROCESS_REQUIREMENTS.json` 是 deterministic sealed metadata projection，只作为 internal operation input，不独立编辑，也不把 native rule body 加载进 model。host 只读取 DISCOVER 返回的 selected complete rules。

`LOAD_PLAN_RESOLVE` 保持 compatibility/support operation，可定位 non-rule supporting artifacts、Framework-wide maintenance/explanation context 与 bounded affected-module fallback；它不是 pre-DISCOVER catalog filter，不能静默排除 requirement。

legacy schema1 process input 只用于 discovery/evaluation compatibility。它没有 bound authorization package 或 complete AuthorityContext，因此 categorical governed action 不能通过 ADMIT/FINALIZE，并返回 `LEGACY_AUTHORITY_CONTEXT_UNBOUND`。governed action boundary 必须使用 schema2。

机械 PASS 只证明 current identities 与 supplied structural receipts，不证明 semantic correctness、model attention、host invocation 或独立 authorization/Review/Git/external gate。

## Target-before-pin adoption preflight

root project upgrade 从 `ADOPTION_PROFILE.json` 取得 direct sources 与 target behavior。对 profile target，它创建隔离的 target projection，写入 target project、Bootstrap、corrections、process policy、project-selected budget 与 migrated current task route，然后调用 target `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。只有 complete selected pack 在项目 ceiling 内 PASS 才可准备 actual transaction。

旧 current-process input 若提供，只作为 exact-bound user decision 来源，不执行 current-pin resolver；因此旧 budget 或 1.11/1.12 two-field task schema 不会形成 target-before-pin deadlock。

该 preflight 是 compatibility observation，不是 alternate resolver、authority 或 consumer fast path。schema3 actor-bound upgrade package、exact pre/postimages、protected paths、project decision、task-last write、forward recovery 与后续 Review/acceptance/Git/external gate 保持独立。

## Project selection

project authority field 是 `.ai-workspace/project.json.frameworkToolBackend`。`1.16.0` 只接受 `powershell7`；registration/upgrade deterministic 写入该值。所有 task/operation 继承它。authorization package 不重复该字段；既有 `projectConfigIdentity` 会在 selection 或其他 config byte 改变时使 package 失效。

host 先读 project pin，再读 pinned `TOOLCHAIN.json`。backend ID、`OFFICIAL` status、platform、runtime edition/version 与 exact entrypoint 都必须匹配。unknown field/backend、missing entrypoint、path escape、unavailable runtime 或 contract drift 在 operation 前 fail closed。Framework 不 install/download runtime。

## Router compatibility

唯一 canonical `ai-workspace-router` Skill 位于 repository root `skills/ai-workspace-router/SKILL.md`，只负责 navigation。`TOOLCHAIN.json.routerCompatibility.canonicalSkillPath` 绑定该路径，`versionContractPath` 指向 version 内的 `REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE` history file。

Framework 1.15+ 通过 sealed `TOOLCHAIN.json` 声明 exact operations、process-catalog schema/version 与 native rule-body source。1.14.0/1.14.1 只通过 root Skill 内的已知 Tool Contract identities 接入。declaration 缺失、冲突或 unknown 时，回到 pinned project Bootstrap 并报告 `INCOMPATIBLE_OR_UNKNOWN`。

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
