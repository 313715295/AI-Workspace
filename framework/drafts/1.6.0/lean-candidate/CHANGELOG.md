# Framework 1.6.0候选变更

相对稳定1.5.2，本候选是`FULL_RELEASE`公共合同变更，当前仍为DRAFT。

## A — RemoteBatch与protected-safe Git

- 新增`REMOTE_BATCH_SCHEMA.json`与`check-remote-batch.ps1`：同一本地repo、多remote、逐项一次尝试、诚实`SUCCEEDED/FAILED/UNKNOWN`与现场aggregate。
- 删除自动retry/PreviousLedger/compensation设计义务；重试必须是fresh batch与fresh authorization，force/delete/撤销另签高风险包。
- 新增`PROJECT_CONFIG_SCHEMA.json`和`project.json` schema 3；`protectedPaths`与整个project config identity成为唯一保护策略输入。
- 新增`invoke-protected-safe-git.ps1`；bounded allowlist与保护路径重叠时不启动Git，返回`UNVERIFIED`且不广泛重试。

## B — 短期资源绑定

- 任务卡默认只写`Resource requirement: DEFAULT`；例外只写minimum quality、required tools与continuity。
- 新增`resolve-resource-binding.ps1`，binding digest覆盖需求、adapter policy、现场能力、选择质量/工具、continuity、phase与context。
- `check-authorization.ps1`对执行/测试/Review动作复证binding locator、identity与digest；任何绑定输入变化使旧PASS不可复用。

## C/G — 直达路由与controller epoch

- 新增`CONTROLLER_SCHEMA.json`、starter `controller.json`和`check-controller-route.ps1`。
- PROJECT_CONTROLLER授权条件绑定controller ID、epoch与整个controller文件identity；DOMAIN_OWNER分支保持独立。
- routine controller报告被抑制，同状态去重；旧epoch routine只作审计，旧epoch decision/authorization/ACK拒绝，exception只有基于current task复证后可重路由一次。

## 迁移

- 新register要求1.6新项目明确ControllerId，生成schema 3 project和epoch 1 controller；不在配置落盘前扫描source工作树。
- 1.4.1/1.5.0/1.5.1/1.5.2 repo-local项目升级到1.6.0时，必须提供冻结protected migration与legacy controller authorization inventory；事务写入project、Bootstrap、controller和revocation ledger。
- Framework发行、根脚本替换、CURRENT变化和项目采用继续分包。
