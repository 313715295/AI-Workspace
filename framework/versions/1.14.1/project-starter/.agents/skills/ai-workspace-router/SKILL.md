---
name: ai-workspace-router
description: Navigate AI Workspace Framework requirements at natural prompt and governed action/output boundaries. Use for non-trivial work in a project with an .ai-workspace control plane, after task/context/authority changes or compaction/resume/handoff uncertainty, and before final output. Do not invoke per tool call.
---

# AI Workspace router

This Skill is Framework-managed navigation and is `NON_AUTHORITY`. Repository-local Bootstrap, the exact project pin, current Controller/task objects, project corrections, process policy, action packages, product files and observed evidence remain authoritative.

## Activate

Activate on:

- a project-relevant user prompt that begins or materially redirects governed work;
- task, actor, role, phase, profile, objective, action, result, scope, user-decision or authority-source change;
- compaction, resume, handoff or uncertainty about the bound context;
- the natural pre-action boundary for a governed action;
- the natural pre-output boundary before a final user, terminal, handoff, Review or acceptance result.

Do not activate for every tool call or ordinary unchanged-context step. Explicit `$ai-workspace-router` is the manual recovery route. When implicit invocation cannot be observed, retain the `INVOCATION_UNPROVEN` evidence ceiling.

## Navigate

1. Locate and fully follow `.ai-workspace/BOOTSTRAP.md`. Bind the project Git root, explicit `project.json.frameworkVersion`, backend, release seal, Controller, current task, actor/role/phase/profile, current identities, exclusions and protection boundaries. Recovery grants no action.
2. Reuse a prior source-composition receipt only when its bound project/pin/seal/Controller/task/actor-role-phase-profile/corrections/policy/config/capability identities are unchanged. Otherwise rediscover.
3. Form an ephemeral `IntentEnvelope` with only: objective, requested action/result, semantic/path/capability/mutation/external hints and ambiguity state. It never contains authorized actions, observed capabilities or exact authority scope and never grants permission.
4. Use the pinned `TOOLCHAIN.json` operation `PROCESS_REQUIREMENTS_RESOLVE` in `DISCOVER` mode. Let it mechanically extract `AuthorityContext`; do not replace current facts with a model summary. The original user prompt remains alongside the returned selected canonical full texts.
5. If the resolver returns UNKNOWN semantic applicability, load conservatively. If required facts, authorization, exact scope, Git top, protection state or intent/authority reconciliation are unresolved, stop the governed action with the exact blocker.
6. Before a governed action, call `ADMIT_ACTION` with the unchanged DISCOVER receipt and real preparation/authorization evidence. Mechanical PASS proves only observable structure and never grants the action.
7. Before final output, call `FINALIZE_OUTPUT` with actual result and delivery receipts. Complete missing safe work or report the exact blocker; do not label `MISSING` or `NOT_DELIVERED` as completion.

## Keep gates separate

`SOURCE_WRITE`, `TEST_WRITE`, `TEST_RUN`, `REVIEW_ROUTE`, `REVIEW_EXECUTE`, `OWNER_ACCEPT`, `GIT_STAGE`, `GIT_COMMIT`, `PUSH`, `BROWSER_RUN`, `DEVICE_RUN` and `EXTERNAL` retain their own current packages and stop lines. Process resolution, a resource route or this Skill cannot merge, infer or widen them.

## Cost and evidence

Use the current main-model turn to interpret ordinary prompt intent; structured task intent requires no independent model call. An optional compatible provider may add at most one intent-only call. No persistent cache, provider registry, service, poller, ledger or per-tool hook is created. If the host cannot prove invocation or physical enforcement, say so.
