# AI Workspace

这是 AI 多会话协作 Framework 的统一使用入口，也是 Framework 开发与发行的唯一仓库。它帮助一个人持续协调多个 AI 会话，同时把可恢复的协作事实留在文件里。日常工作按风险使用 `MICRO / STANDARD / CRITICAL` 三档；完整重型闭环只用于真正的高风险任务。

## 这是什么

`AI-Workspace`长期只保存通用Framework、版本、中立模板和初始化工具。真实项目的稳定上下文、当前状态、任务卡与报告应进入项目自己的版本控制边界，通过项目`BOOTSTRAP.md`连接固定Framework版本。

当前默认分支不携带具体项目控制面，也不跟踪空的`projects/`占位；`archive/`只保留通用的只读归档入口。项目资料及迁移原始证据属于对应项目仓，不得继续写入通用Framework历史。只有本地确实挂载旧中央项目时，发现流程才把未跟踪的`projects/<project-id>/`作为legacy输入读取。

## 它解决什么

这套工作区让一个人可以围绕项目主控协调跨领域目标和顺序，由领域分管长期持有各自上下文并闭环大部分任务，再按需临时挂载执行者和独立审核者。稳定资料、状态和任务边界不依赖某一段聊天，因此能降低会话更换、上下文丢失、重复沟通、越权写入和把自检冒充所需独立批准的风险。

## 它不是什么

- 不是源码仓，不保存或替代项目代码。
- 不是自动运行的“AI公司”；角色不会自行常驻、扩权或启动阶段。
- 不是聊天记录仓库；聊天摘要不能替代稳定资料、状态和任务卡。
- 不会在没有明确授权时自动修改代码或 Git、联网、安装、发布或创建外部状态。

## 目录里有什么

```text
AI-Workspace/
├─ framework/                   # 通用角色、流程、审核与固定版本
├─ scripts/                     # 跨版本register / upgrade机械入口
└─ archive/                     # 一次性迁移的原始历史资料

<project-git-root>/
└─ .ai-workspace/               # repo-local项目控制面，随项目Git跟踪
```

项目仓库的`.ai-workspace`保存该项目的资料、状态、任务和Bootstrap，但不复制整套Framework；Bootstrap从当前挂载工作区唯一定位固定版本。项目根的薄入口可以指向`.ai-workspace/BOOTSTRAP.md`。

与Framework语义绑定的checker、tests、templates和examples随版本存放；跨版本入口`register-project.ps1`与`upgrade-project.ps1`留在根`scripts`。register只创建全新repo-local控制面；upgrade只做同布局版本升级，两者默认预览且不stage/commit。已退役的1.3.0根checker不再随仓库分发；1.3.0目录只保留历史字节与向较新中央版本升级时的源模板，不能再作为运行或升级目标。中央legacy项目搬到repo-local是各项目另行授权的一次性操作，不是Framework通用命令，也不由upgrade自动完成。

`AI-Workspace`同时是开发与发行仓，默认分支在`framework/versions/`下保留全部稳定版本，供项目pin、普通Git检出、ZIP下载和本地升级直接使用。`framework/CURRENT`只决定新项目默认版本，不改变已有项目pin。tag可以作为可选审计或下载标记，但Framework注册、恢复和升级不得依赖tag；固定版本目录缺失时明确拒绝，不从tag或当前HEAD猜测历史模板。

Framework版本按`DRAFT / REVIEW / STABLE / RETIRED`理解：开发中的候选可以返工；版本进入STABLE即不可原位修改，修正一律通过新的patch版本发布，例如`1.3.1 → 1.3.2`。是否已被项目消费只影响保留或退休策略，不影响不可变性；`RETIRED`版本可以只保留历史内容而不继续提供运行入口。1.3.0即为这种历史保留版本，旧项目应先升级到仍受支持的固定版本。

