# Framework 1.8.0

Status: `STABLE / CONSUMABLE / PIN_ELIGIBLE` after release-manifest seal.

Baseline: immutable Framework 1.7.0.

Framework 1.8.0 removes the Framework-global version selector. Projects select an exact version and own their pins. Registration copies this version's `project-starter`; upgrade changes only the caller project's managed control objects and preserves project-owned facts.

This release also reduces repeated launch, routing, authorization and evidence work:

- one valid implementation package can close recovery-to-implementation launch without a second manual start;
- `REUSE / MUST_NEW / BLOCKED` and standing same-scope task creation have explicit boundaries;
- one terminal report covers `READY / COMPLETE / BLOCKED / RANGE_GATE_REQUIRED`;
- Controller identity has one machine truth in `controller.json`;
- action batches receive one preflight with per-action results;
- risk and Review follow the actual action;
- PowerShell 5.1 and PowerShell 7 agree on knowledge timestamp strings.

It does not add consumer discovery, automatic adoption, a mutable-card field manifest, an authorization-consumption ledger, a second draft tree, cross-repository transactions or automatic retries.

Read `RECOVERY_CORE.md` first. Use `LOAD_MANIFEST.json` for role/profile/phase modules.
