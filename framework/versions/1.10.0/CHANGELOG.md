# Framework 1.10.0 change log

Baseline: immutable Framework 1.9.0.

- Added one project-owned correction authority object and strict schema/checker.
- Added cumulative release coverage metadata without project identities.
- Added pre/post adoption reporting, conflict blocking, record preservation and downgrade re-evaluation.
- Preserved all 1.9.0 owner-first, Knowledge, delivery, proportionality, Review and authorization behavior.
- Added no actor registry, Review pool, handoff ledger, service, queue, polling or automatic consumer upgrade.

Release class: `MINOR`. Baseline: immutable `1.9.0`.

## Added

- a strict project-owned `.ai-workspace/corrections.json` authority object;
- one cumulative coverage mapping sealed inside the 1.10.0 payload;
- deterministic `INCORPORATED / STILL_EFFECTIVE / CONFLICT` evaluation against a selected version;
- registration, upgrade pre/post reporting, byte preservation and downgrade reactivation tests.

## Changed

- project recovery applies the pinned Framework plus still-effective correction records;
- upgrade blocks explicit conflicts before pin writes and rechecks the same records after projection;
- unknown, unsealed, malformed or mismatched coverage retains corrections instead of silently retiring them.

## Preserved

- immutable Framework 1.9.0 and its owner-first, Knowledge, compact-delivery, proportionality and Review contracts;
- explicit project-owned adoption, no Framework-global selector and no parallel draft tree.

## Not added

No consumer registry, automatic project upgrade, actor/Reviewer pool, handoff or consumption ledger, background Knowledge monitor, token-budget subsystem, host hook/adapter, project/model metric store, ACK/polling protocol, retry service or second status truth.
