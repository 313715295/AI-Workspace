# Knowledge 与 reference

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:BEGIN -->
Knowledge是项目显式选用的REFERENCE_ONLY/NON_AUTHORITY资料，不替代源码、产品事实、任务/Controller、人类决定或Framework。METHOD是可复用原理/方法/经验，PROJECT_DERIVED是依赖本项目真实事实的信息；供给方和目录不改变性质，同一项目来源可包含两类。读取方法不使其成为MUST。

按项目sourceBindings及真实保护范围选择来源和条目。启用能力不要求全库读取；未选择来源仅校验声明结构，不因闲置库离线阻塞普通治理。索引、来源许可、可达性、实际正文读取和规范采用分别核对，不悄悄切同名来源，不跟随引文URL自动抓取或授权。

默认返回定位，明确需要正文才请求FULLTEXT；按TOOL_CONTRACT的index3/QUERY字段一次固定所选来源快照，逐项消费CURRENT/STALE/UNAVAILABLE及来源身份。PROJECT_DERIVED只在所属项目核真实依赖；METHOD的原创出处可为空，不编造引文，实际引用仍保留真实出处和维护责任。FOLLOW不后台同步、不替旧方案换来源或隐式更新规范。

读取/哈希前遵守根与子路径的保护、reparse和逃逸限制。机器轨迹或hash不证明模型持有全文或自然使用效果；CURRENT只表示内容维护状态。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_QUERY:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:BEGIN -->
只有实际QUERY影响判断时，原任务保留必要引用及依赖复核；只启用或无影响不增加记录。项目采用/使用事实留项目，Framework不建消费者登记。

真实authority内容改变后，沿KNOWLEDGE_IMPACT_CHECK用明确changed paths核PROJECT_DERIVED依赖。直接重叠、可证无直接影响和依赖不足的UNKNOWN分别报告，来源失败单列；受影响或未知条目在适用成果接受前刷新或标STALE，工具只读。METHOD不伪造项目依赖，其内容更新按维护来源和项目固定/跟随决定处理。

Framework内容维护者负责随包方法/标准/preset质量，项目负责私有内容，共享库有明确维护者而无需常驻会话。原事实、失败/试验和专家意见留原件；可复用方法保留完整唯一解释及维护入口，CURRENT不证明应用效果，日期旧不自动失效。详细内容整理/版本更新/反馈方法按需要读knowledge/README和问题驱动方法，基本任务改进责任仍取TASK。私有事实不入通用包，跨项目反馈沿已授权接点，不新增后台索引/同步、排名服务或回执台账。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_IMPACT_MAINTENANCE:END -->
