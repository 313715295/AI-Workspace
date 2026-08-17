# 任务、范围与实施

本模块在任务规划、实施、验证和审核阶段加载。它补充`RECOVERY_CORE.md`的公共不变量；授权字段与签发层级只由`AUTHORIZATION_MODEL.md`定义。

## 1. 长期责任与路由

routine状态由领域owner直接闭环：不轮询、不要求ACK链、不把READY/PASS/HOLD/INPUT_COMPLIANCE/OWNER_ACCEPTED/HANDOFF_SENT或writer=NONE逐条上报主控。主控主动pull热卡，只接收跨域、公共合同、资源冲突、routine-exclusion冲突与OBJECT_DRIFT等例外；产品决定由负责领域owner直接问用户，主控只整合跨域和阶段门。终态只允许一个responsible reporter，重复状态按stable identity去重。

Framework只有两层长期责任：项目主控和领域owner。用户持有产品目标与最终取舍；执行者和独立审核者是按任务挂载的临时角色，不形成常驻管理层。

- 主控：阶段顺序、跨域接口、公共合同、资源、冲突、项目Git/external总门和需要用户决定的选项。
- 领域owner：本域权威、current实现与证据、任务树和上下游；在批准目标内调查、拆分、签发本地阶段包、验收和路由必要Review。
- 执行者：消费冻结授权，实施、测试、自检并主动回唯一owner；无产品、范围、Git或external批准权。
- 审核者：独立取证并签发指定维度verdict；无默认候选写权、调度权或阶段权。

本域、可逆、无公共合同变化由领域owner闭环。跨域、公共合同、阶段路线、领域冲突或高不可逆风险回主控。单域产品决定由持有权威的领域owner直接向用户说明候选与代价；主控只整合跨域产品决定、重大公共方案、项目阶段和外部动作，不重复领域日常审核，也不越过领域owner指挥其执行者。

## 2. 生命周期与档位

任务概念生命周期：

```text
BACKLOG → READY → IN_PROGRESS → REVIEW → APPROVED → MERGED → VERIFIED → CLOSED
                           ↘ CHANGES_REQUESTED ↗
任意进行中状态 → BLOCKED / CANCELLED
```

稳定内容已提交但仍等待独立external状态时，任务保持active；不得把commit冒充发布完成。外部成功后记录真实结果再关闭，失败则记录`BLOCKED`与真实状态。

档位：

- `MICRO`：四维均低、单领域、同turn闭合、直接可验证、无公共合同/持久状态/external/并行owner冲突。owner可直接执行，默认无完整卡、临时执行者或独立Reviewer。跨turn、阻断或扩面立即升`STANDARD`。
- `STANDARD`：普通低/中风险功能、缺陷或跨turn工作。使用紧凑热卡或等价current对象；至少包含目标/非目标、owner、风险、exact/forbidden、验收、验证、Git/external和下一动作。
- `CRITICAL`：跨域公共合同、复杂状态机、核心循环、持久状态、平台/runtime、账号/发行、不可逆动作或高失败代价。需要完整影响闭包、稳定候选、依赖/验证上限和合格独立审核。

四维风险为影响范围、行为复杂度、依赖数量和可观察性；另考虑失败代价。不得只按文件数、行数或任务名称降档。不确定性本身是升级理由。

## 3. 可达性与事实基线

在设计和验证前把问题分类为：

- `CURRENT_REACHABLE`：当前producer、入口和生命周期真实可达，或已有可复核trace/repro。
- `CONTRACT_REACHABLE`：公共合同允许，但current自然生产链没有入口。
- `FUTURE_ONLY`：仅属于未来能力，不阻断current候选。
- `UNVERIFIED`：现有证据无法证明。

`CURRENT_REACHABLE`按玩家/运行影响选择集成、browser、device或玩家证据；`CONTRACT_REACHABLE`默认用最窄direct/contract反例；`FUTURE_ONLY`路由未来任务。不得只因理论可能就制造假producer、假UI或重型设备门。

搜索先建立有限注意力地图：权威定义、producer、direct consumers、状态写入者、测试、runner、docs和已知入口。搜索命中不是事实；结论必须回到完整原文、真实实现、调用链或运行证据。