Framework 1.5.0现作为`STABLE / OPT_IN`固定版本发布，提供通用恢复核心、确定性按需模块、分级阶段授权和风险相称的审核/证据机制。`framework/CURRENT`仍为1.4.1，因此默认注册和任何已有项目pin都不会自动变化；项目只有在独立升级任务中显式选择1.5.0才会消费它。

## 怎么使用

先做三件事：让 AI 从项目 `BOOTSTRAP.md` 恢复固定版本，按下面的风险边界选择工作档位，再在该档位内调查、修改和验证。用户不需要运行 Framework 脚本或手工维护机械字段。

| 档位 | 适用工作 | 默认载体与记录 | 审核 |
|---|---|---|---|
| `MICRO` | 单领域、低风险、可直接验证、无公共合同/持久状态/外部动作/并行owner冲突，健康owner会话可在同一turn闭合 | owner直接执行；默认不建完整任务卡。无卡时当轮明确目标、exact/forbidden、验证、Git/外部权限和结果 | owner自检；不虚构独立批准 |
| `STANDARD` | 普通单领域功能、缺陷或任何跨turn工作 | 紧凑任务卡；保留目标/非目标、owner、风险、exact/forbidden、验收、验证、Git/外部权限和下一动作 | 按风险由领域owner或合格上下文聚焦审核；不机械新建会话 |
| `CRITICAL` | 跨域公共合同、复杂状态机、核心循环、持久状态、平台/runtime、账号/发布、不可逆动作或缺陷代价高 | 完整范围闭包、稳定对象、外部生命周期门和完整范围摘要；actor/notifier仅是实际多会话时的可选宿主扩展 | 与方案设计者及实质写入者不同的合格最终审核者；保留范围、产品、owner、质量与权限停止线 |

任何档位都必须有唯一owner、明确范围与验证，不覆盖他人改动，不跳过真实 `HEAD` / index / diff，也不从修改权限推定 commit、push 或外部动作权限。影响面、owner或风险不确定时向上升级；`MICRO`跨turn、阻断或扩面时立即升级`STANDARD`。

第一次使用可直接阅读项目固定版本的`EXAMPLES.md`；任务卡从同版本`TASK_TEMPLATE.md`选对应档位，不从`CRITICAL`模板倒删字段。

### 第一次使用、新项目、换电脑或分享给别人

这些场景使用同一个初始化流程：

1. 把本 `AI-Workspace` 目录和项目源码仓同时加入 AI 的工作区。
2. 新开一个 AI 会话，复制下面这段提示并补充三项真实信息：

```text
请按当前 AI-Workspace README 的统一使用流程，先判断这是已有项目还是新项目。
项目名称：<名称>
源码仓位置：<本地路径>
产品目标：<直接描述，或一个/多个本地文档路径>
请先检查项目Git根是否有完整有效的`.ai-workspace`；有则按其Bootstrap冷恢复。只有repo-local不存在时才检查AI-Workspace中央legacy项目。已有任一布局都不得调用注册脚本或重建；两者身份冲突时停止。只有确认两处均不存在时才初始化。请自动调查可推导的信息，只把无法可靠判断且会影响产品、保护、长期owner/资源、Git或外部权限的问题一次性问我。
```

后续由 AI 会话先核对项目Git根`.ai-workspace/project.json`与`BOOTSTRAP.md`，仅在其不存在时核对中央legacy。完整repo-local优先；并存时中央冻结只读，身份冲突fail closed。只有确认两处都不存在，才在Git根创建`.ai-workspace`候选并验证。用户不需要理解项目 ID、脚本参数、模板替换或逐份编辑项目文件。

如果初始化失败，把界面中的现象或报错原文交给同一 AI 会话处理；不要自行执行故障命令或修改生成目录。

### 已有项目的日常使用

让 AI 会话先从项目Git根发现`.ai-workspace/BOOTSTRAP.md`；只有它不存在时才读中央legacy `projects/<project-id>/BOOTSTRAP.md`。再按Bootstrap顺序恢复固定Framework、项目资料、当前状态和任务卡。现有项目升级必须保持原拓扑；中央→repo-local只能走独立迁移任务，不由用户手工改版本指针或复制目录。

