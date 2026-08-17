# AI Workspace Framework Repository

This repository contains the AI-Workspace Framework source and immutable releases. It is not a consumer product repository and, in the final sibling topology, it does not own the dynamic maintenance control plane.

Before editing, read `README.md`. During the approved separation only, a complete local `.ai-workspace/` remains authoritative while its current migration task explicitly says the handoff is incomplete. Otherwise, Framework maintenance authority must come from the sibling `AI-Workspace-Maintenance/.ai-workspace/BOOTSTRAP.md`; if that entry is missing, partial, or conflicting, stop instead of creating a replacement control plane here.

Never modify an existing released directory under `framework/versions/`; create and independently review a new version. Framework release, root `CURRENT`, Git publication, and each consumer project's pin are separate actions. Preserve task ownership and do not turn chat history, archived material, or the Framework repository itself into maintenance authority.

System, developer, and current user instructions take precedence.
