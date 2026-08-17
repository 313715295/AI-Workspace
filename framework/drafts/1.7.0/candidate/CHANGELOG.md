# Framework 1.7.0 change log

## Added

- `framework-maintenance-sibling` schema4 control layout with one safe sibling Framework target;
- maintenance project starter and complete Bootstrap recovery route;
- deterministic control/target Git-top resolver bound to project config identity;
- loader `Topology` selector and complete `FRAMEWORK_MAINTENANCE.md` module;
- schema2 repository-bound authorization for one-package/one-repository writes, gated by the same final steady-state resolver used by recovery and safe Git;
- schema1 authorization is accepted only when an unoverridden Git discovery proves cwd belongs to a non-reparse schema3 repo-local top whose canonical config, exclusions and capabilities are strictly valid; Maintenance cannot select the weaker format;
- maintenance-aware safe-Git selection with separate routine exclusions and dirty evidence.
- CURRENT-only steady-state maintenance recovery, unconditional target control-plane rejection and component-by-component reparse rejection; physical relocation remains project-specific offline work.
- complete-candidate two-Git recovery fixtures, schema/type/identity/cross-repository negatives and per-repository STATUS/DIFF/INDEX evidence.

## Preserved

- repo-local schema3 remains the default and retains its existing starter, authorization, loader and safe-Git behavior;
- existing stable versions remain immutable;
- consumer controllers, pins and adoption decisions remain project-local;
- Review, Git, push, external and release gates remain separate.

## Not added

No arbitrary absolute target paths, `..` task paths, target search, multiple targets, cross-repository atomic transaction, retry/compensation service, central ledger, background monitor or automatic consumer upgrade.
