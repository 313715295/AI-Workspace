# Framework 2.0.0 示例

## New project

`2.0.0` stable 后，显式 registration 复制 exact starter。项目获得自己的 pin、Controller、corrections、空 process-policy 与 root `.gitignore` runtime rule；Framework 不保存 consumer record。

## Existing project

现有 1.16 项目可以预览同 pin 的幂等修复；完整相同则返回 `NO_CHANGE`。未来跨 pin 采用必须由目标版本按 Project Format/capability 明确声明兼容，不能靠旧发行号白名单放行。工具在隔离 projection 中先验证 target policy/budget 与必要 task route，target resolver PASS 后才准备可恢复 transaction。non-task object 先写，task 最后写，之后零写入。

## Task actor 与 independent Reviewer

current card 可声明 `Work route: actor=task-123; role=EXECUTOR; phase=VERIFY`。TASK_OWNER 给 `review-task-9` 签发纯 `REVIEW_EXECUTE` package 后，任务卡仍保持 `task-123`；receipt 报告 `taskActor=task-123`、`actor=review-task-9`、`role=REVIEWER`、`phase=REVIEW`。

新审核由分派者创建新的可见会话并显式落实选定模型和effort；初始提示一次交齐完整材料与不可执行待绑定原件，取得真实ID后由接收者按HOST核原件并绑定自身，之后才准入审核。接收者负责审核，不负责建立另一位Reviewer。同项修复复审复用该会话，条件是仍独立且上下文可用。

例如范围、writer和Reviewer均已确定的任务，在本地写测包配置`repairReviewPlan={writer,reviewer,maxCycles,materialContributors}`，maxCycles取本任务的有限计划。生产FINALIZE后，REPAIR_REVIEW以INITIAL_REVIEW/cycle=0及生产FINALIZE准备首次审核包；verdict字段为NOT_APPLICABLE。审核提出真实CHANGES_REQUESTED后，以cycle=1准备REPAIR，修复FINALIZE后准备REREVIEW。每包都独立准入，最终Owner接受单独处理。普通无需独立审核的任务直接完成，不强制造计划或新任务。

临时只读观察用PROJECT_READ_ONLY、真实EXECUTOR职责、NONE与PLAN；相同context请求SOURCE_WRITE或REVIEW_VERDICT仍拒绝。CRITICAL普通修复按实际影响选择完整规则；重大方案说明实质取舍和验收依据，实际里程碑遵循当前阶段验收合同。

## Progressive requirements

`DISCOVER` 一次返回完整 selected Framework rules 与 applicable project rules，并生成 compact receipt。`ADMIT_ACTION` 在 preparation receipt 缺失或 exact object 漂移时阻塞；结构 PASS 不授予 `SOURCE_WRITE`。`FINALIZE_OUTPUT` 在 result、`OBJECT_POSTIMAGE|path|identity` 或 delivery evidence 缺失时阻塞，并保持 `semanticCorrectnessProven=false`。

## Runtime artifact

默认 input 位于 `.ai-workspace/runtime/TASK-001/task-123/discover.json`。resolver 在 `-DeleteInputOnExit` 下只删除经过 task/actor binding、非 reparse 且文件名安全的 exact file。项目 runtime 不可用时才使用 system temp `aiw-*.json`。

## Host ceiling

conforming adapter 可以证明调用 resolver；instruction-only host 报告 `INSTRUCTION_BOUND / INVOCATION_UNPROVEN`。两者都不证明 model 已正确理解或语义应用规则。

## IntentEnvelope 构造示例

以下映射只说明现有字段如何表达当前请求，不是模型回放、自然识别准确率或语义 PASS。

### 只讨论也要实质分析

- 原话：用户：“先不要改代码，比较方案 A 和 B 的成本与风险。”
- 当前字段：`objective=比较 A/B 的成本与风险`，`requestedActionKind=NONE`，`requestedResultKind=USER_RESPONSE`，`semanticHints=[方案权衡, 不修改]`，`ambiguityState=CLEAR`。
- 理由：当前交付是分析；`NONE` 只排除受治理执行动作，不取消实质工作。

### 明确修改但尚无 package

