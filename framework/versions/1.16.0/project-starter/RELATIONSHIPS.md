# {{DISPLAY_NAME}} — 可选稳定关系图

只记录已批准、跨任务稳定且无法靠一次直接搜索可靠恢复的语义关系。简单引用、current过程和未批准方案不复制。

| 概念 | 上游权威 | 下游消费者 | 影响原因 | 批准任务/决定 | 最后核实 |
|---|---|---|---|---|---|

初始化默认不创建本文件。只有项目确有跨任务稳定、无法从已有资料直接恢复的关系时，才由 AI 基于用户指定的权威资料按批准任务建立并增量维护；找不到权威或尚未批准时留在任务卡。Framework 升级不要求创建或批量重写本文件。

`.ai-workspace/corrections.json`与`framework/versions/1.16.0/CORRECTION_COVERAGE.json`共同决定当前pin下仍有效的项目correction；只有精确的legacy/native/catalog/source-record映射可抑制一条correction，未知、歧义或源漂移均保留。coverage必须通过1.16.0 sealed payload校验，结果不持久化为第二对象。
