# {{DISPLAY_NAME}} — 项目资料入口

本文件只保存少量稳定项目事实和用户已经指定的权威资料入口，不复制产品、架构、质量或流程标准正文。AI 按当前任务读取必要来源；未确认的事实保持未记录，不用大量占位项要求用户填写。

## 基本身份

- Project ID：`{{PROJECT_ID}}`
- Project root：`.ai-workspace/project.json.repositoryRoot = ..`，普通项目不要求 Git。
- Control plane：`repo-local`
- Pinned Framework：`{{FRAMEWORK_VERSION}}`

## 用户指定的现有资料

用户或项目 Owner 可在这里记录已经确认用途的入口，例如产品说明、架构决策、测试指南或发布手册。资料可以位于项目内，也可以位于本机其他目录或独立仓库 checkout；路径和组织方式由使用者决定。

| 用途 | 来源入口 | 适用范围或备注 |
|---|---|---|

普通资料入口只用于定位事实，不自动成为规范规则，也不从其中的普通链接递归加载其他文档。需要作为永久流程规则的标准，由 AI 按用户选择写入 `.ai-workspace/process-policy.json` 的显式来源绑定；用户不必手写机器 JSON。

## 控制与动态状态

- Controller、Framework pin、routine exclusions 与 optional capabilities：读取 `.ai-workspace/project.json` 和 `.ai-workspace/controller.json`。
- 永久项目规则：读取 `.ai-workspace/process-policy.json`；项目纠正：读取 `.ai-workspace/corrections.json`。
- 已知 taskId 直接读 current task card；未知时由 `tasks/README.md` 定位。`STATUS.md` 只在需要项目阶段等全局事实时读取。
- 已采用的专业标准由 process-policy 定位；知识来源由 project.json 的 KNOWLEDGE_REFERENCE.sources 定位，采用、固定/跟随及私有内容维护均由项目管理。额外审核要求归相应标准或任务，不要求专门的资料文件名。

聊天、模板、导航摘要和历史报告只作 locator。写入、测试、Review、`RESULT_ACCEPT`、Git 与外部操作仍分别授权。
