---
name: ai-workspace-router
description: 为含 .ai-workspace 的项目按需导航 Framework 规则；用于任务或上下文变化、受治理动作和正式交付边界。普通连续步骤不重复加载。
---

# AI Workspace Router

本 Skill 是 Framework 的导航入口（`NON_AUTHORITY`），只负责定位当前流程、触发调用和引导加载，不另定义流程规则。

## 绑定项目

使用明确的项目根；未指定时只检查当前 Git 根及其直接子目录中的 `.ai-workspace/project.json`，仅唯一有效候选可自动绑定。无法唯一确定时先确认项目，不递归猜测。

版本只取项目 pin。从该项目 `BOOTSTRAP.md` 和对应 `TOOLCHAIN.json` 取得本次调用所需事实与工具入口，不自行选择版本或替代恢复合同。

支持 Tool Contract `1`、Router 协议 `schemaVersion=1`、目录 `schemaVersion=2/version=3` 与 `MARKDOWN_EXACT_BLOCK`；`TOOLCHAIN.json` 须声明本 Skill `COMPATIBLE` 并映射 `LOAD_PLAN_RESOLVE`、`PROCESS_REQUIREMENTS_RESOLVE`、`WORKFLOW_ROUTE_RESOLVE`。声明缺失、冲突或协议未知时报告 `INCOMPATIBLE_OR_UNKNOWN`，退回已绑定项目的 Bootstrap。

## 自然边界：加载与复用

首次进入或任务、上下文、权威变化时，按 pin 刷新；连续工作复用已加载规则。普通追问、工具调用或重新授权不自动触发全文重载；上下文不确定时按 pin 重载。具体失效条件读取框架规则，不在此维护第二份清单。显式 `$ai-workspace-router` 用于重新检查当前绑定。

1. 调用 `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`，由解析器从完整规则索引选择本次适用规则，模型只读取命中的完整正文区块。存在任务时绑定当前任务；没有适用任务且 pin 明确支持时，解释/现状核对/方案讨论使用 `PROJECT_READ_ONLY`，不能伪造任务或执行 action。有效纠正、内联项目规则和来源绑定的项目标准同样参与选择；支持材料和映射回退按 pin 要求处理。完整检查索引与校验来源身份不等于把所有正文加载进模型。
2. 每个独立受治理动作前，前置命中的紧凑义务，用当前有效 receipt 调用 `ADMIT_ACTION`。
3. 正式交付前，以实际结果和必要交付证据调用 `FINALIZE_OUTPUT`。准备、结果与缺项处理要求来自命中规则，不能由本 Skill 代替。

一次性输入默认放入被项目 Git 忽略的 `.ai-workspace/runtime/<task-or-request>/<actor>/`。优先使用 pin 提供的紧凑 receipt/boundary 格式；输入与收据格式、保存、清理及不可用时的处理均遵循 pin 合同。

## 保持 gate 独立

导航不授予权限，也不合并或替代框架的独立动作门禁。恢复、试点、授权、保护边界、证据上限与异常处置等细则，以当前 pin 的完整命中规则为准；精简入口不等于省略这些要求。
