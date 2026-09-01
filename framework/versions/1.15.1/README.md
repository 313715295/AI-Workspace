# Framework 1.15.1

Lifecycle: non-consumable candidate until independent Source Review, Maintenance `OWNER_ACCEPT` and deterministic sealing complete.

Baseline: immutable stable Framework 1.15.0. Release class: `PATCH`.

Framework 1.15.1 preserves the complete 1.15 progressive-loading and authority model while repairing two bounded compatibility defects:

- the host first reads only the minimum project/task/source facts needed to form a bound discovery input;
- `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER` selects against the complete metadata catalog, then returns the complete bodies of only the selected exact Markdown blocks;
- Framework Markdown remains the sole native rule-body authority; fragments own selectors and exact block locators, while `PROCESS_REQUIREMENTS.json` is generated metadata and carries no copied `fullText`;
- `LOAD_PLAN_RESOLVE` remains available for compatibility, non-rule supporting artifacts, Framework-wide explanation/maintenance and bounded affected-module fallback, but it does not pre-filter the rule catalog;
- the host-global `ai-workspace-router` Skill provides navigation for compatible Framework releases without becoming project authority or a repo-local managed copy;
- project registration and actor-bound upgrade use deterministic preparation/recovery paths. Adoption from 1.14.0 or 1.14.1 requires a current active actor route plus one closed schema3 Controller package that binds both preimages and final live-object postimages; when the current resolver fails solely on its 12288-byte selected-pack ceiling, the tool independently composes and retains the complete current rule pack under the 1.15.1 absolute ceiling before the ordinary actor-bound plan; project task projection is last and no write follows it;
- Router context tests derive actual canonical Skill bytes and separately enforce its identity, required navigation semantics and maximum ceiling instead of repeating a frozen byte literal;
- proportional release handling uses affected checks during editing, one frozen complete current-version suite, one independent Source Review, separate `OWNER_ACCEPT` and deterministic post-seal verification. An additional semantic Review is required only after reviewed free-form or executable bytes change.

The resolver grants no authority and proves no semantic correctness. SOURCE_WRITE, TEST, REVIEW, OWNER_ACCEPT, GIT, PUSH, BROWSER, DEVICE, EXTERNAL and protection gates remain independent. Project corrections and project-specific process rules remain separate authorities and are composed without being copied into Framework rule bodies.

Read `RECOVERY_CORE.md` first when the host-global Skill is unavailable, incompatible or not proven to have run. Resolve executable operations through `TOOLCHAIN.json`. Framework 1.15.1 continues to provide `powershell7` as its only official backend and declares Windows as its release-evidenced platform.
