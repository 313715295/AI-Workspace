# Framework开发与发行

本模块只由Framework维护/发行owner加载，不进入普通项目任务。

## 1. 生命周期

- `DRAFT`：可返工、不可项目pin、不可由register/upgrade发现。
- `REVIEW`：候选内容与测试冻结，只允许指定返工。
- `STABLE`：完整批准、测试和发行收口完成；发布到`framework/versions/<version>/`后不可原位修改。
- `RETIRED`：历史保留，可停止新消费；不得重写历史字节。

DRAFT使用`framework/drafts/<version>/`；正式项目只定位`framework/versions/<pin>/`。从DRAFT晋升不是普通目录复制：发行owner必须冻结完整inventory、内容identity、测试结果、Review verdict和迁移/兼容结论。进入稳定目录后禁止原位修正，后续finding发布patch版本。

版本生命周期不等于每次都走同一发行重量。发行owner先分类：

- `FULL_RELEASE`：新增/破坏公共合同、模块inventory、starter拓扑、根register/upgrade事务、CURRENT策略或不兼容schema；运行完整迁移矩阵、全角色加载闭包、完整集成测试和独立Framework Review。
- `PATCH_HOTFIX`：从当前稳定版派生，保持向后兼容，不改变模块/starter/根事务拓扑，只修正文档、checker、模板或局部脚本缺陷；走受影响范围的direct正反例、strict文本、依赖smoke和必要聚焦Review。

PATCH不得为了“看起来像发行”重复完整迁移、全角色×档位矩阵、跨项目自然样本或未受影响的register/upgrade集成。只有literal delta触及相应机制时才升级对应测试；影响面不明或出现第一个不兼容证据时立即升级`FULL_RELEASE`。`drafts/<version>`对PATCH只是临时编辑区，不是需要长期等待的试点阶段。

## 2. 1.5.1 PATCH_HOTFIX输入

1. 1.5.0→1.5.1 patch迁移矩阵0个未解释语义缺口，1.5.0稳定目录零修改；
2. 公共核心、loader模块集合和starter inventory相对1.5.0拓扑不变；
3. loader对受影响的owner/controller计划与core-only计划保持确定、有序、去重并输出成本；
4. 授权checker覆盖签发层级、用户门、action、path、identity、actor和失效条件；task checker覆盖条件式阶段验收链、用户证据candidate与`current_exact`绑定及正反例；
5. task checker、template、prompts、examples与patch hotfix tests同步；根register/upgrade未修改，复用1.5.0完整发行证据并只做1.5.0→1.5.1 smoke；
6. 脚本成功输出紧凑，详细诊断按需；不得用频繁工具调用抵消上下文节省；
7. 因本patch修改机械hard gate，执行一次fresh聚焦Framework Review；普通文案/示例patch不机械要求独立Review；
8. 自然样本只作为后续CURRENT或大型项目采用输入，不阻塞PATCH稳定发行。

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

分别模拟/执行1.4.0、1.4.1、1.5.0和1.5.1候选恢复与阶段流，输出：语义差异、加载成本、误拒/漏放、需要迁移的项目字节、工具调用量、质量与返工风险。

结论必须是`KEEP / ADJUST / REJECT`：

- 发现漏掉保护、owner、public contract、试玩或Review门：REJECT或先修；
- 发现普通控制动作仍被发布级门阻断、脚本调用反弹或需批量重写历史：ADJUST；
- 质量不降、返工不升且恢复/协调成本显著下降：KEEP。

对比前后都不自动改Pocket pin。只有1.5.1先进入STABLE、Pocket W1整阶段闭环，Pocket再创建独立升级任务并获得项目授权，才可从1.4.0直接修改pin到1.5.1。

## 5. 发布动作分离

内容批准、生成正式version目录、更新根脚本、运行全量tests、建立commit、可选tag、push、修改CURRENT和项目升级都是不同动作。任何一步成功不推定下一步。

CURRENT只在新稳定版本内容批准、完整测试和发行owner收口后更新；它只影响新项目默认版本。已存在项目继续读取自己的固定pin。
