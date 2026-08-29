# Framework 1.12.0 change log

Baseline: immutable Framework 1.11.0.

Release class: `MINOR`.

## Added

- language-independent `TOOL_CONTRACT.md` for official Framework operations;
- one payload-sealed `TOOLCHAIN.json` mapping operation names to backend entrypoints;
- project-level `frameworkToolBackend` selection, fixed to `powershell7` in this release;
- PowerShell 7 runtime guards on every official versioned entrypoint;
- one platform-neutral conformance route with Windows as the only platform officially declared and evidenced by 1.12.0; Linux/macOS admission remains future work.

## Changed

- Bootstrap resolves tools through the pinned version's toolchain manifest rather than assuming a script implementation from prose;
- 1.12.0 registration and upgrade require `pwsh` before project write and project the selected backend into `project.json`;
- child PowerShell calls reuse the current PowerShell 7 runtime instead of `powershell.exe`;
- path handling uses platform-neutral separators and reports normalized repository-relative evidence.

## Preserved

- immutable Framework 1.11.0 and older releases, including their PowerShell 5.1 compatibility claims;
- project-owned pins, Controller identity, project corrections and work-route/module loading;
- separate source, test, Review, Git, push and project-adoption gates.

## Not added

No launcher, zsh/Python backend, runtime installation/download, runtime code generation, backend switch command, task/action/package-level selection, backend registry/service/ledger, global Framework default, consumer registry or automatic project upgrade.
