# AI Workspace Framework entry

本仓库只保存通用Framework、根集成工具和不可变版本，不保存真实项目状态。

- 先读 `README.md`。
- Framework维护权威来自专用Maintenance控制仓的repo-local `.ai-workspace/BOOTSTRAP.md`。
- 已发布的 `framework/versions/<version>/` 不得原位修改；新版本直接在最终版本目录开发，冻结、独立Review和稳定封印前不可消费。
- Framework没有全局默认版本。新项目显式选择版本并复制该版本的 `project-starter`；已有项目只认自己的repo-local pin。
- Framework发布不会发现或升级consumer，也不记录真实项目身份、路径、Controller、任务或采用状态。
- source、test、Review、Git、push和external分别授权。

系统指令、当前用户指令和宿主环境约束优先。
