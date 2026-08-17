<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} AI entry

Project ID=`{{PROJECT_ID}}`; control plane layout=`framework-maintenance-sibling`; control plane=`.ai-workspace/`; pinned Framework=`{{FRAMEWORK_VERSION}}`. This is the only dynamic authority entry. Chat, sibling repository state, memory and `framework/CURRENT` are locators only.

## 1. Locate and validate

1. Resolve the supplied cwd to the Maintenance control Git top. Strictly read `.ai-workspace/project.json`; require schema4, `repositoryRoot=..`, the expected project ID and pin, empty `frameworkCapabilities`, and exactly one `frameworkTarget` with a non-CONTROL repository ID, one safe sibling directory name and literal routine exclusions.
2. Strictly read `.ai-workspace/controller.json`; require the same project ID, a non-empty controller ID, integer epoch at least 1 and `state=CURRENT`.
3. Resolve the control Git root parent without following a reparse point. The parent must contain neither `.git` nor `.ai-workspace`. Join only the validated single target directory component; do not search other directories or accept an absolute/`..` locator.
4. From that target locate the complete pinned `framework/versions/{{FRAMEWORK_VERSION}}`. Run its `scripts/resolve-framework-maintenance-target.ps1` with the control Git root and frozen project config identity.
5. Require resolver output `controllerState=CURRENT`. The target must have no canonical `.ai-workspace`. Any target control-plane entry, missing component, intermediate reparse, parent authority, pin entry, config/controller drift or Git-top conflict fails closed.

`<FW>` below is the complete stable version under the resolved Framework target. `<CONTROL>` and `<TARGET>` are the resolver's exact Git roots.

## 2. Recover and load

1. Read `<FW>/RECOVERY_CORE.md` completely.
2. Lightly read Maintenance `STATUS.md`, `tasks/README.md` and the assigned task header to determine role/profile/phase.
3. Run `<FW>/scripts/resolve-load-plan.ps1` with `Topology=FRAMEWORK_MAINTENANCE_SIBLING`, the selected role/profile/phase/host and no capabilities; read every returned module completely.
4. Read Maintenance `PROJECT.md`, `REVIEW_PROFILE.md`, `RELATIONSHIPS.md`, `STATUS.md`, the task index, full assigned task and named authority objects.
5. Explicitly read `<TARGET>/AGENTS.md` and the target Framework entry named by the task. A sibling repository's instructions are not assumed to be inherited automatically.
6. Reprove control and target HEAD/index/dirty separately. Use the maintenance-aware safe-Git entry with frozen config identity, one repository ID and bounded literal paths. One repository's VERIFIED result cannot fill the other repository's UNVERIFIED result.
7. Reprove the current authorization package. Schema2 packages bind `repositoryId + projectConfigIdentity`; exact paths and identities are relative to that repository only.

WARM rebinding is allowed only inside the same healthy session when config, resolver result, repository IDs, Git tops, owner, impact and loaded manifest have not changed. Any drift escalates to FULL_COLD.

## 3. Before actions

Report recovery mode, control/target Git tops, selected repository ID, baseline, owner, objective, exact/forbidden paths, validation, both dirty boundaries, controller identity/epoch, authorization and the single next action.

Without a valid package, both repositories remain read-only. CONTROL_WRITE is valid only for repository ID `CONTROL`; Framework source/test actions are valid only for the configured target repository ID. Control and target state changes use separate packages. Review, Git, push and external remain separate gates.

This Bootstrap is a steady-state recovery contract, not a directory migration procedure. Creating or relocating the two repositories and retiring an old control plane requires a separately authorized, project-specific offline task. Until that task has established this exact final layout and a fresh FULL_COLD accepts it, the previous project authority remains unchanged.
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
Project-specific stable facts may be written only here. Do not copy generic Framework rules. Upgrade preserves this region byte for byte.
<!-- PROJECT-CUSTOM:END -->
