# {{DISPLAY_NAME}} — current status

> Initialized {{CREATED_DATE}}. Current routing only; recovery must still validate the Git top, schema3 config, controller object, task cards and actual repository state.

## Baseline

- Project ID: `{{PROJECT_ID}}`
- Control plane: `repo-local`, repository root `..`
- Pinned Framework: `{{FRAMEWORK_VERSION}}`
- Controller: read `.ai-workspace/controller.json`
- Routine excluded paths: read `.ai-workspace/project.json`
- Optional Framework capabilities: `DISABLED` (`frameworkCapabilities={}`)
- Project corrections: `.ai-workspace/corrections.json / evaluate on recovery and before/after pin adoption`
- Initialization result: `NEEDS_INPUT`

## Current work

- Current phase: establish project facts; do not auto-start product implementation.
- Current task: none.
- Current writer/reviewer: `NONE / NONE`
- HEAD/index/source state: `UNVERIFIED`
- Git/push/external: closed until separately authorized.

## Next action

The initializing owner records project-specific facts, owners, routine excluded paths and current task routing, then performs one FULL_COLD recovery against the pinned Framework. Missing product, ownership or authority decisions return once to the user; routine file/test/review steps do not require per-step user confirmation after a bounded task is approved.
