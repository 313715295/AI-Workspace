# Framework 1.6.0 FULL_RELEASE规划

状态：`DRAFT_RANGE / NOT_CONSUMABLE / A_C_G_ROUTE_004_CONTROL_FREEZE / WRITER_NONE / REVIEWER_NONE`

- baseline：Framework 1.5.2 `STABLE / OPT_IN`；稳定目录永久只读。
- 发行类型：`FULL_RELEASE`。
- 用户决定：2026-08-13，用户确认按主控建议将原1.5.3功能路线调整为1.6.0完整发行。
- 减重决定：2026-08-14，用户确认在不削弱owner/writer、authorization、protected path、controller epoch、preimage、remote真实结果和fail-closed边界的前提下，删除重复表示、默认字段展开、自动remote retry/compensation和无条件高成本门；先重新冻结范围，再一次性实现，不在旧candidate上继续补丁。
- 减法审计决定：2026-08-15，用户接受一次只读减法设计审计结论。`A_C_G_LEAN_CANDIDATE_004`停止补丁并转为`NON_CURRENT / AUDIT_ONLY / NOT_AN_IMPLEMENTATION_BASE`；1.6.0保留必要安全不变量，但删除没有真实宿主消费者、由既有规则可承载或重复证明同一事实的机器机制。
- Route-003决定：2026-08-15，用户接受Review-2后的`REDESIGN + SIMPLIFY`。`A_C_G_MINIMAL_CANDIDATE_002`冻结为`CHANGES_REQUESTED / NON_CURRENT / AUDIT_ONLY`，不得继续按finding追加条件；新路线保持原exact39工作inventory但把protected-path语义producer、自动清理算法和产品决定路由视为整单元替换，形成新candidate identity，不新增候选目录、角色、审批、账本、checker或用户步骤。
- Route-004决定：2026-08-15，用户明确选择按真实威胁模型继续减法：把通用protected-policy降为项目`routineExcludedPaths`日常排除；Framework升级只支持current controller主持的独占维护窗口，不支持升级期间并发控制写；取消升级脚本内递归自动清理，保留可审计恢复材料；同时把历史“统一语言”迁移缺口纳入1.6.0现有治理模块。Route-003 partial delta不是实现基线，必须整体重冻后才能继续。
- 当前对象：本规划与同目录`VERSION.json`只建立版本路线，不构成模块、脚本、starter、register、upgrade、项目pin、Git或发行授权。
- `framework/CURRENT`、所有项目pin、正式version inventory均保持不变。

## 1. 为什么不是1.5.3功能版

多remote批次、协调治理、知识resolver、starter骨架与register/upgrade迁移均可能改变公共合同、模块inventory或根事务。按当前发行规则，这些属于`FULL_RELEASE`，不能包装成兼容`PATCH_HOTFIX`。1.5.3只在未来出现真正兼容热修时使用；否则跳过。

## 2. 已确认规划分片

### A. 日常Git排除与简单多remote动作

- `.ai-workspace/project.json` schema 3只保存`routineExcludedPaths: string[]`。它表示日常恢复、搜索、Git概况、diff建议和批量暂存不得展示或操作这些路径；它不是机密性、操作系统权限或source写授权。source读取/写入继续由current任务的exact/forbidden与owner授权承担。
- 路径只接受规范repo-relative字面文件/目录定位符，拒绝root、绝对/越界、空组件、`.`/`..`、ADS、尾随点/空格、非NFC及大小写碰撞。这里复用现有安全相对路径规则，不建立deny能力矩阵、glob语义、`ProtectedPolicy.psm1`或第二套路径语言。
- 日常Git入口只接受枚举操作、bounded positive pathset、固定project config identity并自动附加项目routine exclusions；禁止`git add .`和调用者临时扩大范围。被排除路径不得出现在返回结果、暂存或提交建议中；Git可能为计算状态内部观察tracked metadata，因此本能力只承诺“日常不展示/不操作”，不宣称零内部读取。
- 如果当前Git操作不能可靠避免把排除对象带入结果或动作，返回不含该locator的`UNVERIFIED`，不靠结果净化、统计重试或扩大扫描冒充完整整仓事实。用户明确要求处理排除文件时，由current owner另签fresh exact单路径Git包；完成即恢复日常排除。
- 新项目register只写默认空列表，不扫描source工作树。schema 2旧项目升级消费任务冻结的`routineExcludedPathsMigration`，只把明确列表写入schema 3；它不从历史聊天、Git状态或source扫描推导排除项。
- 同一repo向多个remote推送不建立`RemoteBatch`持久DTO、schema、ledger或专用checker。Git/external任务直接冻结stable candidate、唯一Git closer、明确remote/ref清单和一次阶段授权；每个remote最多尝试一次并逐项记录真实`SUCCEEDED / FAILED / UNKNOWN`，整体只作现场摘要。
- 重试重新读取current head并取得fresh authorization；force、删除ref或撤销远端效果另签高风险external包。一个remote成功不得冒充全部成功。
- 旧`RemoteTransaction / PreviousLedger / COMPENSATION`合同保持不可消费；`A_C_G_LEAN_CANDIDATE_004`与更早candidate/root树只作审计输入。新的最小候选从stable 1.5.2与current root脚本重新冻结，不复制旧DTO/helper。

