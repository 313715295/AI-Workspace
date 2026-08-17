# Framework 1.8.0 change log

Release class: `MINOR`. Baseline: immutable `1.7.0`.

## Added

- explicit-version registration and release-manifest eligibility checks;
- direct final-version development with a non-consumable Review/seal gate;
- launch closure, routing decision and terminal delivery contracts;
- batch action authorization preflight with per-action results;
- host-authenticated stale-message boundary and a lightweight Codex model-route mapping;
- PowerShell 5.1/7 knowledge timestamp compatibility;
- focused final seal verification after full candidate Review.

## Changed

- projects, not Framework root, own selected version pins;
- new projects copy the selected version's existing `project-starter`;
- upgrades preserve project-owned facts and modify only declared managed objects;
- task cards, STATUS and task index have reduced, non-duplicated hot-state responsibilities;
- Review requirements follow the action's risk rather than incidental file count.

## Removed

- Framework-global default/version selector;
- `currentEligible` release metadata;
- planned draft/candidate projection for new versions;
- implicit-default project registration.

## Not added

No consumer registry, automatic project upgrade, mutable task-field manifest, authorization-consumption ledger, background monitor, retry/compensation service or multi-repository atomic transaction.
