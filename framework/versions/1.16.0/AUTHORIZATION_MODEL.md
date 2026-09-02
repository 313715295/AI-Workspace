# Authorization model

<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:BEGIN -->
Authorization is explicit, scoped and phase-local. It is not inferred from recovery, Review, a task assignment or chat intent.

## Actions

`CONTROL_WRITE`, `SOURCE_WRITE`, `TEST_WRITE`, `TEST_RUN`, `BROWSER_RUN`, `DEVICE_RUN`, `REVIEW_ROUTE`, `REVIEW_EXECUTE`, `GIT_STAGE`, `GIT_COMMIT`, `PUSH`, `EXTERNAL`.

Safe in-scope reads need no implementation package. Every mutating or side-effecting action above remains distinct.

## Package binding

A package binds framework version, task ID and current whole-task identity, profile, lifecycle, owner, issuer, grantee, action set, exact paths, whole-object identities, decision class, user confirmation and project-config identity. The checker compares the package grantee with the task-bound actor as well as the observed host actor. Controller and repository fields remain conditional on topology and issuer role.

Package JSON is parsed as strict security input. Duplicate members are rejected recursively after escape decoding, including Unicode-escaped names that decode to an existing member; last-member-wins parser behavior never resolves authority.

Required invalidators include task, owner, grantee, action set, path set, object, user decision, Controller epoch, repository and project-config drift. Unknown drift fails closed.

The selected tool backend is contained in project config and is therefore bound by `projectConfigIdentity` in both repo-local schema1 and Maintenance schema2 packages. Packages do not repeat `frameworkToolBackend`; a backend/config byte change invalidates them without creating a second selection truth.

Framework 1.16.0 accepts an `ObservedAction` array. One unchanged lease may preflight several granted actions once; the checker returns one result per requested action. Duplicate, unknown or ungranted actions fail. Existing single-action callers remain valid.

Batch preflight does not merge capabilities: a successful `SOURCE_WRITE` result is not `TEST_RUN`, Review or Git authority. Once a bound identity, repository or decision drifts, issue a fresh package for later phases.

`PROCESS_REQUIREMENTS_RESOLVE/ADMIT_ACTION` consumes the current task/source decision and verifies required preparation, but returns `authorityGranted=false`. Both the process decision and the independent action checker must pass. Neither can substitute for the other.

There is no repository authorization-consumption ledger. Validity ends through the bound invalidators and explicit phase release. If the host cannot prove single consumption, do not claim it.
<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:END -->

<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:BEGIN -->
Protected or excluded read/hash/diff/index/write boundaries remain exact and fail closed. UNKNOWN scope or an unavailable bounded helper returns the narrow blocker and never authorizes broad search, fallback access or a widened path set.
<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:END -->

<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:BEGIN -->
Build authority context only from current mechanically observed project, Controller, task, package, scope, identity, capability, recovery and host facts. Treat the requested objective/action/result and semantic hints as an intent envelope only. Authority facts always win; UNKNOWN, unauthorized action or a hint/fact mismatch blocks the governed action or conservatively selects the affected rule blocks.
<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:END -->

<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:BEGIN -->
## Controller and roles

`controller.json` is the sole literal current Controller ID/epoch. A PROJECT_CONTROLLER issuer must match that object exactly. DOMAIN_OWNER cannot impersonate Controller fields.

Only PROJECT_CONTROLLER and DOMAIN_OWNER are long-lived responsibilities. Executor, writer, Reviewer, Git, browser, device and resource route are temporary task/phase hats. A fresh package is required when its action, grantee, path/object set or user decision changes; this invalidates the old package, not the healthy recovery baseline, and does not by itself require PROJECT_CONTROLLER issuance.

Inside an unchanged domain task, the DOMAIN_OWNER is the default direct issuer and phase consumer. The Owner may execute, select an eligible actor, issue a pure `REVIEW_EXECUTE` package to an independent Reviewer, receive the verdict and perform `OWNER_ACCEPT` without a Controller relay. A qualified cross-domain actor may write while the task owner remains unchanged. For CRITICAL Review, the task owner, package issuer, candidate writer and every material contributor remain disqualified from the final independent Reviewer role.

Route through PROJECT_CONTROLLER only when it owns the unique next action or must resolve an owner/public-decision, cross-domain contract, protected-path, project-phase, Git/device/external or resource-conflict boundary. Resource selection alone grants no authority.

Controller handoff is directional and ends at `TAKEOVER_COMPLETE`. Predecessor read-only grace is not routing authority and not retirement permission.
<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:END -->

<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:BEGIN -->
## User decisions

A user confirmation remains valid while the frozen decision, scope, risk and boundary are unchanged. Material or unknown drift requires a new decision; unrelated metadata or deterministic projection does not.

Drift classes are `MATERIAL / UNRELATED_METADATA / PROJECTION / UNKNOWN`. Immutable candidates, protected objects and canonical evidence retain strict whole-object stops.
<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:END -->
