# Framework 1.10.0 versus 1.11.0

| Concern | 1.10.0 | 1.11.0 |
|---|---|---|
| owner-first roles, direct handoff and WARM rebind | released behavior | unchanged |
| Knowledge discovery/query/freshness | released behavior | unchanged |
| compact delivery and proportionality | released behavior | unchanged |
| project correction lifecycle | released behavior | unchanged; incorporation additionally requires reachable normative rules, behavior tests and requirement-level Review |
| task loader route | host infers role/profile/phase before calling the loader | task card declares authoritative role/phase; loader can bind the card directly |
| long-session refresh | selected modules are loaded during recovery | reload only at work-route/context boundaries; unchanged continuous work does not reload |
| adoption behavior | pre/post incorporated/effective/conflict report and record preservation | unchanged |
| downgrade/alternate version | retained overlay re-evaluates the same records | unchanged |
| added machinery | one project correction object and one cumulative release mapping | adds one task-card `Work route` line; no new object, role, service, queue or ledger |
| safety | one writer, protected paths, independent gates | preserved |
