# AI Workspace

AI-Workspace 是多会话协作 Framework 的开发与发行仓。真实项目的稳定资料、状态和任务卡存放在项目自己的`.ai-workspace/`中；项目通过固定版本pin读取这里的Framework，不复制第二套通用流程。

## 它解决什么

- 会话更换后能从项目权威恢复，而不是依赖聊天摘要。
- 项目主控负责跨域路线，领域owner闭环本域工作，执行者和Reviewer按需挂载。
- 按`MICRO / STANDARD / CRITICAL`匹配任务成本，不把发布级防御套给普通修改。
- source/test、测试/browser/device、Review、Git、push和external分开授权。
- 保留唯一owner、保护路径、范围闭包、重大方案、用户试玩、必要独立审核和外部动作硬门。

它不是产品源码仓、聊天记录仓或自动运行的“AI公司”；本仓本身就是Framework源码与发行仓。工具可用不等于已经授权；Framework也不会在没有权限时自动修改代码、Git、设备、账号或外部状态。

## 目录

```text
AI-Workspace/
├─ README.md                  # 用户与维护者短入口
├─ INITIALIZATION.md          # 仅新项目/新机器/初始化故障时按需读取
├─ framework/
│  ├─ CURRENT                # 新项目默认版本，不改变已有项目pin
│  ├─ ROADMAP.md             # 未选入具体版本的唯一规划池；不可消费
│  └─ versions/<version>/    # 已发布稳定版本
└─ scripts/                   # register / upgrade机械入口

<project-git-root>/
└─ .ai-workspace/             # 项目自己的repo-local控制面
```

普通项目会话不加载本README、版本对比或发行证据；它从项目`.ai-workspace/BOOTSTRAP.md`开始，再由固定版本loader按角色、风险、阶段和宿主加载必要模块。

Framework维护采用平级双仓：纯Framework仓不跟踪`.ai-workspace/`；动态维护控制面放在同一专用父目录下的`AI-Workspace-Maintenance`仓。普通consumer项目仍保留自己的repo-local控制面，不受该维护拓扑影响。

## 当前版本策略

- `framework/CURRENT`为`1.6.1`，只影响新项目默认选择；显式1.6.1与省略`FrameworkVersion`的CURRENT-default preview/apply/repeat均已通过，并完成pre/post-projection独立复审。
- Framework 1.6.1现为`STABLE / CONSUMABLE / CURRENT / PIN_ELIGIBLE`的兼容补丁；1.6.0继续作为不可变稳定基线，已有项目不会自动升级。
- Framework 1.7.0现为`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE`的维护拓扑功能版本；它允许维护控制项目与Framework源码仓平级分离，但不会自动改变根CURRENT或任何consumer pin。
- 根级CURRENT选择资格只取`lifecycle=STABLE + consumable=true + projectPinEligible=true + 有效project-starter/register smoke`。已发布版本中的`currentEligible`是不可变的发布时快照，已弃用为live selector，不能覆盖上述root合同；未来版本应移除该冗余字段或赋予单一可验证语义。稳定发布与选择CURRENT始终是两个原子动作。
- 1.6.0采用减法后的协调治理：多remote只记录逐项真实结果与诚实部分成功，不实现跨仓库原子事务、自动retry或自动compensation；日常Git排除、独占串行升级、controller epoch与统一语言治理均保持最小机制。
- 1.6.0已包含默认关闭的项目级按需知识合同、schema、checker与可选loader selector；项目不启用、没有知识库或使用空索引均为受支持状态。知识内容、common聚合与具体项目初始化仍由项目独立采用，两个项目的自然证据只约束未来common知识晋升。
- 1.6.1只为现有知识checker增加可选的1～3个显式Entry ID选择；不传参数时保留1.6.0按ID返回前三条的兼容行为，且仍先复证完整索引与全部CURRENT reference/authority。补丁不增加搜索、排名、缓存、后台维护或第二入口。
- 1.5.3仅保留给保持公共合同、模块/starter拓扑和根事务不变的真正兼容`PATCH_HOTFIX`；没有适用热修时直接跳过。
- 已发布`framework/versions/<version>/`不可原位修改；修正发布新的patch版本。
- `FULL_RELEASE`用于公共合同、模块/starter拓扑、根事务或不兼容schema变化。
- `PATCH_HOTFIX`用于兼容的文档、模板、checker或局部脚本修正，只验证受影响范围；不机械重复完整迁移、全角色矩阵或自然样本。

项目升级始终另立项目任务：先预览并验证真实控制面、owner、保护路径、热任务和Git状态，再显式修改pin。Framework稳定发布、根CURRENT、Git publication和项目pin采用互不自动授权。

## 怎么使用

### 已有项目

