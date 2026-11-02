# 输入格式（schemaVersion 1）

核心只需要两个脱敏JSON文件；不依赖Codex、网络或运行模型。

`study.json`：

```json
{
  "schemaVersion": 1,
  "round": "r1",
  "cutoff": "2026-01-01T12:00:00Z",
  "clockDomain": "documented-shared-clock",
  "rateBasis": "Explicit credits per million; supplied tariff date",
  "costUnit": "codex_credits",
  "comparisonScope": "turn",
  "rates": {"model-name": {"input": 100, "cachedInput": 10, "output": 500}},
  "tailExcluded": true,
  "trajectoryKind": "real_host_followup_not_context_compression",
  "turns": [{"id":"t1","threadId":"h1","role":"subject","participant":"P1","case":"C1","stage":"0","costScope":"turn","requested":{"model":"model-name","effort":"high"},"sentAt":"2026-01-01T11:00:00Z"}],
  "observations": [],
  "limitations": ["Uncounted final reporting tail"]
}
```

`events.json`：

```json
[
  {"type":"context","turnId":"t1","threadId":"h1","timestamp":"2026-01-01T11:00:01Z","model":"model-name","effort":"high"},
  {"type":"usage","turnId":"t1","threadId":"h1","timestamp":"2026-01-01T11:00:02Z","responseId":"r1","usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":60,"total_tokens":1100}},
  {"type":"timing","turnId":"t1","threadId":"h1","timestamp":"2026-01-01T11:00:05Z","startedAt":"2026-01-01T11:00:01Z","completedAt":"2026-01-01T11:00:05Z","activeMs":4000,"activityKind":"host_duration_including_tools_and_backend_waits"}
]
```

身份必须显式绑定，不能把未匹配turn推断为统筹。用`role:"coordinator"`另列统筹turn。同一thread的不同turn可分别属于不同轮次，仅列本轮授权身份。`responseId`在数据集内唯一；相同身份和usage的重复记录只计一次，冲突重复会报错。`cumulativeUsage`可选，表示同turn累计值，用于对账，不能传整个历史thread累计值。

所有时间需带时区。`timestamp`是记录可见时间；截止时间含等于边界的记录。不要用导出时刻回填未知发生时间。`costUnit`仅可为`codex_credits`（历史默认）或`api_usd`，一个study只用一种单位；费率均按每百万token，需写明来源和日期，不能将两单位相加。Codex credits按`(input-cached)*inputRate + cached*cachedRate + output*outputRate`计算；cache-write原计数可为null，且不另加未有依据的写入价。API USD若有cache-write须提供实际计数与显式`cacheWrite`费率，公式将写入token从普通非缓存输入中扣出单独计价；缺计数或费率保持unknown。`input_tokens`包括缓存读取。reasoning已含于output，不重复计费。input/output/total三项已知时必须严格满足total=input+output；矛盾响应或累计值直接拒绝，缺失值保留null。供应商不同口径由输入适配显式归一化，核心不猜值。费率必须有限且非负；新增GPT-6型号没有默认费率，实际model ID、计费通道、日期和计时定义取当次证据。

`responseCount`仅是截止前去重后的可观察usage记录数；重复记录不加数，不能证明供应商请求总数。`responseCountBasis`和`responseCoverage`在每行、角色汇总、CSV及Markdown保留此边界。`measurementComplete`要求有usage、截止前完成、每响应input/cached-input/output/total齐全、累计usage与去重响应合计一致；它不要求费率或API专用cache-write计价数据。`costComplete`单独表示全部观测响应均有可核验费用；未知费率/计价字段保持null和已知小计。配置核验、时钟核验及workflow冻结派发核验分别列出。比较还要求study显式`comparisonScope`与turn显式`costScope`一致，范围只可为`turn`、`stage`或`task`。阶段费用不自动充当完整任务费用；未完成或配置不符的尝试仍保留已知消耗。整项费用未知时，`knownCostSubtotal`给出去重响应中可计价部分，`unknownCostResponses`注明缺项；已知小计不是完整账单。

观察记录示例：

```json
[
  {"kind":"preregistered","case":"C1","participant":"P1","rawPass":false,"score":95},
  {"kind":"checker_false_negative","case":"C1","participant":"P1","rawPass":false,"resolvedPass":true,"label":"Documented public-interface mismatch","sourceRef":"review-evidence"},
  {"kind":"post_hoc_unscored","case":"C1","participant":"P1","rawPass":false,"expected":"INVALID","actual":"ID_REUSE","noWrites":true}
]
```

原分数只是原证据，不由费用或新观察自动改写。人工/模型语义记录可标`basis:"semantic"`。报告保留各通道，不将它们加成一个新排名。

## 可选导入适配器

