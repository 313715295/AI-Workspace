# Framework 1.9.0

Status: `STABLE / CONSUMABLE / PIN_ELIGIBLE` after release-manifest seal.

Baseline: immutable Framework 1.8.0.

Framework 1.9.0 keeps the 1.8.0 project-owned version model: projects select an exact version and own their pins. Registration copies this version's `project-starter`; upgrade changes only the caller project's managed control objects and preserves project-owned facts.

This release also reduces repeated launch, routing, authorization and evidence work:

- owner-first direct execution and handoff keep domain semantics on the owning task;
- executor, Reviewer and resource selections are temporary phase hats, not long-lived management roles;
- `REUSE + NONE/WARM` is preferred for healthy same-task rebinds; a fresh package does not imply Controller issuance or FULL_COLD;
- CRITICAL Review excludes the task owner, issuer, candidate writer and material contributors;
- terminal delivery rejects a Controller relay when no Controller boundary exists and avoids routine `wait_threads`;
- Knowledge can `DISCOVER` compact metadata, `QUERY` at most three selected IDs and check changed-authority impact without a background service;
- CRITICAL architecture/workflow plans that add machinery carry one compact proportionality conclusion;
- stable-release self-tests use their own pending/sealed fixtures.

It does not add consumer discovery, automatic adoption, actor/Reviewer pools, a handoff/authorization ledger, background Knowledge maintenance, a token-budget subsystem, host hooks, a second draft tree, cross-repository transactions or automatic retries.

Read `RECOVERY_CORE.md` first. Use `LOAD_MANIFEST.json` for role/profile/phase modules.
