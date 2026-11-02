# 可选方法参考

本库是 Framework 随包提供的 METHOD 参考，各条目的内容版本取索引。它不包含项目权威，不自动成为 MUST，不登记消费者，也不修改项目采用事实。项目可选择其中一篇；无需为了接入 Framework 全部加载。

当前project7在 `sourceBindings` 维护来源位置与读取许可，`frameworkCapabilities.KNOWLEDGE_REFERENCE.sources` 通过 bindingId 选择库。引用本库的本地副本时，LOCAL_DIRECTORY 的 root 指向实际固定包的 `framework/versions/2.0.0` 绝对目录，indexLocator 为 `knowledge/index.json`。项目自选 source ID；明确该来源后发现条目，无 facets 的 QUERY 用 `sourceId:entryId`，有四维 FacetQueryJson 时在显式 SourceId 内筛选，可进一步用 EntryId 收窄。PINNED 绑定精确索引 identity/revision，FOLLOW 每次查询固定一个实际快照；示例不替项目决定更新或规范采用。

先发现来源元数据，再选择库和条目。默认查询只返回定位信息，明确需要正文时才用 FULLTEXT。Git/HTTPS 绑定只按当前 provider 合同读取获准内容；条目中的引文 URL 仅供核验出处，不自动联网抓取或注册为库。位置、许可、可达、实读、应用效果与规范采用分别核对；地址存在不证明私有全文、附件或声画验证可用。若项目明确将正文作为规范采用，沿当前policy3绑定完整采用单元及有序依赖，再通过项目Bootstrap和当前过程选择加载；QUERY/FULLTEXT本身不产生规范效力。

| 遇到的问题 | 条目与正文 |
|---|---|
| 同一 PNG/文件形式承担不同用途，混合文档或交付集合难以选要求 | ARTIFACT_CLASSIFICATION：[产物分类](cross-domain/ARTIFACT_CLASSIFICATION.md) |
| 真实失败或专业知识不足，不清楚学什么、读什么以及如何验证和留给下次 | PROBLEM_DRIVEN_IMPROVEMENT：[问题驱动改进](cross-domain/PROBLEM_DRIVEN_IMPROVEMENT.md) |
| 软件行为承诺改变，需要保留完整条件、例外、并发基线和可观察场景 | BEHAVIOR_SPEC_CHANGE：[软件行为规格与变更](software/BEHAVIOR_SPEC_CHANGE.md) |
| 输入取消、失焦、目标销毁或晚到回调 | UI_INPUT_CANCELLATION：[输入取消](game/UI_INPUT_CANCELLATION.md) |
| 表现预测、确认与权威状态相互干扰 | PRESENTATION_AUTHORITY：[表现与权威](game/PRESENTATION_AUTHORITY.md) |
| 行为结果与性能测量被混为一谈 | BEHAVIOR_AND_PERFORMANCE：[行为与性能](game/BEHAVIOR_AND_PERFORMANCE.md) |

跨行业两篇是通用原创整理，不编造外部引文；索引 originalSources 为空只表示没有列出外部引文。匿名化例子是教学反例，CURRENT 仅表示维护状态，内容可读不证明自然使用、专业效果或降本。基本任务责任仍在 TASK_AND_SCOPE，不以可选方法替代必须规则。已知合法专业文档也可直接阅读，不强制先注册库。

维护责任属于 Framework 内容维护者：修改方法时核对原始来源、适用范围与反例，更新 contentVersion、verifiedAt 和正文 identity；调整来源/适用条件也更新索引与当前入口。verifiedAt 记录该条目的核验时间，不表示应用效果通过。撤回不可靠内容时标记 STALE 或 HISTORICAL，保留理由和旧冻结证据；固定分发字节按发行合同处理，时间较旧不自动失效。读者在原任务保留具体反例，沿已有获准接点反馈维护者，供给方提供版本差异，由项目决定更新；不建采用登记或逐项回执。完整保存/更新/反馈方法只在上述问题驱动改进正文维护。

正文为独立整理的工程方法，引用处明确区分平台事实与本文建议。仅链接和简短独立概述原始材料，不复制第三方 Skill、代码或长段落，也不假定链接授予转载权。来源版权归原权利人。实际项目仍需验证自身输入系统、网络模型、运行设备和验收条件。

需要帮助寻找方案或审核遗漏时，可直接参考上级PERSPECTIVE_LENSES.md的五个可选问题；它不属于原生规则、不产生视角回执，也不要求启用知识查询或增加索引条目。