日常协作中，用户主要与项目主控讨论目标和产品取舍；主控负责跨域路线、顺序和冲突，领域分管长期持有领域上下文并闭环大部分任务。执行者和独立审核者只在具体任务中临时挂载，不是第三层管理者。具体权责、审核和 Git 规则以项目固定 Framework 与 `BOOTSTRAP.md` 为准，本 README 不复制第二套完整流程。1.4.x项目按固定版本的`GOVERNANCE / WORKFLOW / REVIEW`文档恢复；1.5.x项目先读`RECOVERY_CORE.md`，再由固定版本loader按role/profile/phase/host完整加载所需模块。

AI会话首次进入项目/角色，或无法证明之前的恢复基线时，会从Bootstrap做完整冷恢复；这是首次建立可信基线的成本，不是每张任务的默认步骤。同一健康会话处理新任务、Review返工或idle后唤醒时，默认按档位只增量核对必要权威、新任务卡、变化事实、真实状态和重新授权；一旦身份、权限、保护边界或影响面不确定，就回到完整冷恢复。日常增量不会继承旧任务权限，也不降低审核或验证。

跨域目标通常由一张父任务卡协调，领域输入被消费后及时退出热任务。`MICRO`无持久卡时不运行checker；有卡的`MICRO`和普通`STANDARD`只检查各自必要声明，只有实际挂载多角色时才启用actor/notifier字段；`CRITICAL`保留完整范围摘要。AI在进入审核、Git收口或关闭前，把机器观察到的本任务具体路径交给项目固定版本内的checker。checker只核对卡内声明、观察路径和生命周期一致性，不识别Git owner、不判断设计正确，也不授予Git、阶段或外部权限。

审核绑定稳定内容对象；候选变化时只重审真正受影响的部分，影响不明仍完整复审。内容提交后还有外部发布的任务会保持active，直到真实发布结果落账才关闭。用户不需要运行检查脚本或维护这些机械字段。

独立任务默认依靠主动回传，不靠轮询维持进度感。具体任务、消息、等待和可选actor/notifier字段属于宿主适配，不进入核心治理；使用Codex时，1.4.x读取固定版本的`HOST_ADAPTER_CODEX.md`，1.5.x由固定版本loader加载`HOST_CODEX.md`。其他宿主应提供等价适配，但不得改变唯一owner、审核独立性、范围、Git或外部权限。

### 用户何时需要介入

- 做产品目标、体验、优先级或阶段的最终取舍；
- 回答 AI 从源码和产品资料中仍无法可靠判断的信息；
- 明确 Git、push、联网、安装、登录、上传、发布等权限或外部动作；
- 主动要求会话健康检查，并决定继续、压缩或轮换会话。

除此之外，AI 应在已授权边界内自行调查、路由、执行和验证，不把脚本参数、模板替换或逐份文件编辑转交用户。

## 附录：供初始化 AI 会话执行（AI 初始化执行规则）

以下内容供初始化 AI 会话执行；用户按前面的“怎么使用”操作即可，通常无需阅读本附录。

统一流程只恢复已有项目协作上下文，或在确认不存在时创建新项目协作目录；不创建或修改源码仓，不改写任何已发布Framework版本目录，也不授予 Git、联网、安装或外部状态权限。完成恢复或初始化不自动启动任何产品阶段。

### 先识别已有项目，再调查新项目

统一流程从当前工作区中的 `AI-Workspace`、项目名称、本地源码仓位置，以及产品目标的直接文字或一个/多个本地文档路径开始。不得要求用户重复提供可从这些对象可靠推导的协作目录、Framework 版本、project ID、技术栈、已有文档或验证入口。

