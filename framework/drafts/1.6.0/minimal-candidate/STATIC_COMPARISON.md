# Framework 1.5.2 versus 1.6.0 minimal comparison

| Concern | 1.5.2 | 1.6.0 minimal |
|---|---|---|
| task schema and loader behavior | stable | task schema and default base plan unchanged; explicit enabled capabilities may append an optional module |
| project config | schema2 | schema3 routine exclusions + disabled capability seam |
| current controller | project text pointers | separate ID/epoch object + authorization binding |
| routine Git inspection | project convention | bounded literal allowlist; configured routine exclusion or invalid input returns `UNVERIFIED`; exact path may be explicitly overridden |
| routine routing | owner/controller prose | direct owner, controller pull, exception-only, no ACK chain |
| resource choice | four quality levels | same levels; task minimum only when non-default; no binding artifact |
| multi-remote | owner/external contract | one attempt and honest result per remote; no ledger/compensation |
| schema2 upgrade | two-object pin/bootstrap | three-object recoverable migration to schema3 |

The minor release adds project-control safety and default-off project knowledge infrastructure without adding new default workflow nodes. Knowledge content, common aggregation, and Pocket initialization are not part of this candidate.
