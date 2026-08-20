# AI Workspace Framework roadmap

This file contains generic release history and unselected Framework directions. It is not a task board, authorization object, consumer registry or project evidence store.

## Release line

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
