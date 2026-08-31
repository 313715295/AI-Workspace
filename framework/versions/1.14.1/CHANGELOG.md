# Framework 1.14.1 change log

Baseline: immutable Framework 1.14.0. Release class: `PATCH`.

## Fixed

- the sealed process catalog remains the sole resolver/composer input but is no longer returned by the model-facing load plan before its selected rules, removing one complete duplicate rule load;
- Framework-controlled context budgets now cover the router Skill, selected role/phase/recovery modules and selected rule pack instead of measuring the selected pack alone;
- repository checkout policy covers `.psm1` and `.mjs`, preventing common Windows `core.autocrlf=true` checkouts from invalidating stable payload bytes;
- root registration and upgrade tools recognize 1.14.1 through the existing 1.14 transaction model, including direct healthy 1.11–1.14.0 adoption while preserving 1.14.0 registration behavior;
- release handling distinguishes root maintenance, compatible PATCH and MINOR work, uses affected tests during implementation and one final complete current-version suite, one independent Source Review plus focused same-scope rereview, separate OWNER_ACCEPT and deterministic post-seal verification without an unconditional second semantic Review.

## Preserved

- the complete 1.14 authority, authorization, correction, process-resolution, router, project migration and external-action behavior;
- role/phase Markdown modules and the canonical fragment-to-catalog projection;
- independent SOURCE, TEST, REVIEW, OWNER_ACCEPT, GIT, PUSH, BROWSER, DEVICE, EXTERNAL and protection gates;
- immutable older releases and project-owned version pins.

## Not added

No new Framework capability, schema migration, role, backend, resolver, composer, catalog, cache, service, registry, queue, ledger, poller, automatic project upgrade or consumer operation. Framework 1.15.0 remains deferred until a later explicit need.
