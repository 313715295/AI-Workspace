# AI Workspace Entry

This repository is the shared collaboration control plane, not a product source repository.

Before editing, read `README.md`. For project work, first resolve the supplied Git top level and prefer its complete `.ai-workspace/BOOTSTRAP.md`; only when repo-local control is absent may you fall back to the matching legacy `projects/<project-id>/BOOTSTRAP.md`. Identity conflicts fail closed. For framework maintenance, never modify an existing released directory under `framework/versions/`; create and review a new version, then update project pins explicitly.

Project source and repo-local control-plane changes belong in the project's own repository. Moving a legacy central control plane is a separately authorized, project-specific operation rather than a Framework command; the central directory remains the authority until that operation is committed and cold-recovered. Preserve task ownership and do not turn chat history or archived material into authority.

System, developer, and current user instructions take precedence.