权威冲突时先判断对象是否current、是否同一职责、是否已被supersede。不能从聊天、旧报告或迁移线索覆盖current机制。无法消歧时保持只读并回owner。

## 4. 改前范围闭包

资源选择使用四档`OWNER_FRONTIER / FOCUSED_HIGH / ROUTINE_BALANCED / MECHANICAL_LOW`。任务只在非默认时记录最低质量、必要工具和连续性；宿主按真实任务风险分配，不创建binding文件、digest或第二资源真相。不能满足最低要求时保持未分配并回owner，不静默降级。

复用其他任务或owner的结果前，必须在实际消费点核对project、domain、owner、role与task lineage；无需为此创建长期carrier或checker。问题、事实、推断、建议和决定分开：建议变化必须给出新增事实或明确说明先前判断为何错误，不能只随用户语气改变。

统一语言只治理稳定概念，不要求普通任务维护全量词典。每个稳定概念由项目或领域权威给出canonical term与authority locator；中文产品术语、英文代码标识和UI文字可以不同，但必须有可定位映射。新稳定概念先由领域owner定名再进入代码；改名必须列出direct consumers，旧alias必须有owner和退出条件。普通任务不记录`Terminology impact=NONE`，只有新增绑定或改变既有概念时记录`Terminology impact=BIND / CHANGE`及对应locator。只有改变玩家可见含义或产品语义时才请求用户决定。

任何写入前冻结：

1. 目标行为、当前行为和明确不改变的相邻行为；
2. exact paths与禁止路径；
3. producer、direct consumers、tests、runner/manifest和必要docs；
4. conditional contingency：只有literal证据触发时才允许进入的备选路径；
5. 项目`routineExcludedPaths`、任务exact/forbidden和其他owner字节边界；
6. 验收、验证上限、Git/external状态和唯一下一动作；
7. 与档位相称的pre-mortem及每项对应检查。

`MICRO`可在当轮明确这些事实而不建卡；`STANDARD / CRITICAL`必须有可恢复热对象。影响面未知时先只读调查，不把猜测写成contingency。

路径使用workspace相对规范化形式；拒绝绝对路径、`..`、ADS、保留名、尾随点/空格、大小写或Unicode碰撞。范围只包含本任务需要改变或验证所有权的对象，不用全仓manifest证明普通局部修改。

## 5. 方案标准

方案至少回答：

- 问题根因和为什么当前producer能到达；
- 单一真相、写入者、读取者、调用顺序和数据生命周期；
- 成功、失败、取消、中断、恢复和清理路径；
- 公共接口/状态/数据形状是否改变；
- 对玩家、用户、运维或外部阶段的可观察变化；
- 为什么不需要更大的抽象、兼容分支、第二状态或新服务；
- 直接证据如何证伪方案。

优先修根因并融入现有结构。不得用兼容分支掩盖错误抽象、复制第二套真相、为未来假需求增加持久状态，或把调用侧准入错误塞进纯计算/布局管线。

重大方案/公共合同先经过用户或项目主控规定的方案门；确认后领域owner可在冻结范围内签发本地实施包，不逐文件回主控或用户。

阶段技术证据不自动等于阶段完成。只有会推进项目或多领域里程碑的`CRITICAL`父任务才标记`Phase gate: TRUE`，并按“技术证据 → 领域合同核对 → runtime/platform适用性 → 项目主控签署 → 用户最终门”闭环。普通实现卡、聚焦Review卡和不承担阶段推进的`CRITICAL`卡使用`Phase gate: FALSE`，不增加验收链。

- 技术执行者或Reviewer只生产稳定证据与结论，不取得产品合同或阶段签署权。
- 领域owner核对其稳定产品/设计合同是否完整兑现；这是合同完整性检查，不重复用户已完成的主观试玩。
- runtime/platform仅在阶段确有运行、设备、发行或环境适用性时验收；不适用必须给出简短原因，不制造空审核。
- 项目主控在前置项闭合后签署跨域阶段ready；用户只确认产品结果、阶段推进或其明确保留的最终决定。
- 证据争议、范围漂移或新产品取舍回相应owner；不为无争议证据再创建一名fresh Reviewer。

