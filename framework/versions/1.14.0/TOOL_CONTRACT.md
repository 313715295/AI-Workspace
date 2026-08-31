# Tool Contract v1

Framework operations are language-independent contracts. A backend is an immutable implementation selected once by the adopting project, not a task role, action, resource route or authorization capability.

## PROCESS_REQUIREMENTS_RESOLVE

The operation has three logical modes over one source composer:

- `DISCOVER` strictly binds project, task whole identity, host-authenticated actor, role, phase, profile, project-declared capabilities, objective/action/result kind and normalized exact scope. `pathHints` must be inside that scope, `capabilityHints` must be observed, and mutation/external hints must agree with the requested action. A CLEAR contradiction fails; UNKNOWN retains a conservative-load ceiling and cannot admit the governed action. Caller capability drift, unknown action/result kinds and unsafe relative paths fail closed. It selects and returns the full text of applicable sealed Framework requirements, still-effective corrections and permanent project rules, a source-composition identity and a separate selection identity over the complete normalized intent.
- `ADMIT_ACTION` consumes an exact ephemeral DISCOVER receipt, revalidates every bound task/Framework/catalog/coverage/project/correction/policy/custom source identity, reruns the complete authorization observation against current exact object bytes and checks selected preparation requirements before a distinct governed action. It never grants the action.
- `FINALIZE_OUTPUT` performs the same source revalidation and checks observable result/delivery completeness before the actual final output. For every authorized exact path, result receipts contain exactly one `OBJECT_POSTIMAGE|<relative-path>|<byteLength|UPPER_SHA256>` matching the current repository object.

UNKNOWN semantic applicability conservatively loads the rule. Schema1 free-text corrections and legacy PROJECT-CUSTOM use full-source compatibility loading and unchanged-context reuse, with `LEGACY_PROGRESSIVE_SELECTION_UNPROVEN`; no compact-saving claim is made. Source composition, progressive selection and boundary-decision identities are distinct, with separate invalidators; selection binds the full intent envelope and boundary decisions also bind the discovered context identity. A backend may reread unchanged bytes and must not claim a physical cache hit unless observed. Receipts are ephemeral, non-authoritative and never a repository ledger.

Legacy schema-1 process input remains discovery/evaluation compatibility only. It has no bound authorization package or complete AuthorityContext, so a categorical governed action can never pass `ADMIT_ACTION` or `FINALIZE_OUTPUT`; the resolver returns `LEGACY_AUTHORITY_CONTEXT_UNBOUND`. Schema 2 is required for any governed action boundary.

Mechanical PASS proves only current identities and supplied structural receipts. It does not prove semantic correctness, model attention, host invocation or an independent authorization/Review/Git/external gate.

## Project selection

The exact project authority field is `.ai-workspace/project.json.frameworkToolBackend`. Framework 1.14.0 accepts only `powershell7`; registration and upgrade write that value deterministically. Every task and operation inherits it. Authorization packages do not repeat the value: their existing `projectConfigIdentity` binding invalidates the package when the selection or any other project config byte changes.

The host reads the project pin, then the pinned version's sealed `TOOLCHAIN.json`. It requires an exact backend ID match, an `OFFICIAL` backend, a supported platform and an available runtime meeting the declared edition/version. Unknown fields, unknown backend, missing entrypoint, path escape, unavailable runtime or contract drift fails closed before the requested operation. Framework does not install or download a runtime.

## Invocation

Operation names and entrypoint paths come only from `TOOLCHAIN.json`. Paths are version-root-relative, NFC-normalized, forward-slash logical locators with no absolute path, drive, empty component, `.` or `..`. The host invokes the selected entrypoint directly with the operation's documented arguments; no user-facing launcher or generated wrapper is part of the contract.

The official `powershell7` backend is invoked with `pwsh -NoProfile -NonInteractive -File <entrypoint> ...`. Each 1.14.0 backend entrypoint independently rejects a non-Core runtime or PowerShell major version below 7.

## Results and evidence

Exit code `0` means the operation returned its documented accepted result. Any nonzero exit fails the requested boundary; callers preserve the entrypoint's explicit reason instead of guessing success from prose. Structured `-AsJson` output, when supported by an operation, is preferred for host decisions. Human-readable output is a projection of the same result, not another authority object.

File identities remain `byteLength|UPPER_SHA256` over exact bytes. JSON and Markdown payloads use strict UTF-8 without BOM and LF line endings. Security-relevant JSON rejects duplicate members recursively after JSON escape decoding; a parser's last-member behavior is never authority. Repository-relative evidence uses forward slashes. Platform conformance compares normalized status, reason, operation, relative locator and identity fields; it never compares temporary roots or raw absolute paths.

The contract permits later platform admission, but each released toolchain lists only platforms it actually supports. 1.14.0 lists Windows only. Platform-specific evidence requirements remain explicit:

- Windows uses reparse-point and case-insensitive path probes where the filesystem reports them.
- Linux uses symbolic-link, executable/permission and case-sensitive probes.
- macOS uses symbolic-link and permission probes while accepting the actual volume's reported case behavior.
- Git safe-directory, separator normalization and strict UTF-8/LF fixtures run on every platform.

A platform is supported only after its actual conformance run passes. Missing CI/host evidence is a capability ceiling, not inferred compatibility.

## Backend lifecycle

Backend selection changes only at a project adoption/switch boundary after a released Framework version supplies the target backend. The project must have no active writer/reviewer lease, must invalidate outstanding packages through project config identity drift, project the managed config transactionally and complete fresh recovery plus conformance checks. Framework 1.14.0 supplies only one backend, so it intentionally provides no switch command.

This contract adds no backend registry, service, ledger, plugin market, runtime code generation, task-level choice or global Framework default. Skills and ordinary host tools remain host concerns.
