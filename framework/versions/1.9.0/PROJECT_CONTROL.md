# Project control

A project's repo-local `.ai-workspace/project.json.frameworkVersion` is its only version-selection authority. Framework root stores no consumer records and has no global default selector.

## Registration

Root `scripts/register-project.ps1` requires an explicit exact version and Controller ID. Before any project write it validates:

- target `VERSION.json` is `STABLE`, consumable and pin-eligible;
- target `RELEASE_MANIFEST.json` matches the canonical payload and says source Review is approved;
- target `project-starter` inventory is exact;
- destination Git top, path and existing control-plane conditions are safe.

It materializes exactly the selected version's `project-starter`. The starter is the reusable project process; registration does not invent another process.

## Upgrade

Root `scripts/upgrade-project.ps1` requires caller-supplied `ProjectRoot` and exact `ToVersion`. It validates the target release before writes, accepts healthy schema3 sources supported by the migration matrix, and preserves:

- project ID and display name;
- repo-local layout and repository root;
- Controller ID, epoch and state;
- routine exclusions and capabilities;
- Bootstrap project custom region.

Only declared managed objects change. The tool does not search for consumers, modify source/product files, stage/commit/push or update another project.

## Controller lifecycle

The machine truth is `controller.json`. Handoff freezes old/new identity and epoch, writes hot projections first when authorized, writes the Controller object last, and finishes `TAKEOVER_COMPLETE`. Old read-only grace may preserve bytes for recovery but does not retain long-term routing authority or authorize cleanup.

## Knowledge capability

Knowledge reference remains optional, project-local and non-authoritative. `DISCOVER` returns compact metadata; `QUERY` validates at most three selected IDs at request scope. A read-only changed-authority impact check helps the owning task refresh or mark affected entries stale at its normal acceptance boundary. No background service or automatic write exists, and Knowledge cannot change product facts, task authority or Framework pin.

## Owner-first project work

Project adoption loads the 1.9.0 starter and task contract, but it does not rewrite existing task cards or sessions. Inside an unchanged domain task, DOMAIN_OWNER directly selects temporary actors/Reviewers, issues fresh scoped packages and receives their results. PROJECT_CONTROLLER handles only a Controller-owned next action or an owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary.
