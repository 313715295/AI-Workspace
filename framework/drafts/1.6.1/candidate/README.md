# Framework 1.6.1

- lifecycle: `DRAFT / NOT_CONSUMABLE / NOT_CURRENT / NOT_PIN_ELIGIBLE`
- baseline: immutable Framework 1.6.0
- release class: `PATCH_HOTFIX`

This candidate keeps the 1.6.0 task schema, project schema, loader topology, authorization model and default-off knowledge behavior. Its only functional addition is optional exact Entry ID selection in the existing project knowledge checker; no selector preserves the 1.6.0 first-three behavior.

It does not add search, ranking, automatic routing, knowledge content, common aggregation, caching, background maintenance, a second checker, a second transaction engine or any default workflow node.

This draft is not consumable or pin eligible. Independent Review, formal stable projection, live-root replacement, `framework/CURRENT`, Pocket adoption and Git remain separate gates.
