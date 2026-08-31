# Framework 1.14.0 recovery core

Recovery proves authority and current facts; it grants no write, test, Review, Git, browser/device or external capability.

## Required order

1. Prove actual cwd and Git top without trusting chat or memory.
2. Read the project's repo-local `.ai-workspace/project.json`, `controller.json`, `corrections.json` and `BOOTSTRAP.md` strictly, including the project-level `frameworkToolBackend` selection.
3. Resolve exactly `framework/versions/<project.json.frameworkVersion>/`.
4. Validate `VERSION.json`, `RELEASE_MANIFEST.json`, `LOAD_MANIFEST.json`, `TOOLCHAIN.json` and the selected inventory. Match the project backend exactly and require its declared PowerShell 7 runtime before invoking an operation.
5. Resolve operation `LOAD_PLAN_RESOLVE` through `TOOLCHAIN.json` and invoke it for the assigned task's authoritative `actor + role + phase` Work route and profile; compare actor with the host-authenticated current task ID and load the returned modules in manifest order. A 1.11/1.12 two-field route remains read-only recoverable with `LEGACY_ACTOR_CONTEXT_UNBOUND`; it must be owner-rebound before the first 1.14 substantive action.
6. Read `PROJECT.md`, `RELATIONSHIPS.md`, `STATUS.md`, task index, current active cards and `REVIEW_PROFILE.md`.
7. Reprove protected paths and real Git state with the versioned safe-Git helper where required.
8. Report the unique next action, writer/reviewer/authorization state and evidence ceiling.

Before launch, resolve `PROCESS_REQUIREMENTS_RESOLVE` and run `DISCOVER` with the frozen task, actor/role/phase, profile, objective/action/result kind, exact scope and three independent sources: sealed Framework catalog, still-effective corrections and either structured project policy or the legacy PROJECT-CUSTOM carrier. It returns selected full rules and one source-composition identity; it grants nothing. The legacy correction command is only a compatibility view over the same composer.

Run `ADMIT_ACTION` at a natural action boundary and `FINALIZE_OUTPUT` before a final result. They reuse the exact DISCOVER receipt and verify observable preparation/result completeness. UNKNOWN conservatively loads rather than excludes. Mechanical PASS never proves semantic correctness, model attention or host invocation.

Recovery reports the current task owner separately from temporary actor, Reviewer and resource routes. A healthy same-task role/action rebind may use WARM recovery plus a fresh package; package invalidation alone does not require FULL_COLD or Controller issuance.

Initial recovery, compaction, pause/resume, handoff or uncertain context loads `RECOVER + current Work phase`. A task, actor, role, Work phase, profile, capability or source-authority change reruns the loader and DISCOVER. Objective/exact-scope/action/result changes invalidate only the ephemeral boundary decision while reusing an unchanged source composition. Do not reload per tool call or authorization refresh.

The project pin is the only Framework-version authority. Root HEAD, tags, network state or another project's pin are never fallbacks.

`controller.json` is the sole literal current Controller ID and epoch. Cards normally reference the Controller role or object; historical literal IDs are audit-only.

If authority objects conflict, a required module is missing, the pin is not a sealed stable release, or host identity cannot be proven for an authenticity-dependent action, stop with the narrow blocker.

Backend selection is project-level Framework-use configuration, not task/action authority. A selection change invalidates outstanding packages through `projectConfigIdentity` and requires a safe project adoption boundary plus fresh recovery. Unknown backend, missing entrypoint, unsupported platform or unavailable runtime fails closed; no fallback, install or generated adapter is implied.
