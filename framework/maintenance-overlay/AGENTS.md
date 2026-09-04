<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework Maintenance 导航

对受本仓库 `.ai-workspace` 管理的非简单 Framework maintenance，仅在 pinned release 满足 sealed compatibility predicate 时使用 root canonical `ai-workspace-router` Skill。缺失、未发现或不兼容时直接执行 `.ai-workspace/BOOTSTRAP.md`。不需要 repo-local Skill copy。

在自然 prompt、context change、独立 action 与最终输出边界激活；bound context 未变化时复用，不按每次 tool call 调用。

Skill 只负责 navigation。Maintenance authority 保持在 `.ai-workspace`；Framework target 是独立 repository 与 authorization boundary。项目 instruction 可写在 managed block 之外。
<!-- AI-WORKSPACE-FRAMEWORK:END -->
