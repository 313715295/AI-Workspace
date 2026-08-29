# Framework 1.12.0

Release payload state: final lifecycle fields are included before exact source Review. Project adoption remains unavailable until `RELEASE_MANIFEST.json` independently records approved source Review and completed integration for these exact payload bytes.

Baseline: immutable Framework 1.11.0.

Framework 1.12.0 separates the language-independent operation contract from its concrete tool implementation without introducing another workflow system:

- `TOOL_CONTRACT.md` defines selection, invocation, normalized results, identity/path behavior and fail-closed rules;
- sealed `TOOLCHAIN.json` maps abstract operations to exact version-local entrypoints;
- project config selects one `frameworkToolBackend`, inherited by every task and check;
- `powershell7` is the only official 1.12.0 backend and every entrypoint rejects Windows PowerShell 5.1;
- registration and upgrade write the project-level selection and fail before project mutation when `pwsh` is unavailable or the current platform is not declared;
- the normalized contract is platform-neutral, while this release officially declares and validates Windows only; Linux/macOS remain future admission targets.

The release retains 1.11.0 work-route loading, project correction lifecycle, owner-first direct routing and independent Review contracts. It adds no launcher, zsh/Python backend, runtime generation, task-level backend choice, registry, service, ledger, global version default, consumer record or automatic project adoption.

Read `RECOVERY_CORE.md` first. The host then reads `TOOLCHAIN.json`, matches `.ai-workspace/project.json.frameworkToolBackend`, and directly invokes the selected sealed entrypoint.
