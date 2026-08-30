<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI entry

Project ID=`{{PROJECT_ID}}`; control plane layout=`framework-maintenance-sibling`; control plane=`.ai-workspace/`; pinned Framework=`{{FRAMEWORK_VERSION}}`. This is the only dynamic authority entry. Chat, sibling repository state, memory, root HEAD, tags and network state are locators only.

## 1. Locate and validate

1. Resolve the supplied cwd to the Maintenance control Git top. Strictly read `.ai-workspace/project.json`; require schema4, `repositoryRoot=..`, the expected project ID and pin, `frameworkToolBackend=powershell7`, empty `frameworkCapabilities`, and exactly one `frameworkTarget` with a non-CONTROL repository ID, one safe sibling directory name and literal routine exclusions.
2. Strictly read `.ai-workspace/controller.json`; require the same project ID, a non-empty controller ID, integer epoch at least 1 and `state=CURRENT`.
3. Resolve the control Git root parent without following a reparse point. The parent must contain neither `.git` nor `.ai-workspace`. Join only the validated single target directory component; do not search other directories or accept an absolute/`..` locator.
4. From that target locate the complete pinned `framework/versions/{{FRAMEWORK_VERSION}}`. Strictly read its payload-sealed `TOOLCHAIN.json`; require an exact project backend match, `OFFICIAL` status, the current platform and an available `pwsh` Core runtime at major version 7 or later. Resolve operation `MAINTENANCE_TARGET_RESOLVE` and invoke that exact entrypoint with the control Git root and frozen project config identity.
5. Strictly validate CONTROL `.ai-workspace/corrections.json` and configured `.ai-workspace/process-policy.json`; compose them with sealed Framework requirements only through `PROCESS_REQUIREMENTS_RESOLVE`.
6. Require resolver output `controllerState=CURRENT`. The target must have no canonical `.ai-workspace`. Any target control-plane entry, missing component, intermediate reparse, parent authority, pin entry, config/controller drift or Git-top conflict fails closed.

`<FW>` below is the complete stable version under the resolved Framework target. `<CONTROL>` and `<TARGET>` are the resolver's exact Git roots. Operation names below are resolved only through `<FW>/TOOLCHAIN.json`.

## 2. Recover and load

1. Read `<FW>/RECOVERY_CORE.md` completely.
2. Lightly read Maintenance `STATUS.md` and `tasks/README.md` to locate the assigned task, then read its current header. The task card's `Work route` and range profile are authority; the index is only a projection.
3. On initial recovery or context discontinuity, resolve operation `LOAD_PLAN_RESOLVE` and invoke its sealed entrypoint with `-TaskPath <assigned-task> -ObservedActor <host-task-id> -IncludeRecovery`, `Topology=FRAMEWORK_MAINTENANCE_SIBLING`, the host and no capabilities; read every returned module completely. A 1.11/1.12 two-field route is read-only recoverable with `LEGACY_ACTOR_CONTEXT_UNBOUND`.
4. Invoke `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER` for the current task context and read the selected full rules. Reuse its ephemeral source receipt while its bound identities remain unchanged.
4. Read Maintenance `PROJECT.md`, `REVIEW_PROFILE.md`, `RELATIONSHIPS.md`, `STATUS.md`, the task index, full assigned task and named authority objects.
5. Explicitly read `<TARGET>/AGENTS.md` and the target Framework entry named by the task. A sibling repository's instructions are not assumed to be inherited automatically.
6. Reprove control and target HEAD/index/dirty separately. Use the maintenance-aware safe-Git entry with frozen config identity, one repository ID and bounded literal paths. One repository's VERIFIED result cannot fill the other repository's UNVERIFIED result.
7. Reprove the current authorization package. Schema2 packages bind `repositoryId + projectConfigIdentity`; exact paths and identities are relative to that repository only.

WARM rebinding is allowed only inside the same healthy session when config, resolver result, repository IDs, Git tops, owner, impact and loaded manifest have not changed. Any drift escalates to FULL_COLD.

Rerun loader+DISCOVER on task/actor/role/phase/profile or rule-source drift. Objective/action/result/scope drift invalidates only the boundary decision. Do not reload per tool call.

Before any task launch/routing, terminal delivery, authenticated message, Controller handoff or hot-state projection, derive one strict ephemeral input from the just-loaded authority, re-proven `<CONTROL>`/`<TARGET>` Git tops, selected repository/package, current public decision and host-authenticated envelope. Resolve operation `WORKFLOW_ROUTE_RESOLVE` and invoke its sealed entrypoint with `-InputPath <ephemeral-input> -AsJson`; missing input fails closed. Remove the input after use. It is not project state, authority or a ledger.

## 3. Before actions

Report recovery mode, control/target Git tops, selected repository ID, baseline, owner, objective, exact/forbidden paths, validation, both dirty boundaries, controller identity/epoch, authorization and the single next action.

Without a valid package, both repositories remain read-only. CONTROL_WRITE is valid only for repository ID `CONTROL`; Framework source/test actions are valid only for the configured target repository ID. Control and target state changes use separate packages. Review, Git, push and external remain separate gates.

Fresh authorization after action/grantee/path/object/decision drift does not by itself require Controller relay or FULL_COLD. In an unchanged domain task, its DOMAIN_OWNER directly selects eligible temporary actors/Reviewers, issues scoped packages and receives terminal results. PROJECT_CONTROLLER is used only for a Controller-owned unique next action or an owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary.

This Bootstrap is a steady-state recovery contract, not a directory migration procedure. Creating or relocating the two repositories and retiring an old control plane requires a separately authorized, project-specific offline task. Until that task has established this exact final layout and a fresh FULL_COLD accepts it, the previous project authority remains unchanged.
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
No permanent project process rule is active in this legacy region. Structured rules belong to `.ai-workspace/process-policy.json`.
<!-- PROJECT-CUSTOM:END -->

<!-- PROJECT-CORRECTIONS:BEGIN -->
## Project correction overlay

CONTROL execution authority is the pinned Framework plus every still-effective correction and permanent project policy rule. The current process resolver is the sole composer; the correction command is only its legacy report view.

This block survives adoption of an older or alternate Framework version. It introduces no target control plane, role, task, ledger, background service or second state object.
<!-- PROJECT-CORRECTIONS:END -->
