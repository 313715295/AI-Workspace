# AI-Workspace项目初始化与恢复入口

本文件只在以下场景按需读取：新项目首次接入、新电脑/新工作区发现项目、repo-local控制面缺失，或初始化/升级身份冲突。普通已有项目会话直接从项目`.ai-workspace/BOOTSTRAP.md`恢复，不读取本文件。

## 1. 先识别已有项目

1. 从AI-Workspace根和用户提供的源码路径识别真实Git顶层；非Git、子目录或身份不明时停止。
2. 严格读取`<project-git-root>/.ai-workspace/project.json`和`BOOTSTRAP.md`。完整schema2 repo-local控制面优先。
3. partial、reparse、不可读、项目ID/repository/pin冲突或未知live bytes立即`NEEDS_INPUT`；不得覆盖、补洞或回退到猜测。
4. repo-local完全不存在时，才检查已挂载的中央legacy `projects/<project-id>/`。匹配的legacy存在时按其Bootstrap恢复，禁止register。
5. repo-local与legacy并存且身份一致时，repo-local是唯一入口、legacy冻结只读；身份冲突时停止。
6. 只有两处控制面都不存在，才进入“全新项目”分支。

聊天、旧摘要、tag、当前HEAD、网络结果和`framework/CURRENT`不能替代项目固定身份或历史版本目录。

## 2. 调查全新项目

在创建任何文件前，只读建立有限注意力地图：

- 项目入口、技术栈、构建、测试和运行方式；
- 产品/架构资料及其current权威；
- 源码、测试、资产、生成物和保护路径线索；
- 已存在的AI薄入口、Git状态、分支/worktree和并行owner风险；
- 用户提供的产品目标、目标平台和本地资料。

把结果分为“事实 / 建议 / 冲突 / 待确认”。可从源码和资料可靠推导的内容不重复询问用户。

项目ID规范为小写ASCII段并以单个连字符连接；无法可靠转换或用户明确自定义时，把它放进一次性问题，不静默猜测。

## 3. 一次性确认

只询问仍会改变安全工作或项目身份的缺口：

- 产品目标、目标用户与目标平台；
- 必须保护、禁止读取/改写或由用户独占的路径；
- 启用哪些长期领域及可确认owner；
- 实际可用模型、质量档、预算或资源限制；
- 本地Git、commit、push、branch/worktree和回退权限；
- 下载、安装、登录、账号、设备、上传、提审和发布权限。

未确认项保持`UNVERIFIED`。用户只确认产品结果、重大方案/公共合同和外部动作；普通本地实现与验证由有权owner按阶段包签发，不要求逐文件批准。

缺少会导致危险写入的决定时输出`NEEDS_INPUT`，不创建控制面。

## 4. 创建全新repo-local控制面

仅在确认以下条件后执行：

- 输入是真实项目Git顶层；
- `.ai-workspace`完全不存在；
- 没有同ID中央legacy；
- 项目Git状态满足项目定义的初始化边界；
- 使用明确的稳定Framework版本，不能从DRAFT、tag或“最新”猜测。

流程：

1. 调用根`scripts/register-project.ps1`默认预览，核对目标、版本和固定inventory。
2. 取得Apply授权后，从固定版本`project-starter`在项目仓同级隐藏staging中生成候选。
3. 验证完整后同仓rename为`.ai-workspace`；失败只清理可证明由本次流程创建的staging。
4. register不stage、commit或push；重复同身份只在完整inventory一致时返回`ALREADY_REGISTERED`。
5. 项目owner把稳定身份、目标与架构边界写入`PROJECT.md`，项目特有审核重点写入`REVIEW_PROFILE.md`，current/未验证写入`STATUS.md`，仅将已批准关系写入`RELATIONSHIPS.md`。
6. 不创建无真实工作的任务卡，不把建议、示例或聊天升级为机制权威。

生成inventory至少包括：

```text
.ai-workspace/
├─ .gitattributes
├─ project.json
├─ BOOTSTRAP.md
├─ PROJECT.md
├─ REVIEW_PROFILE.md
├─ RELATIONSHIPS.md
├─ STATUS.md
└─ tasks/
   ├─ README.md
   ├─ active/
   └─ archive/
```

## 5. 初始化验证

至少验证：

- `project.json`可解析，schema2、项目ID、display name、`repo-local`、`repositoryRoot=..`和Framework pin一致；
- 文本严格UTF-8无BOM、无NUL/U+FFFD、LF并以换行结束；
- 无未替换模板、本机绝对Framework路径或示例项目泄漏；
- Bootstrap能从项目配置唯一定位固定Framework，并按恢复核心、loader模块、项目资料、current任务和任务权威顺序恢复；
- `tasks/active`与`tasks/archive`存在，项目README不复制完整Framework；
- 保护边界、Git/push/external没有被默认授权；
- 除新`.ai-workspace`候选外，源码、index、refs和中央legacy均未改变。

全部闭合后输出`READY`，列出生成目录、固定版本、非阻塞`UNVERIFIED`和唯一下一动作。验证失败时输出`NEEDS_INPUT`或精确失败原因，不把手工脚本修复转交用户。

## 6. 已有项目恢复

已有项目不得重新register或用starter覆盖。按项目Bootstrap选择：

- `FULL_COLD_RECOVERY`：首次进入、长期角色换新、基线不可证明、pin/项目身份变化、保护/owner/影响面不明或健康检查失败。
- `WARM_TASK_REBIND`：同一健康会话且已证明项目、角色、Framework、owner和保护基线；只增量读取新任务、变化权威、真实HEAD/index/actual和新授权。

WARM不继承旧任务权限，也不重复未变化核心/模块；任何冲突立即升级FULL_COLD。

## 7. 同拓扑Framework升级

项目升级只从当前固定稳定版本到明确目标稳定版本：

1. 先运行根`scripts/upgrade-project.ps1`预览。
2. 复证项目Git根、旧/新固定版本、Bootstrap受管区、自定义区、保护路径和真实dirty边界。
3. Apply只更新`project.json`pin与Bootstrap唯一FRAMEWORK-MANAGED区，逐字保留PROJECT-CUSTOM区。
4. 不重建PROJECT/STATUS/RELATIONSHIPS/tasks，不批量迁移历史卡，不stage/commit/push。
5. 升级后立即以新版本完整冷恢复，验证owner、current任务、保护路径、权限和Git状态。

受管区被项目改写、marker缺失、目标starter拓扑不同、目标非STABLE或事务前提不成立时拒绝并保持零mutation。

## 8. 中央legacy搬迁

中央legacy→repo-local不是通用upgrade。必须由项目owner另建一次性专属任务，冻结实时源清单并明确转换`project.json`、Bootstrap和薄入口。

项目仓提交并完成repo-local冷恢复前，中央副本始终是唯一权威。成功后中央冻结和删除分别授权；任何时刻不得让两处同时可写。Framework根脚本不会自动复制、提交、切换权威或删除中央项目。

## 9. 权威边界

- 本文件是初始化/恢复算法入口，不是项目运行时治理模块。
- 通用角色、任务、授权、Review、Git和external规则由项目固定Framework持有。
- 项目稳定事实进入项目`.ai-workspace`；Framework根不保存具体项目控制面。
- 已发布版本目录不可原位修改；兼容修正发布patch，破坏性变化走完整发行。
- register、upgrade、commit、push、CURRENT切换和项目pin变更是不同动作，成功不互相授权。
