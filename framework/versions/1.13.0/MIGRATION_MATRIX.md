# Framework 1.13.0 migration matrix

| Source | Target | Required behavior |
|---|---|---|
| new project | explicit stable 1.13.0 | require PowerShell 7 first; copy the exact starter; create schema4 config, corrections and empty process-policy; require Controller ID |
| healthy repo-local schema3 1.6.0–1.12.0 | 1.13.0 | compare corrections; preserve facts, Controller, correction bytes, exclusions/capabilities and `PROJECT-CUSTOM`; add the PowerShell 7 backend; retain schema3 and do not silently create process-policy |
| healthy repo-local schema4 1.13.0 | 1.13.0 | validate backend, policy locator/object, Bootstrap, corrections and Controller; return already upgraded |
| schema3 project with free-text corrections | 1.13.0 | derive project-scoped aliases and canonical source identities; suppress only exact sealed mappings; load/reuse every unmatched record with `LEGACY_PROGRESSIVE_SELECTION_UNPROVEN` |
| schema3 project with normative `PROJECT-CUSTOM` | 1.13.0 | retain it as current project authority with `LEGACY_PROJECT_CUSTOM_PROGRESSIVE_SELECTION_UNPROVEN`; no empty-source or compact-selection claim |
| schema4 1.13 project with empty structured policy | older supported version | retain corrections and `PROJECT-CUSTOM`; project schema3 without the policy locator; preserve the now-inactive policy file as recoverable history |
| schema4 1.13 project with active structured policy rules | older supported version | fail `STRUCTURED_PROCESS_POLICY_DOWNGRADE_CONFLICT`; the older version cannot interpret those permanent rules |
| correction evaluation against an older ID-only coverage record | older supported version | report `LEGACY_ID_ONLY_RETAINED`; do not suppress a current correction without exact native/catalog/source-record mapping |
| schema4 project after policy migration | older version | block unless a separately reviewed reverse project transaction restores every retired legacy rule without dual authority |
| schema2 legacy | 1.13.0 | blocked; first use a historical supported route to establish healthy schema3 control |
| unavailable backend/runtime or unsupported platform | 1.13.0 | fail closed before project write; no install, download or fallback |

Adoption is project-owned. Preview must report exact incorporated, retained and conflicting corrections before pin projection and recheck after projection. Records are never deleted by upgrade.

Existing two-field 1.11/1.12 task routes remain readable with `LEGACY_ACTOR_CONTEXT_UNBOUND`, but the current task owner must bind the real actor at the first 1.13 substantive action. There is no bulk task rewrite or actor inference.

Moving permanent rules from `PROJECT-CUSTOM` to `.ai-workspace/process-policy.json` is a separate project transaction binding config, Bootstrap and policy pre/postimages. Registration may create the empty carrier; ordinary upgrade does not perform that migration.
