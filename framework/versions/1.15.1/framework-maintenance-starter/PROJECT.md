# {{DISPLAY_NAME}} — stable project facts

## Identity

- Project ID: `{{PROJECT_ID}}`
- Control Git root: `.ai-workspace/project.json.repositoryRoot = ..`
- Layout: `framework-maintenance-sibling`
- Pinned Framework: `{{FRAMEWORK_VERSION}}`
- Target repository: `.ai-workspace/project.json.frameworkTarget`
- Purpose: maintain, review and release the sibling AI-Workspace Framework repository without placing dynamic project authority inside the Framework target.

## Stable boundaries

- The dedicated parent is a workspace/sandbox boundary only; it has no Git or control plane.
- This Maintenance repository is the only dynamic authority and stores controller, tasks, authorizations, ROADMAP decisions and release state.
- The sibling Framework repository stores Framework source, versions, scripts, tests and a static AGENTS entry; it has no `.ai-workspace`.
- Existing consumer projects keep their own repo-local controllers, pins and adoption decisions.
- One authorization package binds one repository ID. Control and target writes, Review, Git, push and external remain separate gates.
- Stable Framework versions are immutable. Candidate implementation, sealed version publication, explicit project-pin adoption, directory migration and Git publication are separate actions.
- CONTROL `.ai-workspace/corrections.json` is the sole project-correction record; it never belongs to the Framework target.

## Recovery and validation

- Start only from `.ai-workspace/BOOTSTRAP.md`.
- Resolve the sibling target with the pinned version's maintenance resolver and a frozen project config identity.
- Read the target AGENTS entry explicitly; do not infer sibling instruction inheritance.
- Reprove both Git tops and dirty boundaries independently.
- Recovery rejects every complete, partial, foreign or reparse target `.ai-workspace`; no migration-mode exception exists.
- Physical repository relocation and old-control retirement are separately authorized project-specific offline work, not Framework runtime behavior.