### B. 默认资源选择与显式例外

- 质量规则保持`OWNER_FRONTIER / FOCUSED_HIGH / ROUTINE_BALANCED / MECHANICAL_LOW`。owner与重大跨域判断用frontier，聚焦分析、客观验收和fresh Review用focused high；普通机械工作只有自然样本证明缺陷率和返工率不恶化后才允许下调。
- 默认任务不持久化资源矩阵。只有非默认minimum、必需工具或fresh/same-context约束才在任务卡记录简短需求；具体model/effort alias与现场可用性属于host adapter。
- 1.6.0不建立resource binding临时文件、resolver、digest、capability snapshot或authorization字段。宿主在dispatch/fresh rebind时按任务风险与显式例外选择资源；无法满足最低质量、工具或独立性时保持未分配并回owner，不静默降级。
- latency/cost/concurrency只在项目或任务明确设置非默认限制时记录。资源选择不增加普通MICRO/STANDARD的文件、checker调用或授权路径。

### C. 独立任务、等待、复用与归档

- 长周期领域工作优先使用可主动回传的独立任务；内部子agent只用于同一活跃回合内可闭合的短并行工作，不承担需要未来唤醒主控的长期职责。
- 不用轮询维持进度感。只有当前消费者确实依赖结果时，才允许一次有界状态快照或事件等待；任务完成、需要裁决或命中停止线时主动回传。
- 已完成任务按terminal状态归档；复用前必须重新核对项目、领域、角色、候选血缘、当前owner、生命周期、资源和路径冲突。
- 普通`INLINE / DIRECT_OWNER_DEFAULT / NO_POLL / TERMINAL_ONLY / userDecisionHandoff=NONE`是Framework默认值，不要求每张任务卡重复展开完整coordination contract；只有`INDEPENDENT_TASK`、有界等待、非默认report target或用户决定handoff才持久化差异。checker从默认与显式例外合成唯一effective contract。
- 独立任务中的用户决定必须在handoff携带`sourceTaskId + bound candidate/evidence + user原话或稳定turn locator + invalidatesOn`。主控本地上下文没有该回合，不等于用户未确认；在撤销或要求重复确认前必须先核对来源任务。反过来，只有推荐说明而没有绑定候选后的用户接受，也不能标成`USER_CONFIRMED`。
- `QUESTION_NOT_DECISION`：用户询问“能不能、是否可以、什么时候合适、你的建议是什么”只授权调查、可行性与利弊回答，不构成采用、排期变化、CONTROL_WRITE或writer启动。只有明确接受、选择或命令才可形成`USER_CONFIRMED`；不允许由“建议可行”推导“用户已决定执行”。

### D. peer任务复用的身份门

- 只有实际复用已有peer任务、跨项目路由，或project/domain/owner/role/review lineage无法从current注册关系证明时，才核对目标项目、repo/control root、领域、owner、lifecycle、独立性、exact冲突和外部权限。
- 该门复用现有Bootstrap、current任务和Review独立性事实，不新增`check-peer-task-reuse.ps1`、七字段carrier或常态持久化对象。无法证明匹配时新建正确任务或仅把跨项目输出作为`REFERENCE_ONLY`输入。
- fresh/current且注册关系明确的跨领域handoff继续走C/G紧凑字段；携带用户决定时再核对来源任务、绑定候选、原话/稳定turn locator与失效条件。
- 误路由立即STOP；其verdict为`INVALID / NON_CURRENT`。owner可独立采纳合理纠错，但必须重新走合法Review。

