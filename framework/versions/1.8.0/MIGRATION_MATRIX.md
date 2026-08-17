# Framework 1.8.0 migration matrix

| Source | Target | Contract |
|---|---|---|
| new project | explicit 1.8.0 | copy exact 1.8.0 `project-starter`; Controller ID required |
| healthy repo-local schema3 1.6.0 | 1.8.0 | managed project/Bootstrap update; preserve Controller and project facts |
| healthy repo-local schema3 1.6.1 | 1.8.0 | same |
| healthy repo-local schema3 1.7.0 | 1.8.0 | same |
| healthy repo-local schema3 1.8.0 | 1.8.0 | verify and return already upgraded |
| schema2 legacy | 1.8.0 | blocked; first use the historical supported migration route to schema3 |
| partial, unknown or conflicting control plane | 1.8.0 | fail closed without writes |
| any real consumer | automatic adoption | unsupported |

Upgrade operates only on the caller-supplied project and never changes Controller identity/epoch, product source, Git or external state.
