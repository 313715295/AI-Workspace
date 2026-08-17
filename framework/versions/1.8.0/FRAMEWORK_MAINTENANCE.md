# Framework maintenance sibling topology

The final topology has one dynamic Maintenance control repository and one Framework target repository under a dedicated parent directory.

The Maintenance repo owns `.ai-workspace`, Controller, tasks, authorization and Review routing. The Framework target owns generic source, immutable versions and root tools, and must not become a second control-plane authority.

The Maintenance `project.json` binds a repository ID and safe sibling directory, never an arbitrary absolute target. Resolver, authorization and safe Git prove both Git tops independently, reject reparse paths, process Git overrides, extra target control planes, wrong repositories and non-steady Controller state.

Physical relocation, predecessor closure and cleanup are project-specific operations outside Framework runtime. They require separate authority and must not be inferred from a stable release.

Framework Maintenance does not create a consumer registry, search multiple targets, perform cross-repository atomic transactions, auto-retry, compensate or upgrade projects.
