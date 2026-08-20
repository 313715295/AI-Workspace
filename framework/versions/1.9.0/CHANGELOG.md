# Framework 1.9.0 change log

Release class: `MINOR`. Baseline: immutable `1.8.0`.

## Added

- stable self-test fixtures that distinguish pending candidates from sealed release bytes;
- Knowledge `DISCOVER` metadata and request-scoped `QUERY` for one to three selected IDs;
- read-only authority-change impact results `DIRECT_AFFECTED / NONE_DIRECT / UNKNOWN`;
- explicit owner-first actor/Reviewer routing with temporary task/phase hats;
- CRITICAL Review exclusion of task owner, issuer, candidate writer and material contributors;
- compact terminal delivery that rejects an unnecessary Controller relay;
- a compact CRITICAL architecture proportionality gate.

## Changed

- fresh authorization is separated from Controller issuance and FULL_COLD recovery;
- same-task role/resource rebind prefers `REUSE + NONE/WARM` when authority and impact remain stable;
- direct owner→executor, writer↔Reviewer and Reviewer→owner handoffs avoid semantic relay;
- knowledge schema1 remains readable while schema2 can declare plural authority dependencies;
- stable 1.8.0 remains immutable and project adoption remains explicit/project-owned.

## Removed

- none from the immutable 1.8.0 baseline; its no-global-selector and no-draft model is retained.

## Not added

No consumer registry, automatic project upgrade, actor/Reviewer pool, handoff or consumption ledger, background Knowledge monitor, token-budget subsystem, host hook/adapter, project/model metric store, ACK/polling protocol, retry service or second status truth.