验收链规定的是阶段字段的闭合顺序，不规定技术Review与用户试玩的实际先后。owner按风险与总成本选择：试玩便宜且容易提前发现产品问题时先试玩，避免审核无效候选；技术安全性或试玩准备依赖审核时先Review再试玩。只要stable candidate、用户决定和适用范围未漂移，项目签署后可把已有用户证据绑定到`User final gate`，不得机械要求用户再次确认；`CONFIRMED`必须携带与任务`current_exact`逐字一致的candidate。候选或用户决定变化时，该门回到`PENDING`并重新经过相应用户门。

## 6. 实施纪律

1. 写前复证当前授权包、对象identity、其他owner边界和实际dirty状态。
2. 只改授权exact；发现第N+1路径或职责变化立即停止，不先写后补卡。
3. 不覆盖、回退、清理、格式化或暂存范围外字节。
4. 新行为必须有direct coverage；已有测试绿不能代替新增行为证据。
5. 改动有机进入现有结构，检查命名、单一真相、错误语义、数据流、热路径分配和清理。
6. 额外发现分类为范围内阻断、范围外current问题、future问题或卫生建议；不无限扩大当前任务。
7. `DIRECT_USER_FEEDBACK_REQUIRES_OWNER_REBIND`：用户反馈或反例使同一candidate旧READY与旧授权包失效；反馈本身不授writer。只读定位后，唯一owner重新冻结actor/actions、exact、对象identity与current用户决定并重新签发，执行者不得直接续写。

无必要不新增报告、关系图或第二状态对象。只有多个长期consumer、lineage证据或大型审计确有净收益时才建独立报告；先说明consumer、改变的决定和现有记录为何不足。

## 7. 任务对象与current/history

热卡只保存current责任、稳定对象/section、权限、边界、验收、验证上限、未验证、阻断和唯一下一动作。建议目标10–20KB，不以字节门机械删掉必要权威。

完成过程、旧manifest、过期actor、历史审核长文和已supersede方案进入：

- Git commit/blob；或
- 单一只读history carrier，标记`NON_CURRENT / AUDIT_ONLY / NO_AUTHORITY / NO_ACTION`并与热卡双向locator。

历史迁移必须逐字或有可复核重组证明；carrier不能成为第二current。现存legacy大卡只在自然写边界、owner授权且不会打断在审对象时收薄；1.5升级不批量重写库存。

普通控制字段变化使用字段/section revision、限定diff或known-exact delta判断，不以whole-file SHA变化自动宣告内容对象失效。公共合同、候选内容和发布manifest仍使用稳定内容身份。

## 8. 委派、资源和Review路由

只委派边界清楚、可独立验证、写入互斥的工作。总体方案、未批准取舍、强耦合核心逻辑、脏工作树整合和最终跨域判断仍由长期owner承担。

临时执行者不继承旧任务权限；每次绑定新的task、owner、actions、exact、identity、用户门和停止线。输出是证据输入，不自动成为项目事实。

资源按最低充分质量选择：owner/重大跨域判断用frontier；聚焦分析、客观验收和fresh Review用高质量聚焦档；机械工作只有在自然样本证明缺陷率与返工率不恶化后才下调。资源不足、理解偏差或返工上升立即回升。

需要独立Review时，owner一次冻结reviewer、stable candidate、依赖、验证上限、允许的一次限定返工、轮次上限和停止线。范围内finding可直返，不要求owner逐轮转述；范围/产品/公共合同/owner/权限/质量底线、同一finding复发或轮次用尽立即回owner。

## 9. 沟通、交接与停止线

执行者稳定完成、真实阻断或范围冲突后主动向唯一owner完整回传一次，然后停写。任务final、侧栏完成或idle不等于回传，也不需要owner轮询或ACK才能停写。

用户汇报默认只包含：结果、剩余/未验证、是否需要操作和少量证据上限。SHA、manifest、actor和机械细节留控制面，除非用户要求或它们就是阻断原因。

以下任一出现立即停止并回owner：

- exact外路径、对象漂移或其他writer介入；
- 产品/公共合同/跨域职责变化；
- owner、签发者、执行者、权限、任务禁止边界或日常排除冲突；
- 无法维持direct coverage、原子性或单一真相；
- 同一Review finding复发、轮次上限或新独立性问题；
- 需要未授权Git、push、device或external动作。
