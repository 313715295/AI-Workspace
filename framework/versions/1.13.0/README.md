# Framework 1.13.0

Release payload state: final `STABLE / CONSUMABLE / PIN_ELIGIBLE` lifecycle fields are included before exact source Review. Project adoption remains unavailable until `RELEASE_MANIFEST.json` independently records approved source Review and completed integration for these exact payload bytes. Post-release project observation is optional and does not block the stable seal.

Baseline: immutable Framework 1.12.0.

Framework 1.13.0 adds one progressive process-requirement front door for all Framework-governed work:

- `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER` composes the sealed Framework catalog, still-effective project corrections and the project's permanent process rules without merging their authority;
- `ADMIT_ACTION` checks observable preparation before the intended action;
- `FINALIZE_OUTPUT` checks observable result and delivery receipts before the final output;
- task cards bind the current host actor together with role and phase;
- only selected structured requirements return their full text; unchanged source/context bindings are reused through the ephemeral DISCOVER receipt;
- legacy free-text corrections and pre-migration `PROJECT-CUSTOM` remain fully effective, but carry an explicit non-progressive evidence ceiling;
- an incorporated correction is suppressed only through an exact sealed alias, native requirement and canonical source-record mapping.

The resolver grants no authority and proves no semantic correctness. SOURCE_WRITE, TEST, REVIEW, OWNER_ACCEPT, GIT, PUSH, BROWSER, DEVICE, EXTERNAL and protection gates remain independent. A non-conforming host can still omit an invocation; `hostEnforcementGrade` states that ceiling rather than hiding it.

1.13.0 adds one structured project-owned `.ai-workspace/process-policy.json` carrier for new permanent project-specific process rules. Existing projects retain their current `PROJECT-CUSTOM` authority until a separately reviewed atomic project migration moves a rule; one rule may not be active in both carriers.

No second authority, merged effective-state file, service, registry, poller, ledger, per-tool hook, runtime rule generator, automatic project adoption or new long-lived role is added. Framework 1.12.0 and older stable payloads remain immutable.

Read `RECOVERY_CORE.md` first. Resolve operations through `TOOLCHAIN.json`; Framework 1.13.0 continues to provide `powershell7` as its only official backend and declares Windows as its only release-evidenced platform.
