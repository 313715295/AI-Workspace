# Framework 1.16.0

Lifecycle authority: `VERSION.json` and `RELEASE_MANIFEST.json`. This README does not duplicate or select lifecycle state.

Baseline: immutable stable Framework 1.15.1. Release class: `MINOR`.

Framework 1.16.0 keeps the single progressive-loading composer and adds a bounded adoption/runtime contract:

- `ADOPTION_PROFILE.json` is the fixed mechanical source for registration eligibility, direct source versions, project-control shape, exact enabled-capability binding and the three process-pack ceilings. Root registration and upgrade tools consume that profile instead of adding another target-version branch.
- `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER` returns the selected complete canonical Markdown blocks once at the natural context boundary plus a compact reusable receipt containing bindings and preparation/result obligations, but no copied `fullText`.
- `ADMIT_ACTION` and `FINALIZE_OUTPUT` consume the compact receipt, revalidate its sources and selection context, and require a full DISCOVER reload whenever those bindings are uncertain or drift.
- Ordinary selected packs are limited to 32768 bytes and the general absolute ceiling is 65536 bytes. Only a verified still-effective schema1 correction set with clear intent, no normative `PROJECT-CUSTOM` content and no source-record mismatch may use the explicit 98304-byte compatibility ceiling; the result carries a visible `LEGACY_SCHEMA1_CORRECTION_COMPATIBILITY` marker. Current schemas never inherit that exception.
- Temporary resolver inputs are deleted only when the caller explicitly requests cleanup and the exact file is a non-reparse `aiw-*.json` beneath the operating-system temp directory. Success and failure remove only that file; unsafe cleanup requests fail without deletion.
- A schema2 `CONTROL` package may finalize its own exact active task from the bound preimage to one postimage. The task ID and Owner must remain unchanged, the task must be the package's exact `CONTROL_WRITE` object, an exact postimage receipt is required, and every other source remains drift-intolerant.
- Registration and direct upgrades from stable 1.14.1, 1.15.0 and 1.15.1 use the profile-declared schema4/PowerShell 7/host-global-router projection. Upgrade passes the project's exact ordinal-sorted enabled capability IDs unchanged into the current-pin bridge; intent hints grant nothing. The active task remains the last project write.
- Version-independent release governance lives at Framework root in `framework/FRAMEWORK_RELEASE.md`; it is absent from this sealed payload and from the runtime fragment/catalog selection surface.

The resolver grants no authority and proves no semantic correctness. SOURCE_WRITE, TEST, REVIEW, `OWNER_ACCEPT`, Git, push, browser/device, external and protection gates remain independent. Project corrections and project-specific process rules remain separate project authorities.

Read `RECOVERY_CORE.md` first when the host-global Skill is unavailable, incompatible or not proven to have run. Resolve executable operations through `TOOLCHAIN.json`. Framework 1.16.0 provides `powershell7` as its only official backend and has release evidence for Windows only.
