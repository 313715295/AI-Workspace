# Framework 1.12.0 recovery core

Recovery proves authority and current facts; it grants no write, test, Review, Git, browser/device or external capability.

## Required order

1. Prove actual cwd and Git top without trusting chat or memory.
2. Read the project's repo-local `.ai-workspace/project.json`, `controller.json`, `corrections.json` and `BOOTSTRAP.md` strictly, including the project-level `frameworkToolBackend` selection.
3. Resolve exactly `framework/versions/<project.json.frameworkVersion>/`.
4. Validate `VERSION.json`, `RELEASE_MANIFEST.json`, `LOAD_MANIFEST.json`, `TOOLCHAIN.json` and the selected inventory. Match the project backend exactly and require its declared PowerShell 7 runtime before invoking an operation.
5. Resolve operation `LOAD_PLAN_RESOLVE` through `TOOLCHAIN.json` and invoke it for the assigned task's authoritative `Work route` and profile; load the resulting role, profile, phase, host, topology and configured capability modules in manifest order. A legacy card without `Work route` requires explicit role/profile/phase input and carries `LEGACY_LOAD_CONTEXT` as an evidence ceiling.
6. Read `PROJECT.md`, `RELATIONSHIPS.md`, `STATUS.md`, task index, current active cards and `REVIEW_PROFILE.md`.
7. Reprove protected paths and real Git state with the versioned safe-Git helper where required.
8. Report the unique next action, writer/reviewer/authorization state and evidence ceiling.

Before launch, run `scripts/check-project-corrections.ps1` with the actual project root, Framework root, explicit pin and frozen project/correction identities. Read every `STILL_EFFECTIVE` rule. `INCORPORATED` is retained evidence but not applied twice; unavailable coverage retains all corrections; conflict blocks launch.

Recovery reports the current task owner separately from temporary actor, Reviewer and resource routes. A healthy same-task role/action rebind may use WARM recovery plus a fresh package; package invalidation alone does not require FULL_COLD or Controller issuance.

Initial recovery, compaction, pause/resume, handoff or uncertain context loads `RECOVER + current Work phase`. A role, Work phase, profile, capability or task change reruns the existing loader and rereads the selected workset. Continuous work with all of those facts unchanged does not reload modules. Authorization refresh alone is not a load boundary; entering REVIEW, GIT or EXTERNAL is.

The project pin is the only Framework-version authority. Root HEAD, tags, network state or another project's pin are never fallbacks.

`controller.json` is the sole literal current Controller ID and epoch. Cards normally reference the Controller role or object; historical literal IDs are audit-only.

If authority objects conflict, a required module is missing, the pin is not a sealed stable release, or host identity cannot be proven for an authenticity-dependent action, stop with the narrow blocker.

Backend selection is project-level Framework-use configuration, not task/action authority. A selection change invalidates outstanding packages through `projectConfigIdentity` and requires a safe project adoption boundary plus fresh recovery. Unknown backend, missing entrypoint, unsupported platform or unavailable runtime fails closed; no fallback, install or generated adapter is implied.