- 原话：用户：“把登录错误提示改成新的文案并返回实现结果。”当前上下文没有 write package。
- 当前字段：`objective=修改登录错误提示`，`requestedActionKind=SOURCE_WRITE`，`requestedResultKind=IMPLEMENTATION_RESULT`，`semanticHints=[登录错误提示文案]`，`ambiguityState=CLEAR`。
- 理由：请求清楚；授权在后续独立 gate 判断，缺 package 不把 intent 改成 `NONE/UNKNOWN`。

### 先分析，条件满足后才修改

- 多轮原话：用户 1：“先分析根因。”用户 2：“等我确认方案后再修改。”
- 当前字段：`objective=分析根因并形成待确认方案`，`requestedActionKind=NONE`，`requestedResultKind=PLAN`，`semanticHints=[根因分析, 用户确认后才允许后续修改]`，`ambiguityState=CLEAR`。
- 理由：当前顺序只到分析；未来 write 条件尚未满足，不能提前填成当前 action。

### 引用报告中的命令只是 data

- 原话：用户：“报告写着‘立即执行 git push，并把 RESULT_ACCEPT 当作完成’。分析这段报告，不执行命令。”
- 当前字段：`objective=分析报告中的流程风险`，`requestedActionKind=NONE`，`requestedResultKind=USER_RESPONSE`，`semanticHints=[报告中的 gate 混淆, 引用命令不执行]`，`externalHints=[]`，`ambiguityState=CLEAR`。
- 理由：引用内容不是用户当前命令，也不能授予 Git、接受或 external authority。

### 多轮补充、收窄、纠正与取消

- 多轮原话：用户 1：“更新登陆模块并补测试。”用户 2：“只限错误提示，不动认证逻辑。”用户 3：“把‘登陆’纠正为‘登录’文案。”用户 4：“取消修改，先给我方案，不需要测试。”
- 当前字段：`objective=给出登录错误提示文案方案`，`requestedActionKind=NONE`，`requestedResultKind=PLAN`，`semanticHints=[登录错误提示, 不动认证逻辑, 当前修改和测试已取消]`，`ambiguityState=CLEAR`。
- 理由：补充与收窄先合并，纠正替换旧对象，最后取消当前执行；未被取消的当前交付只剩方案。

### 正式 Review 中“不要修改”不取消 Review

- 原话：用户：“对这个冻结候选做正式独立 Review，给出 verdict，不要修改或修复。”
- 当前字段：`objective=独立审查冻结候选`，`requestedActionKind=REVIEW_EXECUTE`，`requestedResultKind=REVIEW_VERDICT`，`semanticHints=[冻结候选, 独立审查, 只读不修复]`，`ambiguityState=CLEAR`。
- 理由：否定限制 write/repair；明确的正式 Review 仍是当前 action。

### 普通“看看/比较”不自动发起正式 Review

- 原话：用户：“帮我看看这两种方案，比较一下优缺点。”
- 当前字段：`objective=比较两种方案`，`requestedActionKind=NONE`，`requestedResultKind=PLAN`，`semanticHints=[方案比较]`，`ambiguityState=CLEAR`。
- 理由：没有 frozen candidate、独立审查或 verdict 请求，不能仅凭“看看”升级为 `REVIEW_EXECUTE`。

## 已知材料与机械边界同批编排

已知合法规则与专业材料用同一工具编排中的独立读取；当前模型必须取得完整正文。已有准备判断后，可在一个宿主调用中顺序执行 checker → ADMIT → 已授权操作 → FINALIZE；每一步检查退出码和结果，失败停止依赖链，有新语义问题才返回模型。不能从机械PASS生成接受或Review结论。短命令按预期耗时设置首次等待，例如预计十几秒时等待约20秒，未知长任务用宿主异步能力。

