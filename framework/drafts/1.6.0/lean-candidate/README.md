# Framework 1.6.0

状态：`DRAFT / NOT_CONSUMABLE / NOT_PIN_ELIGIBLE`。

本目录是从不可变的1.5.2稳定库存逐字建立后实施的clean-baseline候选。它尚未经过独立实现Review、集成、发行或项目采用；不得由`CURRENT`、项目pin、register默认值或任何项目恢复链消费。

## 本候选已实现的分片

- A：同一本地仓库面向多个remote的单次`RemoteBatch`。每个remote最多尝试一次，逐项记录真实结果并现场派生整体状态；没有自动retry、PreviousLedger或自动compensation。
- A/Git安全：`.ai-workspace/project.json` schema 3中的`protectedPaths`是唯一机器策略；Framework Git入口只消费固定配置与bounded allowlist，失败返回`UNVERIFIED`，不扩大扫描。
- B：任务卡只保存`DEFAULT`或minimum/tools/continuity例外；`resolve-resource-binding.ps1`生成短期binding，authorization checker复证其locator、identity和digest。
- C/G：默认领域直达、no-poll、terminal-only、exception-only escalation；`.ai-workspace/controller.json`是current controller/epoch唯一真相，旧epoch的决定、授权和ACK不得进入current控制链。
- register/upgrade草案：新项目生成schema 3 project与epoch 1 controller；旧项目迁移以冻结输入和可恢复本地事务写入新控制对象。

## 明确不在本分片

D/E/F/H、知识库、common知识、项目瘦身、正式version、CURRENT、项目pin、Git、push、remote执行与external均未打开。旧`candidate/**`和`root-scripts/**`只作审计历史，不是本目录producer或consumer。

## 证据上限

direct/static/隔离fixture只能证明候选合同和失败语义，不等于独立Review、真实Git/remote、发行或项目采用。只有后续fresh Review批准、完整集成通过并另行发行，才能生成稳定`framework/versions/1.6.0/`。
