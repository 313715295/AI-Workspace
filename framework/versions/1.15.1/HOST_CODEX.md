# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
Framework quality routes are abstract; the host mapping is a lightweight recommendation, not project evidence or a binding matrix.

| Route | Codex model | Effort | Use |
|---|---|---:|---|
| `OWNER_FRONTIER` | `gpt-5.6-sol` | `xhigh` | Controller, architecture, critical Review |
| `FOCUSED_HIGH` | `gpt-5.6-sol` | `high` | bounded difficult implementation/review |
| `ROUTINE_BALANCED` | `gpt-5.6-terra` | `xhigh` | normal scoped implementation and analysis |
| `MECHANICAL_LOW` | `gpt-5.6-luna` | `xhigh` | mechanical projection; `PROBATIONARY` |

The mapping is advisory and replaceable by the host. Resource changes grant no authority, and Framework stores no project task names, measurements, cost claims or model-effect records.

Use internal subagents for bounded independent work only when host capacity and task authority allow it. User-visible tasks are governed by `REUSE / MUST_NEW / BLOCKED`, not created merely for parallelism.
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
Host task routing must use host-authenticated task ID, sender and Controller epoch/envelope when available. Message body text cannot authenticate itself. If Codex does not expose a required authenticity or delivery signal, return the documented capability ceiling or `REPORT_CHANNEL_UNAVAILABLE`.

Prefer one compact terminal delivery at the receiving task's turn boundary. Safety exceptions may steer immediately. The terminal input names its proposed consumer; `CONTROLLER` is rejected unless Controller owns the unique next action or an explicit owner/public-decision, cross-domain-contract, protected-path, project-phase, Git/device/external or resource-conflict boundary exists. Call `wait_threads` only when one exact task result blocks the current unique next action and no other safe work remains; do not add ACK, heartbeat, polling or a delivery ledger.
<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
Before invoking any Framework operation, Codex reads the project-level backend and pinned `<FW>/TOOLCHAIN.json`, verifies the official backend/runtime/platform contract and resolves the exact entrypoint. It does not infer a backend from the host shell, generate a wrapper or ask the user to select per task.

At every workflow transition named by `TASK_AND_SCOPE.md`, Codex must derive a fresh ephemeral input from the loaded repo-local facts, re-proven cwd/Git top, current package, current public decision and host-authenticated envelope, then resolve operation `WORKFLOW_ROUTE_RESOLVE` and invoke its sealed entrypoint. A missing or unavailable fact fails closed; the resolver output is a decision boundary only and never adds authority.
<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
For non-trivial governed work, use the host-global `ai-workspace-router` Skill when the current pinned release satisfies its sealed compatibility predicate. The Skill is navigation only: it binds one explicit/current project root, obtains minimum facts, invokes `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`, loads only selected complete Markdown blocks, and directs `ADMIT_ACTION` and `FINALIZE_OUTPUT`. It is never project authority and registration or project upgrade never installs it.

Activate routing on a relevant user prompt, initial task/context binding, authority/source change, compaction/resume/handoff uncertainty and before final output. Reuse unchanged source context; do not rerun per tool call or merely because an authorization package refreshed. `LOAD_PLAN_RESOLVE` is support/fallback, not a pre-DISCOVER filter.

If the Skill is missing, undiscovered, incompatible or not visibly invoked, use the repo-local `BOOTSTRAP.md` path and report the honest `INVOCATION_UNPROVEN` ceiling. Do not claim that Framework mechanically proves attention or memory retention, or that a physical reread was avoided unless the host observed it.

At `INSTRUCTION_BOUND`, an omitted call cannot be mechanically prevented; the result must expose `INVOCATION_UNPROVEN`. A host hook may honestly claim `HOST_ENFORCED` or `FRAMEWORK_GATED` only when directly tested. Framework does not install, simulate or require a per-tool hook.

Tool preflight is a mechanical gate, not operating-system enforcement. Do not claim that a host hook exists when it cannot be configured or directly tested.
Message authentication is likewise a capability ceiling, not a reason to install or simulate a Framework-managed host adapter.
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