### E. 调查、修复与机制变化

- 继续使用`TASK_AND_SCOPE.md`与`REVIEW_AND_EVIDENCE.md`的既有规则：用户反例只授权只读调查并使旧READY失效，不授writer、不自动扩大路径。
- 用户询问“是否可行、何时合适、你的建议”不是采用决定。只有明确接受、选择或命令才改变排期、机制或授权。
- 既有权威、根因和修复边界明确时由领域owner按普通BUG闭合；只有权威、产品语义或机制确有歧义时才回用户。1.6.0不新增分类enum、任务字段或checker。
- 测试不得用候选补偿逻辑反向定义产品机制。
- `UNIFIED_LANGUAGE`：稳定概念必须在项目或领域权威中有canonical term与authority locator。中文产品术语、英文代码标识和UI文字可以不同，但必须显式映射；新稳定概念先由领域owner定名再进入代码，改名必须覆盖direct consumers，旧alias必须有owner与退出条件。普通任务不展开`Terminology impact=NONE`，只有`BIND / CHANGE`才在任务范围中记录；只有改变玩家可见含义或产品语义时才回用户。
- Review复用现有文档/代码验证检查同义多真相、同名异义、未声明alias、旧术语复活以及权威与代码映射漂移；不新增术语schema、checker、服务或强制全项目词典。

### F. 项目级与通用知识

- 项目知识固定`REFERENCE_ONLY / NON_AUTHORITY`，在Bootstrap、project pin、current任务和专业权威恢复后按需读取。
- 默认最多返回3条`CURRENT`；`STALE/HISTORICAL`不进入普通任务决策；每条具备locator、verifiedAt、invalidatesOn和tokenEstimate。
- 项目closure只产candidate；对应owner核验后才能成为项目知识。项目级知识的初始化、启用和维护由采用项目自己完成，不要求先存在第二项目，也不把项目内容复制进Framework。
- common知识晋升是1.6.0发布后的未来路线：至少两个独立项目自然复证且无反例，再由Framework maintainer fresh Review。两个项目届时必须各自满足至少6次自然查询、至少2个真实领域、零权威覆盖/越权错误、冻结的token/latency/命中与fallback成本指标；查询、候选、响应、owner核验与失败均绑定稳定identity、verifiedAt和invalidatesOn。单次成功查询、人工演示查询或跨项目复用同一批样本均不计作第二项目复证。
- 任一authority conflict、locator失效、STALE误入CURRENT、错误自动授权或未披露fallback均使对应项目批次`ADJUST/REJECT`；common聚合必须保留两项目的独立结果和失败，不得用总成功率掩盖单项目硬失败。
- 1.6.0只发行项目级知识基础能力，不发行common知识内容或跨项目聚合。该能力必须默认关闭，并把未启用、没有知识库和空索引作为正常状态；Pocket Legion在1.6.0发布并独立升级后，才按最终schema初始化内容、显式启用并在真实任务中开始自然采样。第二项目缺失和项目自然样本为0不阻塞1.6.0项目级能力实现、Review或发行，只阻塞未来common晋升。
- Pocket采用顺序固定为：升级pin/control schema → 配置`routineExcludedPaths` → 指定项目术语权威 → 基于项目权威与术语权威初始化知识内容 → 显式启用`KNOWLEDGE_REFERENCE` → 删除已上收Framework的本地重复规则 → FULL_COLD复证 → 恢复产品任务并开始自然采样。术语权威是项目authority，知识条目只能引用它，不能反向定义canonical term。
- loader保持既有`role + profile + phase + host`基础选择器，并新增唯一可选capability selector：`KNOWLEDGE_REFERENCE`。`resolve-load-plan.ps1`的公共接口接受零个或多个显式capability；默认空集合时不得加载知识模块，未知、重复或host不支持的capability必须fail closed，不能回落到 broad role/profile bucket。
- `KNOWLEDGE_REFERENCE`只把`KNOWLEDGE_AND_REFERENCE.md`及其schema/resolver contract追加到基础恢复计划之后，且每次最多一次；它只开放REFERENCE_ONLY读取协议，不自动查询项目索引、不创建索引、不改变authority或授予任何写/Review/Git权限。项目索引缺失、locator失效或与current authority冲突时resolver返回`REFERENCE_UNAVAILABLE`并继续以Bootstrap/pin/current task为唯一恢复链。
- 1.6.0发行成本门必须把基础plumbing与optional payload分账并用隔离fixture证明：`RECOVERY_CORE / PROJECT_CONTROL / HOST_CODEX / Bootstrap`等为识别capability、绑定config identity与失效WARM cache产生的默认固定bytes/token增量必须相对无knowledge的A-C+G 1.6.0基线单独冻结、报告并满足明确上限；未启用时不得向load plan追加`KNOWLEDGE_AND_REFERENCE.md`、knowledge schema、项目索引、条目或任何knowledge内容payload，因此该optional payload增量必须为0；显式selector启用后的新增payload另有冻结上限且稳定去重。fixture还必须覆盖未启用、无库、空索引、有效索引、locator失效、authority conflict与fallback。真实自然查询成本属于项目采用后的效用证据，不冒充Framework发行前机械验证，也不阻塞项目级能力发行。旧项目升级不自动启用capability，也不生成知识状态；只有项目采用任务显式配置并通过locator/authority复证后才能使用。
- 项目opt-in的唯一producer是`.ai-workspace/project.json` schema 3中的`frameworkCapabilities`对象。默认starter写空对象`{}`；启用时唯一合法项为`"KNOWLEDGE_REFERENCE": {"enabled": true, "indexLocator": "<repo-relative normalized path>"}`。缺字段、空对象或`enabled=false`均表示未启用；重复JSON key、未知capability、绝对/越界/非NFC locator或enabled却缺locator必须在Bootstrap调用loader前fail closed。
- `.ai-workspace/BOOTSTRAP.md`严格读取project.json并把已启用capability的规范有序集合传给`resolve-load-plan.ps1 -Capability <set>`；未opt-in时显式传空集合或省略参数，结果必须等价。`RECOVERY_CORE.md`、`PROJECT_CONTROL.md`和`HOST_CODEX.md`同步把capability/config identity纳入调用与WARM重算合同；capability集合、project.json identity、index locator identity或LOAD_MANIFEST identity变化均使旧load plan/cache失效。