1. 从本 README 所在目录识别包含 `framework` 的`AI-Workspace`根，并把用户给出的源码仓解析为真实Git顶层；非Git或子目录输入fail closed。全新克隆可能没有`projects`目录，这只表示中央legacy库存为空。
2. 将项目名称规范化为小写 ASCII `project-id`，只允许小写字母或数字组成的段并以单个连字符连接。无法可靠转换或用户明确要自定义时，把 ID 作为同一批问题的一项，不得静默猜测。
3. 在任何创建动作之前，先严格读取`<project-git-root>/.ai-workspace/project.json`和`BOOTSTRAP.md`。完整schema2 repo-local控制面优先；partial、reparse、ID/repository/pin冲突立即`NEEDS_INPUT`，不得覆盖或回退中央猜测。
4. repo-local不存在时，若`projects`存在则只读核对中央legacy `project.json`与`BOOTSTRAP.md`。找到匹配中央项目时禁止调用register；按其Bootstrap冷恢复。两种布局并存且身份一致时repo-local为入口、中央冻结只读；冲突时停止。
5. 中央legacy的`project.json.repositoryPath`因换电脑等原因与当前真实Git顶层不一致、失效或无法核实时标为`UNVERIFIED`并输出`NEEDS_INPUT`。路径校正必须进入已有项目任务与权限门。
6. 只有确认repo-local和中央legacy都不存在时，才读取`framework/CURRENT`。若CURRENT尚未发布repo-local starter，register必须拒绝自动猜“最新”版本；只有owner明确批准固定1.4.0或更高版本后才可显式选择。
7. 对新项目确认源码仓路径存在，只读建立注意力地图：项目入口、技术栈、产品/架构文档、测试与构建入口、现有 AI 薄适配、保护路径线索及当前工作树风险。读取用户给出的本地产品文档，区分明确事实、可推导建议、冲突和缺失，并记录依据。不得写源码或执行 Git 写操作。
8. 新项目控制面固定为`<project-git-root>/.ai-workspace`，不允许自定义到其他目录；目标必须完全不存在，项目Git工作树必须干净。

### 一次性提问与权限边界

先完成发现，再把仍会改变项目身份、责任或权限的缺口一次性汇总；已从源码或产品资料得到可靠答案的项目不得重复询问：

- 产品目标、目标用户与目标平台；
- 必须保护、禁止读取/改写或由用户独占的路径；
- 启用哪些长期领域，以及可确认的长期 owner；
- 实际可用模型、请求档位、预算或其他资源限制；
- 本地 Git、commit、push、分支/worktree 和回退权限；
- 下载、安装、登录、账号绑定、上传、发布等外部动作权限。

不确定项写为 `UNVERIFIED`，并在创建前用“事实 / 建议 / 冲突 / 待确认”短表汇总。用户未指定人员、资源或权限时可以给建议，但不得写成已授权事实。若仍缺少会导致危险写入的决定，输出 `NEEDS_INPUT`，不要创建目录。Framework 的会话健康检查只在用户准备判断压缩或轮换时由用户触发，不因初始化自动运行。

### 创建与完善

以下步骤只适用于已经确认不存在匹配项目的新项目分支；已有项目不得进入本节。

1. 再次确认项目Git顶层、干净工作树、无同ID中央legacy，并确认`.ai-workspace`完全不存在；任何partial、文件、reparse或未知字节都fail closed，不覆盖、不合并、不清理。
2. 初始化会话先调用`scripts/register-project.ps1`默认预览，核对目标、固定版本和模板清单；再取得本任务Apply授权。脚本参数不展示给用户，也不得从预览推定Git授权。
3. Apply只从固定版本`project-starter`在项目仓内同级隐藏staging机械实例化`.gitattributes`、`project.json`、`BOOTSTRAP.md`、`PROJECT.md`、`REVIEW_PROFILE.md`、`RELATIONSHIPS.md`、`STATUS.md`、`tasks/README.md`及`tasks/active`、`tasks/archive`，完整验证后同仓rename为`.ai-workspace`；失败清理已知staging，不stage/commit。
4. 脚本生成schema2：`controlPlaneLayout=repo-local`、`repositoryRoot=..`与固定`frameworkVersion`。重复同身份Apply返回`ALREADY_REGISTERED`；任何身份或内容冲突停止。
5. 初始化会话随后把确认事实有机写入生成文档。稳定身份、目标、架构边界和权威地图进入 `PROJECT.md`；项目特有审核重点进入 `REVIEW_PROFILE.md`；current 与未验证项进入 `STATUS.md`；未批准关系不写入 `RELATIONSHIPS.md`。
6. 不创建无真实工作的任务卡，不复制通用流程，不把聊天、示例值或建议升级为机制权威。

