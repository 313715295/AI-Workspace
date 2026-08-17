# Framework 1.6.1 migration matrix

| Source | Target | Required input | Result |
|---|---|---|---|
| healthy 1.6.0 repo-local schema3 | 1.6.1 schema3 | matching current ControllerId | exclusive two-object project pin + managed Bootstrap transaction; controller validated, unchanged |
| healthy 1.6.1 repo-local schema3 | 1.6.1 | matching current ControllerId | no write after strict health check |
| 1.4.1/1.5.x repo-local schema2 | 1.6.1 | N/A | fail closed; upgrade to 1.6.0 first through the established three-object route |
| central legacy, partial/reparse, unknown schema or unhealthy controller | 1.6.1 | N/A | fail closed; no success claim |

The patch reuses the only `.framework-upgrade-transaction` reader/recovery/commit implementation. It preserves the Bootstrap custom block, writes serially, retains recovery material and does not support concurrent control writers or automatic cleanup. The established 1.4.1/1.5.x→1.6.0 three-object route remains unchanged and separately covered.

Old registration and old-target upgrade compatibility remain covered by the consolidated Framework test runner. Release and project pin migration are separate actions.
