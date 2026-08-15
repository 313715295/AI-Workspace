# Git、平台与外部动作

本模块只在Git或external阶段加载。普通调查、实现和本地验证不因本模块存在而获得任何Git、设备、账号或发布权限。

## 1. Git所有权

同一仓库同一时刻只有一个Git closer操作index/commit。任务授权必须区分`GIT_STAGE`与`GIT_COMMIT`；push、发布、删除和回退另行授权。

Git closer在收口前核对：

1. 真实Git顶层、HEAD/branch和当前index；
2. 本任务exact、stable candidate与依赖manifest；
3. staged/unstaged/untracked中其他owner和用户字节；
4. scoped tests、strict text、diff-check和任务要求的Review/试玩门；
5. 当前授权包是否覆盖action与精确路径。

只逐项stage授权路径，禁止`git add .`、范围外格式化、清理、unstage或回退。不得用`assume-unchanged`/`skip-worktree`隐藏差异。共享dirty工作树不是自动阻断；无法证明本任务与其他字节隔离时才停止。

领域owner只有在项目主控明确委派Git closer或阶段包标记允许时才能签发本域checkpoint；跨域整合、公共版本、发布分支和存在不明dirty时由项目指定Git closer收口。

### 1.1 Protected-safe入口

`.ai-workspace/project.json` schema 3中的`protectedPaths`是唯一机器策略，整个project.json `bytes|SHA256`是唯一`projectConfigIdentity`。Framework提供的inventory/status/diff/index只能调用`invoke-protected-safe-git.ps1`并传操作枚举、bounded allowlist和冻结config identity；调用者自填exclude、任务卡复述或聊天摘要不是输入。

脚本在启动Git前验证config/schema/path规范化，并对allowlist与每条适用保护规则做祖先/后代双向重叠检查。任何缺失、损坏、重复/碰撞、identity漂移、重叠或命令失败都返回该操作`UNVERIFIED`并停止；禁止扩大路径重试。保护对象不得进入允许pathset、输出或evidence。

### 1.2 RemoteBatch

`RemoteBatch`只表示同一本地repo和同一stable candidate到多个remote的普通ref push集合。顶层绑定project/task/candidate、唯一Git closer、batch authorization和整个project config identity；每个remote绑定脱敏endpoint fingerprint、refspec与expected local/remote head，最多尝试一次。

逐项只记录`SUCCEEDED / FAILED / UNKNOWN`与secret-safe receipt或error class；整体状态现场派生，不持久化第二aggregate。本版没有PreviousLedger、自动retry或自动compensation。重试是fresh batch+fresh authorization+fresh heads；force、删除ref或撤销远端效果另签高风险external包。

## 2. branch/worktree成本门

共享本地仓默认不为每个任务、会话或Reviewer创建branch/worktree/独立index。只有以下情况之一成立才使用：

- 文件所有权不可避免重叠；
- 长周期或高风险实验需要可回收隔离；
- 多个候选真实并行；
- 主工作树必须持续保持可发布。

创建前评估dirty diff复制/应用成本、磁盘、依赖安装/缓存、合并冲突、保护路径与集成顺序，并指定唯一集成负责人。独立Review通常只需读取stable candidate，不以独立worktree作为独立性的形式门。

## 3. External动作分层

下列状态彼此独立，前一步不授权后一步：

1. 官方资料只读查阅；
2. 下载；
3. 安装或接受许可协议；
4. 登录、账号/团队绑定或AppID；
5. 设备授权与本地运行；
6. 上传测试包；
7. 提审；
8. 正式发布、付费或其他不可逆动作。

只读盘点可由领域owner常规批准；下载/安装依项目权限；账号、设备、上传、提审、push和发布必须绑定用户确认或项目明确外部授权。任务卡、日志、截图和仓库不得保存密码、token、私钥或其他秘密。

本地构建、测试包生成、设备可运行、上传成功、平台审核通过和正式发布分别记录真实时间、执行者、输入对象和结果。不得用模拟器冒充真机、Web壳冒充平台产物、截图冒充交互或commit冒充发布。

## 4. 工具链与产物证据

相关任务按需要核对：

- 官方来源、访问日期、精确版本；
- 下载URL/文件名/字节/SHA和可用签名；
- 安装器、安装目录、缓存、项目工程与产物分离；
- 空间上限、清理、卸载和回滚；
- 构建输入commit、配置、工具版本、日志、包体与可复现命令；
- runtime/设备的客户端、OS/GPU、分辨率/DPR、生命周期、性能矩阵；
- 网络、资源、后台恢复、context loss和版本回退。

只执行与current可达风险相称的项目；普通功能Git checkpoint不加载或运行整套平台十项。

## 5. 外部生命周期与任务关闭

内容已APPROVED/MERGED但仍等待external时，原任务保持active并记录待执行actor、授权和真实远端状态。外部成功后先记录branch/commit/tag/push/upload/review/release等实际结果，再关闭归档；失败或冲突保持active并记录`BLOCKED`，不伪造成功或无限轮询。

push失败、平台状态无变化或等待审核时依靠外部事件/主动回传；不使用循环查询维持进度感。监控只有用户明确要求并有有界频率/停止条件时启用。

## 6. Framework与项目版本

稳定Framework版本保留在唯一AI-Workspace仓的`framework/versions/`，`CURRENT`只改变新项目默认值。tag只作可选审计/下载标记，不参与项目恢复。稳定版本不可原位修改；修正发布新版本。

Framework发布、`CURRENT`更新、项目pin升级和Pocket等具体项目迁移是四个独立动作。Framework STABLE不自动升级项目；项目升级必须另立任务并使用当时真实项目状态验证。
