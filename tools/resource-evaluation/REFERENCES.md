# 公开资料导航

查阅日期：2026-09-07。用于筛选候选和识别证据缺口；不在此复制排行榜、维护分数或费用快照，也不建立抓取/同步脚本。使用时重新核对页面日期、模型版本、推理设置和测试环境。

2026-09-12补充：一次综合判断任务能力、推理工作量与完整 model＋effort 交付成本。Astra/low 可与 Sol/high、Sol/xhigh 一起进入候选；官方规格用于核对参数，可靠外部实测用于形成首次选择的依据，自然项目结果再修正适用范围。这里没有证明三者在长期项目中的统一排名，也不要求为比较另开模型请求或新试验。

## 官方资料

| 入口 | 用途与边界 |
|---|---|
| [OpenAI：GPT-6 Astra模型页](https://developers.openai.com/api/docs/models/gpt-6-astra) | 核对模型能力说明、支持参数与API规格；厂商说明不能替代项目验收。 |
| [OpenAI：GPT-5.6 Sol模型页](https://developers.openai.com/api/docs/models/gpt-5.6-sol) | 与Astra页分别核对支持的effort及规格；API参数说明不证明Codex宿主已接受配置，也不证明跨模型同档等价。 |
| [OpenAI：模型使用指引](https://developers.openai.com/api/docs/guides/latest-model) | 查阅当前模型的行为、提示和迁移建议；动态入口可能更新，必须确认正文对应的模型。 |
| [OpenAI：GPT-5.5指引](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.5) | “Behavioral changes”中的medium起点及高effort可能过度推理的说明属于GPT-5.5，不能冒称Astra专有指引，也不能直接外推成所有模型的默认配置。 |

## 第三方评测

| Artificial Analysis入口 | 用途与边界 |
|---|---|
| [GPT-6 Astra](https://artificialanalysis.ai/models/releases/gpt-6-astra) | 查看该发布系列的能力、速度和费用比较；逐项确认具体配置、测量状态和缺失字段。 |
| [GPT-5.6 Sol](https://artificialanalysis.ai/zh/models/releases/gpt-5-6-sol) | 查看发布系列的候选配置；具体测量状态需核对对应配置与指标条目。 |
| [GPT-5.6 Terra](https://artificialanalysis.ai/models/releases/gpt-5-6-terra) | 按自身资料与任务要求判断，不能继承Sol结论；具体测量状态需核对对应条目。 |
| [GPT-5.6 Luna](https://artificialanalysis.ai/models/releases/gpt-5-6-luna) | 应单独判断，不能按同名effort推断能力；具体测量状态需核对对应条目。 |
| [智能基准方法](https://artificialanalysis.ai/methodology/intelligence-benchmarking) | 查阅题集、权重、运行方式和版本变化。综合指数组合了多种评测，不能解释为项目任务成功率。 |

查阅时Sol、Terra、Luna的release汇总页出现“Estimate (independent evaluation forthcoming)”标记。仅凭汇总页不能确定该标记覆盖哪些数据点；具体配置/指标需查对应条目，不能统一当作独立实测，也不能据此声称所有档位均未独立实测。

## 补充案例与历史分析

以下来源于2026-09-07核对，用于提出选型假设，不直接改变使用者的资源规则或触发新试验。

| 入口 | 用途与边界 |
|---|---|
| [Simon Willison：Astra鹈鹕SVG实验](https://simonwillison.net/2026/Sep/4/astra-pelicans/) · [结果网格](https://static.simonwillison.net/static/2026/gpt-6-and-5.6-pelicans.html) | 2026-09-04的单任务展示；作者偏好Sol/xhigh而非max，并认为Astra低档在该题表现更好。它说明具体结果不保证随effort单调改善；主观视觉判断不能外推为coding、Review或长期协作排名。文章与结果页的Sol价格口径不同，引用费用需绑定具体来源与时点。 |
| [Artificial Analysis：GPT-5.6家族发布分析](https://artificialanalysis.ai/articles/gpt-5-6-has-landed) | 2026-07-09、当时指数v4.1和价格下，Sol/Luna在综合能力与每任务成本的前沿比较中优于Terra。不能与当前v4.2分数或价格混用，也不证明Terra在所有工作负载无价值；文中Codex编码指标与综合指数须分开解释。 |
| [Sol/medium与Terra/xhigh当前比较](https://artificialanalysis.ai/models/comparisons/gpt-5-6-sol-medium-vs-gpt-5-6-terra-xhigh) | 动态页；分别看能力、首token等待、输出速度与完整任务成本。每百万token更便宜或输出更快，不等于整项任务更便宜或完成更快；缺失指标保留未知。 |

评估时选择满足质量要求且预期完整任务成本合适的模型和足够effort；同类任务证据或已识别难点可支持直接选择较高档位，不要求先失败，也不为证明最低档而反复试验。根据具体问题取用首次质量、返工、Review缺陷、工具调用、压缩、范围漂移、人工介入及总成本等已有证据，不将所有指标变成每个任务的必填表。
## 如何用于选型

- 区分官方描述、估计值和独立实测；版本、effort、费用或速度缺失时保留未知，不按零值或其他模型补齐。只有设置与口径可比时才直接比较。
- API报价、基准每题费用与Codex实际账单口径不同。项目总成本还应包括统筹、审查、返工和等待；本工具按输入费率估算，不能把估算冒充实扣。
- 长期中文协作、真实上下文压缩后的连续性及Review覆盖，需要项目内证据；公开综合基准不能直接证明这些能力。
- 首次结合上述资料与已有同类任务记录选择，后续用自然结果修正同一判断；这些是证据来源，不是固定阶段或额外选型回合。仅当剩余疑点会改变实际选型时，按 [README的使用条件](README.md#何时使用) 做已获授权的小规模有界对照；不因资料缺项自动启动新试验。
