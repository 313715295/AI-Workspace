# Framework维护控制面与平级目标仓

本模块只为`controlPlaneLayout=framework-maintenance-sibling`加载。它不改变普通项目repo-local规则，也不授予任意跨仓访问。

## 1. 固定拓扑

Maintenance控制仓和Framework目标仓必须是同一普通父目录下的两个平级、非reparse Git top。父目录自身不得包含`.git`或`.ai-workspace`。控制仓持有唯一`.ai-workspace`；正常运行时目标仓不得持有`.ai-workspace`。

配置只允许一个`frameworkTarget`：稳定`repositoryId`、单一安全`siblingDirectory`和目标仓routine exclusions。不得接受绝对路径、`..`、通配符、junction/symlink、自动搜索到的第二目标或用户主目录级宽泛根。

schema4首版固定`frameworkCapabilities={}`。普通repo-local的可选知识能力不被删除；未来若Maintenance需要能力字段，作为独立公共合同和版本任务评估。

## 2. 恢复顺序

1. 从Maintenance仓`.ai-workspace/BOOTSTRAP.md`读取并严格验证schema4 config、controller和显式pin。
2. 以冻结project config identity运行`resolve-framework-maintenance-target.ps1`，复证control/target两个Git top和目标pin入口。
3. 用`Topology=FRAMEWORK_MAINTENANCE_SIBLING`运行loader并完整读取本模块。
4. 读取Maintenance项目事实、任务与authorization；再显式读取目标仓`AGENTS.md`、Framework入口和任务点名的target对象。
5. 分别取得control和target的HEAD/index/dirty；任一UNVERIFIED不允许用另一仓结果补洞。
6. 报告当前包绑定的repository ID。没有fresh包时保持两个仓只读。

Codex的平级目标规则不被假定为自动加载；Bootstrap的显式读取是Framework合同的一部分，但不能覆盖系统、宿主或目标仓更高优先级指令。

## 3. 写入与授权

maintenance schema2授权包必须包含`repositoryId`和`projectConfigIdentity`，且一个包只绑定一个仓：

- `CONTROL`：只覆盖Maintenance控制仓的CONTROL_WRITE及明确的本仓Git动作；
- 配置中的target repository ID：只覆盖Framework source/test/read-only verification及明确的目标仓Git动作。

路径始终相对于包绑定的Git top。控制卡与目标源码需要状态变化时分成两个连续包；target包不得写Maintenance控制文件，control包不得写Framework目标源码。writer交接、repository ID、project config、controller epoch、pathset、object identity或用户决定变化均使包失效。

schema2 authorization checker必须直接运行同版本steady-state resolver，而不是复制一套拓扑判断。resolver没有同时证明CURRENT controller、两个真实Git top、完整目标pin与目标控制面absence时，CONTROL和target包都fail closed。

授权包不能自行降级选择schema1。checker拒绝`GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR`进程覆盖，证明实际cwd按组件属于无reparse Git top，并严格验证canonical schema3 config、routine exclusions与capabilities；Maintenance/schema4只接受schema2。schema1兼容性只属于通过这些检查的实际repo-local项目。

## 4. Git与dirty

`invoke-protected-safe-git.ps1`在maintenance布局下必须收到control root、repository ID和冻结project config identity，并消费resolver结果。每个仓分别应用自己的routine exclusions、bounded positive pathset及Git closer；禁止在父目录运行Git、`git add .`、跨仓stage或用一个仓的clean推定另一个仓clean。

## 5. 稳态边界与物理迁移

Framework 1.7.0只定义最终稳态：Maintenance控制仓的controller为唯一`CURRENT`，控制仓持有唯一canonical `.ai-workspace`，Framework目标仓没有`.ai-workspace`。resolver、Bootstrap、authorization与safe Git只接受该稳态，不提供迁移观察开关、临时controller状态、双权威选择、自动切换、自动回滚或跨仓事务。

创建专用父目录、创建Maintenance仓、移动Framework仓、转移或退役旧控制面以及首次FULL_COLD属于具体项目的离线迁移。该操作必须另立项目任务，冻结真实源/目标、旧权威、恢复材料和中断处理，并取得涉及目录、控制面与Git的实际授权；它不是Framework版本安装或starter渲染的一部分。迁移未完成且未被fresh FULL_COLD接受前，旧项目权威不因1.7.0候选存在而变化。

目标仓出现完整、部分、foreign或reparse `.ai-workspace`时一律fail closed。Framework不会读取它来判断权威，也不会用聊天、历史卡或恢复目录补足最终稳态。
