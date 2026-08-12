# Framework 1.5.0

## 状态

- lifecycle: `STABLE / CONSUMABLE / OPT_IN / NOT_CURRENT`
- source baseline: `Framework 1.4.1 STABLE`
- owner role: `FRAMEWORK_MAINTAINER`
- release status: `FOCUSED_REVIEW_APPROVED / RELEASE_INTEGRATION_VERIFIED`
- project pin authority: `PROJECT_SPECIFIC_UPGRADE_ONLY`

1.5.0是可显式选择的稳定版本。`framework/CURRENT`仍为1.4.1，因此新项目不会默认进入1.5.0；已有项目也不会自动升级。任何项目pin变更都必须通过项目自己的升级任务、真实状态验证和权限门。

## 本版要解决的问题

1. 首次恢复把大段通用Framework、项目资料和热任务卡一次性全文加载，常在开始业务工作前消耗约四万token。
2. `MICRO / STANDARD / CRITICAL`已存在，但恢复、manifest、审核和范围证明仍有发布级防御向普通任务外溢的情况。
3. “默认只读、分阶段授权”主要是文字合同；授权对象、动作、路径、身份、用户决策和失效条件没有统一机械预检。
4. 领域owner能够承担方案、实施和聚焦审核，但权限委派缺少清晰分层，容易把所有本地动作重新汇聚到项目主控或用户。
5. 宿主消息工具、等待、工作树和多会话恢复容易被当成常规动作，而不是有成本的例外。

## 设计原则

- 保留必要硬门：唯一owner、保护路径、范围闭包、公共合同和重大方案门、用户试玩、必要独立审核、Git/push/external分离。
- 降低重复成本：公共恢复核心一次读取；角色、档位、阶段和宿主模块按确定性并集加载；同一授权包可覆盖一个阶段的多个明确动作，不逐命令申请或逐工具调用重复预检。
- 不建立数据库、服务、第二状态系统、逐任务指标平台、角色乘档位的组合文档、长期manifest仓库或每段正文SHA。
- 稳定版只从`framework/versions/1.5.0/`消费；开发草稿、tag、HEAD或网络均不能替代固定目录。
- Framework checker只声明它实际证明的事实，不把结构一致性冒充设计批准、Git归属或宿主级拦截。

## 1.5.0能力

| 能力 | 当前对象 | 目标 |
|---|---|---|
| 通用恢复核心 | `RECOVERY_CORE.md` | 只保留所有角色都必须知道的不变量、发现、恢复、风险和停止线 |
| 确定性按需加载 | `LOAD_MANIFEST.json`、`scripts/resolve-load-plan.ps1` | 由role/profile/phase/host机械求并集并输出字节/token估算 |
| 分级授权包 | `AUTHORIZATION_MODEL.md`、`scripts/check-authorization.ps1` | 一次性绑定task、owner、签发者、唯一执行者、actions、exact、身份、用户门和失效条件 |
| Codex宿主约束 | `HOST_CODEX.md` | 禁止默认worktree、禁止进度轮询、定义pre-tool机械预检边界 |
| 发行测试 | `tests/run-framework-tests.ps1` | 验证稳定元数据、加载闭包、任务/授权正反例、文本质量、注册、升级与失败回滚 |

运行脚本的本地计算本身不进入模型上下文；模型可见的调用文本和stdout/stderr会占用上下文。因此运行时脚本默认只返回一行稳定结果，详细JSON仅供诊断或机器集成。阶段授权PASS在同一连续writer lease内复用，不为每次文件编辑和测试命令重复调用。

## 非目标

- 不重写1.4.1稳定目录；根注册/升级脚本保持跨版本通用实现，1.5.0由发行测试验证兼容。
- 不为Pocket Legion创建Framework实施卡，不改变Pocket W1任务、source/test、Git、Review或外部状态。
- 不把模型品牌写入跨宿主核心合同；宿主只映射质量等级。降低资源档必须经自然任务样本证明缺陷率和返工率没有显著上升。
- 不要求用户逐条批准本地读写、测试或审核路由。用户门只用于产品结果、重大方案/公共合同和外部动作；其余由已授权的项目主控或领域owner按权限等级签发阶段包。

## 发布与Pocket升级前对比门

1. 1.5.0已与1.4.1完成静态合同、加载量、失败门和迁移复杂度对比。
2. 选择不干扰Pocket W1的自然样本验证：恢复是否完整、授权误拒/漏放、准备耗时、返工率和缺陷拦截不得恶化。
3. Pocket达到可升级状态后，使用其当时真实热卡、owner拓扑、保护路径、Git状态和玩家验证流程，比较Pocket固定1.4.0、稳定1.4.1与稳定1.5.0。
4. 对比必须输出`KEEP / ADJUST / REJECT`。发现误拒、漏放、上下文成本反弹、迁移需批量重写热卡或质量/返工显著恶化时，先修1.5.0，不改Pocket pin。
5. Pocket另立升级任务并通过真实对比后才允许修改pin；Framework稳定发行不是项目升级的自动后继动作。

## 完成定义

- cold recovery加载计划有确定性输出，并能证明没有漏掉所选角色/阶段的完整模块。
- 授权checker覆盖允许、越权action、越界path、identity drift、actor漂移、缺失用户确认、无权签发和失效条件缺失等正反例。
- `MICRO / STANDARD / CRITICAL`的记录、审核、manifest和验证成本与风险匹配。
- Framework级机械预检与宿主/操作系统级强制边界被明确区分；不能把“要求调用checker”写成“宿主绝不可能绕过”。
- 1.4.1、`CURRENT`、现有项目pin和项目业务任务保持不变；1.5.0只提供显式opt-in。
