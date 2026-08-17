# Framework 1.7.0 migration matrix

| Source | Target | Result |
|---|---|---|
| healthy repo-local schema3 project | repo-local 1.7.0 | existing layout preserved; project pin adoption remains a separate project task |
| new Framework Maintenance project already in final layout | schema4 `framework-maintenance-sibling` | render CURRENT starter, verify two sibling Git tops and target without `.ai-workspace`, then FULL_COLD |
| current AI-Workspace self-hosted repo-local control plane | separate Maintenance control repo + sibling Framework target | no Framework runtime migration; require a separately authorized project-specific offline migration task, then fresh FULL_COLD |
| Maintenance controller not CURRENT | any maintenance recovery or authorization | fail closed; no transitional controller state exists |
| CURRENT Maintenance + target canonical `.ai-workspace` absent | normal maintenance recovery | Maintenance is the unique authority; run FULL_COLD |
| CURRENT Maintenance + target canonical `.ai-workspace` present, partial, foreign or reparse | any recovery | fail closed; do not inspect it as alternate authority |
| parent contains `.git`/`.ai-workspace`, any walked component is reparse/dangling, either root is non-Git, pin entry is incomplete, config/controller/repository ID drifts | any maintenance action | fail closed with no broader search or fallback |
| central legacy, partial or unknown control plane | 1.7.0 | fail closed; no success claim |

The maintenance route does not reuse a control package as a target package and does not promise or implement physical relocation or cross-repository atomicity. Existing repo-local register/upgrade behavior remains independently covered and no consumer is upgraded automatically.
