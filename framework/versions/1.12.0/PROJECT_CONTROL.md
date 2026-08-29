# Project control

A project's repo-local `.ai-workspace/project.json.frameworkVersion` is its only version-selection authority. Framework root stores no consumer records and has no global default selector.

## Registration

Root `scripts/register-project.ps1` requires an explicit exact version and Controller ID. Before any project write it validates:

- target `VERSION.json` is `STABLE`, consumable and pin-eligible;
- target `RELEASE_MANIFEST.json` matches the canonical payload and says source Review is approved;
- target `project-starter` inventory is exact;
- destination Git top, path and existing control-plane conditions are safe;
- the selected version's `TOOLCHAIN.json` is exact, `pwsh` satisfies its sole official `powershell7` backend and the current host platform is declared by that backend.

It materializes exactly the selected version's `project-starter`. For 1.12.0 that starter records `frameworkToolBackend=powershell7`. The starter is the reusable project process; registration does not invent another process.

## Upgrade

Root `scripts/upgrade-project.ps1` requires caller-supplied `RepositoryPath`, `ControllerId` and exact `ToVersion`. It validates the target release before writes, accepts healthy schema3 sources supported by the migration matrix, and preserves:

- project ID and display name;
- repo-local layout and repository root;
- Controller ID, epoch and state;
- routine exclusions and capabilities;
- Bootstrap project custom region.

For a 1.12.0 target, upgrade also projects the target starter's project-level backend field and requires both PowerShell 7 and a platform declared by that backend before recovery or project mutation. The field is inherited by every task and is not copied into authorization packages; existing project-config identity binding already invalidates packages when it changes.

Only declared managed objects change. The tool does not search for consumers, modify source/product files, stage/commit/push or update another project.

The 1.12.0 starter makes the current task's `Work route` the loader input. It does not move task state into Framework root, create a consumer record or make the task index a second authority.

## Tool backend

`TOOL_CONTRACT.md` defines language-independent operations and `TOOLCHAIN.json` maps them to sealed entrypoints. Framework 1.12.0 offers only `powershell7`; the host/AI resolves and invokes those entrypoints directly. There is no launcher, task-level backend choice, runtime generation or automatic installation. A future backend switch is project-level adoption work and is not exposed until a release contains a second official backend.

## Controller lifecycle

The machine truth is `controller.json`. Handoff freezes old/new identity and epoch, writes hot projections first when authorized, writes the Controller object last, and finishes `TAKEOVER_COMPLETE`. Old read-only grace may preserve bytes for recovery but does not retain long-term routing authority or authorize cleanup.

## Knowledge capability

Knowledge reference remains optional, project-local and non-authoritative. `DISCOVER` returns compact metadata; `QUERY` validates at most three selected IDs at request scope. A read-only changed-authority impact check helps the owning task refresh or mark affected entries stale at its normal acceptance boundary. No background service or automatic write exists, and Knowledge cannot change product facts, task authority or Framework pin.

## Owner-first project work

Project adoption loads the 1.12.0 starter and task contract, but it does not rewrite existing task cards or sessions. Inside an unchanged domain task, DOMAIN_OWNER directly selects temporary actors/Reviewers, issues fresh scoped packages and receives their results. PROJECT_CONTROLLER handles only a Controller-owned next action or an owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary.

## Project corrections

`.ai-workspace/corrections.json` is an independent project authority object. It is neither a task card nor the permanent PROJECT-CUSTOM region. A task may discover or update a correction, but task lifecycle and chat history do not control its retention.

Each record preserves a stable correction ID, the Framework version/range against which it was introduced, the observed failure/reason, effective rule, applicability boundary and decision/evidence locator. There is no partial-incorporation state. Framework 1.12.0 lists incorporated IDs in its cumulative payload-sealed `CORRECTION_COVERAGE.json`; a mutable or unsealed copy is never authority.

Effective project rules are `project correction records - correction IDs incorporated by the explicit pinned version`. Incorporated records remain project evidence and are not applied twice or deleted. Unknown, missing, malformed or release-identity-mismatched coverage retains every project correction. An explicit target-version conflict blocks adoption before the pin write.

Coverage metadata is not semantic proof. A Framework release incorporates a correction only when the effective requirement is implemented in applicable normative modules reachable through the load manifest, exercised by behavior tests and accepted by independent Review against the original reason and boundary. No correction-to-module registry or absorption ledger is created.

Registration materializes one empty corrections object. Upgrade validates and reports incorporated, still-effective and conflicting records before pin projection, preserves existing correction bytes, adds the empty object only for a legacy project adopting 1.12.0, and rechecks after projection. Adopting an older or alternate version re-evaluates the same records; it never silently retires them.
