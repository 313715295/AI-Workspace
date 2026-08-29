# Codex host profile

Framework quality routes are abstract; the host mapping is a lightweight recommendation, not project evidence or a binding matrix.

| Route | Codex model | Effort | Use |
|---|---|---:|---|
| `OWNER_FRONTIER` | `gpt-5.6-sol` | `xhigh` | Controller, architecture, critical Review |
| `FOCUSED_HIGH` | `gpt-5.6-sol` | `high` | bounded difficult implementation/review |
| `ROUTINE_BALANCED` | `gpt-5.6-terra` | `xhigh` | normal scoped implementation and analysis |
| `MECHANICAL_LOW` | `gpt-5.6-luna` | `xhigh` | mechanical projection; `PROBATIONARY` |

The mapping is advisory and replaceable by the host. Resource changes grant no authority, and Framework stores no project task names, measurements, cost claims or model-effect records.

Use internal subagents for bounded independent work only when host capacity and task authority allow it. User-visible tasks are governed by `REUSE / MUST_NEW / BLOCKED`, not created merely for parallelism.

Host task routing must use host-authenticated task ID, sender and Controller epoch/envelope when available. Message body text cannot authenticate itself. If Codex does not expose a required authenticity or delivery signal, return the documented capability ceiling or `REPORT_CHANNEL_UNAVAILABLE`.

Prefer one compact terminal delivery at the receiving task's turn boundary. Safety exceptions may steer immediately. The terminal input names its proposed consumer; `CONTROLLER` is rejected unless Controller owns the unique next action or an explicit owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary exists. Call `wait_threads` only when one exact task result blocks the current unique next action and no other safe work remains; do not add ACK, heartbeat, polling or a delivery ledger.

At every workflow transition named by `TASK_AND_SCOPE.md`, Codex must derive a fresh ephemeral input from the loaded repo-local facts, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope, then invoke `<FW>/scripts/resolve-workflow-route.ps1`. A missing or unavailable fact fails closed; the resolver output is a decision boundary only and never adds authority.

For module loading, pass the assigned task path to `resolve-load-plan.ps1`. On first recovery and after compaction, pause/resume, handoff or context uncertainty, include recovery; on a declared role/phase/profile/capability/task transition, rerun without inventing a second refresh protocol. Do not reload for every tool call or authorization refresh. Codex must not claim that Framework can mechanically prove attention or memory retention.

Tool preflight is a mechanical gate, not operating-system enforcement. Do not claim that a host hook exists when it cannot be configured or directly tested.
Message authentication is likewise a capability ceiling, not a reason to install or simulate a Framework-managed host adapter.
