# Framework 1.7.0

- lifecycle: `STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE`
- baseline: immutable Framework 1.6.1
- release class: `MINOR`

This candidate adds one bounded Framework-maintenance topology: a Maintenance control repository with the only dynamic `.ai-workspace` manages one sibling AI-Workspace Framework Git repository under a dedicated non-Git parent workspace.

Existing projects keep the repo-local schema3 layout and default behavior. The new schema4 maintenance starter, target resolver, topology-aware loader, repository-bound authorization and maintenance-safe Git path do not grant arbitrary cross-repository access, multi-target transactions, background services or consumer writes.

The maintenance starter is a steady-state `CURRENT` control plane. Schema1 authorization rejects Git repository environment overrides, proves cwd belongs to a non-reparse Git top, and strictly validates the canonical schema3 config, exclusions and capabilities; only that repo-local layout accepts schema1, while schema4 Maintenance requires schema2. Recovery and every schema2 authorization run the same target resolver and require that controller to remain CURRENT, both Git tops and the pinned Framework entry to be valid, and the Framework target to have no `.ai-workspace`. Every config, controller and required target path is walked component by component without following reparse points. Physical relocation and old-control retirement are separately authorized project work, not a Framework runtime state machine.

This stable version is available for explicit project adoption. Live roots/CURRENT, physical directory migration, each repository's Git publication and every consumer pin remain separate actions.
