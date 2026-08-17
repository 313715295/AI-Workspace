# Framework 1.6.1

- lifecycle: `STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE`
- baseline: immutable Framework 1.6.0
- release class: `PATCH_HOTFIX`

This release keeps the 1.6.0 task schema, project schema, loader topology, authorization model and default-off knowledge behavior. Its only functional addition is optional exact Entry ID selection in the existing project knowledge checker; no selector preserves the 1.6.0 first-three behavior.

It does not add search, ranking, automatic routing, knowledge content, common aggregation, caching, background maintenance, a second checker, a second transaction engine or any default workflow node.

Framework 1.6.1 is a stable, project-pin-eligible release. Its publication does not by itself replace live-root scripts, change `framework/CURRENT`, adopt it in Pocket Legion or publish Git; those remain separate actions.