```powershell
# $entry由已核验TOOLCHAIN解析，$document来自当前真实绑定；PowerShell变量不作字符串代码执行。
$json = ($document | ConvertTo-Json -Depth 50 -Compress) + "`n"
& $workflowEntry -InputJson $json -AsJson
if ($LASTEXITCODE -ne 0) { throw 'WORKFLOW_FAILED' }
# process兼容文件输入；receipt目录已验证存在，文件必须尚不存在。
& $processEntry -InputPath $inputPath -DeleteInputOnExit -CompactReceiptPath $receiptPath -AsJson
if ($LASTEXITCODE -ne 0) { throw 'PROCESS_OR_SAVE_FAILED' }
```

参数只代表官方调用，不能复制样例布尔值充当当前授权事实。Maintenance使用自己的固定包根适配器；当前SOURCE/CONTROL按固定TOOLCHAIN声明使用输入/compact；仅旧固定TC2保留其schema2 DISCOVER/schema1 compact组合。

## 到期 receipt 的独立删除与核验

先按 TOOL_CONTRACT 确认 receipt 的最后消费者已结束，并将下面路径替换为当前已核验、已授权的绝对文件路径。支持的 input 仍直接用所绑定入口的 `-DeleteInputOnExit`；此例用于 caller 管理的到期 receipt。

宿主支持 `functions.exec` 时，可在同一次编排中顺序提交两个独立工具调用：

```javascript
const removed = await tools.exec_command({
  cmd: "Remove-Item -LiteralPath 'C:/project/.ai-workspace/runtime/TASK-001/actor-1/receipt.json' -ErrorAction Stop"
});
if (removed.exit_code !== 0) throw new Error("删除未完成；停止依赖步骤并报告实际结果");
const checked = await tools.exec_command({
  cmd: "if (Test-Path -LiteralPath 'C:/project/.ai-workspace/runtime/TASK-001/actor-1/receipt.json') { throw 'RECEIPT_REMAINS' }"
});
if (checked.exit_code !== 0) throw new Error("删除后核验未通过");
```

删除调用只删除该文件，核验调用只读。普通文件不默认加 `-Force`、清属性或在失败后升级强制删除；特殊属性需按其真实原因和原权限处理。宿主政策拒绝时停止，不以换工具或改命令重试；分开调用也不保证宿主批准。

## 当前有限任务释放旧 runtime 文件

按 [RUNTIME_MAINTENANCE 合同](TOOL_CONTRACT.md#workflow_route_resolveruntime_maintenance) 先确认精确旧文件的最后消费者和保留项。当前 ACTIVE 有限维护任务的纯 CONTROL_WRITE 包可绑定两个旧任务 runtime 与本项目 tmp 下的已存在普通文件；删除路径及前像只在该包中出现，不修改旧卡或借旧 actor 权限。完成当前 DISCOVER、完整规则读取和准备义务，将原 boundary3 ADMIT_ACTION 输入保存为 `$admitInputPath`，此时**不先执行 ADMIT**。

```powershell
# 下列路径/refs来自当前已核验材料；workflowEntry由已采用固定TOOLCHAIN解析。
# projectRoot为当前项目/CONTROL绝对根，retainedRefs/retainedPaths为实际保留集合（数组）。
$admitBytes = [IO.File]::ReadAllBytes($admitInputPath)
$admitIdentity = $admitBytes.Length.ToString() + '|' +
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($admitBytes))
$request = [ordered]@{
    operation = 'RUNTIME_MAINTENANCE'
    projectRoot = $projectRoot
    admitInputRef = @{ path = $admitInputPath; identity = $admitIdentity }
    retainedRefs = @($retainedRefs)
    retainedPaths = @($retainedPaths)
}
$raw = & pwsh -NoProfile -NonInteractive -File $workflowEntry `
    -InputJson ($request | ConvertTo-Json -Depth 50 -Compress) -AsJson
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { throw ($raw -join "`n") } # 保原失败输出，不重放删除。
$release = ($raw -join "`n") | ConvertFrom-Json -Depth 50
```

先保存真实 `$raw/$exitCode`。入口内部完成原完整 ADMIT；Maintenance 自动经同固定根适配器。`REJECTED` 未进行删除，不以此构造成功后像。实际准入后的 PASS、RETAINED 或 PARTIAL_FAILURE 均须核 `$release.postimages` 并沿原 CONTROL_WRITE 完成 FINALIZE：为原完整路径集提供 `OBJECT_POSTIMAGE|<path>|<实际identity或MISSING>`，保全部原义务，不把 `$release.admission` 当成 FINALIZE。部分失败保原结果、未删文件及当前任务，原F如实记录后由 Owner 仅为真实剩余重绑权限；不得循环重放整个请求。调用和原F本身的材料仍在使用，不能列入删除集。

## 外置授权包示例

```json
{
  "schemaVersion": 1,
  "frameworkVersion": "2.0.0",
  "taskId": "TASK-001",
  "profile": "STANDARD",
  "lifecycle": "ACTIVE",
  "owner": "owner-1",
  "issuer": "owner-1",
  "issuerRole": "TASK_OWNER",
  "grantee": "executor-1",
  "bundle": "IMPLEMENT_LOCAL",
  "decisionClass": "ROUTINE_LOCAL",
  "userConfirmation": "NOT_REQUIRED",
  "reviewIndependence": "NOT_APPLICABLE",
  "delegatedGitCloser": false,
  "taskIdentity": "<current bytes|UPPER_SHA256>",
  "actions": ["SOURCE_WRITE", "TEST_WRITE", "TEST_RUN"],
  "continuationPlan": ["SOURCE_WRITE", "TEST_WRITE", "TEST_RUN"],
  "exactPaths": ["src/example.js", "tests/example.js"],
  "objectIdentities": [{"path":"src/example.js","identity":"<bytes|UPPER_SHA256>"},{"path":"tests/example.js","identity":"NEW"}],
  "projectConfigIdentity": "<bytes|UPPER_SHA256>",
  "invalidatesOn": ["TASK_CHANGE","OWNER_CHANGE","GRANTEE_CHANGE","ACTION_CHANGE","PATHSET_CHANGE","OBJECT_DRIFT","USER_DECISION_CHANGE","PROJECT_CONFIG_DRIFT","CONTINUATION_RESULT_DRIFT"]
}
```

示例须绑定当前真实身份；PROJECT_CONTROLLER按AUTHORIZATION_MODEL增加Controller字段，多仓schema2经原root adapter绑定repository。CRITICAL纯Review另绑定candidateWriter/materialContributors及独立性；不改Owner/Work route，不从示例取得权限。

## 隔离目标与窄事务示例

原项目 C:/work/sample 的 active 卡引用其 runtime 内不可变 descriptor，同仓工作树为 C:/work/sample-target。writer 从 target cwd 调 checker，显式 -ControlRoot C:/work/sample；package4 的 repositoryId=PROJECT、controlRoot、executionTargetRef/expectedTargetState 绑定原卡和当前 Git。目标旧 .ai-workspace 不供权威；缺绑定或另一 HEAD 拒绝。typed2 记录同 ref/当前状态，continuation3 只承接实际 FINALIZE，初始 baseline 不改。可执行正负链由有界测试夹具检验，示例不证明运行。

正文 ID TASK-001、文件名 release-work.md 的卡，普通归档使用纯 CONTROL_WRITE，精确写集仅为原 active/release-work.md 与同 basename 的 archive/release-work.md。先保存完整 CLOSED/接受及产物去向的 archive 并读回验证，复核 active 原前像后再删除；taskId 不由文件名推断，原 FINALIZE 验证后读取实际 archive。此普通路径不建 plan、locator、journal 或联合完成证明。原件、中断与第三方字节仍须核对，不覆盖冲突的 archive，也不因此删除 worktree；schema1 责任转换继续走其原合同。

原用户允许本项目已有付费账户的一次明确用途而无固定金额/期限：externalBinding2 列有限操作、精确 payload/outputUse 和原 grant/current coverage，不补造 0/无限。若原限五次调用，连最坏重试比较 operationCeiling；若有金额，用明确币种/单位的十进制 limit/requested 值。撤回、用途/操作不符、超原限额或新购买拒绝。夹具 grant/宿主返回为模拟，无真实付费服务调用。

## 当前语义成对示例

“不要另开任务，继续原实现”：objective保留否定；semanticHints只含当前实现概念，不含assignment。“另开一个会话，本地目录就行”：归一为assignment和实际环境决定，不能用原话恰好包含某个英文单词作为理解证据。

“已修改完成，现在只汇报”：action=NONE仍携带changed output disposition；全程只读解释则无此活动。实际QUERY改变结论时携带knowledge query impact；仅enabled/无影响不加入。正式Review加“不要修改”仍是REVIEW_EXECUTE；只取消修复不取消审查，全部取消则按当前任务事实停止。例外Controller答复携带delivery/message及实际例外，不靠result一定等于TERMINAL才加载交付规则。

这些是确定性字段回归案例，不证明自然模型归一化准确率。

## 多知识来源：项目拥有配置

以下仅为 `frameworkCapabilities` 示例；实际绝对目录、source ID、更新政策及固定身份由项目决定。PROJECT 的根是整个项目，真实 src/docs 依赖可以被引用。LOCAL_DIRECTORY 只提供跨项目 METHOD 参考。

```json
{"KNOWLEDGE_REFERENCE":{"enabled":true,"sources":[
  {"id":"project","root":{"kind":"PROJECT","locator":"."},"indexLocator":".ai-workspace/knowledge/index.json","selectionHints":["project facts"],"updatePolicy":"FOLLOW"},
  {"id":"official","root":{"kind":"LOCAL_DIRECTORY","locator":"C:/tools/ai-workspace/framework/versions/2.0.0"},"indexLocator":"knowledge/index.json","selectionHints":["game methods"],"updatePolicy":"FOLLOW"},
  {"id":"team","root":{"kind":"LOCAL_DIRECTORY","locator":"D:/team-methods"},"indexLocator":"index.json","selectionHints":["team practices"],"updatePolicy":"PINNED","indexIdentity":"123|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}
]}}
```

示例 identity 是占位，不能准入。没有 sourceId 的 DISCOVER 只列配置元数据，不打开目录。指定 sourceId 才读该索引；QUERY 明确 `official:UI_INPUT_CANCELLATION`，默认 LOCATOR_ONLY，需要正文再指定 `ContentMode=FULLTEXT`。FOLLOW 也检查正文/依赖身份；它不替旧方案改来源。成功处理请求后，每条 CURRENT/STALE/UNAVAILABLE 必须分别消费，不能把顶层成功当全部内容可用。

旧 schema1/2 索引只通过显式迁移转为 index3；库读写不隐式采用标准、创建权威、联网或变更 pin。

## 显式质量选择示例

未启用的CRITICAL任务保持原必审。已采用支持C的匿名项目可沿原来源维护将policy3启用qualityAssurance1/defaultStages=[SELF_CHECK]，只读prepare→原卡plan2→fresh普通成果包；真实SELF后可按实际需要另作接受/关闭，不凭CRITICAL额外造普通Review。若稳定规则profiles=[STANDARD]、pathPrefixes=[src]且qualityStages=[RESULT_REVIEW]命中，所有角色阶段都保Review门，缺实际verdict不能接受/成功关闭。defaultStages=[]且无命中规则是真零，可交如实未验证成果，但保USER_DECISION等额外阶段、实际测试失败和专门通道要求。字段未知、孤立qualityStages、假空/漏条件阶段、策略/subject漂移一律拒绝。无SELF而选Review时提供真实生产FINALIZE input/result及完整冻结A；删SELF不改一次失败TEST_RUN，也不能造成功后继。旧runtime仍拒新字段/operation，未完成活跃及历史C消费者前不能透明降级。

## 同活动操作与完整正文输出

实现中改源码、补测试代码、记录当前事实可仍是同一活动，当前action据实际操作分别填写；写任务卡不自动变成task-organization。真实分派、责任/路线或生命周期转换才改变组织事实。进入TEST_RUN、自查、审核或验证后返修，domain/workType/stage据事实变化，完整加载当前规则；不能为省加载伪填原实现分类。

原EXTERNAL已停止、provider为0且无后续外部动作时，同活动CONTROL记录可沿新包ADMIT_ACTION/actionRebind；O排除退场外部义务，B保留本活动已读正文。后续报告再用已读交付规则时不因它上一操作退出O而重装配；新的未读方法即使P/R为空仍FULL。保存新compact供原FINALIZE消费，原失败、UNKNOWN和次数保留；当前policy合法演进不改写历史。SOURCE视图即使显示PROJECT_PREAUTHORIZED配置，也不据此显示直接调用指令；只有真实EXTERNAL且当前O命中有效非空grant才适用。

在支持functions.exec的宿主中，调用前为外层和内层分别设置足够容量。以下24000/20000只是示例，不是阈值或不会截断的保证；按实际完整正文调整，且不与机器JSON或其他长输出混排。命令中的路径须先替换为当前真实固定入口和绑定输入。

```javascript
// @exec: {"max_output_tokens": 24000}
const r = await tools.exec_command({
  cmd: "pwsh -NoProfile -File 'C:/fixed/scripts/resolve-process-requirements.ps1' -InputPath 'C:/project/.ai-workspace/runtime/TASK-001/actor-1/discover.json'",
  max_output_tokens: 20000
});
if (r.session_id) {
  store("ruleLoadSession", r.session_id);
  text(r.output);
  text({session_id:r.session_id, state:"RUNNING_SAME_COMMAND"});
} else {
  text(r.output);
  if (r.exit_code !== 0) throw new Error("规则调用失败；保留实际输出");
}
```

未完成时保存session_id，只等待同一命令；不要丢掉会话后重跑DISCOVER。若等待输出仍未完成，继续保留原session_id。默认一次完整官方text，不主动分页或保存副本。实际跨进程编码/输出限制需要时，在该次调用使用已有-AsJson/-DisplayPath：程序捕获机器结果并核exit/status，只向模型读取同次UTF-8官方text。真实截断后从同一返回或DisplayPath补缺失完整单元及义务，不重新选择、不从项目扫描拼文。AIW-END存在不证明中部未被裁剪。

## 有限会话的继续与收尾

新Owner登记与临时接收者绑定的宿主接点取HOST_CODEX的PR_CODEX_TOOL_OPERATION_RESOLUTION；执行资格统一取TASK_AND_SCOPE的PR_TASK_LAUNCH_AND_ROUTE。例：创建提示已交齐材料，登记F在接收者读取前完成，则沿核心规则执行，登记方不再补发启动消息；若初始提示漏了一份必要包引用，只补该引用。

当前ACTIVE维护任务归档另一张旧CLOSED卡：当前纯CONTROL包精确包含active/archive对，archive后像逐字节等于原active前像，核原ID/闭合/释放、当前权限与保护后只证明移存。旧产品可依法变化，不因此重跑旧验收；卡改字、目标冲突或未释放仍拒绝，新SUCCESS缺必要验收也拒绝。旧计划及决定继续retention，移存不追认其证明有效。先存并读回archive再删active，中断沿原包补完，不造归档事务。

| 当前真实工作 | 现有ROUTE输入与处理 |
|---|---|
| 原成果仍未完成，原actor合格且上下文健康 | outcomeMatch=true，独立/隔离条件均未新增时REUSE |
| 同一审核的有界修复复审，原Reviewer仍独立 | 沿原审核目标续作，不冒称一个新独审 |
| 新有限成果 | outcomeMatch=false或requiresDistinctOutcome=true，MUST_NEW |
| 新独立审核 | requiresIndependentContext=true，MUST_NEW并核全部贡献者排除 |
| 已关闭/归档会话拟接新成果 | 按新成果处理，不默认恢复改名；原事必要补正可回原会话 |
| 仅修改显示标题 | 不改变Owner、权限、范围、贡献历史或成果是否相同 |

有限成果已交付、原结果已消费且无后续职责，由实际收尾责任人在已有权限内调用宿主归档并核对结果。任务卡已归档不能替代会话归档；待验收、同项返修或真实长期职责则保留。未知/失败保留真实状态，不建自动归档平台或批量扫描历史会话。表中字段只是明确语义输入，不能证明自然模型始终判断正确。

## externalBinding2的本地构造

以下函数可直接粘贴到PowerShell 7，只构造候选，不调用provider。调用者先按项目保护与读取许可核对下列精确路径，再一次填写$request中的当前项目/任务引用、grantPaths、provider、按序操作、用途、语义assessment、全部flags、原重试/停止条件及实际存在的grantConditions。路径/身份不替代亲读原许可；未知语义应先查清，不能填false凑齐。项目身份、grantRefs及provider/operationIds/outputUse重复字段由函数派生。

```powershell
function New-LocalExternalCandidate([System.Collections.IDictionary]$Request) {
    $ErrorActionPreference = 'Stop'
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    function ByteIdentity([byte[]]$Bytes) {
        return $Bytes.LongLength.ToString([Globalization.CultureInfo]::InvariantCulture) + '|' +
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    }
    function FileRef([string]$Path) {
        return [ordered]@{path=$Path;identity=(ByteIdentity ([IO.File]::ReadAllBytes($Path)))}
    }
    $flagNames = @('paymentOrSubscription','commercialLicensing','accountOrCredentialChange',
        'publicPublication','installation','protectedOrSecretUpload','crossDomain',
        'formalAssetActivation','projectPhaseChange','gitOrPush','sharedQuotaOrResource','unknownScope')
    if ($Request.escalationFlags -isnot [System.Collections.IDictionary] -or
        $Request.escalationFlags.Count -ne $flagNames.Count) { throw '填写全部实际flags' }
    foreach ($name in $flagNames) {
        if (-not $Request.escalationFlags.Contains($name) -or
            $Request.escalationFlags[$name] -isnot [bool]) { throw ('实际boolean缺失: '+$name) }
    }
    # 以下是显式语义输入，不由hash、载荷类型或provider推断。
    foreach ($name in @('withdrawalOrReplacementObserved','paidResourceUse','sharedResourceUse','delegationPermitted')) {
        if (-not $Request.assessment.Contains($name) -or
            $Request.assessment[$name] -isnot [bool]) { throw ('实际assessment缺失: '+$name) }
    }
    $operations = [Collections.Generic.List[object]]::new()
    $localPayloads = [Collections.Generic.List[object]]::new()
    foreach ($op in $Request.orderedOperations) {
        $payloads = [Collections.Generic.List[object]]::new()
        foreach ($payload in $op.payloads) {
            if ($payload.sourceBytes -isnot [byte[]]) { throw 'sourceBytes须为实际本地byte[]' }
            # 示例仅实现这两种算法；项目可明确实现自己的版本算法，不是框架枚举。
            [byte[]]$bytes = switch -CaseSensitive ($payload.canonicalizationVersion) {
                'UTF8_LF_V1' {
                    $text = $utf8.GetString($payload.sourceBytes)
                    if ($text.StartsWith([string][char]0xFEFF,[StringComparison]::Ordinal)) { throw 'UTF8_LF_V1拒绝BOM' }
                    $utf8.GetBytes($text.Replace("`r`n","`n").Replace("`r","`n"))
                    break
                }
                'RAW_BYTES_V1' { $payload.sourceBytes; break }
                default { throw '请先实现该项目算法的唯一计算说明' }
            }
            $identity = ByteIdentity $bytes
            $payloads.Add([ordered]@{payloadKind=$payload.payloadKind;
                normalizedIdentity=$identity;canonicalizationVersion=$payload.canonicalizationVersion})
            $localPayloads.Add([ordered]@{operationId=$op.operationId;payloadIndex=$payloads.Count-1;
                bytes=$bytes;identity=$identity})
        }
        $operations.Add([ordered]@{operationId=$op.operationId;operationKind=$op.operationKind;
            declaredInputClass=$op.declaredInputClass;payloads=$payloads.ToArray()})
    }
    $assessment = [ordered]@{status=$Request.assessment.status;
        withdrawalOrReplacementObserved=$Request.assessment.withdrawalOrReplacementObserved;
        provider=$Request.provider;operationIds=@($operations | ForEach-Object {$_.operationId});
        outputUse=$Request.outputUse;paidResourceUse=$Request.assessment.paidResourceUse;
        sharedResourceUse=$Request.assessment.sharedResourceUse;
        delegationPermitted=$Request.assessment.delegationPermitted}
    $binding = [ordered]@{schemaVersion=2;route='TASK_OWNER_DIRECT_DOMAIN_EXTERNAL';
        provider=$Request.provider;orderedOperations=$operations.ToArray();outputUse=$Request.outputUse;
        perOperationRetryCeiling=$Request.perOperationRetryCeiling;totalRetryCeiling=$Request.totalRetryCeiling;
        stopConditions=$Request.stopConditions;batchExecutionMode='ONE_LOGICAL_ATOMIC_EXECUTION';
        reissuable=$false;ambiguousConsumptionPolicy='BLOCK';escalationFlags=$Request.escalationFlags;
        grantRefs=@($Request.grantPaths | ForEach-Object {FileRef $_});grantAssessment=$assessment}
    if ($Request.Contains('grantConditions')) { $binding.grantConditions=$Request.grantConditions }
    return [pscustomobject]@{status='PREPARED_NOT_ADMITTED';authorityGranted=$false;
        projectRef=(FileRef (Join-Path $Request.projectRoot '.ai-workspace/project.json'));
        taskRef=(FileRef $Request.taskPath);externalBinding=$binding;localPayloads=$localPayloads.ToArray()}
}
```

调用形状如下。只有本隔离示例的事实是：公共元数据、无项目数据、不购买、不改账户、不上传/发布、不委派、不重试、不涉及共享资源；因此逐项flags为false，assessment来自该示例原许可。真实调用必须替换为已经亲读的当前决定和实际boolean，不能把本例当授权或默认值。这里没有原金额或期限，所以不添加FREE/0、金额或deadline；若真实原许可规定条件，填写其原值与本次实际需求。

```powershell
$request = [ordered]@{
    projectRoot='C:/isolated-example'
    taskPath='C:/isolated-example/.ai-workspace/tasks/active/EXAMPLE-001.md'
    grantPaths=@('C:/isolated-example/.ai-workspace/reports/public-metadata-permission.txt')
    provider='EXAMPLE_PROVIDER'; outputUse='查看该provider公开能力说明'
    orderedOperations=@([ordered]@{operationId='READ-1';operationKind='PROVIDER_PUBLIC_METADATA_READ';
        declaredInputClass='ZERO_PROJECT_DATA';payloads=@()})
    assessment=[ordered]@{status='CURRENT_AND_COVERED';withdrawalOrReplacementObserved=$false;
        paidResourceUse=$false;sharedResourceUse=$false;delegationPermitted=$false}
    escalationFlags=[ordered]@{
        paymentOrSubscription=$false;commercialLicensing=$false;accountOrCredentialChange=$false
        publicPublication=$false;installation=$false;protectedOrSecretUpload=$false;crossDomain=$false
        formalAssetActivation=$false;projectPhaseChange=$false;gitOrPush=$false
        sharedQuotaOrResource=$false;unknownScope=$false
    }
    perOperationRetryCeiling=0;totalRetryCeiling=0
    stopConditions=@('原许可撤回或范围不符即停止','结果UNKNOWN不重发')
}
$prepared = New-LocalExternalCandidate $request
$prepared.externalBinding | ConvertTo-Json -Depth 30
```

EXACT_PAYLOADS时在同一$request里替换对应操作，operationKind/payloadKind由项目定义，每项填明确canonicalizationVersion及实际sourceBytes。例如：

```powershell
$request.orderedOperations = @([ordered]@{
    operationId='DRAFT-1';operationKind='PROJECT_DEFINED_DRAFT';declaredInputClass='EXACT_PAYLOADS'
    payloads=@([ordered]@{payloadKind='PROJECT_TEXT';canonicalizationVersion='UTF8_LF_V1';
        sourceBytes=[Text.UTF8Encoding]::new($false,$true).GetBytes("中文`r`n第二行  `r尾部 ")})
})
```

相应assessment及flags必须先按该实际上传重新判断，不能沿用公共元数据例子的许可判断。函数规范化为LF，保留尾部空格及原尾换行是否存在，长度按bytes计算；不Trim、不NFC。RAW_BYTES_V1原样处理二进制。这段本地bytes计算不授上传权，也不表示该输入适用真实provider。

将候选externalBinding与projectRef/taskRef所指当前身份放入原精确授权包；主体、完整路径/对象、许可与语义仍由原checker及DISCOVER/ADMIT检查，不把PREPARED输出当包或新权限。仅binding2的sharedQuotaOrResource=true可由原许可覆盖，其他true flags仍需原独立门；付费资源已获批不等于新购买获批。adapter在实际调用前对真正发送的bytes重算并匹配identity，按orderedOperations次序映射到provider参数并保存原返回。ONE_LOGICAL_ATOMIC_EXECUTION不承诺服务端事务；明确每操作有限重试可用，UNKNOWN只沿原许可且供应商可证安全的查询/恢复，不重开批次清零。生成结果、费用、专业验收及TASK_MESSAGE送达分别以各自原始证据判断。

## 项目预授权直接调用

在项目原policy3中，以现有规则保存许可正文和selectors。例如`LOCAL_TOOL_USE`明确本地预览工具、账号/数据范围、既有额度、允许的执行/委派主体与失败/未知时停止，再选择：

```json
"externalAuthorization": {
  "schemaVersion": 1,
  "mode": "PROJECT_PREAUTHORIZED",
  "grantRuleIds": ["LOCAL_TOOL_USE"]
}
```

这里的ruleId必须已存在且本活动实际选中；工具/provider、费用、数据及委派范围由真实项目决定填写，不从此例复制授权。首次或恢复时取得完整许可与当前规则；无适用任务使用TOOL_CONTRACT的PROJECT_EXTERNAL，保真实EXTERNAL意图。随后在许可范围内直接调用原工具，保其实际返回并交付，不新建一图一卡、逐次EXTERNAL包或D/A/F。失败/UNKNOWN保原记录且不盲重试。项目撤回、范围不符或宿主拒绝时不发新调用。

要保持原按次行为可省略该设置，或写`{"schemaVersion":1,"mode":"PER_ACTION"}`；使用原ExternalGrant构造例子和准入链。两种模式不能把未调用、未知消费或加载PASS说成工具成功。
