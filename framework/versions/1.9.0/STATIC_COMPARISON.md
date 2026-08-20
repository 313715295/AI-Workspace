# Framework 1.8.0 versus 1.9.0

| Concern | 1.8.0 | 1.9.0 |
|---|---|---|
| owner/actor route | temporary hats documented but recurring Controller relay remained possible | owner-first direct issuance/handoff; unnecessary Controller terminal relay rejected |
| role/resource change | mechanically routable | explicitly `REUSE + NONE/WARM`; fresh package does not imply FULL_COLD |
| CRITICAL independence | package declares independence | writer and material-contributor exclusion is bound mechanically |
| knowledge entry selection | caller must already know an exact ID | compact `DISCOVER`, then request-scoped `QUERY` for at most three IDs |
| knowledge freshness | query-time identity guard | read-only changed-authority impact result plus query-time guard |
| stable self-test | sealed source bytes could break the pending fixture assumption | fixture creates its own pending and sealed states |
| architecture proportionality | advisory lens | compact CRITICAL schema gate, no ledger or resolver state |
| hot-state pointers | reduced/non-duplicated | unchanged; no second pointer set added |
| safety | one writer, protected paths, independent gates | preserved |