1. 同时把AI-Workspace与项目Git根加入工作区。
2. 让AI从项目`.ai-workspace/BOOTSTRAP.md`开始；只有repo-local控制面完全不存在时，才检查项目定义的中央legacy入口。
3. Bootstrap验证项目ID、Git根、Framework pin和保护边界，再选择FULL_COLD或WARM恢复。
4. 恢复后按任务档位工作；无有效写包时保持只读。

可直接使用：

```text
请严格从项目Git根的 .ai-workspace/BOOTSTRAP.md 开始恢复；聊天和旧摘要只作定位。按固定Framework恢复owner、current任务、保护路径、真实Git状态和当前授权，再报告唯一下一动作。
```

### 新项目、换电脑或初始化故障

读取[INITIALIZATION.md](INITIALIZATION.md)。该文件包含完整发现、一次性提问、register、验证和legacy边界；普通已有项目会话不读取它。

用户可提供：

```text
项目名称：<名称>
源码仓位置：<本地路径>
产品目标：<直接描述，或本地文档路径>
请先判断是否已有完整 .ai-workspace；有则恢复，只有两处控制面都不存在时才初始化。自动调查可推导信息，只把会改变产品、保护、长期owner、资源、Git或外部权限的问题一次性问我。
```

### 日常分工

- 用户：确认产品结果、重大方案/公共合同、阶段推进和外部动作。
- 项目主控：阶段顺序、跨域接口、冲突、项目Git/external总门和用户选项。
- 领域owner：本域权威、拆分、授权、验收和必要Review路由；批准边界内不逐动作回主控。
- 执行者：在冻结包内实施、验证并主动回owner。
- Reviewer：对指定稳定对象给独立结论，不取得写入、调度、阶段或Git权。

用户不需要逐文件、逐测试或逐轮Review点击授权。一次阶段包可以覆盖明确的task、owner、唯一执行者、actions、exact paths、对象身份、用户门和失效条件；范围、身份、owner、用户决定或阶段边界变化时才重新授权。

### 用户何时需要介入

- 产品目标、体验、优先级、重大架构或阶段的最终取舍；
- 源码和项目资料无法可靠判断的真实业务信息；
- push、登录、设备、下载/安装、上传、提审、发布等外部动作；
- 不可逆操作或用户明确保留的风险决定。

普通只读调查、范围内实现、direct tests、机械验证、领域验收和必要Review路由由有权owner闭环。

## 运行时加载与token

文件存在于仓库不会自动消耗模型上下文。1.5.x loader只加载`LOAD_MANIFEST.json`为当前`role + profile + phase + host`选择的完整模块。

以下通常是发行证据，不进入普通项目loader：

- `STATIC_COMPARISON.md`
- `MIGRATION_MATRIX.md`
- `CHANGELOG.md`
- 版本`README.md`
- `TASK_TEMPLATE.md`、`EXAMPLES.md`、`PROMPTS.md`（需要创建任务或取示例时才读取）

`FRAMEWORK_RELEASE.md`只由Framework维护/发行角色加载。脚本本地计算本身不占模型token；发送给模型的命令文本和stdout/stderr才占上下文，因此成功默认输出一行摘要，详细JSON只用于诊断。

## 安全与Git边界

- 每个任务只有一个长期owner；共享dirty工作树中的其他owner和用户字节不得覆盖、回退、清理、暂存或提交。
- 保护路径按visibility/read/hash/diff/index/write分别定义。
- 默认不为新会话或Reviewer创建worktree；只有范围重叠、长周期隔离候选或主工作树必须保持可发布时才使用。
- 同一仓同一时刻只有一个Git closer；只精确stage授权路径，禁止`git add .`。
- stage、commit、push、发布、删除和回退分别授权。
- 独立任务主动回传，不使用轮询维持进度感。

## Framework维护

维护前读取目标版本的`FRAMEWORK_RELEASE.md`。尚未选入版本的通用方向只进入[framework/ROADMAP.md](framework/ROADMAP.md)；选定发布批次后才投影到对应draft。稳定版本不可原位修改：开发先进入候选目录，按`FULL_RELEASE`或`PATCH_HOTFIX`验证，通过后生成新的稳定version与manifest。

Framework 1.7.0稳定版位于`framework/versions/1.7.0/`，但根CURRENT仍是1.6.1；`framework/drafts/1.7.0/`只保留设计、实现与审核审计记录，不是可消费入口。后续修正必须另建patch或minor候选，不能原位修改稳定版。

根README是用户短入口，不承载完整初始化算法、版本迁移矩阵或运行时治理正文。新项目初始化读取`INITIALIZATION.md`；项目运行读取固定Framework；发行对比材料只在维护任务中按需读取。
