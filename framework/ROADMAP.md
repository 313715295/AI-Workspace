# AI Workspace Framework roadmap

This file contains generic release history and unselected Framework directions. It is not a task board, authorization object, consumer registry or project evidence store.

## Release line

### 1.8.0 — direct version and project-owned adoption

Status: implementation candidate.

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

## Unselected directions

### Natural host-route evidence

Collect later, project-local natural samples for the four abstract quality routes before promoting low-cost routing beyond `PROBATIONARY`. Framework may state a lightweight host mapping, but it must not store project task names, measurements or claims of proven savings.

### Host-authenticated delivery

Where a host exposes immutable task identity, sender identity, Controller epoch and delivery result, add direct conformance fixtures. Where unavailable, preserve `REPORT_CHANNEL_UNAVAILABLE` rather than simulating authenticity.

### Lifecycle ergonomics

Evaluate whether archive projection and immutable evidence locators can be simplified further without weakening history, protected objects or independent Review. Do not introduce a second truth for mutable cards.

## Admission rule

A roadmap item enters a version only after a user or authorized maintainer selects the release, scope, owner, evidence and Review route. New selected work belongs in that version's release task; no placeholder draft tree is required.
