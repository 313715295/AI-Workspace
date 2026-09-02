<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework managed navigation

For non-trivial Framework maintenance governed by this repository's `.ai-workspace` control plane, use the host-global `ai-workspace-router` Skill only when the pinned release satisfies its sealed compatibility predicate. If the Skill is missing, undiscovered or incompatible, follow `.ai-workspace/BOOTSTRAP.md` directly. No repo-local Skill copy is required.

Activate navigation at natural prompt, context-change, distinct-action and final-output boundaries. Reuse unchanged bound context and never invoke it per tool call.

The Skill is navigation only. Maintenance authority remains in `.ai-workspace`, and the Framework target remains a separate repository and authorization boundary. Project-owned instructions may be added outside this managed block.
<!-- AI-WORKSPACE-FRAMEWORK:END -->
