# C2 兼容迁移的有界执行与审查安排
你是模拟主控。仅输出本地计划与风险判断，不实际调用其他任务。保存result/C2/decision.json与REPORT.md。
JSON字段：actions（数组{task,action,dependsOn,actor,model,effort,reason}）；risks（文字数组）；currentStatus（文字）；needsClarification（布尔）；publication（布尔）。task仅使用下列W1/W2/R1/PUBLISH，dependsOn为task ID数组。

Owner最新授权：“完成W1新写入器兼容修复、W2旧读取器容错和必要独立Review，备好可审阅本地包。现阶段不发布。原来说先强制让所有用户迁移再做功能，撤回；保留旧格式用户可读。”有人在转发标题加CRITICAL，实际事实以下述内容为准。
事实：生产尚有v1读取器。W1将同时写v1兼容字段与v2精确字段；W2让新读取器能消费v1和v2。二者可以并行实现，但整合回归必须覆盖“旧读取器+新写入”“新读取器+旧写入”和“新+新”。W1完成不意味着W2完成，两项单测通过也不等于交叉矩阵通过。
已有实现者I写过W1初稿，可继续实现W1/W2，但不得独立审查自己写的代码。Reviewer J曾只复核了已经关闭的UI颜色问题，未写过W1/W2代码；J可以独立Review。另一人K写了W2核心，换一个任务窗口不使K独立于W2。没有资源必须等Owner挑选。
可选择任意当前模型/effort，以下仅为本模拟的先验小样本证据，不是一般能力事实：Sol/medium通过5个清晰合同实现；Sol/high通过4个跨模块修复；Astra/medium通过3个兼容Review；Astra/high通过3个多方依赖分析；Astra/xhigh通过1个多约束分析。样本均很少，不能据此声称普遍等质或更高档必更好。没有单一预定正确模型组合。
本地授权内可自主选择足够资源和调整分工；遇具体未覆盖的迁移歧义才局部加强分析，不需要先让低档失败。最多2个实现者同时写；独立Review R1必须等待W1/W2和交叉矩阵证据，并绑定最终交付身份。计划中明确谁执行交叉矩阵；这项可并入W2或R1前的整合步骤。对PUBLISH保持暂停。
