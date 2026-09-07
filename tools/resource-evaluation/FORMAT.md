# 输入格式（schemaVersion 1）

核心只需要两个脱敏JSON文件；不依赖Codex、网络或运行模型。

`study.json`：

```json
{
  "schemaVersion": 1,
  "round": "r1",
  "cutoff": "2026-01-01T12:00:00Z",
  "rateBasis": "Explicit credits per million; supplied tariff date",
  "rates": {"model-name": {"input": 100, "cachedInput": 10, "output": 500}},
  "tailExcluded": true,
  "trajectoryKind": "real_host_followup_not_context_compression",
  "turns": [{"id":"t1","threadId":"h1","role":"subject","participant":"P1","case":"C1","stage":"0","requested":{"model":"model-name","effort":"high"},"sentAt":"2026-01-01T11:00:00Z"}],
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

所有时间需带时区。`timestamp`是记录可见时间；截止时间含等于边界的记录。不要用导出时刻回填未知发生时间。计费要求input/cached/output和已知为0的cache-write；reasoning或total缺失仍显示null。`input_tokens`包括缓存读取，公式为`(input-cached)*inputRate + cached*cachedRate + output*outputRate`，除以一百万。费率必须有限且非负。

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
- 直接复用study的turns、rates、cutoff、observations，并用`events`指向脱敏事件文件。新增数据只生成新计量版本；老报告不覆盖。相关案例和时间定义由操作者显式保留，不强行视为独立样本。
- 正常rerun不重跑旧检查器。修改已冻结答案只报告漂移；若要重新答题，必须另设明确的新样本ID。修正验收器解释放在独立观察通道，不能编辑首交机械结果。
