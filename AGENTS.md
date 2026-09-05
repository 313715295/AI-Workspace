# AI Workspace Framework 仓库入口

本仓库保存通用 Framework 源、根级集成工具和已封存版本。它不是消费者项目，也不持有任何消费者的真实动态状态。

编辑前先读 `README.md`。Framework 维护 authority 来自专用 Maintenance 控制仓自己的 `.ai-workspace/BOOTSTRAP.md`。如果该 authority 缺失、不完整或互相冲突，必须停止，不能在本仓库另建替代控制面。

Framework 发行工作还必须读取 `framework/FRAMEWORK_RELEASE.md`。该根级文件是与版本无关的当前发布流程；Maintenance 控制仓提供任务、授权、Review 和证据，但不复制第二份发布流程。

不得原地修改已经发布的 `framework/versions/<version>/`。新版本直接在最终版本目录中开发，在候选冻结、独立 Review 和正式封存前保持不可采用。Framework 没有全局版本选择器；版本发行、根工具集成、Git 发布和每个项目的显式采用是不同动作。

不得把真实消费者身份、路径、任务、pin 或采用状态写入 Framework。保持准确的责任归属、受保护路径、单一 writer，以及 Review、Git 和外部操作边界。

系统指令、开发者指令和当前用户指令优先。
