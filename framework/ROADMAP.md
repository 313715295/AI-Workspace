# AI-Workspace Framework Roadmap

> 状态：`VERSION_INDEPENDENT / NON_CONSUMABLE / PLANNING_ONLY / SINGLE_FUTURE_POOL`
>
> 本文件是尚未选入具体发布版本的唯一规划池。它不授予项目写入、Framework发行、项目升级、Git、设备或外部动作权限，也不改变任何项目pin或`framework/CURRENT`。只有选定发布批次后，才把该批次的冻结范围投影到`framework/drafts/<target>/FRAMEWORK_PLAN.md`；已发布`framework/versions/<version>/`保持不可变。

## 路由规则

1. 每个条目只描述通用问题、期望结果、准入证据和停止线，不在这里复制实现设计或项目任务卡。
2. 进入版本draft前必须有明确maintainer、目标版本、依赖、范围、验证和独立Review路线；未选择版本的条目不得散落到稳定版本README或新建占位draft。
3. 已完成条目保留短结果与稳定locator；取消或被更小机制取代时记录原因，不保留并行规划真相。
4. 项目特例留在项目自己的`.ai-workspace/`；本文件只接收可跨项目复用的差额。

## 当前执行批次

### FRAMEWORK_MAINTENANCE_SIBLING_TARGET_TOPOLOGY

- 状态：`COMPLETE / STABLE_1.7.0 / NOT_CURRENT`
- 问题：当前1.6.1把项目控制面、Controller、路径授权和Git top绑定在同一repo-local仓，导致Framework源码/发行对象与维护Framework的项目控制状态混在同一个Git仓；直接把控制面移到平级维护仓会使Bootstrap、授权和安全Git入口失效。
- 目标：保留普通项目repo-local默认模式，新增仅用于Framework维护的单一平级目标布局。专用父目录只作workspace边界；`AI-Workspace-Maintenance`持有唯一动态控制面，`AI-Workspace`只保存Framework和静态保护入口；每个授权包绑定一个repository ID，两个Git top、dirty和Git closer分别验证。
- 目标版本：`1.7.0 / MINOR`；用户决定=`USER_2026-08-16_APPROVED_FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY_AND_CONTROLLER_ARRANGEMENT`；任务=`.ai-workspace/tasks/active/AIW-FRAMEWORK-MAINTENANCE-TOPOLOGY-001.md`。
- 结果：stable 1.7.0已完成候选Review、稳定投影、direct tests和Release Review；提供最终平级双仓稳态合同，保持普通repo-local回归，并继续拒绝错误目标、reparse、漂移及跨仓越权。
- 项目迁移边界：真实AI-Workspace物理分离不属于Framework runtime。当前项目采用“先发布Framework、再全新clone目标仓、最后独立建立Maintenance控制面”的项目专属路线，不复活通用cutover状态机。
- 停止线：不扩成任意跨仓管理、多目标事务、后台服务或consumer写入；stable 1.7.0保持不可变和`NOT_CURRENT`；目录迁移、Git publication、CURRENT和consumer采用分别授权。

### CURRENT_ELIGIBILITY_AND_POINTER

- 状态：`COMPLETE / ROOT_CONTRACT_VERIFIED`
- 问题：稳定发布与选择`framework/CURRENT`是两个原子动作，但历史`currentEligible=false`发布快照会与已稳定、可消费、可pin的真实状态产生歧义。
- 目标：根级选择合同只依赖`STABLE + consumable + projectPinEligible + valid starter/register smoke`；旧稳定版本中的`currentEligible`只作为不可变发布时快照，不作为live selector。未来发布移除该冗余字段或赋予单一、可验证语义。
- 准入：不修改已发布版本；根README与选择流程语义一致；新项目默认注册smoke通过；CURRENT切换可独立Review和回退。
- 停止线：不得因为切换CURRENT自动修改任何已有项目pin。

### CURRENT_1_6_1_SELECTION

