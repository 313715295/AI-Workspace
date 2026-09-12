# Resource Evaluation Tool

轻量、离线、零依赖的 Node CLI。它把原先由统筹模型反复做的准备、冻结、收取整理、机械检查、配置核对、计量和结果表交给脚本；**不执行模型、不发消息、不轮询、不调度后台任务**。与 Framework、pin、发布/采用、权限和资源策略完全独立。

## 何时使用

一次综合判断即可：任务需要怎样的专业与上下文理解，推导、约束耦合和验证工作有多重，以及哪个足够的 **model＋effort** 组合预计能以合适的完整交付成本达标。能力、工作量、风险、可验证性和成本是同一次判断的依据，不拆成五次模型请求，也不按工作阶段固定配置。

首次选型可用官方规格与可靠的外部实测缩小候选，入口及证据限制见 [REFERENCES.md](REFERENCES.md)。例如可同时考虑 **Astra/low、Sol/high、Sol/xhigh**：模型能力较强但推理较少，与另一模型投入更多推理，哪种足够且合算需结合具体任务；同名 effort 不等价，较高 effort 或较低单价都不保证更好的完整结果。这是候选比较，不能读成默认配置或排序。

健康配置正常复用；自然任务的验收、遗漏、返工和审查结果用于修正原判断的适用范围。成本包括执行、统筹、工具与恢复、等待、交接、审查及返工，缺失消耗保留未知。资料不清、工具缺失或交接往返先改善对应条件，不默认增加推理能解决。

只有未解问题会改变实际选择、且公开资料与已有任务证据不足时，才按已有授权用本工具比较少数组合；事先明确验收、预算和停止条件。不要求先失败，不新增选型回合、固定复评、资源台账、每任务 A/B 或全模型试验，不因样本全过自动加题。

保留历史题目、首交、评分与消耗供复核，不常态化扩大模拟试验。这里只说明如何使用评估材料，不规定项目的角色配置、资源权限或升档流程；项目实际选型遵循其当前有效规则。

## 快速运行

需要 Node 20+。直接运行，无需安装依赖：

```sh
node --test test/tool.test.cjs
node cli.cjs summarize --study examples/r4/study.json --events examples/r4/events.json --out work/my-r4-report
node examples/replay-workflow.cjs work/my-workflow-proof
```

后两个输出目录必须是新的。R4重放为受试 **267.44061**、统筹 **285.85545** credits，保留原截点及未计尾部限制。开发本工具的费用另列于交付验证记录，绝不算进R4。示例仅携带脱敏计量和少量原模拟题/首交，不含原会话、实际宿主ID、凭据或机器绝对路径。

## 下次试验的最短工作顺序

以下仅适用于已经决定开展的有界试验，是脚本与宿主操作顺序，不是五次模型选型请求。机械步骤由脚本处理，模型只承担必要的语义判断。

1. 人/模型一次完成题目有效性、公开合同、评分、参考/反例的判断。复制 `examples/batch-template.json`，填写固定问题、模型/effort组合、停止条件、费率和文件位置。题面、私有评分与独立检查器分别指定；检查器应是可信的、只读提交的独立Node脚本。
2. `node cli.cjs workflow --config batch.json --out work/batch`。脚本冻结输入/评分/检查器，生成每项最小派发包；输出只列新增、缺项和路径。宿主外部一次完整派发，**只把public-initial交给受试者，不暴露控制目录**。
3. 宿主完成首次作答后，在同一配置的 `submissions` 填路径和 `final:true`，运行同一命令。脚本快照首交、执行已冻结检查器、保存原始输出；没有自动补交、重跑或升档。多回合题只按已冻结清单发送必要消息，前一阶段先用 `import --kind submission` 冻结；没有ACK/许可循环。整个消息清单提前冻结，未来消息不放入初始受试包。阶段到实际宿主同一任务的对应关系仍由操作者负责。
4. 通过脱敏数据或可选日志适配器补实际turn身份与usage。再次运行同一命令，仅处理新增/变化输入：不重跑已完成机械检查，不替换首交，不重建未变化计量报告。已完成题面/模型配置若变化会提示使用新case或participant ID；未完成题面的变化生成新准备版本并保留旧版本。
5. 人/模型只看摘要中的缺项、失败证据路径，处理语义判断、验收器异常解释及最终资源取舍。已有语义结论可作为 `observations` 输入；原机械分数始终保留。完成固定数量即结束，无额外题目、模型或自动扩展。

重复运行依然会读取小配置/脱敏元数据，并计算文件哈希以检查漂移；它避免的是重复模型统筹、重复检查器运行和重复首交处理，不承诺零I/O。输入变化时可重新汇总小元数据，但原结果文件不改。实际节省需在后续真实试验中测量，**此交付没有测得节省百分比**。

## CLI

```sh
node cli.cjs help
node cli.cjs init --out work/new-study
node cli.cjs import --source materials --kind materials --label case1 --out work/frozen-materials
node cli.cjs import --source rubric --kind rubric --label case1 --out work/frozen-rubric
node cli.cjs import --source first-result --kind submission --label p1-case1 --out work/first-p1
node cli.cjs verify --source work/first-p1/payload --manifest work/first-p1/freeze.json
node cli.cjs freeze --source materials --kind materials --out work/materials-manifest.json
```

`import`逐字节保留原文件（包括原freeze文件），外层另建manifest；不是文本脱敏器。仅选择授权的必要材料，不把完整会话/凭据打包。`freeze`只生成清单，清单应保存在输入目录之外。校验包含额外未列文件；不跟随符号链接。输出不会覆盖现存快照或报告。

`workflow`允许复用自己的工作目录。其`state.json`只保存离线增量状态，首交、机械结果和准备包均有哈希校验。工作目录包含私有评分，不能直接交给受试任务。机械检查器超时10秒、输出上限64KiB，只用参数数组启动Node、不经过shell；这不是代码沙箱，请只配置已检查的可信脚本。失败检查器或损坏的半成品不会被自动重试/清除，需要操作者解释或另建明确的新工作项。

模型/effort、轮次、费率、截止时间、受试与统筹身份都来自配置；新增模型没有默认费率。日志适配仅支持明确指定的文件和turn选择，不扫描账户目录或完整任务历史。详细数据格式见 [FORMAT.md](FORMAT.md)。

## 能证明什么

- 费率估算不是账单；推理tokens已含在output，不能再次相加。非零cache-write的费率语义暂不支持，费用明确为unknown。
- 缺失费率/配置/计量不会回退为另一个模型或零；无统筹身份显示未提供。配置错误的样本不进入有效比较，但实际已知消耗仍计入费用。
- 截点后记录不计入，未完成活动耗时保持null，不按比例猜测；不同活动时间定义分组，不能强行相加。缺少工具等待记录不能解释为零等待。
- `preregistered`、`checker_false_negative`、`post_hoc_unscored`分开保存，CLI不擅自重判答案或改历史分数。真实host follow-up不等于真实上下文压缩。
- 数值复算、哈希和机械检查不证明题目有效、完整合同正确、语义审查独立或总体模型排名。这些判断留给人/模型。

R4示例的组织验证见运行后 `work/my-workflow-proof/proof.json`：首次结果哈希不变；第二次新增结果为0；追加仅为F2--C2；原D8机械3/5失败及外部假阴性解释分开保留。示例重用的是原R4完整费用账本，这些费用不是两次本地导入动作或CLI开发的费用。
