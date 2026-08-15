# Framework 1.6.0 change log

## Added

- schema3 repo-local `project.json` with routine-only `routineExcludedPaths` and an empty default-off `frameworkCapabilities` object;
- `controller.json` as the only machine truth for current controller ID and epoch;
- PROJECT_CONTROLLER authorization binding to controller ID, epoch, and whole-file identity;
- bounded routine-safe Git STATUS/DIFF/INDEX entry with literal allow paths, default routine exclusions, exact-path override, and honest `UNVERIFIED`;
- structural storage of routine exclusions in project config; bounded consumers validate exclusions when used, without a policy module or permission claim;
- Framework 1.6 registration and recoverable schema2-to-schema3 three-object migration;
- a default-off project knowledge contract, schema, checker, and explicit optional loader selector.

## Simplified

- routine owner traffic is direct, terminal-only and exception-only; no ACK chain or route ledger;
- non-default resource needs live in the task and the host dispatches them; no binding artifact;
- simple multi-remote work records one honest result per remote; no transaction DTO, automatic retry, or compensation;
- repeated same-class findings force simplify/remove/defer/redesign instead of another local patch round.

## Deferred

Knowledge content, common knowledge aggregation, Pocket project initialization, project slimming, release, CURRENT and project adoption remain separately gated. Framework candidate integration is complete.