- 状态：`COMPLETE / CURRENT_1.6.1`
- 问题：`1.6.1`已稳定、可消费、可pin，但根CURRENT仍指向`1.4.1`。
- 目标：先让已批准的stable 1.6.1与live-root/register/INITIALIZATION发布对象成为任何pointer Git提交的祖先；再在根合同闭合、显式1.6.1新项目register smoke及独立Review通过后，把`framework/CURRENT`投影到`1.6.1`，并只同步必要根入口。指针投影与Git提交保持分离授权。
- 准入：stable 1.6.1 identity无变化；显式版本register preview/apply/repeat通过；exact3投影后，在全新Git仓省略`FrameworkVersion`完成CURRENT-default preview/apply/repeat并验证schema3/controller/starter；随后focused post-projection独立复审通过；根README准确。以上全部PASS后，才可另门批准exact3 Git commit。
- 停止线：任一post-projection smoke或复审失败即不提交并把CURRENT恢复/重冻到已审preimage；不得新建1.6.2、修改`framework/versions/1.6.1`、自动升级项目，或让pointer提交指向其祖先中不存在的发布对象。

## 未选版本的通用差额

### POWERSHELL_7_KNOWLEDGE_JSON_COMPATIBILITY

- 状态：`BACKLOG / PATCH_OR_MINOR_CANDIDATE`
- 问题：Windows PowerShell 5.1将knowledge index的`verifiedAt`保留为字符串，PowerShell 7的`ConvertFrom-Json`可能转成`DateTime`，导致同一checker提前返回`ENTRY_VALUES`。
- 目标：明确并统一两种宿主下JSON字符串字段的验证语义，同时保持现有安全失败与完整索引复证。
- 准入：PS5.1/PS7同fixture同结论；兼容测试覆盖合法UTC字符串、非法值和类型漂移。
- 停止线：不阻塞已明确限定为PS5.1的项目采用，不为此单独强制发布1.6.2。

### FRAMEWORK_RELEASE_FLOW_SIMPLIFICATION

- 状态：`BACKLOG`
- 目标：稳定候选只做一次完整实现Review、一次发布投影Review和必要运行测试；同一finding优先合并返工，避免人为制造无限补丁链。
- 准入：不降低immutable、manifest、迁移、独立Review或运行证据门；完整与patch发行路线仍可区分。

### FRAMEWORK_FOUR_ROUTE_RESOURCE_MAPPING

- 状态：`BACKLOG / HOST_MAPPING_ONLY`
- 目标：只在`HOST_CODEX`四个抽象质量档上提供轻量host映射，不增加binding文件、checker、矩阵或第二真相；异常只向上升级。
- 当前项目证据：Pocket映射为`OWNER_FRONTIER -> sol+xhigh`、`FOCUSED_HIGH -> sol+high`、`ROUTINE_BALANCED -> terra+xhigh`、`MECHANICAL_LOW -> luna+xhigh (PROBATIONARY)`。
- 准入：至少有自然任务的质量/成本证据；probationary不得写成已验证降本。

### WAIT_PEER_AND_BUG_ADMISSION_REMAINDER

- 状态：`BACKLOG / DELTA_ONLY`
- 已消费基线：1.6.1已有same-turn内部agent边界、bounded wait准入、domain-owner直达、controller pull、exception-only/no-ACK及基本Bug权威边界。
- 仅保留差额：应用层peer复用键、pin/archive/repo-card/lease四者的完成握手；复杂Bug分类中的producer/consumer恢复、semantic delta、相邻不变量与patch-chain重开门。
- 停止线：不复制Pocket项目的统计、任务名或局部热入口规则。

### PEER_REUSE_DECISION_AND_AUTOCREATE_AUTHORITY

- 状态：`BACKLOG / HOST_CONTRACT_REQUIRED`
- 问题：peer是否可复用与host是否允许创建新应用任务是两项不同判断；把“用户没有逐次说新建”当成复用理由，会把跨项目、跨cwd或跨谱系旧任务错误复活。
- 目标：owner先按`project + peer class + owner + task/review lineage + resource route + cwd/worktree + protection boundary`机械判定`REUSE / MUST_NEW / BLOCKED`。若结论为`MUST_NEW`且新peer仍落在用户已批准的task/review路线、资源上限、并发上限和保护边界内，则该路线直接授权host创建同范围peer，不再逐次向用户确认；新任务只取得冻结包显式授予的最小权限。
- 重新询问边界：只有创建会改变project/cwd、长期role或owner、task/review路线、资源/并发上限、保护边界，或引入Git/device/external等新权限时，才回到用户。标题、聊天摘要、旧任务可见性或已归档状态不能替代复用键。
- Host合同：host必须能把当前用户的standing project policy或当前阶段包识别为显式create authority；host不支持时安全失败为`BLOCKED_HOST_CREATE_AUTHORITY`，不得退化为错误复用。Framework项目文档不能静默扩大host/system权限。
- 准入：下一版本同时冻结authorization model、host mapping、task/review模板和机械用例；至少覆盖same-route `MUST_NEW`自动创建、reuse-key完全匹配复用、资源越界重新询问、host不支持安全失败四条路径，且不增加第二binding文件、ACK、ledger或轮询器。

