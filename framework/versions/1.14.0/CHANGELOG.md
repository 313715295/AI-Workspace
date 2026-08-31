# Framework 1.14.0 change log

Baseline: immutable Framework 1.13.0. Release class: `MINOR`.

## Added

- one repo-local, non-authoritative `ai-workspace-router` Skill plus a bounded managed `AGENTS.md` block, so natural prompt/task/phase boundaries rediscover and fully load only the applicable rules without per-tool reload;
- closed ephemeral `AuthorityContext` and model-interpreted `IntentEnvelope` contracts for schema-2 process discovery;
- canonical module-owned requirement fragments and `build-process-requirements.ps1`, with ordinal generation checks against the single native catalog;
- corrections schema v2 progressive selectors and whole-record identities while preserving schema-v1 compatibility and exact absorption semantics;
- one bounded `DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL` authorization branch for free, zero-project-data, single-atomic provider metadata/status/capability reads;
- five exact replayable process-budget fixtures and a cold-process measurement harness recording median and nearest-rank p95 evidence.

## Changed

- the existing `PROCESS_REQUIREMENTS_RESOLVE` front door keeps its three modes but schema 2 now derives complete current authority facts, reconciles declared path/capability/mutation/external intent with those facts, binds full intent/context identities, consumes the full authorization checker, blocks exact-object drift again at `ADMIT_ACTION`, and verifies exact postimage receipts at `FINALIZE_OUTPUT`; legacy schema 1 remains discovery/evaluation-only and cannot pass a categorical governed boundary without the missing AuthorityContext;
- the existing single composer now performs progressive selection across the sealed Framework catalog, still-effective corrections and permanent project rules while rejecting the same effective rule duplicated across carriers;
- registration now renders and validates its complete fixed 13-object transaction at one deterministic previewed same-volume locator outside the repository, atomically promotes it as the first repository write, binds the state transaction ID and recovery destination back to those trusted locators, and reconciles only a known-empty leftover preparation directory after verified recovery; registration, ordinary six-object transition and actor-bound recovery also require the actual physical old/new/state tree to equal the declared closure before any live write; unknown material or live bytes stop, known OLD/MIXED state resumes, project-owned `AGENTS.md` bytes outside the managed block remain exact, and downgrade removes only Framework-managed router bytes; every existing component of `AGENTS.md` and `.agents/skills/ai-workspace-router/SKILL.md` is repository-contained, correctly typed and non-reparse at preflight and immediately before managed writes/deletion, so a junction or symlink cannot redirect the router projection outside the repository;
- deterministic repository-resident upgrade preparation/transaction/recovery paths exposed as a preview write set, plus a Controller-authorized actor-bound upgrade that binds the exact current task, complete write set and current Controller ID/epoch/object identity, projects the target pin first, atomically writes the task last and then stops for immediate target-version FULL_COLD;
- recursive duplicate-member rejection for authorization JSON, including Unicode-escaped equivalent names, before ordinary JSON projection;
- healthy 1.12 schema3, inherited 1.13 schema3 and native 1.13 schema4 projects all have explicit 1.14 projection coverage; repeat registration accepts both native corrections v2 and the supported preserved non-empty corrections v1 state after checker validation; structured project policy remains project-owned rather than a second Framework authority;
- release sequencing is explicit: full source Review, Maintenance `OWNER_ACCEPT`, limited deterministic seal projection, then focused independent post-seal Review.

## Preserved

- the Framework 1.12 Tool Contract and official Windows PowerShell 7 backend;
- immutable older releases and project-owned version pins;
- owner-first routing, healthy WARM rebind, compact non-interrupt delivery and project correction retention;
- independent SOURCE_WRITE, TEST, REVIEW, OWNER_ACCEPT, GIT, PUSH, BROWSER, DEVICE, EXTERNAL and protection gates.

## Not added

No second effective authority, actor or Reviewer pool, trigger registry, merged policy projection, service, poller, ledger, per-tool reload/hook, automatic correction rewrite, automatic project upgrade or host-enforcement claim.
