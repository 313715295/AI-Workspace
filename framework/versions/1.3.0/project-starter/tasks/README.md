# {{DISPLAY_NAME}} 任务卡

## 目录语义

- `active/`：仍有真实下一动作、明确触发器或待决事项的任务。
- `archive/`：已关闭任务记录，只用于追溯，不作为current授权。
- 新任务从固定Framework `{{FRAMEWORK_VERSION}}`的`TASK_TEMPLATE.md`创建。

## 当前热索引

初始化时没有active任务。出现真实工作后，只登记恢复所需的任务ID、唯一owner、状态、保护边界与下一动作；详细范围、审核、Git和证据门只以任务卡原文为准。

未触发的排队对象不展开全文，已关闭结果移入`archive/`。本页不复制完整工作流，也不得与聊天摘要拼接成新授权。
