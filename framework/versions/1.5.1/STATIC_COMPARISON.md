# Framework 1.5.0 vs 1.5.1静态对比

日期：2026-08-12。token使用`ceil(UTF-8 bytes / 4)`作保守估算，不是官方计费tokenizer结果。1.5.1已进入STABLE；本表只比较Framework字节与流程增量，不代表Pocket升级结论。

## 1. 按需加载成本

1.5.1没有新增运行模块或loader分支。阶段验收语义只进入既有`TASK_AND_SCOPE.md`与`REVIEW_AND_EVIDENCE.md`；所有角色必读核心仅增加一句“用户反馈不授writer、旧包失效并由owner重签”的硬边界。

| 典型1.5.1加载计划 | 模块数 | bytes | 估算tokens |
|---|---:|---:|---:|
| DOMAIN_OWNER / STANDARD / PLAN+IMPLEMENT+VERIFY / CODEX | 5 | 39,241 | 9,811 |
| CONTROLLER / CRITICAL / RECOVER+PLAN / CODEX | 6 | 43,963 | 10,991 |
| FRAMEWORK_MAINTAINER / CRITICAL / 全阶段 / CODEX | 8 | 53,168 | 13,292 |

相同计划在1.5.0分别为36,017B/9,005、40,612B/10,153、48,557B/12,140；领域owner增加3,224B/806保守token，主控增加3,351B/838 token，Framework维护全阶段增加4,611B/1,152 token。`EXECUTOR / MICRO / DISCOVER / GENERIC`仍只加载`RECOVERY_CORE.md`，由9,441B/2,361增至9,705B/2,427，即增加264B/66保守token。

根入口也已按需拆分：旧根README约20,041B，短入口为6,724B；完整初始化算法7,183B进入`INITIALIZATION.md`，只在新项目、新机器或初始化故障时加载。已有项目从repo-local Bootstrap进入，根入口和初始化文件都不进入普通loader。

## 2. 流程成本是否匹配风险

| 任务类型 | 1.5.1增量 | 原因 |
|---|---|---|
| MICRO / STANDARD | 0字段 | 不承担项目阶段推进，不加载验收矩阵 |
| 普通CRITICAL | 1行`Phase gate: FALSE` | 明确不把技术对象误作阶段父卡 |
| 阶段CRITICAL父卡 | 1行开关 + 6行矩阵 | 机械区分证据、领域合同、runtime/platform、项目签署与用户最终门 |
| 无争议技术证据 | 0名额外Reviewer | 领域owner做合同完整性核对，不重复独立技术Review或用户试玩 |
| 不适用runtime/platform | 1个短理由 | 允许N/A，不生产空报告或假验收 |

矩阵只在阶段父卡中存在，避免把W1技术审计直接连到用户最终门，也避免所有任务都新增Design、Platform或主控签字。它防止阶段漏验收造成的返工，成本低于事后重新路由整个阶段。

## 3. 兼容与迁移成本

- schema1.5任务卡继续通过checker，不批量重写current/history。
- schema1.5.1 MICRO/STANDARD无新增字段；普通CRITICAL仅声明FALSE。
- 项目升级不新增文件、服务、数据库或第二状态；starter inventory不变。
- Pocket升级时只比较真实1.4.0现状与稳定1.5.1，并抽查1.5.0差异；W1闭环前不改pin。

## 4. Pocket W1自然样本结论

Pocket W1的实际闭环顺序是：同一候选用户试玩通过 → fresh技术Review通过 → Design领域合同验收 → 主控阶段收口。样本确认阶段需要领域产品验收，但不需要第二次技术Review；当前PC/normal-Web阶段的device项写`NOT_APPLICABLE`也没有制造空报告。

样本同时发现一处成本风险：原草案把`User final gate`写成项目签署后的新动作，容易迫使用户重复确认。1.5.1现明确区分“技术Review/用户试玩的可选执行顺序”和“矩阵最终绑定顺序”：便宜试玩可先拦截反例，高风险对象可先审再玩；同一stable candidate上的既有用户结论直接复用，`CONFIRMED`额外携带一个candidate并由checker逐字比对`current_exact`，candidate或用户决定漂移才重开用户门。该调整不新增角色或项目状态。

## 5. 仍需验证

1. fresh聚焦Framework Review-2已确认条件门没有漏放或误拒；
2. PATCH_HOTFIX direct tests、完整回归与发行manifest复验已通过；未重复制造额外自然样本门；
3. Pocket升级预览仍须确认无批量卡迁移、保护路径/Git边界不退化。

任何一项导致普通任务新增显著协调、阶段验收重复用户试玩、或checker逼迫无关owner出报告，1.5.1判定`ADJUST`，不得升级Pocket。
