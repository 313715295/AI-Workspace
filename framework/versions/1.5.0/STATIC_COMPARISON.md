# Framework 1.4.1 vs 1.5.0静态对比

日期：2026-08-12。此处只比较Framework文件与1.5.0机制，不代表Pocket真实升级结论。token使用`ceil(UTF-8 bytes / 4)`作保守估算，不是官方计费tokenizer结果。

## 1. 参考基线

1.4.1四份常用核心文档：

| 对象 | Bytes | 估算tokens |
|---|---:|---:|
| GOVERNANCE + WORKFLOW + REVIEW + Codex host | 76,526 | 19,132 |
| 上述 + PERSPECTIVE_LENSES | 80,556 | 20,139 |
| 1.4.1版本根全部Markdown | 109,563 | 27,391 |

76,526B是“把四份核心全文带入上下文”的参考包络，不表示1.4.1文本合同要求每个执行者都必须逐字加载全部内容；1.4.1依赖人工选择相关章节，缺少可机械复算的角色成本。1.5.0对比的是实际可确定加载包。

## 2. 1.5.0确定性加载

| 场景 | 完整模块 | Bytes | 估算tokens | 相对1.4.1四文档包络 |
|---|---:|---:|---:|---:|
| generic MICRO只读DISCOVER | 1 | 9,441 | 2,361 | -87.7% |
| Codex STANDARD执行IMPLEMENT | 3 | 22,286 | 5,572 | -70.9% |
| Codex STANDARD领域owner PLAN+IMPLEMENT+VERIFY | 5 | 36,017 | 9,005 | -52.9% |
| Codex CRITICAL fresh REVIEW | 4 | 30,969 | 7,743 | -59.5% |
| Codex CRITICAL主控 RECOVER+PLAN | 6 | 40,612 | 10,153 | -46.9% |
| Framework维护者完整职责 | 8 | 48,557 | 12,140 | -36.5% |

当前运行时模块完整并集为48,557B。Review-1冻结候选是DRAFT目录全部30个文件、132,302B；该历史数字包含本文件本身，不是排除自身的递归小计。templates、examples、starter、scripts、tests和迁移证据不进入普通项目加载；发行体积与模型上下文成本必须分开计算。每次冻结候选的目录总量由对应manifest给出。

## 3. 项目总上下文预期

Framework层的STANDARD执行包约5.6k token；领域owner约9.0k；主控冷恢复约10.1k。最终项目总成本还要加：

- Bootstrap轻路由；
- PROJECT/REVIEW_PROFILE/RELATIONSHIPS/STATUS的项目current部分；
- tasks热索引和当前热卡；
- 业务权威、actual diff和必要源码。

因此1.5.0不能只用Framework模块数字宣称“首次恢复低于某值”。项目侧仍需把热卡控制在current、历史carrier只按需读取，并在Pocket可升级时用真实字节复测。目标仍是STANDARD首次工作总上下文约12–18k token、CRITICAL约20–25k；当前Framework层为目标留出了空间，但未完成项目实证。

## 4. 脚本调用成本

- loader只在FULL_COLD或role/profile/phase/host/manifest变化时运行一次；成功一行包含paths与成本，通常约几十token。
- authorization checker在连续writer lease取得时验证计划批次；PASS一行。task/owner/action/path/identity或边界变化才重验。
- task checker只在Review、Git或关闭边界运行；普通编辑过程不调用。
- 发行测试只在Framework开发/发行运行，不进入项目日常会话。

脚本的本地计算、hash和文件读取不进入模型上下文；模型可见命令和stdout/stderr会占token。理想宿主hook本地静默复用PASS digest，只暴露首次摘要或失败。Codex尚未证明有不可绕过的全局pre-tool hook，因此当前只能称机械预检，不冒充操作系统级强制。

## 5. 防御强度变化

降低：

- FULL_COLD不再全文加载三份大文档；WARM不重跑未变化loader。
- 阶段包不逐命令/逐工具调用申请或预检。
- MICRO/普通STANDARD不默认独立Reviewer、worktree、完整manifest和长审核报告。
- 普通控制卡字段变化不以whole-file SHA阻断content批准。
- user只确认产品结果、重大方案/公共合同和external；领域owner签发范围内本地阶段包。
- wait/轮询不作为异步任务正常流程。

保留：

- 唯一owner/writer、保护路径、exact影响闭包和真实dirty隔离。
- 公共合同/状态机/重大玩家行为的方案与独立Review。
- 用户试玩先于最终Review；反例使旧READY失效。
- Git closer与stage/commit/push/external分离。
- runtime/device/platform证据不能由静态检查冒充。
- stable版本不可原位修改，项目pin单独升级。

## 6. 迁移成本

- project.json继续schema2，starter inventory不变。
- 现有项目只需在独立升级任务中更新pin和Bootstrap受管区；PROJECT/STATUS/RELATIONSHIPS/tasks不重建。
- 新任务采用1.5模板；含既有范围摘要的legacy卡继续执行严格文本与scope校验并返回`PASS_LEGACY_SCOPE`，只有确实没有范围摘要的旧对象才返回`LEGACY_UNCHECKED`；不强制全仓迁移。
- tasks旧索引没有profile/phase时，Bootstrap从分配任务顶部current元数据取值；不要求升级时批量改索引。
- 根register/upgrade的跨版本实现无需语义改写，1.5.0发行测试已覆盖显式注册、默认CURRENT、1.4.1→1.5.0升级、custom保留和managed-conflict零mutation。

## 7. 当前风险与停止线

1. fresh独立Framework聚焦Review最终APPROVED；Review-1/2 findings均已限定返工并由后续聚焦复审闭合。
2. authorization/task checker已覆盖NEW对象、Windows/Unicode路径规范化、空角色、未知动作、畸形JSON与旧卡scope反例；仍需自然项目样本观察真实误拒/漏放。
3. 宿主PASS digest复用是合同，尚无Codex全局hook级强制证明；1.5.0不把机械预检冒充操作系统级强制。
4. 还没有自然项目样本，不能证明真实返工率没有恶化；因此`CURRENT`保持1.4.1。
5. Pocket W1进行中，不能用当前控制面做升级实验或改pin。

这些残余风险不阻止1.5.0作为显式opt-in稳定版本，但阻止自动切换`CURRENT`和Pocket pin。Pocket达到可升级状态后另做1.4.0/1.4.1/1.5.0真实对比，并按`KEEP / ADJUST / REJECT`修订。
