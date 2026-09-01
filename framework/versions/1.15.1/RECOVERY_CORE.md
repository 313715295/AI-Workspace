# Framework 1.15.1 recovery core

<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:BEGIN -->
Recovery proves authority and current facts; it grants no write, test, Review, Git, browser/device or external capability.

## Required order

1. Prove actual cwd and Git top without trusting chat or memory.
2. Read the project's repo-local `.ai-workspace/project.json`, `controller.json`, `corrections.json` and `BOOTSTRAP.md` strictly, including the project-level `frameworkToolBackend` selection.
3. Resolve exactly `framework/versions/<project.json.frameworkVersion>/` and validate its stable `VERSION.json`, `RELEASE_MANIFEST.json`, `TOOLCHAIN.json` and generated process-requirement catalog.
4. Bind the current task, authenticated actor, `role + phase` Work route, profile, exact scope, protection boundary, capabilities and current Review profile. Read only the project facts needed to prove those inputs.
5. Resolve `PROCESS_REQUIREMENTS_RESOLVE` through the sealed Tool Contract and run `DISCOVER` over the complete generated catalog plus still-effective corrections and the current permanent project-rule carrier.
6. Load the exact complete Markdown rule blocks selected by the receipt, then obtain any rule-required facts, evidence, schemas, templates or other action artifacts.
7. Use `LOAD_PLAN_RESOLVE` only for 1.14 compatibility, Framework-wide explanation/maintenance, non-rule supporting artifacts or bounded fallback when an affected module's block mapping cannot be proved. It does not filter the catalog or create a second rule decision.
8. Reprove protected paths and real Git state with the versioned safe-Git helper where a selected rule or intended action requires it.
9. Report the unique next action, writer/reviewer/authorization state and evidence ceiling.

The project pin is the only Framework-version authority. Root HEAD, tags, network state or another project's pin are never fallbacks. `controller.json` is the sole literal current Controller ID and epoch; historical literal IDs are audit-only.

If authority objects conflict, a selected block or required artifact is unavailable, the pin is not a sealed stable release, or host identity cannot be proven for an authenticity-dependent action, stop with the narrow blocker.
<!-- AIW-REQUIREMENT:PR_RECOVERY_CURRENT_AUTHORITY:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:BEGIN -->
`DISCOVER` selects against the complete sealed metadata catalog before normative module text is loaded. The composer verifies each selected fragment locator against its owning Markdown module and returns the complete block text plus the fragment-owned preparation and result requirements. It grants nothing.

Run `ADMIT_ACTION` at each distinct governed action boundary and `FINALIZE_OUTPUT` immediately before a final user or consumer result. Both consume the exact `DISCOVER` receipt. UNKNOWN semantic applicability conservatively selects affected blocks. Missing or conflicting mapping first loads every mapped block in the affected module; only an incomplete module mapping falls back to that complete module, never the whole Framework.

Initial recovery, compaction, pause/resume, handoff or uncertain context rebuilds the current source composition and decision. A task, actor, role, Work phase, profile, capability or source-authority change also rebuilds the composition. Objective, exact-scope, action or result change rebuilds only the boundary decision while unchanged source identities and selected rule bodies may be reused. Do not reload per tool call or authorization refresh.

Mechanical PASS never proves semantic correctness, model attention or host invocation. An unavailable or unobserved invocation reports the honest evidence ceiling rather than claiming enforcement.
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES:END -->

<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:BEGIN -->
Recovery reports the current task owner separately from temporary actor, Reviewer and resource routes. A healthy same-task role/action rebind may use NONE/WARM recovery plus a fresh package; package invalidation alone does not require FULL_COLD or Controller issuance.

A 1.11/1.12 two-field route remains read-only recoverable with `LEGACY_ACTOR_CONTEXT_UNBOUND`; it must be owner-rebound before the first substantive action under a release that requires `actor + role + phase`.
<!-- AIW-REQUIREMENT:PR_RECOVERY_ROLE_REBIND:END -->

<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:BEGIN -->
Backend selection is project-level Framework-use configuration, not task/action authority. Match the project selection exactly against `TOOLCHAIN.json` and require the declared runtime/platform before invoking an operation. A selection change invalidates outstanding packages through `projectConfigIdentity` and requires a safe project adoption boundary plus fresh recovery. Unknown backend, missing entrypoint, unsupported platform or unavailable runtime fails closed; no fallback, install or generated adapter is implied.
<!-- AIW-REQUIREMENT:PR_FRAMEWORK_BACKEND_SELECTION:END -->