### CONTROLLER_POINTER_DEDUP

- 状态：`BACKLOG`
- 目标：普通current卡只引用`.ai-workspace/controller.json`或controller角色，不复制literal会话ID；轮换只改唯一controller对象和经证明必需的最小热入口。
- 准入：旧卡/history不做批量改写；迁移必须保留可恢复性和current actor可判定性。

### LONG_LIVED_ROLE_SESSION_BINDING

- 状态：`BACKLOG`
- 目标：应用任务在启动/续接时可机械复证`project + cwd/worktree + long-lived role + authority + resource route`；聊天提示和任务标题只作线索。
- 准入：缺失字段安全失败；跨项目、跨role或cwd漂移不能被高资源档掩盖。

### TRANSITION_EPOCH_TRUSTED_ENVELOPE

- 状态：`BACKLOG`
- 目标：切换前已排队消息携带不可由消息正文伪造的原始controller epoch与稳定envelope；新epoch默认丢弃旧routine消息，只允许current-epoch exception事件。
- 停止线：不建立routine汇报回流、ACK链或第二controller ledger。

### CONTROLLER_HANDOFF_COMPLETION_HANDSHAKE

- 状态：`BACKLOG`
- 目标：把successor `ACCEPT`、pointer commit、old-controller read-only grace、successor fresh reproof和old task archive收敛为一个可机械判定的完成信号。
- 准入：每一阶段只有一个current controller；失败可回到明确的唯一authority，不靠聊天摘要桥接。

### EXCEPTION_TARGET_REBIND_IDEMPOTENCY

- 状态：`BACKLOG`
- 目标：长期owner的exception-only target在controller轮换时恰好重绑一次、可幂等重放、无需ACK，且不得恢复routine任务或向主控回流终态摘要。

### MULTI_FILE_CONTROL_TRANSACTION

- 状态：`BACKLOG / PROCEDURE_TO_PRIMITIVE_EVALUATION`
- 问题：当前多文件控制切换依赖预冻结exact、单writer和事后复证，尚无通用原子事务primitive。
- 目标：先证明跨项目有真实需求，再选择最小的prepare/commit/recover语义；不得把项目级exact13过程包装成未经证明的通用原子保证。
- 停止线：不承诺跨仓库原子事务、自动retry或自动compensation。

## 延后研究

### COMMON_KNOWLEDGE_AGGREGATION

- 状态：`DEFERRED / EVIDENCE_NOT_READY`
- 准入：至少两个真实项目各自完成自然查询与失效维护证据，且能证明共同条目不会形成第二权威。
- 当前结论：不制造第二试点项目，不把初始化、checker、fixture或人工演示计作自然证据。

## 已完成记录

- `CURRENT_ELIGIBILITY_AND_POINTER`：`COMPLETE`。根选择合同冻结在`README.md|当前版本策略`与本文件同名条目；稳定发布中的`currentEligible`只保留为不可变发布时快照，不再作为live selector。
- `CURRENT_1_6_1_SELECTION`：`COMPLETE / CURRENT_1.6.1`。稳定locator=`framework/versions/1.6.1/VERSION.json + RELEASE_MANIFEST.json`，live locators=`framework/CURRENT + README.md + framework/ROADMAP.md`；显式1.6.1与CURRENT-default fresh-Git smoke、pre/post-projection独立Review均通过。该选择不修改任何项目pin。
- `FRAMEWORK_MAINTENANCE_SIBLING_TARGET_TOPOLOGY`：`COMPLETE / STABLE_1.7.0 / NOT_CURRENT`。稳定locator=`framework/versions/1.7.0/VERSION.json + RELEASE_MANIFEST.json`；物理分离和Maintenance接管仍由AI-Workspace项目任务负责，不由稳定版本自动执行。
