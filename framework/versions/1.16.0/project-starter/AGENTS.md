<!-- AI-WORKSPACE-FRAMEWORK:BEGIN -->
# AI Workspace Framework 管理的导航入口

对受本项目 `.ai-workspace` control plane 管理的非简单工作，仅在 pinned release 满足 sealed compatibility predicate 时使用 host-global `ai-workspace-router` Skill。Skill 缺失、未发现或不兼容时，直接执行 `.ai-workspace/BOOTSTRAP.md` 并保留真实 host ceiling。不需要 repo-local Skill copy。

在相关 user prompt、task/authority context change、compaction/resume/handoff uncertainty、独立 governed action 与最终输出前激活。bound context 未变化时复用，不按每次 tool call 重载。

Skill 只负责 navigation，不能授予 write、test、Review、OWNER_ACCEPT、Git、push、browser、device 或 external authority。项目自己的 instruction 可写在本 managed block 之外。
<!-- AI-WORKSPACE-FRAMEWORK:END -->
