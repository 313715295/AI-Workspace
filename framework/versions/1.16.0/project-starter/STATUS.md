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
- Initialization result：`NEEDS_INPUT`

## Current work

- Current phase：建立 project facts；不得自动开始 product implementation。
- Current task：none。
- Current writer/reviewer：`NONE / NONE`
- HEAD/index/source state：`UNVERIFIED`
- Git/push/external：分别授权前保持 closed。

## Next action

initializing owner 记录 project facts、owners、routine excluded paths 与 current task route，然后对 pinned Framework 执行一次 FULL_COLD recovery。缺失 product/ownership/authority decision 只向用户集中返回一次；bounded task 已批准后，routine file/test/review step 不要求逐步确认。
