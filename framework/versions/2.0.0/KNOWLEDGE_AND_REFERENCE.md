# Knowledge 与 reference

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:BEGIN -->
Knowledge 是项目显式选用的 `REFERENCE_ONLY / NON_AUTHORITY` 资料，不替代源码、产品事实、任务/Controller、用户决定或当前Framework。优先保留真实职责、公共保证、重要关系和难以重建的约束；专业方法不能自行变为MUST。

知识性质与供给来源分开：专业拓展知识（METHOD）承载可复用的专业原理、方法和经验，可由Framework提供、项目自行整理或引用其它库；框架随包方法只是其中一种来源。项目自身知识（PROJECT_DERIVED）承载当前项目的具体信息，按真实项目依赖维护。存放在项目内的专业方法仍是METHOD；同一项目来源可包含两类条目，不因供给方或目录改变条目性质。

project schema5 的 `frameworkCapabilities.KNOWLEDGE_REFERENCE={enabled,sources}` 由项目维护。每来源以 id、root、indexLocator、selectionHints、updatePolicy 定位；PINNED 另绑定 indexIdentity，FOLLOW 仅在当前明确读取时取得新索引并返回身份，不后台同步或追认旧方案。配置结构始终校验，包括disabled内容；未被本次选中的来源不做可达性/内容检查，不让闲置外部盘阻塞普通治理。

PROJECT root 为整个当前项目，覆盖项目派生知识真实 src/docs 依赖；LOCAL_DIRECTORY 为显式绝对目录，仅接纳可共享METHOD，不能借此读取另一个项目的派生权威。文件读取/哈希前拒绝来源根或子路径的 reparse、路径逃逸及当前禁读范围；外部URL只是出处，查询器不联网跟随。

索引只读取 schema3：顶层 libraryId 标识库，条目分 PROJECT_DERIVED（projectId及真实authorityDependencies）与 METHOD（originalSources、applicability、contentVersion、maintenance）。同库可被不同项目用各自sourceId选用；查询使用 `sourceId:entryId`，不得悄悄改用同名其他来源。旧schema1/2仅在根采用事务中一次性转换，不保留旧日常读取模式。

METHOD.originalSources可以为空，表示没有列出的外部引文；项目原创方法不必编造网页出处。实际列出的引文仍须有真实出处信息，正文身份、适用范围、内容版本和维护责任始终校验。库的供给来源由sources绑定，条目中的引文URL不充当库的读取入口，也不产生网络读取或规则权限。

DISCOVER 未指定来源时只返回配置的来源元信息；明确 SourceId 后读取这些索引的定位元信息，不返回summary或正文。QUERY选择明确条目，可批量；ContentMode默认LOCATOR_ONLY，正式需要全文时显式FULLTEXT。逐项返回来源/库、实际索引身份及CURRENT、STALE或UNAVAILABLE；正文及实际依赖身份校验后才返回所请求的完整正文。一个坏源或条目不能静默代替另一个，也不能隐去同批健康结果；当前源不可用时说明原因，主任务按真实缺失影响决定是否能继续。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:BEGIN -->
仅当实际QUERY影响判断时，在原任务保留必要引用和依赖复核；只启用能力或没有实际影响不新增记录。项目采用和使用事实留项目，Framework不建消费者或使用登记。

修改真实authority文件后，沿既有KNOWLEDGE_IMPACT_CHECK比较明确changed paths与PROJECT_DERIVED依赖；默认只查PROJECT来源，也可明确来源。重叠为DIRECT_AFFECTED；无重叠且当前依赖证据有效为NONE_DIRECT；所需索引、正文或依赖不可用/漂移时为UNKNOWN，来源失败单列。受影响或未知的项目派生条目须在适用成果接受前刷新或标STALE，工具只读。METHOD不伪造项目依赖，其内容升级按维护来源及项目PINNED/FOLLOW决定处理。

Framework维护随包方法、可选规范和preset的内容/版本质量；用户项目维护私有内容，本地共享库有明确维护责任而不强制常驻会话。自然查询、质量及成本观察归实际项目。无统一条目数量配额、tokenizer服务、语义检索、排名缓存、后台索引/同步或权威提升。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:END -->
