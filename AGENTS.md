# AI Workspace Framework repository

This repository contains generic Framework source, root integration tools and immutable releases. It is not a consumer project and does not own real consumer state.

Before editing, read `README.md`. Framework maintenance authority comes from the dedicated Maintenance control repository's repo-local `.ai-workspace/BOOTSTRAP.md`. If that authority is missing, partial or conflicting, stop rather than creating a replacement control plane here.

Never modify an existing released directory under `framework/versions/`. Create a new version directly in its final version directory, keep it non-consumable until frozen and independently reviewed, then seal it. There is no Framework-global version selector. Release, root integration, Git publication and each project's explicit pin adoption are separate actions.

Do not add real consumer identities, paths, tasks, pins or adoption state to Framework. Preserve exact ownership, protected paths, one-writer and Review/Git/external boundaries.

System, developer and current user instructions take precedence.