### 验证、输出与失败边界

创建后至少验证：

- `project.json` 可解析，schema2、ID、显示名、`repo-local`、相对项目根和Framework pin彼此一致；
- 全部生成文件严格 UTF-8 无 BOM、无 NUL/U+FFFD、无未替换模板标记、无本机或示例项目泄漏，并以换行结尾；
- `BOOTSTRAP.md` 能从项目配置定位固定 Framework，按治理、流程/审核、项目资料、状态、任务卡和任务权威的顺序完成冷恢复；
- `tasks/active` 与 `tasks/archive` 存在，项目 README 只解释库存和定位，不复制完整工作流；
- 相对链接和所指文件存在，保护边界、Git/push 与外部权限没有被默认授权；
- 除新`.ai-workspace`候选外产品字节、index、ref与中央legacy均未被修改。
- 已有项目情境未调用注册脚本，未覆盖或重建；源码路径漂移保持 `UNVERIFIED / NEEDS_INPUT`，等待已有项目任务与权限门。

已有项目完成冷恢复且路径与权限证据一致时，输出恢复结果和下一条允许动作；不输出“新建成功”。新项目全部必要输入和验证通过后输出 `READY`，同时给出生成目录、固定 Framework 版本、仍为 `UNVERIFIED` 的非阻塞项和下一条允许动作。缺少产品/保护/owner 资源/权限决定、已有项目源码路径漂移或验证失败时输出 `NEEDS_INPUT`，只说明需要用户决定的内容或失败现象；不要给用户脚本或手工修复命令。

### 权威、版本与维护边界

- 本 README 同时是唯一用户入口和完整初始化执行权威；不得另建跳转入口或复制第二套初始化合同。
- 通用角色、流程、审核、Git 和会话规则只由项目固定版本持有：1.4.x使用`GOVERNANCE.md`、`WORKFLOW_PLAYBOOK.md`、`REVIEW_CHECKLIST.md`与`TASK_TEMPLATE.md`；1.5.x使用`RECOVERY_CORE.md`及loader选出的完整模块。本 README 只提供简明工作方式介绍。
- 每个项目在 `project.json` 中固定 `frameworkVersion`；`framework/CURRENT`只是新项目默认版本，不强制现有项目升级，也不会让中央修改自动改变项目 pin。
- `project-starter`只提供中立骨架；现有项目不自动重建、迁移或被模板反向覆盖。
- 项目稳定事实进入 `PROJECT.md`，当前状态进入 `STATUS.md`；需要持久记录的工作进入唯一owner任务卡，合格无卡`MICRO`由owner当轮记录结果。聊天历史不是事实来源。
- 默认分支的`framework/versions/`是版本内容权威并保留全部稳定版本；tag只作可选审计/下载标记，不参与运行时解析。稳定版本不得原位改写，后续修正创建新的patch版本。需要新增脚本、schema字段、联网能力、源码写入或治理语义时，必须由对应版本任务明确授权。

### 中央legacy项目的一次性搬迁边界

中央→repo-local不是upgrade，也不是Framework通用产品能力。已有项目只有在项目owner另建专属任务、冻结实时源清单并明确转换`project.json`、`BOOTSTRAP.md`和薄入口后，才可在项目仓生成并逐文件验证候选；Framework脚本不会代为复制、提交、切换权威或删除中央源。

项目仓提交和repo-local完整冷恢复成功前，中央副本始终是唯一权威；失败时可丢弃未提交候选并重新复制。项目仓成功后，中央冻结与删除必须由后继任务分别授权，任何时刻不得让两处同时可写。
