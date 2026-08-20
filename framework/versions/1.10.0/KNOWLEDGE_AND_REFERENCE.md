# Knowledge and reference

Knowledge entries are optional, project-local and `REFERENCE_ONLY / NON_AUTHORITY`. They cannot replace source, product facts, Controller/task authority, a user decision or the pinned Framework contract.

A project enables `KNOWLEDGE_REFERENCE` explicitly in `project.json.frameworkCapabilities`. Missing, disabled, malformed or drifting configuration yields reference unavailable without changing the main task route.

Knowledge use has two explicit steps. `DISCOVER` validates the index and returns only compact metadata—ID, title, tags when present, lifecycle, reference locator and declared authority locators. It never returns summary or reference bodies. `RECOVER`/`PLAN` may then select zero to three IDs; an already declared task/upstream ID list is only a deterministic shortcut. `QUERY` validates reference and authority identities for exactly those selected entries and returns an explicit per-entry `AVAILABLE` or `UNAVAILABLE`. Unknown, duplicate or over-limit requests fail closed; an unrelated stale entry never blocks a fresh requested entry.

Schema1 indexes remain readable: their single `authorityLocator`/`authorityIdentity` pair is one declared dependency. Schema2 may declare tags and multiple exact authority dependencies. PowerShell 5.1 parses JSON normally; PowerShell 7 uses `ConvertFrom-Json -DateKind String` when available so ISO UTC timestamps remain strings on both runtimes.

After a task changes actual authority files, the read-only `check-knowledge-impact.ps1` compares those literal changed paths with declared dependencies. Exact overlap is `DIRECT_AFFECTED`; no overlap with identities still intact is `NONE_DIRECT`; missing or drifting dependency evidence is `UNKNOWN`. Directly affected or unknown entries are refreshed or marked `STALE` before the applicable final acceptance. The checker never writes.

Natural queries, quality/cost samples and project terminology remain in the project that produced them. Framework may define generic fixtures but must not aggregate real consumer evidence.

Initial context control is deliberately small: discovery returns metadata only and query accepts at most three explicit IDs. No tokenizer accounting, summary budget service, semantic search, ranking cache, background indexing/refresh, common project registry, usage ledger or authority elevation is added.