### G. 领域直达、主控按需拉取与汇报去重

- 默认路由固定为`DIRECT_OWNER_DEFAULT`：执行者回领域owner，Reviewer回候选owner，领域owner之间直接交接；`sourceTaskId`只提供来源定位，不自动把主控设为每条消息的抄送者。
- `USER_DECISION_DIRECT`：需要产品决定时，由持有对应专业权威的领域owner在自己的独立任务中直接询问用户。用户答复必须绑定候选/证据、原话或稳定turn locator和失效条件，再写入对应专业权威并直接路由下游；不要求先经主控转述或重复确认。
- `CONTROLLER_PULL`：项目主控通过任务索引、current任务卡、writer/reviewer、授权包和独立任务状态按需编排。领域owner必须把可供编排的current状态、唯一下一动作和停止线持久化到任务卡；只存在于聊天的状态不能作为主控可靠输入。
- 热任务卡只保留current owner/candidate/authorization、验证上限、真实阻断和唯一下一动作；已消费授权、旧Review轮次和过程证据进入稳定history locator或Git对象，不在热入口复制第二状态。默认资源/协调字段由Framework合成，不以展开文本制造identity漂移。
- `EXCEPTION_ONLY_ESCALATION`：只有共享写路径/唯一writer冲突、owner失联或职责无主、控制面/授权损坏、保护路径事件、跨领域合同死锁、项目级Git/external冲突，或用户明确要求主控协调时，才主动上报主控。普通`READY / PASS / HOLD / CONSUMED / OWNER_ACCEPTED / HANDOFF_SENT`不构成主控通知事件。
- `SINGLE_TERMINAL_REPORTER`：同一工作链只允许当前责任owner在用户可复玩、需要项目级裁决或整链终结时发一次主动摘要。下游“已消费/已接受”若未改变用户门、跨域范围或项目状态，不得再次转发。
- `CONTROLLER_EPOCH`：每个项目持久化唯一current controller identity、单调递增epoch和lease/transition状态。successor完成FULL_COLD并明确ACCEPT前旧主控仍是唯一权威；原子pointer commit同时递增epoch、切换identity、重绑长期owner的exception target并关闭旧主控新任务入口。旧主控仅有read-only grace，successor确认后才archive。
- current controller的唯一规范对象是`.ai-workspace/controller.json` schema 1；最小字段固定为`projectId / controllerId / controllerEpoch / state=CURRENT`，整个文件采用canonical UTF-8/LF JSON，`controllerControlIdentity=<bytes|SHA256 of the entire file>`。该小文件只在初始化或主控原子轮换时变化；`STATUS.md`和tasks index只能保存locator/热摘要，不能复制第二个current controller/epoch权威。唯一producer是current PROJECT_CONTROLLER主持的rotation transaction；successor只能在FULL_COLD ACCEPT后参与原子commit。
- 任何`issuerRole=PROJECT_CONTROLLER`的authorization必须逐字绑定`issuerControllerId + issuerControllerEpoch + controllerControlIdentity`，并满足`issuer == issuerControllerId == controller.json.controllerId`、epoch与整个controller.json identity逐字相等。新增三字段只对`PROJECT_CONTROLLER`条件必填；`DOMAIN_OWNER`分支不得要求、推导或消费它们。checker在校验task/path/action/object后读取唯一controller.json、严格解析并自己计算identity；旧epoch、旧controller、旧control identity、issuer不等或缺失条件字段统一返回`STALE_CONTROLLER_AUTHORIZATION`。
- 原子pointer/epoch commit同时撤销所有尚未消费的旧`PROJECT_CONTROLLER`包：旧包只保留`NON_CURRENT / AUDIT_ONLY / NO_ACTION`证据，不自动重签或继承到successor。successor必须基于current task、owner、exact和用户决定另签新包；轮换中in-flight动作若未产生不可逆效果则停止，若已产生效果则诚实记录receipt并按新epoch另行决定恢复/补偿。
- checker公共输入增加唯一`ControllerControlPath`（仅PROJECT_CONTROLLER包时必需）；宿主PASS digest/cache必须包含authorization package identity、controller.json path+identity及原actor/task/action/path/object键，controller identity变化立即失效。调用者提供的摘要不能替代checker实际读取和计算。
- 新项目register要求明确`ControllerId`并生成epoch 1 controller.json。旧项目升级在同一可恢复事务写project schema 3、受管Bootstrap/pin和controller.json；不枚举legacy authorization、不生成revocation ledger。1.6 checker按`frameworkVersion`使全部旧1.5包不可消费，current owner只为仍需继续的工作签fresh 1.6包；进入1.6后的controller轮换再由epoch仅失效PROJECT_CONTROLLER包，不误伤current DOMAIN_OWNER包。
- 1.6升级只在current controller声明的独占维护窗口运行：进入前writer/reviewer/Git/external与其他控制写均为NONE，已有事务目录即拒绝第二次启动。脚本复用现有可恢复事务骨架并显式覆盖`project.json / BOOTSTRAP.md / controller.json`，保存旧/新exact3、顺序写入并在结束时统一复证；中断或未知状态保留恢复材料并停止。它不支持维护窗口内并发控制写，不建立第二套`Minimal16`事务引擎、capture/quarantine双树、锁服务或对抗性并发状态机。
- register/upgrade不在脚本内递归自动清理恢复材料。成功后材料保持`COMPLETED / AUDIT_ONLY`直到采用项目完成FULL_COLD；其后的精确housekeeping是项目采用任务的收尾，不影响升级成功，不引入Windows原生handle API或自动清理器。
- controller-directed消息在实际宿主能够提供时携带`projectId + controllerId + controllerEpoch + sourceTaskId + candidate/state`；接收者先与current controller/task核对。旧epoch routine只作`STALE_QUEUED / AUDIT_ONLY`，decision/authorization/ACK拒绝，exception在current task复证后最多重路由一次且不得复用旧授权。
- 1.6.0不建立route JSON、route ledger或`check-controller-route.ps1`。没有真实host/router消费入口前，route checker测试不能冒充已交付的消息强制能力；文本路由规则与controller/authorization机器门分别承担其真实边界。
- `NO_ACK_CHAIN / STATE_DEDUP`：主控不为普通交接逐条ACK；在current epoch内以`projectId + controllerEpoch + taskId + candidate/state transition + responsible reporter`去重。同一状态被执行者、owner和上游owner重复发送时，只保留责任owner的一份，不形成新的控制动作；stale epoch永远不参与current dedup状态。
- 独立任务仍可直接向用户展示问题和结论；“主控按需拉取”不等于隐藏用户决定，也不允许通过减少汇报省略任务卡持久化、停止线或错误披露。
- 发行验证至少包含：领域owner直接问用户且主控无需中转；普通交接不通知主控；重复终态不形成新控制动作；任务卡未持久化current状态时主控pull fail closed；真实例外仍上报；successor ACCEPT前后权威切换、原子pointer/epoch commit、旧controller authorization拒绝与DOMAIN_OWNER兼容。纯消息路由只验证文本/fixture边界，不宣称host强制。

