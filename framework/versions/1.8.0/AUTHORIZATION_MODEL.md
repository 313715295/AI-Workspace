# Authorization model

Authorization is explicit, scoped and phase-local. It is not inferred from recovery, Review, a task assignment or chat intent.

## Actions

`CONTROL_WRITE`, `SOURCE_WRITE`, `TEST_WRITE`, `TEST_RUN`, `BROWSER_RUN`, `DEVICE_RUN`, `REVIEW_ROUTE`, `REVIEW_EXECUTE`, `GIT_STAGE`, `GIT_COMMIT`, `PUSH`, `EXTERNAL`.

Safe in-scope reads need no implementation package. Every mutating or side-effecting action above remains distinct.

## Package binding

A package binds framework version, task, profile, lifecycle, owner, issuer, grantee, action set, exact paths, whole-object identities, decision class, user confirmation, Controller ID/epoch/control identity, repository identity and project-config identity where applicable.

Required invalidators include task, owner, grantee, action set, path set, object, user decision, Controller epoch, repository and project-config drift. Unknown drift fails closed.

Framework 1.8.0 accepts an `ObservedAction` array. One unchanged lease may preflight several granted actions once; the checker returns one result per requested action. Duplicate, unknown or ungranted actions fail. Existing single-action callers remain valid.

Batch preflight does not merge capabilities: a successful `SOURCE_WRITE` result is not `TEST_RUN`, Review or Git authority. Once a bound identity, repository or decision drifts, issue a fresh package for later phases.

There is no repository authorization-consumption ledger. Validity ends through the bound invalidators and explicit phase release. If the host cannot prove single consumption, do not claim it.

## Controller and roles

`controller.json` is the sole literal current Controller ID/epoch. A PROJECT_CONTROLLER issuer must match that object exactly. DOMAIN_OWNER cannot impersonate Controller fields.

Controller handoff is directional and ends at `TAKEOVER_COMPLETE`. Predecessor read-only grace is not routing authority and not retirement permission.

## User decisions

A user confirmation remains valid while the frozen decision, scope, risk and boundary are unchanged. Material or unknown drift requires a new decision; unrelated metadata or deterministic projection does not.

Drift classes are `MATERIAL / UNRELATED_METADATA / PROJECTION / UNKNOWN`. Immutable candidates, protected objects and canonical evidence retain strict whole-object stops.
