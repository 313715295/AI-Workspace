<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI entry

Project ID=`{{PROJECT_ID}}`; repo-local control plane=`.ai-workspace/`; pinned Framework=`{{FRAMEWORK_VERSION}}`. This is the only entry. Chat, legacy summaries, memory, root HEAD, tags and network state are locators only, never authority.

## 1. Locate and validate

1. Strictly read `.ai-workspace/project.json`; require schema3, repo-local layout, `repositoryRoot=..`, the expected project ID and pin, `frameworkToolBackend=powershell7`, an array-valued `routineExcludedPaths` and an object-valued `frameworkCapabilities`. The capability object may be empty or contain only the pinned Framework's exact `KNOWLEDGE_REFERENCE` shape; unknown/duplicate fields and enabled-without-literal-index fail closed.
2. Strictly read `.ai-workspace/controller.json`; require the same project ID, a non-empty controller ID, integer epoch at least 1, and `state=CURRENT`.
3. From mounted workspaces uniquely locate the AI-Workspace that contains both `README.md` and `framework/versions/{{FRAMEWORK_VERSION}}/RECOVERY_CORE.md`. Zero or multiple matches fail closed.
4. The pinned stable version must be complete and canonically sealed. Strictly read its payload-sealed `TOOLCHAIN.json`; require an exact project backend match, `OFFICIAL` status, the current platform and an available `pwsh` Core runtime at major version 7 or later. Resolve every Framework operation through its exact manifest entrypoint. Do not repair it from another version, tag, HEAD or network state.
5. Strictly validate `.ai-workspace/corrections.json` against this version's project-correction contract. It is an independent project authority object, not a task card or PROJECT-CUSTOM rule.
6. The complete repo-local plane is the only live project authority. Any external historical copy is a locator only and is never read for routing. Partial, reparse, identity conflict or unknown control bytes fail closed.

`<FW>` below means the uniquely located stable `framework/versions/{{FRAMEWORK_VERSION}}` directory. Operation names below are resolved through `<FW>/TOOLCHAIN.json`; shown script locators identify the current `powershell7` mapping, not an independent selection rule.

## 2. Recover and load

1. Read `<FW>/RECOVERY_CORE.md` completely.
2. Lightly read project `STATUS.md` and `tasks/README.md` to locate the assigned task, then read that task's current header. The task card's `Work route` and range profile are authority; the index is only a projection and cannot override them.
3. On initial recovery or context discontinuity, resolve operation `LOAD_PLAN_RESOLVE` and invoke its sealed entrypoint with `-TaskPath <assigned-task> -IncludeRecovery`, the host and canonical enabled capability set, then read every returned module completely. A legacy card without `Work route` additionally requires explicit role/profile/phase and returns `LEGACY_LOAD_CONTEXT`. Empty capabilities produce the base plan; knowledge is passed only when explicitly enabled.
4. Read project `PROJECT.md`, `REVIEW_PROFILE.md`, `RELATIONSHIPS.md`, `STATUS.md`, the task index, the full assigned task, and every authority/implementation object named by it.
5. Reprove the real Git top, current object identities, owners, authorization package, and every protected visibility/read/hash/diff/index/write boundary. Git inventory/status/diff/index resolves operation `PROTECTED_SAFE_GIT` and invokes its sealed entrypoint with a frozen project config identity and bounded allowlist; `UNVERIFIED` is an honest result and never triggers a broad fallback.

WARM rebinding is allowed only inside the same healthy session when identity and impact have not changed. It does not inherit old authorization. Any identity, owner, impact, controller epoch or protection conflict escalates to FULL_COLD.

Rerun the same loader and reread its complete selected workset when task, Work role, Work phase, profile or capability changes. Compaction, pause/resume, handoff or uncertain context uses `-IncludeRecovery`. Continuous work with those facts, pin, host/topology and effective corrections unchanged does not reload. Authorization refresh alone is not a load boundary; entering REVIEW, GIT or EXTERNAL is.

Before any task launch/routing, terminal delivery, authenticated message, Controller handoff or hot-state projection, derive one strict ephemeral input from the just-loaded authority, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope. Resolve operation `WORKFLOW_ROUTE_RESOLVE` and invoke its sealed entrypoint with `-InputPath <ephemeral-input> -AsJson`; missing input fails closed. Remove the input after use. It is not project state, authority or a ledger.

## 3. Before actions

Report recovery mode, baseline, unique owner, objective, profile/reachability, exact/forbidden paths, validation, Git/external state, protection boundaries, current controller identity/epoch, current authorization and the single next action.

Without a valid package, remain read-only. DOMAIN_OWNER packages stay in their domain and omit controller fields. PROJECT_CONTROLLER packages bind current controller ID, epoch and whole-file identity. A fresh package is required after action/grantee/path/object/decision drift, but this does not by itself require Controller issuance or FULL_COLD recovery. A continuous writer lease is checked once per unchanged action/path/object subset; recheck on invalidation, writer transfer, Review, Git or external boundary.

Routine owner states go directly to their consumers. In the same domain task, the DOMAIN_OWNER directly selects eligible temporary actors/Reviewers, issues their packages and receives their terminal result; candidate writer/material contributors remain excluded from CRITICAL independent Review. The controller pulls current cards and receives only owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external, resource-conflict, routine-exclusion and object-drift exceptions. Do not build an ACK chain. Product decisions are asked by the responsible domain owner.

`frameworkCapabilities={}` or `KNOWLEDGE_REFERENCE.enabled=false` means no optional capability is enabled. When explicitly enabled, use `check-knowledge-entry.ps1 -Operation DISCOVER` for compact IDs/titles/tags, select zero to three relevant IDs from current task semantics, then use `-Operation QUERY -EntryId <ids>`. Missing, stale or conflicting requested references return per-entry `UNAVAILABLE` and the formal recovery chain continues; an unrelated stale entry does not block a fresh request. After actual authority files change, run read-only `check-knowledge-impact.ps1` at the normal Review/OWNER_ACCEPT boundary and refresh or mark only `DIRECT_AFFECTED`/`UNKNOWN` entries stale. Knowledge never grants authority or actions, and no background polling or automatic write exists.
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
Project-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

Project execution authority is the pinned Framework plus every record in `.ai-workspace/corrections.json` that is not incorporated by that pinned version. During RECOVER, invoke the strict evaluator from `framework/versions/1.12.0/scripts/check-project-corrections.ps1` with the actual project root, Framework root, pinned version and frozen project/correction identities; then read every returned `STILL_EFFECTIVE` rule and its reason. `INCORPORATED` records remain historical evidence and are not applied twice. `UNAVAILABLE_RETAINED` keeps all records effective. `CONFLICT` blocks launch until the project owner explicitly resolves it.

This block is retained when adopting an older or alternate Framework version, so the same records are re-evaluated rather than deleted. It adds no role, task, ledger, background service or authority beyond `corrections.json`.
<!-- PROJECT-CORRECTIONS:END -->
