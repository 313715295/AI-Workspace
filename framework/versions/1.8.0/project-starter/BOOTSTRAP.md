<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI entry

Project ID=`{{PROJECT_ID}}`; repo-local control plane=`.ai-workspace/`; pinned Framework=`{{FRAMEWORK_VERSION}}`. This is the only entry. Chat, legacy summaries, memory, root HEAD, tags and network state are locators only, never authority.

## 1. Locate and validate

1. Strictly read `.ai-workspace/project.json`; require schema3, repo-local layout, `repositoryRoot=..`, the expected project ID and pin, an array-valued `routineExcludedPaths` and an object-valued `frameworkCapabilities`. The capability object may be empty or contain only the pinned Framework's exact `KNOWLEDGE_REFERENCE` shape; unknown/duplicate fields and enabled-without-literal-index fail closed.
2. Strictly read `.ai-workspace/controller.json`; require the same project ID, a non-empty controller ID, integer epoch at least 1, and `state=CURRENT`.
3. From mounted workspaces uniquely locate the AI-Workspace that contains both `README.md` and `framework/versions/{{FRAMEWORK_VERSION}}/RECOVERY_CORE.md`. Zero or multiple matches fail closed.
4. The pinned stable version must be complete and canonically sealed. Do not repair it from another version, tag, HEAD or network state.
5. The complete repo-local plane is the only live project authority. Any external historical copy is a locator only and is never read for routing. Partial, reparse, identity conflict or unknown control bytes fail closed.

`<FW>` below means the uniquely located stable `framework/versions/{{FRAMEWORK_VERSION}}` directory.

## 2. Recover and load

1. Read `<FW>/RECOVERY_CORE.md` completely.
2. Lightly read project `STATUS.md`, `tasks/README.md`, and the assigned task's current header to determine role/profile/phase. This routes loading only and never replaces the full task.
3. Run `<FW>/scripts/resolve-load-plan.ps1` with the selected role/profile/phase/host and the canonical enabled capability set, then read every returned module completely. Empty capabilities produce the base plan; knowledge is passed only when explicitly enabled.
4. Read project `PROJECT.md`, `REVIEW_PROFILE.md`, `RELATIONSHIPS.md`, `STATUS.md`, the task index, the full assigned task, and every authority/implementation object named by it.
5. Reprove the real Git top, current object identities, owners, authorization package, and every protected visibility/read/hash/diff/index/write boundary. Git inventory/status/diff/index uses `<FW>/scripts/invoke-protected-safe-git.ps1` with a frozen project config identity and bounded allowlist; `UNVERIFIED` is an honest result and never triggers a broad fallback.

WARM rebinding is allowed only inside the same healthy session when identity and impact have not changed. It does not inherit old authorization. Any identity, owner, impact, controller epoch or protection conflict escalates to FULL_COLD.

Before any task launch/routing, terminal delivery, authenticated message, Controller handoff or hot-state projection, derive one strict ephemeral input from the just-loaded authority, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope. Invoke `<FW>/scripts/resolve-workflow-route.ps1 -InputPath <ephemeral-input> -AsJson`; missing input fails closed. Remove the input after use. It is not project state, authority or a ledger.

## 3. Before actions

Report recovery mode, baseline, unique owner, objective, profile/reachability, exact/forbidden paths, validation, Git/external state, protection boundaries, current controller identity/epoch, current authorization and the single next action.

Without a valid package, remain read-only. DOMAIN_OWNER packages stay in their domain and omit controller fields. PROJECT_CONTROLLER packages bind current controller ID, epoch and whole-file identity. A continuous writer lease is checked once per unchanged action/path/object subset; recheck on invalidation, writer transfer, Review, Git or external boundary.

Routine owner states go directly to their consumers. The controller pulls current cards and receives only cross-domain, public-contract, resource-conflict, routine-exclusion and object-drift exceptions. Do not build an ACK chain. Product decisions are asked by the responsible domain owner.

`frameworkCapabilities={}` or `KNOWLEDGE_REFERENCE.enabled=false` means no optional capability is enabled. When explicitly enabled, the index remains `REFERENCE_ONLY / NON_AUTHORITY`; missing, empty, stale or conflicting references return`REFERENCE_UNAVAILABLE`and the formal recovery chain continues. Knowledge never grants authority or actions.
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
Project-specific stable entry facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.
<!-- PROJECT-CUSTOM:END -->