```sh
node cli.cjs import-r4 --results R4-results.json --measurement R4-measurement.json --protocol R4-protocol.json --rates examples/rates.json --out work/r4-import
node cli.cjs adapt-codex --log session-a.jsonl --log session-b.jsonl --map private-selection.json --out work/selected-export
```

R4适配器专用于此旧格式；核心没有R4日期、协调者或模型费率fallback。导入只保留必要字段，真实thread/turn/response ID改为本地别名。缺少原requested证据时，特别是省略protocol的统筹配置，不假装已核验。

本地日志选择文件是**不分发的本地输入**，结构同study，但turn使用：

```json
{"sourceThreadId":"LOCAL_THREAD_ID","sourceTurnId":"LOCAL_TURN_ID","role":"coordinator","requested":{"model":"EXACT_MODEL","effort":"high"}}
```

适配器只导出所选turn的context、usage及可用开始/完成字段。忽略会话文本、工具参数、cwd等；没有session身份的context不会猜测。未知/变更日志格式可能无法提供实际配置或duration，输出明确缺项，不能据此当作0消耗或已完成。

## 增量workflow配置

完整可运行例子由`node examples/replay-workflow.cjs NEW_DIR`生成。最小模板见`examples/batch-template.json`；相对文件路径均以配置文件所在目录解析。

- `cases`固定公开materials、初始消息、必要followUps、私有rubric、checker与可选checkerArgs；占位符`{submission}`替换为冻结提交目录，参数不经过shell。检查器只输出JSON `{pass,passed,total}`，退出0且pass=true才是机械通过。
- `participants`明确每人的model/effort/cases。`stop.maxJobs`约束已配置组合数，`afterAll:true`禁止自动扩展，deadline之后不准备/派发新工作；仍可收取已有结果。`--at`只用于明确的离线历史重放。
- `submissions`键为`participant--case`，值`{path,final:true}`。未声明final的目录不视作首交。每阶段可用单独case/stage标识或`import --kind submission`单独冻结，不用重开模型回合索要ACK。
- 组合键在写入前预检；例如participant `A`/case `B--C`与participant `A--B`/case `C`冲突时直接拒绝并列出两来源，不会把两个job误作一个。
- `public-initial`逐字节派生于已验证的`materials/payload`，并在复用时按冻结清单核验；follow-up仅在冻结材料中保留，初始包不泄露未来消息。
- 直接复用study的turns、rates、cutoff、observations，并用`events`指向脱敏事件文件。新增数据只生成新计量版本；老报告不覆盖。相关案例和时间定义由操作者显式保留，不强行视为独立样本。
- 正常rerun不重跑旧检查器。修改已冻结答案只报告漂移；若要重新答题，必须另设明确的新样本ID。修正验收器解释放在独立观察通道，不能编辑首交机械结果。
- 分析缓存绑定study/events、计算版本及报告生成实现，并在复用前逐个核验JSON、CSV和Markdown哈希。旧记录缺身份或文件漂移会在新目录离线重算并提示；已消费的旧目录不会覆盖。

## 派发和时钟的可比较依据

`clockDomain`只有在来源证明同一时钟域时填写；study值作为默认，turn值用于sentAt，timing事件值用于startedAt/completedAt。相同名称是调用者的有据声明，不是工具完成物理校时的证明。未提供或不同域时保留原始时间及已知成本，elapsedSeconds/dispatchToStartSeconds为null，timingComparable=false。已声明同域时要求sent≤started≤completed，零延迟合法，负延迟拒绝；缺时间也不可比较。不同域不自动计算偏移。原始完成时间另列recordedCompletedAt；completeAtCutoff继续表示当前观测截止内的完成事实。

workflow的subject turn显式提供`dispatchRef={job,definitionIdentity,message}`，分别取已冻结dispatch.json的job、definitionIdentity和initial/followUps中的实际消息名。工具同时核对participant/case、该阶段requested以及actual。requested=actual但偏离冻结派发仍排除，成本保留；缺绑定为unverified，不从名称猜测。coordinator不冒作受试者。独立summarize未接收workflow冻结材料，dispatchConfiguration标not_applicable，不能据此声称已验证派发。

需要改变follow-up配置时，在派发前为participant声明`stageConfigurations={caseId:{"followup.md":{model,effort}}}`；仅允许该case已公开的followUps。此映射进入definitionIdentity和冻结dispatch.json；没有映射的阶段沿冻结requested。turn的stage标签本身不授权变更配置。未知消息、旧定义或归属不符不可比较。

最终eligibleForComparison需要subject、requested/actual已核验、measurementComplete、costComplete、timingComparable及明确相同cost/comparisonScope；workflow再要求dispatchConfiguration=verified。JSON/CSV保存分开的状态、缺项、原时间和派发绑定；Markdown明确分母和证据边界。分析缓存额外绑定实际引用的冻结job和preparedFreeze，因此同study/events下派发事实改变也不会复用旧可比较结论；历史输出保持。