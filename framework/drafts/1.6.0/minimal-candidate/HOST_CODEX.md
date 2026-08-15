# Codex宿主适配

## 1. 质量资源等级

核心Framework只定义质量等级，不绑定长期模型品牌：

- `OWNER_FRONTIER`：项目主控、长期领域owner、重大方案裁决与跨域整合。
- `FOCUSED_HIGH`：优先分析/判断、客观验收、fresh聚焦Review和中高风险实现。
- `ROUTINE_BALANCED`：边界明确、直接测试充分、返工代价低的机械实现与整理。
- `MECHANICAL_LOW`：只用于完全确定性的格式、索引或只读采集；不能做产品判断、方案取舍或最终审核。

具体模型由host dispatch按四档质量映射，不写成长期固定型号。任务只有高于默认时记录最低质量、必要工具和连续性；无法满足则保持未分配并回owner，不静默降级，也不创建binding文件、digest、capability快照或第二资源矩阵。

## 2. 任务载体

- 当前用户任务承载owner必须当轮消费的工作。
- 内部子Agent只用于用户明确要求或宿主规则允许的有界并行子问题，不承担跨turn等待。
- 独立任务只在用户显式创建/要求、跨turn生命周期或真正独立审核需要时使用。
- 新会话不默认创建worktree。只有范围重叠无法避免、长周期隔离实验、并行候选或主工作树必须保持可发布时才创建，并先评估复制dirty diff的成本。

## 3. 主动回传与wait

独立任务主动向约定owner回传完成、阻断或范围门。owner不使用`wait_threads`维持进度感，也不因idle、ACK或普通进度轮询。

`PEER_THREAD_ROUTE_IS_APP_LEVEL`：桌面应用中的长期owner、分管和执行任务是peer task，跨peer回报使用应用级`send_message_to_thread / read_thread`路由；agent协作工具只覆盖同一live agent tree。`agent not found`不能证明peer task离线或不存在；发送失败时只做一次应用级定位/补投递，不轮询、不重跑已完成工作。

只有用户要求同步等待、当前turn必须消费且一次有界等待预计能完成、或已有主动回传但有具体丢失证据时，才允许一次有界等待。超时/无变化不立即重试。

## 4. pre-tool授权门

Codex在取得一个阶段的连续writer lease时，把当前授权包和计划批次的actor/action/path/identity传给`check-authorization.ps1`。首次PASS后，同一task/owner/grantee、相同actions与exact、对象未漂移且没有其他writer介入时，属于已验证子集的连续编辑和测试复用该PASS；不得为每个文件编辑、格式化或测试命令重复制造模型可见的脚本调用。

发生action/pathset扩展、对象或owner漂移、writer交接、用户决定变化、候选冻结，或进入Review/Git/external边界时必须重新预检。loader同样只在FULL_COLD、role/profile/phase/host变化或加载manifest变化时重算；普通温重绑不重复运行未变化的加载计划。

推荐把预检与实际动作放在同一受控宿主hook或wrapper中；成功默认只返回一行摘要，只有失败才返回具体原因。只在聊天中写“已授权”不构成机械门。Codex当前若没有可配置的全局pre-tool hook，Framework只能要求并测试预检脚本，不能声称宿主无法绕过。1.6.0将其明确记录为机械预检的能力边界，不冒充操作系统级不可绕过强制，也不为常态任务增加binding文件或digest缓存合同。

## 5. 用户交互

用户只需确认产品结果、重大方案/公共合同和外部动作。一次确认绑定稳定方案和停止线后，主控或领域owner在范围内签发阶段包；不让用户逐个文件、逐次测试或逐轮Review点击授权。

任务执行中出现玩家反例、重大方案变化、公共合同扩围、外部动作或不可逆风险时再回用户。普通机械状态、SHA和manifest留在控制面；面向用户汇报结果、剩余、是否需操作和证据上限。

## 6. 可选知识引用

Codex只在Bootstrap已严格验证project config后，把canonical capability集合传给loader。load-plan cache绑定project config、capability集合与load manifest identity；知识查询结果禁止缓存（`QUERY_RESULT_CACHE_PROHIBITED`），每次查询都从冻结config派生index locator并重新验证index、reference与authority。宿主不后台轮询、不自动创建/更新索引，也不把查询PASS解释为授权。

未启用、无库、空索引、条目漂移或authority冲突统一按`REFERENCE_UNAVAILABLE`处理，继续正式恢复链。每次普通查询最多消费3条CURRENT引用；fixture和人工演示不计入自然查询样本。
