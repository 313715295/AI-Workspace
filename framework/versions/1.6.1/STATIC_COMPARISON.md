# Framework 1.6.0 versus 1.6.1 patch comparison

| Concern | 1.6.0 | 1.6.1 stable |
|---|---|---|
| knowledge validation | validate complete index and all CURRENT references/authorities | unchanged |
| returned entries | first three CURRENT entries by ID | optional 1–3 exact IDs; omission preserves 1.6.0 behavior |
| search/ranking/cache | absent/prohibited | unchanged |
| project/controller schema | schema3 + current controller | unchanged |
| register | schema3 registration for 1.6.0 | same topology for 1.6.0 and 1.6.1 |
| upgrade | older schema2 to 1.6.0; generic same-topology transaction | adds 1.6.0 schema3 to 1.6.1 two-object upgrade using the same transaction |

The patch adds no module, service, ledger, capability field, default loader byte or workflow node.
