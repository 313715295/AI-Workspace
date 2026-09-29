# {{DISPLAY_NAME}} — current status

> 初始化于 {{CREATED_DATE}}。本文件只提供 current routing；recovery 仍需校验 Git top、schema4 config、controller object、task card 与实际 repository state。

## Baseline

- Project ID：`{{PROJECT_ID}}`
- Control plane：`repo-local`，repository root `..`
- Pinned Framework：`{{FRAMEWORK_VERSION}}`
- Controller：读取 `.ai-workspace/controller.json`
- Routine excluded paths：读取 `.ai-workspace/project.json`
- Optional capabilities：`DISABLED`（`frameworkCapabilities={}`）
- Project corrections：`.ai-workspace/corrections.json / recovery 与 pin adoption 前后评估`
- Process budget：`.ai-workspace/process-policy.json.selectedRulePackBytes`
- Initialization result：`CONTROL_PLANE_READY`；未从用户资料确认的项目事实不由模板代填

## Current work

- Current phase：等待用户任务；按任务需要读取用户已指定的项目资料，不要求先补齐通用模板。
- Current task：none。
- Current writer/reviewer：`NONE / NONE`
- HEAD/index/source state：`UNVERIFIED`
- Git/push/external：分别授权前保持 closed。

## Next action

首次实际任务从本 `BOOTSTRAP.md` 执行 FULL_COLD recovery。AI 优先复用用户给出的产品、架构、质量或标准文档；只对当前任务确实缺失且会改变结果的事实集中询问一次。规范性标准需要时由 AI 写入 process-policy 的显式来源绑定；用户不必手写机器 JSON。
