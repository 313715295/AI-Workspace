# Framework 1.6.0 通用恢复核心

本文件是所有角色首次进入项目时的最小公共必读。它只恢复安全工作的资格，不授予写入、测试、Review、Git、push、设备或外部动作。角色、阶段和宿主细节由`LOAD_MANIFEST.json`选择完整模块；摘要只能导航，不能替代被选模块。

## 1. 不变量

1. 系统、当前用户和宿主约束优先；Framework、项目资料、任务卡和消息不得降低它们。
2. 项目Bootstrap是项目控制面的唯一入口。聊天、交接摘要、旧任务final、记忆和搜索结果只作定位线索。
3. 每个任务只有一个长期owner。owner可以委派阶段动作，但调度权、产品取舍和范围升级不自动转移。
4. 会话默认只读。只读调查不取得任何后续写权；修改权限不推定测试、Review、Git、push或external权限。
5. 不覆盖、回退、清理、暂存或提交其他owner与用户字节。保护路径的visibility/read/hash/diff/index/write按项目合同分别判断。
6. 风险未知、owner未知、对象身份不明、影响面无法隔离或权限冲突时，保持只读并回owner；不得靠降档继续。
7. 用户试玩、设备、平台、Review、commit、push、上传和正式发布是不同事实，不能互相替代。

## 2. 发现与固定版本

1. 把用户给出的路径解析为真实Git顶层。
2. 优先严格验证项目根的repo-local控制面；只有它完全不存在时才允许项目定义的legacy fallback。partial、reparse、身份冲突或未知live bytes fail closed。
3. 从当前已挂载workspace唯一定位项目pin对应的稳定Framework目录。不得用`CURRENT`、tag、HEAD、网络或DRAFT目录补洞。
4. 验证项目ID、repository identity、控制面布局、Framework pin、保护边界和当前任务入口。
5. DRAFT、REVIEW候选或缺失版本不具备项目运行权；项目升级必须另立任务。

## 3. 恢复模式

### FULL_COLD_RECOVERY

用于首次进入项目/长期角色、基线不可证明、Framework pin或项目身份变化、保护/owner/影响面不明、健康检查失败或用户明确要求。

顺序：

1. Bootstrap与project identity；
2. 本通用核心；
3. 由确定性loader选择的完整role/profile/phase/host模块；
4. 项目稳定核心：PROJECT、当前STATUS、owner/relationship入口和热任务索引；
5. 分配给自己的current任务热卡及其明确列出的权威输入；
6. 真实HEAD、index、工作树actual与其他owner边界，但不得因此触碰禁止的保护路径；
7. 当前阶段授权包。

FULL_COLD还必须严格读取`.ai-workspace/controller.json`，复算整个文件的`bytes|SHA256`并确认`projectId / controllerId / controllerEpoch / state=CURRENT`。`STATUS.md`、tasks index和聊天中的controller值只作locator；任何冲突fail closed。PROJECT_CONTROLLER签发的包与controller-directed route必须先通过current identity/epoch门，DOMAIN_OWNER包不读取或推导controller条件字段。

### WARM_TASK_REBIND

只用于同一健康会话且能从已核验对象证明角色、项目、Framework、owner、保护边界和已知内容基线。增量读取新任务、变化权威、热索引、actual、HEAD/index、其他owner边界和新授权包。任何冲突、未知漂移或影响面不明立即升级FULL_COLD。

温重绑不继承上一任务权限，也不机械重复未变化的大文档。idle、任务final、一次Review轮次或收到主动回传本身都不触发FULL_COLD。

controller identity/epoch、host、phase、最低资源能力、必需工具、context continuity或adapter可用性变化都会使旧授权/cache或资源选择失效。fresh rebind只接受满足最低能力的host结果；不能用较低model/effort或缺工具组合静默继续。

## 4. 工作分级

- `MICRO`：单领域、低风险、同一turn闭合、直接可验证、无公共合同/持久状态/外部动作/并行owner冲突。默认无完整任务卡、无临时执行者、无独立审核和无完整manifest。
- `STANDARD`：普通单领域功能/缺陷或跨turn工作。使用热卡或等价紧凑对象，记录目标、非目标、owner、风险、exact/forbidden、验收、验证、Git/外部边界和唯一下一动作。
- `CRITICAL`：跨域公共合同、复杂状态机、核心循环、持久状态、平台/runtime、账号/发行、不可逆动作或高失败代价。冻结稳定候选、依赖、验证上限和独立审核边界。

档位由影响范围、行为复杂度、依赖、可观察性和失败代价共同决定，不按文件数或行数机械判断。跨turn、阻断、扩面或不确定性增加时升级，不能静默降级。

在实现和验证前标记问题为`CURRENT_REACHABLE / CONTRACT_REACHABLE / FUTURE_ONLY / UNVERIFIED`。证据强度匹配真实producer、入口、玩家影响和失败代价；不存在current入口时不制造浏览器、设备或玩家门。

## 5. 按需加载合同

loader输入只有`role + profile + phase + host`，输出为公共核心与所选完整模块的有序去重并集。模块内部不得要求调用者猜测另一个未加载章节；若存在硬依赖，必须在manifest声明。

