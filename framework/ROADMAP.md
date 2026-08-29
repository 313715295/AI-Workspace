# AI Workspace Framework roadmap

This file contains generic release history and unselected Framework directions. It is not a task board, authorization object, consumer registry or project evidence store.

## Release line

### 1.12.0 — Tool Contract and PowerShell 7 backend

Status: candidate and not consumable. Stable release requires frozen source, actual Windows/Ubuntu/macOS PowerShell 7 conformance, fresh independent CRITICAL Review and deterministic manifest seal.

Selected minimum-sufficient scope:

- define one language-independent Tool Contract for operation selection, invocation, normalized results, relative paths, identities and fail-closed behavior;
- publish exactly one payload-sealed `TOOLCHAIN.json` mapping abstract operations to version-local entrypoints;
- add one project-level `frameworkToolBackend` selection inherited by all tasks and checks, bound indirectly through existing project config identity;
- provide `powershell7` as the only official backend, reject non-Core or pre-7 runtimes and remove 1.12 runtime dependence on `powershell.exe`;
- make registration and upgrade require the declared runtime before project write and project the backend field transactionally;
- run one normalized conformance entrypoint on Windows, Ubuntu/Linux and macOS, with explicit filesystem/link/case/permission/path/Git/text evidence ceilings.

Explicitly not selected: a launcher, zsh/Python backend, runtime generation, task/action/package-level backend selection, backend switch command before a second backend exists, registry/service/ledger, automatic runtime installation, global Framework default, consumer registry or automatic project upgrade.

### 1.11.0 — authoritative work route and boundary refresh

Status: stable and consumable after independent Review-2 approval and deterministic release integration; publication state is determined by repository refs rather than this roadmap.

Selected minimum-sufficient scope:

- add one authoritative task-header `Work route: role + phase` for new schema 1.11.0 cards;
- let the existing load-plan resolver bind the assigned task directly and reject role/profile/phase drift;
- load `RECOVER + current Work phase` after initial recovery, compaction, pause/resume, handoff or uncertain context;
- reload on task, role, phase, profile or capability transitions, while unchanged continuous work and authorization refresh do not reload;
- preserve legacy tasks without bulk rewriting through explicit inputs and a visible `LEGACY_LOAD_CONTEXT` evidence ceiling;
- require an incorporated project correction to exist in applicable normative modules, behavior tests and requirement-level independent Review rather than coverage metadata alone;
- extend explicit registration and upgrade paths to exact version 1.11.0 while preserving project-owned pins and correction bytes.

Explicitly not selected: a second refresh resolver, per-action or per-tool reload, host hooks/attention monitoring, Skill/plugin/tool governance, token accounting, Knowledge expansion, accepted-state projection, correction-to-module registries, absorption ledgers, background services, actor/Reviewer pools, ACK/heartbeat/polling, automatic consumer adoption, a global version selector or bulk legacy-card migration.

### 1.10.0 — project correction lifecycle

Status: stable and consumable after independent source Review and release integration; publication state is determined by repository refs rather than this roadmap.

Selected minimum-sufficient scope:

- add one project-owned `.ai-workspace/corrections.json` authority object, separate from tasks and PROJECT-CUSTOM;
- preserve stable ID, introduced Framework range, requirement reason, effective rule, applicability and decision locator;
- publish one cumulative generic version-coverage mapping with no consumer identities or adoption state;
- compute incorporated, still-effective and conflicting corrections before and after explicit pin adoption;
- retain records across upgrades and re-evaluate them on downgrade/alternate-version adoption;
- retain all corrections when coverage is unknown or ambiguous, and block explicit conflicts before pin write;
- reuse the existing Bootstrap, registration, upgrade and recoverable transaction paths.

Explicitly not selected: new roles, task types, services, queues, ledgers, registries, background work, automatic correction writes, automatic consumer upgrades or changes to immutable 1.9.0.

### 1.9.0 — owner-first execution and usable Knowledge

Status: stable and consumable after independent source Review and release integration; publication state is determined by repository refs rather than this roadmap.

Selected minimum-sufficient scope:

- make final sealed bytes pass the default self-test by separating pending and sealed fixtures;
- expose compact Knowledge `DISCOVER`, then request-scoped `QUERY` for at most three selected IDs;
- add read-only changed-authority impact results without background polling, automatic refresh or a maintenance ledger;
- preserve schema1 Knowledge indexes and allow schema2 plural authority dependencies;
- make PROJECT_CONTROLLER/DOMAIN_OWNER the only long-lived responsibilities and executor/Reviewer/resource routes temporary hats;
- prefer owner-first direct issuance and handoff, `REUSE + NONE/WARM`, and fresh package without universal FULL_COLD or mandatory Controller relay;
- bind CRITICAL Review candidate writer/material-contributor exclusions;
- reject a terminal route that names Controller without a real Controller-owned or escalation boundary;
- keep cross-task terminal reports compact and use `wait_threads` only for one blocking result when no other safe work remains;
- require one compact proportionality conclusion only for CRITICAL architecture/workflow plans that add solution or process machinery.

Explicitly not selected: consumer registries or automatic adoption, Framework-global version selectors, draft trees, actor/Reviewer pools, handoff/consumption ledgers, ACK/heartbeat/polling, background Knowledge services, automatic Knowledge writes, token-budget subsystems, host hooks/adapters, project/model measurement stores, universal resolvers, new lifecycle layers or changes to immutable 1.8.0.

### 1.8.0 — direct version and project-owned adoption

Status: stable, consumable and published.

Selected scope:

- remove the Framework-global version selector and require exact version selection;
- materialize the selected version's existing `project-starter`;
- keep project pins, adoption decisions and validation inside each project;
- develop a new version directly in its final directory while withholding consumability until independent Review and stable seal;
- close one authorized task launch without a second manual start round trip;
- mechanize `REUSE / MUST_NEW / BLOCKED`, same-scope standing task creation and one terminal report;
- authenticate host task/sender/controller epoch when the host exposes those fields and fail closed when it does not;
- reduce duplicated Controller, task-index, STATUS and evidence projections;
- support multi-action authorization preflight with per-action results;
- align PowerShell 5.1 and PowerShell 7 knowledge timestamp handling;
- retain independent Review, one-writer, protected path, immutable stable version and separate Git/external gates.

Explicitly not selected: mutable task-field manifests, repository authorization-consumption ledgers, consumer registries, automatic upgrades, global retry/compensation or cross-repository atomic transactions.

### 1.7.0 — Framework maintenance sibling topology

Status: stable, consumable and immutable. It introduced a repository-bound Maintenance control topology and kept ordinary repo-local projects independent.

Earlier releases remain immutable historical contracts.

## Future admission triggers

No additional process machinery is queued merely because 1.9.0 is released. A later version is considered only when natural project evidence shows a remaining failure that the 1.9.0 minimum cannot express safely.

- Host-enforced authenticity remains optional. Consider a trusted adapter/hook only if a supported host path actually needs enforcement beyond mechanical preflight and exposes testable host-derived signals.
- Knowledge context budgets remain unselected until natural DISCOVER/QUERY use demonstrates measurable context growth that compact metadata and the three-ID limit do not contain.
- Project/model success, rework, time and cost samples stay project-local; Framework may consume anonymized conclusions later but does not store those measurements.
- Do not add an actor registry, Reviewer pool, handoff ledger, wait/ACK protocol, background service or second status truth without a new proportionality result and direct failure evidence.

A future item enters a version only after the user or authorized maintainer selects its release, scope, owner, evidence and Review route. No placeholder draft tree is required.
