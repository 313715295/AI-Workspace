# AI Workspace Framework

AI Workspace Framework is a versioned, copyable process contract for AI-assisted projects. This repository contains generic Framework source, immutable releases, starter templates, validators and release tooling. It does not contain real consumer-project state.

## Version authority

There is no Framework-global default or `CURRENT` version.

- Every existing project owns its selected version in `.ai-workspace/project.json.frameworkVersion`.
- Every new registration must name an exact stable Framework version.
- A Framework release never upgrades a project, discovers consumers or records consumer identities.
- A project upgrade is a separate project-owned task against that project's real control plane and Git boundary.

A selected version is consumable only when its `VERSION.json` declares `STABLE`, `consumable=true` and `projectPinEligible=true`, and its `RELEASE_MANIFEST.json` is complete, canonically valid and independently approved.

## Repository layout

```text
framework/
  ROADMAP.md
  versions/
    <version>/
      VERSION.json
      RELEASE_MANIFEST.json
      project-starter/
      framework-maintenance-starter/
      scripts/
      tests/
scripts/
  register-project.ps1
  upgrade-project.ps1
```

Released directories under `framework/versions/<version>/` are immutable. A new version is developed directly in its final version directory, but remains non-consumable until its candidate is frozen, independently reviewed and sealed. A parallel draft copy is not required.

## New project materialization

Registration copies the chosen version's existing `project-starter`; it does not create a second process model.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/register-project.ps1 \
  -RepositoryPath <git-root> \
  -ProjectId <id> \
  -DisplayName <name> \
  -FrameworkVersion 1.8.0 \
  -ControllerId <host-task-id>
```

Preview is the default. Add `-Apply` only under the project's write authority. Omitted `FrameworkVersion`, unknown versions, incomplete release manifests and non-stable versions fail before project writes.

## Existing project upgrade

`scripts/upgrade-project.ps1` accepts a caller-supplied project root and explicit `ToVersion`. It validates the source control plane, target release and recoverable transaction boundary, preserves project-owned identity, controller, routine exclusions, capabilities and Bootstrap custom region, and changes only declared managed objects. It never searches for consumers or changes another project.

The project must run a fresh cold recovery under the new pin before claiming adoption. Natural-flow acceptance can be performed in any later user-selected project task; that evidence remains project-local.

## Maintenance topology

Dynamic Framework-maintenance state belongs to a dedicated control repository. The Framework source repository is the target, not a second control-plane authority. Begin from the Maintenance repository's repo-local `.ai-workspace/BOOTSTRAP.md`; chat, memory and this repository are locators only.

## Safety boundaries

Recovery and safe reads do not grant writes. Source, test write, test run, Review, Git, push, device/browser and external actions remain distinct capabilities. One writer, independent Review where required, protected-path boundaries, immutable stable versions and separate Git/publication gates remain mandatory.

Framework 1.8.0 reduces duplicate routing and evidence work without adding a mutable task-field manifest, authorization-consumption ledger, consumer registry, background monitor, retry service or cross-repository transaction.