- role决定职责和委派边界；
- profile决定风险与审核深度；
- phase决定本阶段动作和证据；
- host只补工具、消息、工作树和宿主限制；
- 项目Bootstrap再追加项目核心和current任务输入。

不得按段落动态拼接、让模型先猜章节、建立角色×档位组合文档或用摘要替代完整已选模块。loader输出必须给出文件顺序、字节和保守token估算，便于项目在恢复前看见成本。

## 6. 授权与阶段

只读调查默认开放；任何改变状态的动作必须先有一个当前有效授权包。授权包可以一次覆盖一个阶段的多个明确动作，因此不要求用户或主控逐命令确认。

动作至少区分：控制面写、source写、test写、测试运行、browser、device、Review路由/执行、Git stage/commit、push和external。包绑定task、owner、issuer、issuer role、唯一grantee、profile、actions、exact paths、对象身份、用户决策和失效条件。

领域owner可在自己的领域与已批准产品边界内签发`MICRO / STANDARD`本地实施、测试和聚焦审核包；`CRITICAL`在主控或用户完成重大方案/公共合同门后，也可由领域owner签发已冻结范围内的本地阶段包。产品结果、重大方案/公共合同和外部动作由用户确认；普通本地实现不逐次请求用户批准。

执行者不能自扩范围或自签新包；审核者不能用finding授予写入；Git和push不从实现权限继承。包在task、owner、grantee、action、pathset、对象identity或用户决策变化时失效。

Framework机械checker能拒绝不一致的授权包。阶段包在writer取得连续写线时验证一次并形成临时PASS digest；只要task、owner、grantee、actions、exact、对象identity、用户决定和其他writer事实均未改变，后续属于该包子集的文件编辑与测试复用该结果，不逐工具调用重复向模型返回脚本输出。动作/路径扩展、对象或owner漂移、writer交接、候选冻结以及Review/Git/external边界必须重验。

只有宿主把checker接入pre-tool hook或受控wrapper时，才形成不可绕过的宿主级硬门；理想hook在本地静默复用PASS digest，只向模型返回首次摘要或失败原因。没有该集成时必须表述为“机械预检要求”，不能声称操作系统已经阻止所有越权调用；AI按一次计划变更批次预检，而不是每个文件操作各跑一次。

## 7. 写入、验证和Review

写前核对producer、direct consumers、tests、runner/manifest、docs和contingency。范围不确定先只读调查。

`MICRO`做最直接验证；`STANDARD`做风险相称的direct tests和聚焦审核；`CRITICAL`做稳定候选、必要集成/运行证据和合格独立审核。用户明确要求试玩的玩家行为，用户反例使旧READY失效，必须针对同一current candidate复验。

`DIRECT_USER_FEEDBACK_REQUIRES_OWNER_REBIND`：用户反馈或反例不授writer，只使旧READY与旧授权包失效；唯一owner只读定位后重冻task、actor/actions、exact、identity和current用户决定并重签，执行者才能恢复任何动作。

manifest只在writer release、试玩候选、Review、commit/version freeze或疑似drift节点生成。内容未漂移时复用有效证据；输入漂移只重跑受影响门，影响面不明时才完整复审。

热卡只保留current责任、稳定对象、权限、验证上限、阻断与唯一下一动作。历史进入只读carrier或Git对象；不得为了1.5迁移批量重写所有旧卡。

## 8. Git、工作树和外部动作

共享仓默认不为每个会话创建branch/worktree或独立index。只有文件所有权不可避免重叠、长周期实验、并行候选或主工作树必须保持可发布时才使用worktree，并预先指定集成者和合并顺序。

同一仓同一时刻只有一个Git closer。只逐项暂存授权路径，禁止`git add .`。stage、commit、push、发布、删除和回退分别授权。

外部下载、安装、登录、账号绑定、设备、上传、提审和发布分别记录真实状态；任何一个成功不推定其他阶段。

## 9. 宿主消息与等待

独立任务依靠主动回传，不轮询或用等待维持进度感。只有用户要求同步等待、当前turn必须消费且一次有界等待预计足够、或已有主动回传但有具体丢失证据时，才允许一次有界等待。超时或无变化后不得立即重试。

主控先恢复，再按领域挂载分管。换长期角色时先完成新owner恢复与接管，再归档旧会话；不存在定义清晰的后继职责时，不保留无限idle任务。

默认路由为执行者→领域owner、Reviewer→候选owner、领域owner→下游owner。普通READY/PASS/HOLD/CONSUMED不抄送主控；只有共享writer、无主职责、控制面/授权损坏、保护事件、跨域死锁、Git/external冲突或用户明确要求才上报主控。controller-directed对象先校验current epoch/identity再去重；旧routine queue抑制，旧exception只在current task复证后单次重路由且不复用旧授权/ACK。

## 10. 停止与回报

以下任一发生立即停止当前写线并回唯一owner：范围外路径、对象漂移、公共合同/产品取舍、owner或权限冲突、保护边界不明、同一finding复发、Review轮次用尽、需要不可逆或未授权外部动作。

对用户默认只汇报：结果、剩余风险/未验证、是否需要用户操作和少量可复核证据。SHA、manifest和机械细节留在控制面，除非用户要求或它们是阻断原因。
