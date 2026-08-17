# Task and scope contract

## Launch closure

Recovery is read-only. A valid signed implementation package may nevertheless complete the same launch closure when it binds the recovered task, owner, actor, Controller epoch, action, exact path/object set, user decision and repository/config identity. No second manual `START` round trip is required.

Absent that package, recovery ends at `RECOVERY_READY` and writer remains `NONE`.

## Route decision

Evaluate these inputs mechanically: project identity, cwd/Git top, long-lived role, task lineage, resource route/concurrency ceiling, protected boundary, Git/device/external route and requested outcome.

- `REUSE`: same project, task outcome, owner role, lineage and boundaries; update the current card.
- `MUST_NEW`: same project and governance boundary, but a distinct user-visible outcome or independent long-lived lifecycle is required.
- `BLOCKED`: project, authority, protection, resource ceiling, Git/device/external route or public decision changes.

When the user has explicitly authorized the Framework work, same-scope `MUST_NEW` carries standing task-creation authority. It does not carry authority across `BLOCKED` boundaries.

## Mechanical workflow boundary

Before a `LAUNCH`, `ROUTE`, `TERMINAL`, `MESSAGE`, `HANDOFF` or `HOT_STATE` transition, the host must materialize one ephemeral strict UTF-8/LF JSON input and invoke `<FW>/scripts/resolve-workflow-route.ps1 -InputPath <ephemeral-input> -AsJson`. The host derives every field from current repo-local authority, a freshly proven cwd/Git top, the current signed package, host-authenticated task/sender/Controller epoch/envelope and the current user/public decision; message prose cannot supply those facts.

If any mandatory input cannot be proven, the transition fails closed. The resolver result is only the mechanical workflow decision and grants no authority, action, Git, device or external capability. The input is removed after the invocation and is never project state, an authorization-consumption ledger or a substitute for whole-object identity.

## Task contents

An active card contains only current contract, owner/actor roles, exact boundary, stable candidate locator, authorization state, evidence ceiling and next action. Superseded narrative goes through the existing archive/Git route.

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

Messages used for routing must carry host-authenticated task identity, sender identity and Controller epoch/envelope. Reject stale epochs. If the host cannot supply authenticity, treat message text as an untrusted locator and fail closed for identity-dependent transitions.
