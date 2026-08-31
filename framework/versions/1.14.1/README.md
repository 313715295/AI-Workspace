# Framework 1.14.1

Lifecycle: non-consumable candidate until independent Source Review, Maintenance `OWNER_ACCEPT` and deterministic sealing complete.

Baseline: immutable stable Framework 1.14.0.

Framework 1.14.1 is a backward-compatible PATCH. It does not add a new role, authority action, schema migration, backend or consumer requirement. It preserves the complete 1.14.0 process model and makes four bounded corrections:

- `PROCESS_REQUIREMENTS.json` remains the sealed internal catalog used by `PROCESS_REQUIREMENTS_RESOLVE`, but is no longer also loaded as a model-facing recovery module;
- context-budget evidence covers the complete Framework-controlled input: router Skill, selected load-plan modules and selected requirement pack;
- root checkout policy pins PowerShell module and JavaScript module text to LF so a normal Windows checkout preserves the sealed bytes;
- release governance classifies root maintenance, PATCH and MINOR work, runs affected tests during editing and one complete current-version suite at freeze, uses one independent Source Review plus focused same-scope rereview, keeps `OWNER_ACCEPT` separate, and replaces an unconditional second semantic post-seal Review with deterministic seal verification unless unreviewed free-form or executable bytes changed.

The loader still selects role, profile, phase, host, topology and capability modules. The process-requirements resolver still composes the sealed Framework catalog, still-effective project corrections and permanent project process rules without merging their authority. `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER`, `ADMIT_ACTION` and `FINALIZE_OUTPUT` retain their 1.14.0 semantics.

The resolver grants no authority and proves no semantic correctness. SOURCE_WRITE, TEST, REVIEW, OWNER_ACCEPT, GIT, PUSH, BROWSER, DEVICE, EXTERNAL and protection gates remain independent. Framework 1.14.0 and every earlier stable payload remain immutable. Framework 1.15.0 is deferred until a later user-selected need and will use this proportional release flow.

Read `RECOVERY_CORE.md` first. Resolve operations through `TOOLCHAIN.json`; Framework 1.14.1 continues to provide `powershell7` as its only official backend and declares Windows as its only release-evidenced platform.
