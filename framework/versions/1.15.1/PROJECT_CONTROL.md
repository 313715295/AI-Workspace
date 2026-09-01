# Project control

<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:BEGIN -->
A project's repo-local `.ai-workspace/project.json.frameworkVersion` is its only version-selection authority. Framework root stores no consumer records and has no global default selector.

## Registration

Root `scripts/register-project.ps1` requires an explicit exact version and Controller ID. Before any project write it validates:

- target `VERSION.json` is `STABLE`, consumable and pin-eligible;
- target `RELEASE_MANIFEST.json` matches the canonical payload and says source Review is approved;
- target `project-starter` inventory is exact;
- destination Git top, path and existing control-plane conditions are safe;
- the selected version's `TOOLCHAIN.json` is exact, `pwsh` satisfies its sole official `powershell7` backend and the current host platform is declared by that backend.

It materializes exactly the selected version's `project-starter`. For 1.15.1 that starter records `frameworkToolBackend=powershell7`, an empty `.ai-workspace/process-policy.json` and its single project-config locator. The starter is the reusable project process; registration does not invent another process.
<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:END -->

<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:BEGIN -->
## Upgrade

Root `scripts/upgrade-project.ps1` requires caller-supplied `RepositoryPath`, `ControllerId` and exact `ToVersion`. It validates the target release before writes, accepts healthy schema3 sources supported by the migration matrix, and preserves:

- project ID and display name;
- repo-local layout and repository root;
- Controller ID, epoch and state;
- routine exclusions and capabilities;
- Bootstrap project custom region.

For a 1.15.1 target, upgrade also projects the target starter's project-level backend field and requires both PowerShell 7 and a platform declared by that backend before recovery or project mutation. The field is inherited by every task and is not copied into authorization packages; existing project-config identity binding already invalidates packages when it changes.

An exact 1.14.0/1.14.1 → 1.15.1 adoption may use the current-pin budget bridge only when the current sealed resolver fails solely with `SELECTED_RULE_PACK_BUDGET_EXCEEDED`. The caller supplies the strict read-only current-process input and expected identity. The upgrade tool independently composes the complete current selection, retains all selected rule bodies and admits the transition only when that complete pack fits the 1.15.1 absolute ceiling. This observation grants no write and does not weaken or replace the actor-bound schema3 package, exact object checks, protected paths, user decision, transaction recovery or task-last stop.

Only declared managed objects change. The tool does not search for consumers, modify source/product files, stage/commit/push or update another project.

The 1.15.1 starter makes the current task's actor/role/phase Work route the loader input and adds one process-policy carrier for permanent project-specific process rules. It does not move task state into Framework root, create a consumer record or make the task index a second authority.
<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:BEGIN -->
## Progressive process requirements

`PROCESS_REQUIREMENTS_RESOLVE` is the one front door for all Framework-governed work. `DISCOVER` composes sealed Framework requirements, still-effective corrections and permanent project rules without merging their authority. `ADMIT_ACTION` checks preparation before a distinct action; `FINALIZE_OUTPUT` checks actual result and delivery before the final output. The returned source/decision receipts are ephemeral and non-authoritative.

New projects use `.ai-workspace/process-policy.json`. A legacy project with real PROJECT-CUSTOM rules keeps that region as the bound project-rule source until one separately reviewed atomic migration both writes the structured carrier and retires the migrated normative bytes. Empty-source claims and dual-carrier rules fail closed. No role, service, registry, poller, ledger or executable project DSL is added.
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:BEGIN -->
## Tool backend

`TOOL_CONTRACT.md` defines language-independent operations and `TOOLCHAIN.json` maps them to sealed entrypoints. Framework 1.15.1 offers only `powershell7`; the host/AI resolves and invokes those entrypoints directly. There is no launcher, task-level backend choice, runtime generation or automatic installation. A future backend switch is project-level adoption work and is not exposed until a release contains a second official backend.
<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:END -->

<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:BEGIN -->
## Controller lifecycle

The machine truth is `controller.json`. Handoff freezes old/new identity and epoch, writes hot projections first when authorized, writes the Controller object last, and finishes `TAKEOVER_COMPLETE`. Old read-only grace may preserve bytes for recovery but does not retain long-term routing authority or authorize cleanup.
<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:BEGIN -->
## Knowledge capability

Knowledge reference remains optional, project-local and non-authoritative. `DISCOVER` returns compact metadata; `QUERY` validates at most three selected IDs at request scope. A read-only changed-authority impact check helps the owning task refresh or mark affected entries stale at its normal acceptance boundary. No background service or automatic write exists, and Knowledge cannot change product facts, task authority or Framework pin.
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:BEGIN -->
## Owner-first project work

Project adoption loads the 1.15.1 starter and task contract, but it does not rewrite existing task cards or sessions. Inside an unchanged domain task, DOMAIN_OWNER directly selects temporary actors/Reviewers, issues fresh scoped packages and receives their results. PROJECT_CONTROLLER handles only a Controller-owned next action or an owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary.
<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:BEGIN -->
## Project corrections

`.ai-workspace/corrections.json` is an independent project authority object. It is neither a task card nor the permanent PROJECT-CUSTOM region. A task may discover or update a correction, but task lifecycle and chat history do not control its retention.

Each record preserves a stable correction ID, the Framework version/range against which it was introduced, the observed failure/reason, effective rule, applicability boundary and decision/evidence locator. There is no partial-incorporation state. Framework 1.15.1 preserves historical ID coverage but permits runtime suppression only through a payload-sealed mapping that matches the project-scoped alias, native requirement, catalog identity and canonical source-record identity.

Effective project rules are the correction records not exactly incorporated by the explicit pinned version. Incorporated records remain project evidence and are not applied twice or deleted. Missing mappings, source drift and invalid coverage retain the correction; an unambiguous declared conflict blocks adoption before the pin write. When the compatibility wrapper evaluates an older target that has only historical ID-level coverage, it reports `LEGACY_ID_ONLY_RETAINED` and keeps those records effective rather than treating coarse metadata as exact proof.

Coverage metadata is not semantic proof. A Framework release incorporates a correction only when the effective requirement is implemented in applicable normative modules reachable through the load manifest, exercised by behavior tests and accepted by independent Review against the original reason and boundary. No correction-to-module registry or absorption ledger is created.

Registration materializes one empty corrections object. Upgrade validates and reports incorporated, still-effective and conflicting records before pin projection, preserves existing correction bytes and legacy PROJECT-CUSTOM bytes, adds no structured policy to a customized legacy region, and rechecks after projection. Adopting an older or alternate version re-evaluates the same records; it never silently retires them.
<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:END -->
