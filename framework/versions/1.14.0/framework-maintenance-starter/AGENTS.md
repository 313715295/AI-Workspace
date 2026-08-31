<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework managed navigation

For non-trivial Framework maintenance governed by this repository's `.ai-workspace` control plane, use the repo-local `ai-workspace-router` Skill at natural prompt, context-change, action and final-output boundaries. Reuse unchanged bound context and never invoke it per tool call.

The Skill is navigation only. Maintenance authority remains in `.ai-workspace`, and the Framework target remains a separate repository and authorization boundary. Project-owned instructions may be added outside this managed block.
<!-- AI-WORKSPACE-FRAMEWORK:END -->
