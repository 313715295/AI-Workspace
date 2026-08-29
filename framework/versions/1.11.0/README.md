# Framework 1.11.0

Status: `STABLE / CONSUMABLE / PIN_ELIGIBLE` after independent Review-2 approval, deterministic release-manifest seal and stable-suite verification.

Baseline: immutable Framework 1.10.0.

Framework 1.11.0 keeps the project-owned version and correction lifecycle introduced by earlier releases. Projects select an exact version and own their pins; registration copies this version's `project-starter`; upgrade changes only the caller project's managed control objects.

This release makes lightweight module loading deterministic without adding a second workflow system:

- new task cards declare one authoritative `Work route: role + phase`;
- the existing load-plan resolver can bind the assigned task and reject caller route drift;
- initial recovery and context discontinuity load `RECOVER + current Work phase`;
- task, role, phase, profile or capability transitions reload the selected workset;
- continuous unchanged work and authorization refresh do not reload;
- legacy cards use explicit inputs and report `LEGACY_LOAD_CONTEXT` until naturally updated.

When a Framework release declares a project correction incorporated, the requirement must also exist in applicable normative modules, behavior tests and requirement-level independent Review. `CORRECTION_COVERAGE.json` alone is not implementation proof.

This release adds no new role, task type, state object, refresh resolver, service, queue, ledger, host hook, background process, consumer registry or automatic adoption. It does not manage Skills, plugins or ordinary tools.

Read `RECOVERY_CORE.md` first. Use `resolve-load-plan.ps1 -TaskPath <assigned-task> -IncludeRecovery` for initial recovery; use the same resolver without `-IncludeRecovery` for a declared work-route transition.
