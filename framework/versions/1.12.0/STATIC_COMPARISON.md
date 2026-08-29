# Framework 1.11.0 versus 1.12.0

| Concern | 1.11.0 | 1.12.0 |
|---|---|---|
| owner-first roles, direct handoff and WARM rebind | released behavior | unchanged |
| Knowledge discovery/query/freshness | released behavior | unchanged |
| compact delivery and proportionality | released behavior | unchanged |
| project correction lifecycle | released behavior with normative-rule/test/Review incorporation proof | unchanged |
| task loader route | task card declares authoritative role/phase; 1.10 and older cards use explicit legacy fallback | unchanged; 1.11 cards remain strict and cannot fall back as legacy |
| tool implementation contract | PowerShell scripts are the shipped implementation without a backend manifest | adds language-independent operation IDs, sealed `TOOLCHAIN.json` and one official `powershell7` backend |
| project backend selection | absent | adds one project-level `frameworkToolBackend` field bound by every authorization package through `projectConfigIdentity` |
| runtime boundary | scripts can be invoked by Windows PowerShell or PowerShell 7 according to each prior implementation | every official 1.12 entrypoint requires PowerShell 7 Core and fails before a requested write when unavailable |
| platform evidence | Windows-local release evidence | the platform-neutral contract and all nine official operations are validated on the only declared 1.12 platform, Windows; Linux/macOS remain unclaimed future admissions |
| adoption behavior | pre/post incorporated/effective/conflict report and record preservation | unchanged |
| downgrade/alternate version | retained overlay re-evaluates the same records | unchanged |
| added machinery | project correction object, cumulative release mapping and task-card `Work route` | adds one immutable toolchain manifest and one project config field; no new role, task, service, queue, registry or ledger |
| safety | one writer, protected paths, independent gates | preserved |
