# {{DISPLAY_NAME}} — current status

> 初始化于 {{CREATED_DATE}}。本文件提供项目与当前任务导航；实际恢复按已采用入口核对当前配置、Controller、任务及动作所需事实。

## Baseline

- Project ID：`{{PROJECT_ID}}`
- Control plane：`{{CONTROL_PLANE_LAYOUT}}`；实际根与布局读取 [项目配置](project.json)
- Pinned Framework：`{{FRAMEWORK_VERSION}}`
- Controller：读取 [当前责任](controller.json)
- Routine excluded paths / optional capabilities：读取 [项目配置](project.json)，不在此复制可变状态
- Project corrections：[项目纠正](corrections.json)
- Adopted standards / selectors：[项目规则](process-policy.json)
- Initialization result：`CONTROL_PLANE_READY`；仅表示基础控制面完成，原有要求承接、宿主加载与业务验证按接入任务报告

## Current work

- Current task：none。
- 当前角色、阶段、writer/reviewer 及下一动作读取实际任务卡；其他工作见 [任务索引](tasks/README.md)。
- Git/push/external 按实际动作分别授权；普通项目工作不以 Git 为前提。

## Next action

按已采用的共享入口从 [BOOTSTRAP](BOOTSTRAP.md) 恢复实际任务，健康续作复用仍有效内容。优先复用用户已指定的要求、设计、质量标准和研究资料；资料读取、规范采用与任务命中分别核对。可选标准和知识引用仅在项目明确选择时采用，未选择知识引用不妨碍读取普通研究资料。基础注册不替代接入任务中尚未完成的要求承接。
