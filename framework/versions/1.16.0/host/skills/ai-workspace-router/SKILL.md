# ai-workspace-router 1.16.0 兼容合同

状态：`REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE / NON_AUTHORITY`

当前可安装且唯一维护的 Skill 位于仓库根目录 `skills/ai-workspace-router/SKILL.md`。本文件只记录 Framework `1.16.0` 的兼容历史，不是第二份 Skill，也不得复制到项目或 host Skill 目录。

`1.16.0` 要求根 Skill 支持 `LOAD_PLAN_RESOLVE`、`PROCESS_REQUIREMENTS_RESOLVE`、`WORKFLOW_ROUTE_RESOLVE`，并遵守自然边界激活、完整规则块单次加载、compact receipt 复用、上下文不确定时重新加载，以及项目 `.ai-workspace/runtime/<task>/<actor>/` 优先的临时文件合同。
