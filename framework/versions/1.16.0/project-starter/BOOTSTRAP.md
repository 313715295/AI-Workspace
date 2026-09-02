<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI entry

Project ID=`{{PROJECT_ID}}`; repo-local control plane=`.ai-workspace/`; pinned Framework=`{{FRAMEWORK_VERSION}}`. This is the only entry. Chat, legacy summaries, memory, root HEAD, tags and network state are locators only, never authority.

## 1. Locate and validate

1. Strictly read `.ai-workspace/project.json`; require schema4, repo-local layout, `repositoryRoot=..`, the expected project ID and pin, `frameworkToolBackend=powershell7`, an array-valued `routineExcludedPaths`, an object-valued `frameworkCapabilities` and the exact structured process-policy locator. The capability object may be empty or contain only the pinned Framework's exact `KNOWLEDGE_REFERENCE` shape; unknown/duplicate fields and enabled-without-literal-index fail closed.
2. Strictly read `.ai-workspace/controller.json`; require the same project ID, a non-empty controller ID, integer epoch at least 1, and `state=CURRENT`.
3. From mounted workspaces uniquely locate the AI-Workspace that contains both `README.md` and `framework/versions/{{FRAMEWORK_VERSION}}/RECOVERY_CORE.md`. Zero or multiple matches fail closed.
4. The pinned stable version must be complete and canonically sealed. Strictly read its payload-sealed `TOOLCHAIN.json`; require an exact project backend match, `OFFICIAL` status, the current platform and an available `pwsh` Core runtime at major version 7 or later. Resolve every Framework operation through its exact manifest entrypoint. Do not repair it from another version, tag, HEAD or network state.
5. Strictly validate `.ai-workspace/corrections.json` and the configured `.ai-workspace/process-policy.json`. They remain independent project authorities; the process resolver composes them with sealed Framework rules without merging source ownership.
6. The complete repo-local plane is the only live project authority. Any external historical copy is a locator only and is never read for routing. Partial, reparse, identity conflict or unknown control bytes fail closed.

`<FW>` below means the uniquely located stable `framework/versions/{{FRAMEWORK_VERSION}}` directory. Operation names below are resolved through `<FW>/TOOLCHAIN.json`; shown script locators identify the current `powershell7` mapping, not an independent selection rule.

## 2. Recover and load

1. Lightly read project `STATUS.md` and `tasks/README.md` only to locate the assigned task, then bind its current header, authenticated actor, `role + phase`, profile, objective/action/result, capabilities, exact scope and protection boundary. The task card is authority; the index is only a projection.
2. Resolve `PROCESS_REQUIREMENTS_RESOLVE` and invoke `DISCOVER` over the complete sealed metadata catalog plus current corrections and project policy. Do this before loading normative modules. Read every exact complete Markdown block returned once, and retain only the separate compact receipt for later boundary checks.
3. Read only the additional project facts, evidence, schemas, templates or other action-required artifacts named by the selected rules and current task. The full assigned task remains current authority; unrelated Framework module bodies do not.
4. Use `LOAD_PLAN_RESOLVE` only for 1.14 compatibility, non-rule supporting artifacts or a bounded affected-module fallback. A missing/conflicting block mapping loads the affected module safely; it never becomes a second catalog filter or broad protected-path fallback.
5. Reprove the real Git top, current object identities, owners, authorization package, and every protected visibility/read/hash/diff/index/write boundary required by the selected rules or intended action. Git inventory/status/diff/index resolves operation `PROTECTED_SAFE_GIT` and invokes its sealed entrypoint with a frozen project config identity and bounded allowlist; `UNVERIFIED` is an honest result and never triggers a broad fallback.

WARM rebinding is allowed only inside the same healthy session when identity and impact have not changed. It does not inherit old authorization. Any identity, owner, impact, controller epoch or protection conflict escalates to FULL_COLD.

Rerun DISCOVER when task, actor, Work role/phase, profile, capability or a rule-source identity changes. Objective/action/result/exact-scope changes rebuild only the boundary decision. Continuous work reuses unchanged selected rules; do not reload per tool call or authorization refresh.

Before any task launch/routing, terminal delivery, authenticated message, Controller handoff or hot-state projection, derive one strict ephemeral input from the just-loaded authority, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope. Resolve operation `WORKFLOW_ROUTE_RESOLVE` and invoke its sealed entrypoint with `-InputPath <ephemeral-input> -AsJson`; missing input fails closed. Remove the input after use. It is not project state, authority or a ledger.

## 3. Before actions

Report recovery mode, baseline, unique owner, objective, profile/reachability, exact/forbidden paths, validation, Git/external state, protection boundaries, current controller identity/epoch, current authorization and the single next action.

Without a valid package, remain read-only. Every package binds the current whole-task identity and task-bound actor. DOMAIN_OWNER packages stay in their domain and omit controller fields. PROJECT_CONTROLLER packages bind current controller ID, epoch and whole-file identity. Schema3 is admitted only for the closed actor-bound project-upgrade bundle. Before a distinct action invoke `ADMIT_ACTION`; both it and the independent action checker must pass.

Immediately before final user/consumer output invoke `FINALIZE_OUTPUT` against the actual result/delivery receipts. Delete the compact receipt after finalization, invalidation or abort. Complete safely missing work or return the exact blocker; a missing/not-delivered marker is not completion. Structural PASS never proves semantic correctness or host enforcement.

Routine owner states go directly to their consumers. In the same domain task, the DOMAIN_OWNER directly selects eligible temporary actors/Reviewers, issues their packages and receives their terminal result; candidate writer/material contributors remain excluded from CRITICAL independent Review. The controller pulls current cards and receives only owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external, resource-conflict, routine-exclusion and object-drift exceptions. Do not build an ACK chain. Product decisions are asked by the responsible domain owner.

`frameworkCapabilities={}` or `KNOWLEDGE_REFERENCE.enabled=false` means no optional capability is enabled. When explicitly enabled, use `check-knowledge-entry.ps1 -Operation DISCOVER` for compact IDs/titles/tags, select zero to three relevant IDs from current task semantics, then use `-Operation QUERY -EntryId <ids>`. Missing, stale or conflicting requested references return per-entry `UNAVAILABLE` and the formal recovery chain continues; an unrelated stale entry does not block a fresh request. After actual authority files change, run read-only `check-knowledge-impact.ps1` at the normal Review/OWNER_ACCEPT boundary and refresh or mark only `DIRECT_AFFECTED`/`UNKNOWN` entries stale. Knowledge never grants authority or actions, and no background polling or automatic write exists.
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
No permanent project process rule is active in this legacy region. Structured rules belong to `.ai-workspace/process-policy.json`.
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

Project execution authority is the pinned Framework plus every still-effective correction and permanent project-specific process rule. `PROCESS_REQUIREMENTS_RESOLVE` is the only current composer. Invoke it through `framework/versions/1.16.0/scripts/resolve-process-requirements.ps1`; the compatibility view at `framework/versions/1.16.0/scripts/check-project-corrections.ps1` uses the same composer and is never a second parser or effective set. These explicit locators stay in this preserved block so a downgrade can still evaluate correction records with the newest adopted correction contract.

This block is retained when adopting an older or alternate Framework version, so the same records are re-evaluated rather than deleted. It adds no role, task, ledger, background service or authority beyond `corrections.json`.
<!-- PROJECT-CORRECTIONS:END -->