### H. 项目采用后的去重瘦身

- Framework 1.6.0发布不自动修改任何项目。每个项目升级仍需单独的采用任务、pin修改、迁移验证与FULL_COLD恢复；只有项目确认新Framework合同已真实可消费后，才可建立后续瘦身任务。
- Pocket Legion在成功升级1.6.0后，先指定项目术语权威并初始化/启用项目知识，再安排独立`PROJECT_CONTROL / KNOWLEDGE_GOVERNANCE`瘦身阶段。该阶段不由Core、Design、Art或Framework发行writer顺手执行，也不与pin升级共用writer或Review。
- 瘦身复用现有`TASK_AND_SCOPE / REVIEW_AND_EVIDENCE / GIT_AND_EXTERNAL`建立Pocket专属任务，不新增公共`PROJECT_SLIMMING_TEMPLATE.md`或Framework自动清理器。
- 项目任务先映射Framework重复、项目特例、产品权威、current证据、历史和失效控制对象，再精确决定保留、归档或删除。产品/机制权威、保护规则、current任务、玩家反例和仍被consumer读取的locator不得借瘦身删除。
- 明确`NON_CURRENT / NO_ACTION`的临时授权、机械历史和重复摘要可按exact owner/Git门闭合；权威、保护或current对象仍按风险进行独立Review和FULL_COLD复证。

