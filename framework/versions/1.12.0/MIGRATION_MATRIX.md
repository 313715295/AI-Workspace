# Framework 1.12.0 migration matrix

| Source | Target | Contract |
|---|---|---|
| new project | explicit 1.12.0 | require `pwsh` 7 first; copy exact 1.12.0 `project-starter`; write `frameworkToolBackend=powershell7`; Controller ID required |
| healthy repo-local schema3 1.6.0–1.11.0 | 1.12.0 | pre-evaluate corrections; preserve facts, Controller, custom region, exclusions/capabilities and correction bytes; project the backend field transactionally |
| healthy repo-local schema3 1.12.0 | 1.12.0 | require the exact backend field and validate Bootstrap/correction overlay; return already upgraded |
| correction-enabled 1.12.0 project | older/alternate supported version | retain correction object and overlay; remove or project backend configuration exactly as required by the selected target's starter contract |
| schema2 legacy | 1.12.0 | blocked; first use the historical supported migration route to schema3 |
| unknown/unavailable backend or missing PowerShell 7 | 1.12.0 | fail closed before project write; no install, download or fallback |
| malformed correction object or explicit target conflict | any | fail closed before pin write |
| unknown/missing/identity-mismatched coverage | any | retain every correction; never silently retire one |
| any real consumer | automatic adoption | unsupported |

Upgrade operates only on the caller-supplied project and never changes Controller identity/epoch, product source, Git or external state. `frameworkToolBackend` is project-level Framework-use configuration; it is not copied into task cards or authorization packages. Its byte change is already covered by project config identity drift.

Framework 1.12.0 supplies no backend switch command because no second official backend exists. A future switch requires a target release that contains the backend, a safe project-level boundary, transactional config projection, fresh recovery and target-backend conformance.
