---
name: ai-workspace-router
description: Navigate non-trivial work in an AI Workspace Framework project by binding its current pin and selecting only applicable authoritative rules. Use when a project has an .ai-workspace control plane, at task/context/authority changes or resume/handoff uncertainty, before governed actions, and before final output. Do not use it as authority or invoke it per tool call.
---

# AI Workspace router

This Skill is Framework-owned navigation and `NON_AUTHORITY`. The selected project's repo-local Bootstrap, exact pin, Controller/task objects, corrections, process policy, action packages, product files and observed evidence remain authoritative.

## Bind one project

1. Use an explicit project root when supplied; otherwise test the current Git root and at most its direct child directories for `.ai-workspace/project.json`.
2. Bind automatically only when exactly one candidate is valid. Multiple, missing or unknown candidates require an explicit root. Never recursively scan a drive or workspace tree.
3. Read the strict project config, exact pinned stable release and `TOOLCHAIN.json`.

Admit the Skill route only when one of these sealed compatibility conditions holds:

- pin `1.14.0` with `TOOLCHAIN.json` identity `1278|A9202A8F8CEC5E69CC464F80D336811ADADC30AFECEA528D767FF0428776E07D`;
- pin `1.14.1` with `TOOLCHAIN.json` identity `1278|CF9613624B6E7636A8242BDB7267A4E949975193308DB8627FB1FFE4ADDB23D6`;
- pin `1.15.0` or later whose sealed Tool Contract declares router compatibility and maps `LOAD_PLAN_RESOLVE`, `PROCESS_REQUIREMENTS_RESOLVE` and `WORKFLOW_ROUTE_RESOLVE`.

Unknown, conflicting or incompatible data uses the repo-local `.ai-workspace/BOOTSTRAP.md` route and reports `INCOMPATIBLE_OR_UNKNOWN`. Do not infer compatibility from this Skill's name or presence.

## Activate at natural boundaries

Activate on a relevant user prompt that starts or materially redirects governed work; initial task/context binding; task, actor, role, phase, profile, capability or rule-source change; compaction, resume, handoff or context uncertainty; a distinct governed action; and immediately before final output.

Reuse unchanged source context. Do not activate for every tool call, ordinary unchanged-context step or an authorization refresh that leaves source context unchanged. Explicit `$ai-workspace-router` is the manual recovery route. When invocation cannot be observed, retain `INVOCATION_UNPROVEN`.

## Navigate

1. Obtain only the minimum current facts required by the pinned release: project/pin/seal/backend, Controller, current task and authenticated actor/role/phase/profile, capabilities, objective/action/result, exact scope and protection boundary.
2. For 1.15 or later, invoke the sealed `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER` directly against the complete metadata catalog. Load every complete Markdown block returned once for sealed Framework rules plus selected effective corrections and project-policy rules; persist only the separate compact receipt. Do not use `LOAD_PLAN` to exclude catalog entries.
3. For 1.14.x, follow its sealed Bootstrap/process resolver contract. Its full-text behavior is compatible but is not evidence of 1.15 block-level loading.
4. If a selected locator or mapping cannot be proved, use the pinned release's bounded affected-module fallback. Never broaden a protected read or load the whole Framework merely because one module is uncertain.
5. Obtain only the additional facts, schemas, templates or supporting artifacts required by the selected rules and intended action.
6. Before each distinct governed action, invoke `ADMIT_ACTION` with the unchanged compact DISCOVER receipt and actual preparation/authorization evidence.
7. Immediately before final output, invoke `FINALIZE_OUTPUT` with the actual result and delivery receipts. Delete the compact receipt after finalization, invalidation or abort; complete missing safe work or return the exact blocker.

## Keep gates separate

`SOURCE_WRITE`, `TEST_WRITE`, `TEST_RUN`, `REVIEW_ROUTE`, `REVIEW_EXECUTE`, `OWNER_ACCEPT`, `GIT_STAGE`, `GIT_COMMIT`, `PUSH`, `BROWSER_RUN`, `DEVICE_RUN` and `EXTERNAL` retain independent current gates. Process resolution, resource routing and this Skill cannot grant, merge, infer or widen them.

Mechanical PASS proves only observable identities, selection and receipts. It does not prove semantic correctness, attention, host enforcement or delivery. Missing or undiscovered Skill state uses Bootstrap safely; registration and project upgrade never imply host-global installation.
