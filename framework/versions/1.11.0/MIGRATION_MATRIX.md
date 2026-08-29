# Framework 1.11.0 migration matrix

| Source | Target | Contract |
|---|---|---|
| new project | explicit 1.11.0 | copy exact 1.11.0 `project-starter`, including empty `corrections.json`; Controller ID required |
| healthy repo-local schema3 1.6.0–1.10.0 | 1.11.0 | pre-evaluate existing/missing corrections; preserve facts, Controller, custom region and existing correction bytes; add empty correction object only when absent |
| healthy repo-local schema3 1.11.0 | 1.11.0 | validate Bootstrap/correction overlay and return already upgraded |
| correction-enabled 1.11.0 project | older/alternate supported version | retain correction object and overlay; re-evaluate IDs against target coverage so unmatched requirements become effective again |
| schema2 legacy | 1.11.0 | blocked; first use the historical supported migration route to schema3 |
| malformed correction object or explicit target conflict | any | fail closed before pin write |
| unknown/missing/identity-mismatched coverage | any | retain every correction; never silently retire one |
| any real consumer | automatic adoption | unsupported |

Upgrade operates only on the caller-supplied project and never changes Controller identity/epoch, product source, Git or external state.

Long-lived tasks and sessions do not change behavior merely because Framework 1.11.0 exists. After the project explicitly adopts 1.11.0, fresh recovery loads the new starter/task contract; healthy same-task sessions may then WARM rebind. Existing cards are not bulk rewritten: until an authorized natural task update adds `Work route`, the loader requires explicit legacy role/profile/phase input and reports `LEGACY_LOAD_CONTEXT` as its evidence ceiling.
