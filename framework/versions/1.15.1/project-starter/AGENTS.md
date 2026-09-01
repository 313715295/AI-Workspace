<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework managed navigation

For non-trivial work governed by this project's `.ai-workspace` control plane, use the host-global `ai-workspace-router` Skill only when the pinned release satisfies its sealed compatibility predicate. If the Skill is missing, undiscovered or incompatible, follow `.ai-workspace/BOOTSTRAP.md` directly and retain the honest host ceiling. No repo-local Skill copy is required.

Activate navigation at a relevant user prompt, task or authority-context change, compaction/resume/handoff uncertainty, a distinct governed action and before final output. Reuse unchanged bound context; do not reload it per tool call.

The Skill is navigation only. It cannot grant write, test, Review, OWNER_ACCEPT, Git, push, browser, device or external authority. Project-owned instructions may be added outside this managed block.
<!-- AI-WORKSPACE-FRAMEWORK:END -->
