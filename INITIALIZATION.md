# AI Workspace initialization and adoption

## 1. Existing project recovery

1. Prove the actual cwd, project Git top and `.ai-workspace/` root.
2. Read `.ai-workspace/project.json`, `controller.json` and `BOOTSTRAP.md` strictly.
3. Resolve only `framework/versions/<project pin>/`; do not infer a version from HEAD, tags, network state or another project.
4. Validate the pinned version inventory and loader, then recover project facts, relationships, status, active tasks and Review profile.
5. Keep recovery read-only until current repo-local authority grants the next action.

The project-local pin is the sole version-selection authority for an existing project.

## 2. New project registration

A new project must select an exact Framework version. Omission is an error; there is no default selector.

1. Verify the selected version has valid `VERSION.json`, canonical `RELEASE_MANIFEST.json` and `project-starter/`.
2. Run root `scripts/register-project.ps1` without `-Apply`.
3. Review the exact destination and starter inventory.
4. Under project write authority, rerun with `-Apply`.
5. Fill project-owned facts in `PROJECT.md`, `RELATIONSHIPS.md`, `REVIEW_PROFILE.md`, `STATUS.md` and tasks without changing the Framework release.
6. Run a fresh cold recovery from the materialized `BOOTSTRAP.md`.

Framework 1.8.0 registration requires `FrameworkVersion` and `ControllerId`, and materializes exactly that version's `project-starter`.

## 3. Existing project upgrade

Upgrade is initiated by the project, not by a Framework release.

1. Create or reuse the project task according to the target version's `REUSE / MUST_NEW / BLOCKED` contract.
2. Freeze source pin, target pin, controller, managed objects, custom regions, protection boundary and Git state.
3. Run root `scripts/upgrade-project.ps1 -ToVersion <exact-version>` in preview mode.
4. Obtain the required project write authority, then apply the recoverable managed-object transaction.
5. Preserve project identity, display name, controller ID/epoch, routine exclusions, capabilities and Bootstrap custom region.
6. Run fresh cold recovery under the new pin and perform project-owned acceptance when appropriate.

The tool operates only on the supplied `ProjectRoot`. It does not discover, register or modify other consumers.

## 4. Separate actions

Framework candidate creation, source Review, stable seal, root-tool integration, Git commit, push/publication and a project's adoption are separate actions. Success in one does not authorize another.

A later natural project task may validate the released workflow. It need not be the task that motivated the Framework change, and its evidence must not be copied into Framework as consumer state.
