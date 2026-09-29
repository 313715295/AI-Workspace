# 可选方法参考

本库是 Framework 随包提供的 METHOD 参考，当前内容版本为 1。它不包含项目权威，不自动成为 MUST，不登记消费者，也不修改项目采用事实。项目可选择其中一篇；无需为了接入 Framework 全部加载。

项目在 `frameworkCapabilities.KNOWLEDGE_REFERENCE.sources` 自行声明来源。引用本库时，`root.kind=LOCAL_DIRECTORY`，`root.locator` 指向实际固定包的 `framework/versions/2.0.0` 绝对目录，`indexLocator=knowledge/index.json`。项目自选 source ID；查询使用该 ID 加条目 ID。PINNED 绑定真实索引 `length|SHA256`，FOLLOW 在查询时报告实际身份；示例不替用户决定更新政策。

先发现来源元数据，再选择库和条目。默认查询只返回定位信息，明确需要正文时才用 FULLTEXT。URL 仅供核验出处，查询器不会联网。三篇首批内容分别处理输入取消、表现与权威分离、行为及性能验证。

维护责任属于 Framework 内容维护者：修改方法时核对原始来源、适用范围与反例，更新 contentVersion、verifiedAt 和正文 identity；调整来源/适用条件也更新索引。撤回不可靠内容时标记 STALE 或 HISTORICAL，保留理由；固定分发字节按发行合同处理。读者发现不适用时在自己的任务记录，不在 Framework 建采用登记。

正文为独立整理的工程方法，引用处明确区分平台事实与本文建议。仅链接和简短独立概述原始材料，不复制第三方 Skill、代码或长段落，也不假定链接授予转载权。来源版权归原权利人。实际项目仍需验证自身输入系统、网络模型、运行设备和验收条件。
