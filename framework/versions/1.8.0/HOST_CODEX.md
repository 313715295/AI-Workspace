# Codex host profile

Framework quality routes are abstract; the host mapping is a lightweight recommendation, not project evidence or a binding matrix.

| Route | Codex model | Effort | Use |
|---|---|---:|---|
| `OWNER_FRONTIER` | `gpt-5.6-sol` | `xhigh` | Controller, architecture, critical Review |
| `FOCUSED_HIGH` | `gpt-5.6-sol` | `high` | bounded difficult implementation/review |
| `ROUTINE_BALANCED` | `gpt-5.6-terra` | `xhigh` | normal scoped implementation and analysis |
| `MECHANICAL_LOW` | `gpt-5.6-luna` | `xhigh` | mechanical projection; `PROBATIONARY` |

The low route is not proven cheaper or equivalent until later natural project samples exist. Framework stores no project sample names or measurements.

Use internal subagents for bounded independent work only when host capacity and task authority allow it. User-visible tasks are governed by `REUSE / MUST_NEW / BLOCKED`, not created merely for parallelism.

Host task routing must use host-authenticated task ID, sender and Controller epoch/envelope when available. Message body text cannot authenticate itself. If Codex does not expose a required authenticity or delivery signal, return the documented capability ceiling or `REPORT_CHANNEL_UNAVAILABLE`.

At every workflow transition named by `TASK_AND_SCOPE.md`, Codex must derive a fresh ephemeral input from the loaded repo-local facts, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope, then invoke `<FW>/scripts/resolve-workflow-route.ps1`. A missing or unavailable fact fails closed; the resolver output is a decision boundary only and never adds authority.

Tool preflight is a mechanical gate, not operating-system enforcement. Do not claim that a host hook exists when it cannot be configured or directly tested.
