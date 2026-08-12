# Framework开发与发行

本模块只由Framework维护/发行owner加载，不进入普通项目任务。

## 1. 生命周期

- `DRAFT`：可返工、不可项目pin、不可由register/upgrade发现。
- `REVIEW`：候选内容与测试冻结，只允许指定返工。
- `STABLE`：完整批准、测试和发行收口完成；发布到`framework/versions/<version>/`后不可原位修改。
- `RETIRED`：历史保留，可停止新消费；不得重写历史字节。

DRAFT使用`framework/drafts/<version>/`；正式项目只定位`framework/versions/<pin>/`。从DRAFT晋升不是普通目录复制：发行owner必须冻结完整inventory、内容identity、测试结果、Review verdict和迁移/兼容结论。进入稳定目录后禁止原位修正，后续finding发布patch版本。

## 2. 1.5.0发行输入

1. 1.4.1→1.5.0迁移矩阵0个未解释语义缺口；
2. 公共核心与所有按需模块完整、自洽、无角色×档位组合爆炸；
3. loader对所有role/profile/phase/host组合确定、有序、去重、依赖闭包并输出成本；
4. 授权checker覆盖签发层级、用户门、action、path、identity、actor、失效条件和正反例；
5. task checker、starter、templates、prompts、examples、register/upgrade和完整tests同步；
6. 脚本成功输出紧凑，详细诊断按需；不得用频繁工具调用抵消上下文节省；
7. fresh独立Framework Review通过；
8. 自然样本计划、停止线和`KEEP / ADJUST / REJECT`落点已冻结；自然样本结果是CURRENT切换和大项目采用门，不要求为发布制造任务。

## 3. 质量与成本指标

静态指标：首次加载bytes/token估算、模块数、重复规则、脚本调用点、成功输出大小、迁移文件数。

自然任务指标：准备耗时、FULL/WARM比例、Review角色数、返工、范围冲突/缺陷拦截、恢复耗时和授权误拒/漏放。允许缺失，不建立逐任务报表或长期平台。

接受原则：先保持质量与返工不恶化，再比较上下文、延迟和人工协调成本。节省单轮token但增加重大返工、漏审或用户纠偏，判定`ADJUST/REJECT`。

## 4. Pocket升级前专项对比

Pocket达到可升级状态后，使用其当时真实：

- 项目控制面与Framework 1.4.0 pin；
- 主控/Design/Core/Render/Platform/Pure Art owner拓扑；
- current热卡与history carrier；
- 保护路径、shared dirty工作树和Git closer规则；
- W1玩家试玩→独立Review流程；
- 近期自然任务的恢复、授权、返工和缺陷数据。

分别模拟/执行1.4.0、1.4.1和1.5.0候选恢复与阶段流，输出：语义差异、加载成本、误拒/漏放、需要迁移的项目字节、工具调用量、质量与返工风险。

结论必须是`KEEP / ADJUST / REJECT`：

- 发现漏掉保护、owner、public contract、试玩或Review门：REJECT或先修；
- 发现普通控制动作仍被发布级门阻断、脚本调用反弹或需批量重写历史：ADJUST；
- 质量不降、返工不升且恢复/协调成本显著下降：KEEP。

对比前后都不自动改Pocket pin。只有1.5.0先进入STABLE，Pocket再创建独立升级任务并获得项目授权，才可修改pin。

## 5. 发布动作分离

内容批准、生成正式version目录、更新根脚本、运行全量tests、建立commit、可选tag、push、修改CURRENT和项目升级都是不同动作。任何一步成功不推定下一步。

CURRENT只在新稳定版本内容批准、完整测试和发行owner收口后更新；它只影响新项目默认版本。已存在项目继续读取自己的固定pin。
