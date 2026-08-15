# Framework 1.6.0 migration matrix

| Source | Target | Required input | Result |
|---|---|---|---|
| 1.4.1 repo-local schema2 | 1.6.0 schema3 | ControllerId + frozen routine-exclusion migration | exclusive three-object recoverable migration |
| 1.5.0 repo-local schema2 | 1.6.0 schema3 | same | same |
| 1.5.1 repo-local schema2 | 1.6.0 schema3 | same | same |
| 1.5.2 repo-local schema2 | 1.6.0 schema3 | same | same |
| healthy 1.6.0 schema3 | 1.6.0 | matching current controller | `ALREADY_UPGRADED` after strict health check |
| central legacy, partial/reparse, unknown source schema, missing/drifted migration | 1.6.0 | N/A | fail closed; no success claim |

The transaction covers `project.json`, `BOOTSTRAP.md`, and `controller.json` during a current-controller maintenance freeze in which all other control writers, Review, Git and external actions are closed. It freezes the old and desired exact3, preserves the Bootstrap custom block, writes serially, and verifies the final exact3. Interruption or an unexpected live state preserves the transaction and stops; the next invocation recovers before accepting a new request. The script does not support concurrent control-plane writers, create a second transaction engine, or recursively delete recovery material. Completed material remains audit-only until the adopting project finishes FULL_COLD and performs exact housekeeping. Routine-exclusion migration is a frozen string list; the migration does not scan source files, infer exclusions, or enumerate legacy authorization packages.

Old registration and old-target upgrade compatibility remain covered by the consolidated Framework test runner. Release and project pin migration are separate actions.
