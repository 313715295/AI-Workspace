# AI Workspace Claude Entry

本仓库是多项目 AI 协作控制面，不是项目源码仓库。

- 先读 `README.md`。
- 处理具体项目时，先确认项目Git顶层并优先读取完整有效的`.ai-workspace/BOOTSTRAP.md`；repo-local不存在时才可回退匹配的中央legacy `projects/<project-id>/BOOTSTRAP.md`，身份冲突必须停止。
- 已发布的 `framework/versions/<version>/` 不得原位修改；规则升级必须新建版本并显式更新项目指针。
- 项目源码与repo-local控制面改动在对应项目仓库完成；中央legacy搬迁是项目专属的一次性操作，不是Framework命令，项目仓提交并冷恢复通过前中央仍是权威。任务所有权、审核和 Git 收口遵守固定版本治理文件。
- `archive/` 只用于追溯，不是当前权威。

系统指令、当前用户指令和宿主环境约束优先。
