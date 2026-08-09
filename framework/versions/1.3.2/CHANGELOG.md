# v1.3.2 变更说明

## 版本性质

Framework 1.3.2是1.3.1的向后兼容patch热修。1.3.1及更早稳定目录保持字节不变；1.3.2继续保留`MICRO / STANDARD / CRITICAL`、两级恢复、范围保护、独立审核与外部权限分离。

版本生命周期统一为`DRAFT / REVIEW / STABLE / RETIRED`：开发中的候选允许返工；版本进入STABLE即不可原位修改，后续修正一律创建新的patch版本。是否已被项目消费只影响保留或退休策略，不影响不可变性；`framework/CURRENT`只决定新项目默认版本，不强制现有项目升级。

## 可达性与证据降本

- 新增`CURRENT_REACHABLE / CONTRACT_REACHABLE / FUTURE_ONLY / UNVERIFIED`四态判断。
- 当前producer、入口或生命周期实际可达时，才按玩家影响升级集成、浏览器、设备或玩家证据。
- 公共合同允许但current没有自然入口时，默认只要求最窄直接/合同反例，不制造假producer或重型外部证明。
- 未来才可达的问题进入未来任务或接口合同，不阻断current候选；无法判断时先只读追producer/consumer。

该规则用于降低“为不会从current路径发生的问题建立完整玩家链路和设备证据”的净成本，不削弱公共合同的fail-closed保护。

## 宿主适配分层

- 核心`GOVERNANCE / WORKFLOW / REVIEW / TEMPLATE / PROMPTS`只持有平台无关owner、范围、权限、审核和生命周期。
- Codex的任务消息、等待、条件式确认、actor/notifier与直接审核发送时序集中到`HOST_ADAPTER_CODEX.md`。
- actor/notifier成为可选宿主扩展：checker在字段存在时验证一致性，没有多会话时不要求任务卡虚构字段。
- 其他宿主可以提供自己的适配页，但不得改变唯一owner、审核独立性或Git/外部权限。

## 单仓多版本发行

- `AI-Workspace`同时是Framework开发与发行的唯一仓库，不再维护第二个发行仓。
- 默认分支在`framework/versions/`保留全部稳定版本，普通Git检出与ZIP下载都能解析项目pin。
- `framework/versions/<version>`是运行与恢复权威；tag只作可选审计或下载标记，缺失tag不影响注册、恢复或升级。
- root `upgrade-project.ps1`只使用默认分支现存版本目录。固定旧目录缺失或不完整时明确拒绝，不从tag或当前HEAD猜历史Bootstrap。

## 项目控制面迁移边界

通用Framework长期只保留规则、工具、中立模板和示例；真实项目的`project.json / BOOTSTRAP / PROJECT / STATUS / REVIEW_PROFILE / RELATIONSHIPS / tasks / reports`应进入项目自己的版本控制边界。

1.3.2只冻结该目标和迁移停止线，不移动当前`projects/pocket-legion`：W1-6B、Roster Phase D及其他在途任务先到稳定检查点，随后再通过独立迁移任务把项目控制面移入项目仓`.ai-workspace/`并更新初始化/升级入口。

## 兼容性

- 1.3.1任务卡继续可读；带actor/notifier的卡作为宿主扩展继续校验。
- 1.3.0机械摘要继续作为兼容输入，不要求旧卡迁移。
- Pocket Legion当前pin不因1.3.2候选或CURRENT变化自动升级。
- 本版本不授权项目目录迁移、Git提交、push、tag或外部发行。
