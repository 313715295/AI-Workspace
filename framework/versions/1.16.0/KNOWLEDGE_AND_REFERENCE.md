# Knowledge 与 reference

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:BEGIN -->
Knowledge entry 是可选、project-local 且 `REFERENCE_ONLY / NON_AUTHORITY` 的资料。它不能替代 source、product facts、Controller/task authority、user decision 或 pinned Framework contract。

项目必须在 `project.json.frameworkCapabilities` 中显式启用 `KNOWLEDGE_REFERENCE`。配置缺失、disabled、malformed 或 drifting 时，只得到 reference unavailable，不改变主任务路线。

Knowledge 使用分两步。`DISCOVER` 校验 index，只返回 compact metadata：ID、title、可选 tags、lifecycle、reference locator 与声明的 authority locators；不得返回 summary 或 reference body。`RECOVER`/`PLAN` 随后可选择 0–3 个 ID；任务或 upstream 已声明的 ID list 只是 deterministic shortcut。`QUERY` 对这些精确选择逐项校验 reference 与 authority identities，并返回明确的 `AVAILABLE` 或 `UNAVAILABLE`。unknown、duplicate 或 over-limit request 必须 fail closed；无关 stale entry 不阻塞新的 requested entry。

schema1 index 仍可读取，其中单个 `authorityLocator`/`authorityIdentity` pair 是一项 declared dependency。schema2 可以声明 tags 和多个 exact authority dependencies。official PowerShell 7 backend 在可用时使用 `ConvertFrom-Json -DateKind String`，使 ISO UTC timestamp 保持 string；旧 immutable release 保留各自 runtime behavior。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:BEGIN -->
任务修改实际 authority file 后，只读 `check-knowledge-impact.ps1` 把 literal changed paths 与 declared dependencies 比较。exact overlap 为 `DIRECT_AFFECTED`；没有 overlap 且 identities 仍完整为 `NONE_DIRECT`；dependency evidence 缺失或漂移为 `UNKNOWN`。directly affected 或 unknown entry 必须在适用 final acceptance 前刷新或标记 `STALE`。checker 不写文件。

natural query、quality/cost sample 与 project terminology 留在产生它们的项目。Framework 可定义 generic fixture，但不得汇总真实 consumer evidence。

初始 context control 保持很小：discovery 只返回 metadata，query 最多接受三个显式 ID。不增加 tokenizer accounting、summary budget service、semantic search、ranking cache、background indexing/refresh、common project registry、usage ledger 或 authority elevation。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:END -->
