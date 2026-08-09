# <TASK-ID> — <标题>

- 状态：BACKLOG
- 领域：<项目定义的主领域>
- 风险：轻 / 中 / 重
- 风险四维：影响范围 / 行为复杂度 / 依赖数量 / 运行时可观察性
- 审核场景：现有对象审计 / 修改后审核
- 唯一长期owner/调度者：<主控或领域分管>
- 执行载体与资源：owner直接执行 / 内部子Agent / 独立任务会话；<项目资源映射与理由>
- 恢复模式与基线：FULL_COLD_RECOVERY / WARM_TASK_REBIND；<基线成立理由、实际增量读取集、未重复读取对象或升级条件>
- 当前写入者：无 / <临时角色>
- 当前actor：OWNER / EXECUTOR / REVIEWER / USER / EXTERNAL / NONE
- 唯一下一动作执行者：OWNER / EXECUTOR / REVIEWER / USER / EXTERNAL / NONE
- Review开始通知方：EXECUTOR / <无执行者且审核者直接审稳定对象时为REVIEWER> / <停止线或range gate后current/next均为OWNER且owner自己冻结并委派或续审时为NONE>
- 审核人：<未参与实质写入的角色；不适用时说明>
- 直接审核闭环：关闭 / <指定审核者、直接消息机制、允许的范围内返工、执行者唯一Review开始通知、固定对象发送后立即停写、实质回复兼作ACK、仅延迟或identity/manifest/范围/独立性/权限异常时向执行者单发条件式ACK或阻断、直返轮次上限、同一发现复发与其他停止线、最终owner回传>
- Git 收口者：<会话或角色>
- Git 权限：关闭 / <条件预授权及精确门>
- 外部动作授权：无 / <精确动作、范围与批准者>
- 回传对象与机制：<唯一owner；完成/阻断/新授权时的消息机制>
- 机械摘要：`lifecycle=ACTIVE_WRITE; current_actor=<...>; next_actor=<...>; current_exact=<expected集合数量>; expected_paths=[<workspace/relative/a>|<workspace/relative/b>]; actual_paths=[<已知实际子集>]; review_start_notifier=<...>`
- 创建/更新：YYYY-MM-DD

## 目标与问题证据

## 非目标

## 权威输入

## 前置事实与工作树

## 范围闭包与文件所有权

### Producer / direct consumer / tests / runner-manifest / docs

跨域任务默认单父卡；若建独立领域卡，在此写明独立生命周期/owner字节/外部状态/可关闭交付物/审核结论的必要性、父卡consumer与退出/归档条件。

### Exact pathset

### Conditional contingency

### Forbidden与保护边界

## 影响范围与关系图

## 方案与 pre-mortem

## 选用评审视角

## 行为声明与验收标准

## 验证命令

### 证据有效键与可复用边界

记录恢复模式、actual对象/manifest、HEAD/index、依赖与环境；温重绑时列出实际增量读取集、未重复读取对象和基线成立理由。进入Review前冻结稳定内容对象/section identity、candidate与依赖manifest、验证上限和任务卡可变区；直接审核闭环逐轮记录delta分类、受影响对象、复用批准、停止线检查和最终owner回传。

新建/实质修改任务卡由AI内部运行`scripts/check-task-card.ps1`。唯一机械摘要的`current_exact`必须为正整数并等于expected集合数量；不要从历史正文的candidate/executor/content/closure exact记录推导current。pathset统一slash与trim并拒绝空项/重复/规范化碰撞；`ACTIVE_WRITE`允许actual为expected已知子集，`REVIEW/ACTIVE/CLOSED`必须完全相等。进入Review、Git收口或关闭前，AI从git status/diff或manifest独立得到本任务actual并以`-ObservedActualPath`逐卡传入；检查器不扫描全仓归属。无摘要legacy卡不因检查器强制迁移。

## 执行记录

## 额外发现及路由

## 审核记录

## Git 收口记录

## 交接/下一步

唯一下一动作：
