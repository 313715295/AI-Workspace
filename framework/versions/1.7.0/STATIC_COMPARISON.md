# Framework 1.6.1 versus 1.7.0

| Concern | 1.6.1 | 1.7.0 |
|---|---|---|
| ordinary project layout | repo-local schema3 | unchanged default |
| Framework maintenance | dynamic control plane mixed into Framework Git root | optional schema4 Maintenance control repo with one sibling Framework target |
| target locator | same Git top only | one safe sibling directory resolved from control Git root parent |
| authorization | schema1, implicit current repository | schema1 preserved; schema2 binds one repository ID and config identity |
| safe Git | one repo-local Git top | repo-local preserved; maintenance route selects control or target and validates both |
| loader | role/profile/phase/host/capability | adds compatible topology selector |
| target instructions | current repo chain | sibling AGENTS must be explicitly read by Maintenance Bootstrap |
| physical migration | project pin/control transactions | outside Framework runtime; a project-specific offline task must establish the final sibling layout before FULL_COLD |

The stable release adds no arbitrary cross-repository manager, multi-target transaction, service, ledger, retry/compensation loop or consumer auto-adoption.
