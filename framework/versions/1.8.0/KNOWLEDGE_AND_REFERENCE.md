# Knowledge and reference

Knowledge entries are optional, project-local and `REFERENCE_ONLY / NON_AUTHORITY`. They cannot replace source, product facts, Controller/task authority, a user decision or the pinned Framework contract.

A project enables `KNOWLEDGE_REFERENCE` explicitly in `project.json.frameworkCapabilities`. Missing, disabled, malformed or drifting configuration yields reference unavailable without changing the main task route.

The checker validates strict schema, exact entry IDs, source locators, status and UTC `verifiedAt` strings. PowerShell 5.1 parses JSON normally; PowerShell 7 uses `ConvertFrom-Json -DateKind String` when available so ISO timestamps remain strings. Both runtimes must accept the same valid UTC strings and reject invalid values or type drift.

Natural queries, quality/cost samples and project terminology remain in the project that produced them. Framework may define generic fixtures but must not aggregate real consumer evidence.

No search service, ranking cache, background indexing, common project registry or authority elevation is added.
