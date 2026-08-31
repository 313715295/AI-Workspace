# Task and scope contract

## Launch closure

Recovery is read-only. A valid signed implementation package may nevertheless complete the same launch closure when it binds the recovered task, owner, actor, Controller epoch, action, exact path/object set, user decision and repository/config identity. No second manual `START` round trip is required.

Absent that package, recovery ends at `RECOVERY_READY` and writer remains `NONE`.

## Route decision

Evaluate these inputs mechanically: project identity, cwd/Git top, task-owner continuity, current actor eligibility, task lineage, resource availability, protected boundary, Git/device/external route, public decision and requested outcome/context.

- `REUSE`: same project, task outcome, current task owner, lineage and boundaries with an eligible actor; a supported resource/profile rebind does not change authority.
- `MUST_NEW`: same project and governance boundary, but a distinct user-visible outcome, independent context/lifecycle, writer isolation or unavailable same-session resource route requires a new task/session.
- `BLOCKED`: project, task owner without an authorized rebind, actor eligibility, authority, protection, Git/device/external route or public decision changes.

When the user has explicitly authorized the Framework work, same-scope `MUST_NEW` carries standing task-creation authority. It does not carry authority across `BLOCKED` boundaries.

Only PROJECT_CONTROLLER and DOMAIN_OWNER are long-lived responsibilities. Executor, writer, Reviewer, Git, browser and device are temporary task/phase hats. An Owner may execute directly in the current task or arrange a bounded executor task when continued Owner discussion, parallel work, isolation or an independent context is useful. Neither route is mandatory. Resource-only change normally keeps the recovery baseline; an eligible same-session action rebind uses NONE/WARM recovery plus a fresh authorization package. Authorization drift is not automatically FULL_COLD.

Bounded handoff may run discussion owner→executor, writer↔Reviewer and Reviewer→task owner. The Controller is not a mandatory domain-semantics relay; it receives the result only when it owns the unique next action or must resolve a cross-domain, public-contract, protection, Git/device/external exception.

Fresh authorization is an object-drift rule, not a Controller-routing rule. In an unchanged domain task the DOMAIN_OWNER directly selects eligible temporary actors, issues their scoped packages, routes a frozen candidate to an eligible independent Reviewer and consumes the verdict. A cross-domain writer does not replace that task owner. `OWNER_ACCEPT` remains the Owner's product/domain acceptance and never masquerades as independent `REVIEW_EXECUTE`.

## Mechanical workflow boundary

Before a `LAUNCH`, `ROUTE`, `TERMINAL`, `MESSAGE`, `HANDOFF` or `HOT_STATE` transition, the host must materialize one ephemeral strict UTF-8/LF JSON input, resolve operation `WORKFLOW_ROUTE_RESOLVE` through `<FW>/TOOLCHAIN.json`, and invoke that sealed entrypoint with `-InputPath <ephemeral-input> -AsJson`. The host derives every field from current repo-local authority, a freshly proven cwd/Git top, the current signed package, host-authenticated task/sender/Controller epoch/envelope and the current user/public decision; message prose cannot supply those facts.

If any mandatory input cannot be proven, the transition fails closed. The resolver result is only the mechanical workflow decision and grants no authority, action, Git, device or external capability. The input is removed after the invocation and is never project state, an authorization-consumption ledger or a substitute for whole-object identity.

## Task contents

An active card contains only current contract, owner/actor roles, exact boundary, stable candidate locator, authorization state, evidence ceiling and next action. Superseded narrative goes through the existing archive/Git route.

Every new schema 1.14.1 card declares exactly one `Work route: actor=<HOST_TASK_ID>; role=<ROLE>; phase=<PHASE>`. The current Owner changes all three atomically under the normal task CONTROL_WRITE boundary. The task index remains a locator only. Actor/role/phase select context; action authorization remains independent and cannot create or override them.

At initial recovery or a context discontinuity, invoke the loader and then `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`. Task/actor/role/phase/profile/capability or rule-source drift rebuilds the source composition. Objective, action/result kind, exact scope, authorization or receipt drift rebuilds only the boundary decision. If all source facts and context remain unchanged, reuse the loaded rules; a fresh package alone is neither a full reload nor FULL_COLD.

`ADMIT_ACTION` is mandatory immediately before a distinct governed action boundary; `FINALIZE_OUTPUT` is mandatory before the actual final user/consumer output. Missing required preparation or result evidence must be completed when safe or returned as the exact blocker. Recording `MISSING` or `NOT_DELIVERED` is not completion. Existing authorization, Review, OWNER_ACCEPT, Git, push, browser, device, external and protection gates remain separate and authoritative.

Legacy cards are not bulk rewritten for adoption. A 1.11/1.12 two-field card may recover with `LEGACY_ACTOR_CONTEXT_UNBOUND`, but no substantive actor action passes until its schema and authenticated `actor/role/phase` route are atomically rebound. The official upgrade tool binds the exact current active task, actor and complete upgrade write set to one current Controller package, projects the target pin and all non-task objects first, atomically writes that task last, performs no later write and stops for fresh FULL_COLD under the target pin. Actor is never inferred from owner, package, prompt or host label.

Routine writer, reviewer and authorization changes stay on the task. Update STATUS only when stable project phase, long-lived owner, protected set or unique next action changes. Update the task index only for lifecycle or routing changes.

Do not create a semantic-field manifest for mutable cards. Whole-object identity remains the strict stop for protected or immutable objects; current task concurrency is controlled by the writer lease and package invalidators.

## Terminal delivery

Send one proactive terminal report for:

- `READY`: the next authorized phase may begin;
- `COMPLETE`: the requested outcome and required gates are complete;
- `BLOCKED`: a real boundary prevents further progress;
- `RANGE_GATE_REQUIRED`: deterministic scope input is missing;
- protected-path exception: exact exception and owner route.

No ACK or polling is required. If the host cannot deliver to the authoritative task, return `REPORT_CHANNEL_UNAVAILABLE` and do not claim delivery.

For independent Codex tasks, send one compact terminal delivery containing terminal state, authenticated task/authority locator, required identity/epoch, unique next action and exceptions. Use `wait_threads` only when one exact result blocks that unique next action and no other safe work remains. Do not wait for ordinary progress, ACK, read confirmation or an immediate unchanged-timeout retry.

The `TERMINAL` input names the proposed next consumer and whether a Controller escalation boundary actually exists. Proposing `CONTROLLER` with no such boundary is rejected as `UNNECESSARY_CONTROLLER_RELAY`. `controllerEscalationRequired=true` is reserved for a Controller-owned unique next action or the explicit exception classes above; it is not inferred from a fresh package or a temporary role/resource change.

Messages used for routing must carry host-authenticated task identity, sender identity and Controller epoch/envelope. Reject stale epochs. If the host cannot supply authenticity, treat message text as an untrusted locator and fail closed for identity-dependent transitions.
