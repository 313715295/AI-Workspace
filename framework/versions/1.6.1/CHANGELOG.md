# Framework 1.6.1 change log

## Changed

- the existing project knowledge checker accepts an optional 1–3 exact Entry ID selection after complete index and CURRENT reference/authority validation;
- omitted Entry IDs preserve the 1.6.0 stable first-three-by-ID behavior;
- register recognizes 1.6.1 as the same schema3/controller topology;
- upgrade supports a healthy 1.6.0 schema3 project moving to 1.6.1 through the existing two-object transaction while validating, but not rewriting, the current controller.

## Unchanged

- knowledge remains default-off, `REFERENCE_ONLY / NON_AUTHORITY`, uncached and project-local;
- schema, loader topology, capability shape, task schema, controller shape and routine-safe Git contract are unchanged;
- no search, ranking, automatic indexing, background service, common aggregation, second checker or second transaction engine is introduced.

## Separate gates

Source Review and stable projection are complete. Focused formal-release Review, live-root replacement, `framework/CURRENT`, Pocket pin adoption, project knowledge content, natural samples and Git remain separately gated.
