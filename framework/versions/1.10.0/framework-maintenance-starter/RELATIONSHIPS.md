# {{DISPLAY_NAME}} — stable relationships

| Concept | Upstream authority | Downstream consumers | Invariant |
|---|---|---|---|
| Current Controller | `.ai-workspace/controller.json` | task routing and authorization preflight | one ID/epoch/CURRENT in the Maintenance repository |
| Framework target | `.ai-workspace/project.json.frameworkTarget` plus resolver actual | Bootstrap, authorization, safe Git and release tasks | one safe sibling Git top; no target control plane |
| Framework pin | `.ai-workspace/project.json.frameworkVersion` | loader and target entry validation | stable explicit project-owned pin; only a sealed release is selectable |
| Consumer adoption | each consumer project's own controller and pin | product project | release notification never changes a consumer automatically |
| Project corrections | CONTROL `.ai-workspace/corrections.json` plus target release coverage | Maintenance recovery and pin adoption | evaluate against explicit pin; no target control state or second status object |