## 2.1 DRAFT_CONTROL候选inventory与消费者矩阵

下表冻结未来`framework/versions/1.6.0/`候选的最小提议inventory。既有路径表示必须评估并按需要修改；`ADD`表示新公共对象。implementation owner可以证明某项由既有对象完整承载后删减`ADD`，但任何新增职责路径、漏掉的direct consumer或范围扩大都必须回RANGE_GATE，不能由writer顺手决定。

| 分片 | 公共合同与主落点 | starter/template/host消费者 | checker与正反例 | migration/兼容责任 |
|---|---|---|---|---|
| A | `GIT_AND_EXTERNAL.md`、`ADD PROJECT_CONFIG_SCHEMA.json`；多remote只保留简单逐项结果合同，不建立DTO/schema/checker | `project-starter/project.json` schema 3唯一承载`routineExcludedPaths`字符串列表；Git/external任务按既有任务字段冻结remote/ref和真实结果 | `ADD scripts/invoke-protected-safe-git.ps1`只消费固定config、bounded positive pathset与routine exclusions；覆盖不展示/不操作、exact单路径例外、失败→UNVERIFIED和禁止整仓暂存；删除`ProtectedPolicy.psm1` | register默认空列表；upgrade只消费冻结migration列表，不扫描source或推导排除项；旧事务树不可消费 |
| B | `TASK_AND_SCOPE.md`、`HOST_CODEX.md` | 仅非默认minimum/tools/continuity按需进入任务；无binding临时文件 | 无新resolver或authorization字段；通过宿主选择、任务证据和Review独立性核对，不能声称机器锁定模型 | 旧卡不批量补字段；无资源binding迁移或cache |
| C/G | `PROJECT_CONTROL.md`、`RECOVERY_CORE.md`、`AUTHORIZATION_MODEL.md`、`HOST_CODEX.md`、`ADD CONTROLLER_SCHEMA.json` | 默认协调快路径、显式handoff例外、`ADD project-starter/controller.json`；STATUS/index只留locator | `scripts/check-task-card.ps1`与`scripts/check-authorization.ps1`闭合任务/授权；不新增route JSON/checker | register建epoch 1；upgrade原子写controller/pin/bootstrap/config，不建legacy revocation ledger；旧1.5包由version门失效 |
| D | `PROJECT_CONTROL.md`、`TASK_AND_SCOPE.md`、`HOST_CODEX.md` | 实际peer复用时读取current目标任务；普通handoff不建carrier | 复用既有project/task/Review事实，无新checker | legacy任务不批量重写；误路由只作REFERENCE_ONLY并重新合法路由 |
| E | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md`、`PROJECT_CONTROL.md` | 问题与决定边界用既有任务/current用户证据；仅术语`BIND / CHANGE`记录canonical term、authority locator、映射与alias退出 | 不新增checker；Review用真实反例核对既有权威、机制变化和统一语言漂移 | legacy结论与术语不批量追溯改写；项目在采用1.6后指定current术语权威 |
| F | `ADD KNOWLEDGE_AND_REFERENCE.md`、`ADD KNOWLEDGE_SCHEMA.json`、`RECOVERY_CORE.md`、`PROJECT_CONTROL.md`、`HOST_CODEX.md`、`LOAD_MANIFEST.json` | `scripts/resolve-load-plan.ps1`新增显式`KNOWLEDGE_REFERENCE` capability；`project-starter/project.json` schema 3是唯一opt-in/locator producer；`project-starter/BOOTSTRAP.md`负责严格解析与传参；`TASK_TEMPLATE.md`承载knowledge evidence | `ADD scripts/check-knowledge-entry.ps1`、resolver/loader/Bootstrap/host cache tests覆盖default-empty、no-library、empty-index、configured enable、not-opted-in、unknown/duplicate/unsupported、invalid locator、explicit-once、WARM invalidation、authority conflict与fallback；成本测试分别冻结基础capability plumbing默认增量上限、未启用optional knowledge payload增量=0、显式启用payload独立上限与稳定去重；fixture不冒充自然样本 | register默认`frameworkCapabilities={}`；旧项目升级schema但不自动启用、创建索引或生成知识状态，项目采用任务在建立有效索引后显式写配置并复证locator后opt-in；common内容和两项目自然证据不进入1.6.0 release manifest |
| H | `FRAMEWORK_RELEASE.md`、`MIGRATION_MATRIX.md`中的采用后边界 | Pocket项目先配置日常排除、指定术语权威、初始化并启用项目知识，再按现有任务合同另立瘦身任务 | 权威/current删除走独立Review+FULL_COLD；明确NON_CURRENT机械清理和完成恢复材料走exact owner+Git门 | 不新增公共slimming/术语模板；只删除Framework已覆盖重复，保留项目特例与权威 |
| 全局 | `README.md`、`VERSION.json`、`LOAD_MANIFEST.json`、`RELEASE_MANIFEST.json`、`CHANGELOG.md`、`STATIC_COMPARISON.md` | 全角色load closure、root register/upgrade、project.json schema 3、热卡current/history分离 | `tests/run-framework-tests.ps1`、strict文本、inventory/hash、load budget、protected-safe Git、旧事务有效引用零残留、失败恢复；不为删除的自动retry/compensation保留伪测试义务 | 完整版本与项目迁移矩阵；Git/release/CURRENT/project pin继续分包 |

迁移矩阵必须覆盖已验证布局的直接来源版本`1.4.1 / 1.5.0 / 1.5.1 / 1.5.2`；更早版本先迁到1.4.1，或以单独兼容任务证明直接路径，不能无证据宣称支持。若1.6.0开发期间发布兼容1.5.3 hotfix，candidate必须在发行前明确选择并证明：以1.5.3为新baseline forward-port/rebase，或将当前candidate标记失效后重新冻结；不得让1.6.0静默覆盖1.5.3安全修复。

## 2.2 减法审计经验的长期落点

- 1.5.2已经在`RECOVERY_CORE / TASK_AND_SCOPE / REVIEW_AND_EVIDENCE`规定聊天非权威、改前producer/consumer/test闭包、单一真相、最小机制、Review轮次上限和同一finding复发停止；这些属于本轮未严格执行的既有规则，不复制第二份正文。
- 1.6.0补充五项缺失澄清：owner改变建议必须指出新增证据并区分事实/推断/建议；同类finding复发后必须在`SIMPLIFY / REMOVE / DEFER / REDESIGN`中重新裁决；没有真实调用入口的checker不能作为已交付能力或release证据；局部日常排除不得冒充通用安全系统；升级安全首先来自独占维护窗口，脚本不为合同禁止的并发写入建立常态复杂度。
- 上述通用澄清分别进入现有`PROJECT_CONTROL.md`和`REVIEW_AND_EVIDENCE.md`，具体protected locator、controller、资源、remote与迁移取舍留在本PLAN及其既有专业模块。不得新增“经验教训文档”、长期记忆系统或每版强制减法审计门。
- 任何后续建议改变若没有新增事实，只能明确承认并纠正先前判断，不能用新的流程对象掩盖推荐摆动。

## 3. 实施与发行顺序

1. `DRAFT_CONTROL`：持久化本次减法决定并冻结新的最小inventory/consumer/test/migration矩阵；writer保持NONE。
2. `MINIMAL A-C+G REBUILD`：candidate004及更早实现树只作审计输入；candidate002只保留冻结identity/verdict。Route-004从当前minimal树整体移除deny-policy/`ProtectedPolicy.psm1`与第二套`Minimal16`并发事务，落入`routineExcludedPaths`和独占串行升级；D/E的直接路由、建议纠错与统一语言短规则并入既有模块，不新增职责路径。
3. `F`：实现默认关闭的项目级knowledge contract/schema/resolver/loader/checker/starter/迁移；闭合未启用、无库、空索引和fail-closed，不实现common内容或跨项目聚合。
4. `INTEGRATION`：复证完整inventory、LOAD_MANIFEST、全角色加载闭包、register/upgrade事务、迁移矩阵、静态成本、旧项目兼容、strict文本、protected-safe Git和失败恢复；没有真实producer/consumer的checker不得进入release inventory。
5. `REVIEW`：每个实现分片在writer前冻结一次完整闭包矩阵；writer释放后由fresh Reviewer审核固定对象。只允许一次合并后的bounded remediation和一次final Review；同类finding复发时必须在`SIMPLIFY / REMOVE / DEFER / REDESIGN`中重新裁决，不能再签局部补丁。
6. `RELEASE`：内容批准、正式version生成、测试、Git、tag/push、CURRENT和项目升级分别授权；任何一步不推定下一步。
7. `PROJECT ADOPTION`：Pocket Legion另立升级任务，预览迁移并显式改pin/control schema；配置仅`level_test2.js`的`routineExcludedPaths`；指定项目术语权威；基于权威初始化项目知识并显式启用`KNOWLEDGE_REFERENCE`；Framework发布不自动采用。
8. `H / POST-UPGRADE SLIMMING`：Pocket删除已由1.6.0上收的本地重复治理，保留项目特例、产品权威和current任务；精确关闭完成恢复材料，随后执行FULL_COLD。
9. `PROJECT RESUME`：FULL_COLD通过后恢复W1等产品任务，并从真实任务开始积累项目知识自然查询样本。

## 4. 当前停止线

- 不把1.5.2逐字baseline复制冒充已完成的1.6.0能力；但clean-baseline路线必须先逐字建立并证明lean树与stable 1.5.2/root source零漂移，再在同一冻结writer范围内应用明确delta。baseline、功能candidate与发行批准是三个不同事实。
- 不修改`framework/versions/1.5.2/**`、`framework/CURRENT`或任何项目pin。
- 不因本规划自动启动writer、Reviewer、Git、push、register/upgrade或外部动作。
- 不在`A_C_G_LEAN_CANDIDATE_004`或`A_C_G_MINIMAL_CANDIDATE_002`按finding继续局部remediation；它们只作审计输入。Route-004必须删除deny能力矩阵、`ProtectedPolicy.psm1`、第二套`Minimal16`并发事务、capture/quarantine双树和脚本内递归自动清理；不得以新helper、锁服务、术语checker或housekeeping框架替代被删机制。同类复杂度若再次回流立即停止实现并直接REMOVE/DEFER，不再开补丁Review链。
- 项目级knowledge公共合同、默认关闭、基础capability plumbing固定增量上限、未启用optional knowledge payload增量=0、显式启用payload独立上限、无库/空索引、locator/authority fail-closed、采用与迁移边界任一无法机械闭合，或任一公共合同仍依赖聊天事实时，1.6.0不得进入`REVIEW`。Pocket或第二项目自然样本缺失只禁止common晋升，不禁止本版项目级能力Review。
