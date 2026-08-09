# 任务模板 v1.4.0

先按`GOVERNANCE.md`与`WORKFLOW_PLAYBOOK.md`选择最低充分档位。`MICRO`默认不建卡；只有需要持久locator但仍能在同turn闭合时才使用下面的最小卡。普通跨turn工作使用`STANDARD`。只有关键风险使用`CRITICAL`完整卡。影响面、owner或风险不确定时向上升级。

`<...>`必须替换。workspace相对路径使用`/`；`expected_paths`是冻结exact，`actual_paths`是当前已知实际子集。进入`REVIEW / ACTIVE / CLOSED`时二者必须相等。

## MICRO持久卡（可选）

```markdown
# <TASK-ID> — <标题>

- 状态：ACTIVE_WRITE
- 任务档位：MICRO
- 风险：低；<四维简述>
- 唯一长期owner/调度者：<owner>
- Exact路径：[<workspace/relative/path>]
- Forbidden路径：[<workspace/relative/protected>]
- Git 权限：关闭 / <精确本地权限>
- 外部动作授权：无
- 范围摘要：`profile=MICRO; lifecycle=ACTIVE_WRITE; expected_paths=[<workspace/relative/path>]; actual_paths=[]`
- 创建/更新：YYYY-MM-DD

## 目标

<目标、直接证据和回退方式>

## 范围与保护

<exact为何足够；forbidden与其他owner边界>

## 验收与验证

<直接验收、命令/观察和真实结果>

## 交接/下一步

唯一下一动作：<同turn动作；若跨turn、阻断或扩面则升级STANDARD>
```

无持久卡的`MICRO`不运行checker，但当轮仍须明确同样的目标、exact/forbidden、验证、Git/外部权限和结果。

## STANDARD紧凑卡

```markdown
# <TASK-ID> — <标题>

- 状态：ACTIVE_WRITE
- 任务档位：STANDARD
- 风险：低 / 中；<四维理由>
- 唯一长期owner/调度者：<owner>
- Exact路径：[<workspace/relative/a>|<workspace/relative/b>]
- Forbidden路径：[<workspace/relative/protected>]
- Git 权限：关闭 / <精确本地权限>
- 外部动作授权：无
- 范围摘要：`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[<workspace/relative/a>|<workspace/relative/b>]; actual_paths=[]`
- 创建/更新：YYYY-MM-DD

## 目标

<问题证据、目标合同>

## 非目标

<明确不改变的行为与边界>

## 范围与保护

<exact/forbidden、必要contingency、直接consumer、其他owner边界>

## 验收与验证

<验收、直接测试、风险相称的pre-mortem和真实结果>

## 交接/下一步

唯一下一动作：<唯一角色和动作>
```

`STANDARD`默认不声明宿主通信字段。只有当前宿主实际挂载多个独立任务上下文且字段能减少歧义时，才按对应`HOST_ADAPTER_*.md`增加扩展；核心范围摘要不因宿主变化而改变。

```markdown
- 当前actor：EXECUTOR
- 唯一下一动作执行者：EXECUTOR
- Review开始通知方：EXECUTOR
- 审核人：<合格审核者>
- 直接审核闭环：关闭 / <消息、返工、轮次和停止线>
- 范围摘要：`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[<workspace/relative/a>|<workspace/relative/b>]; actual_paths=[]; current_actor=EXECUTOR; next_actor=EXECUTOR; review_start_notifier=EXECUTOR`
```

## CRITICAL完整卡

```markdown
# <TASK-ID> — <标题>

- 状态：ACTIVE_WRITE
- 任务档位：CRITICAL
- 风险：高；<风险四维与失败代价>
- 审核场景：现有对象审计 / 修改后审核
- 唯一长期owner/调度者：<主控或领域分管>
- 执行载体与资源：owner直接执行 / 内部子Agent / 独立任务会话；<资源与理由>
- 恢复模式与基线：FULL_COLD_RECOVERY / WARM_TASK_REBIND；<证据或升级条件>
- 当前写入者：无 / <临时角色>
- 审核人：<未参与实质写入的合格角色>
- Git 收口者：<会话或角色>
- Git 权限：关闭 / <条件预授权及精确门>
- 外部动作授权：无 / <逐项动作、范围与批准者>
- Exact路径：[<workspace/relative/a>|<workspace/relative/b>]
- Forbidden路径：[<workspace/relative/protected>]
- 范围摘要：`profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_exact=2; expected_paths=[<workspace/relative/a>|<workspace/relative/b>]; actual_paths=[]`
- 创建/更新：YYYY-MM-DD

## 目标

<问题、证据与目标合同；可达性=CURRENT_REACHABLE / CONTRACT_REACHABLE / FUTURE_ONLY / UNVERIFIED>

## 非目标

<明确不做什么>

## 权威输入与前置事实

<权威、HEAD/index、其他owner、恢复证据>

## 范围与保护

### Producer / direct consumer / tests / runner-manifest / docs

<完整范围闭包；跨域子卡必要性、父卡consumer与退出条件>

### Conditional contingency

<路径与触发条件>

### Forbidden与保护边界

<用户、其他owner和外部边界>

## 方案、影响与pre-mortem

<抽象切入点、关系图影响、至少三项失败原因及对应检查>

## 选用评审视角

<3–5个视角与证据>

## 验收与验证

<行为声明、完成标准、命令、运行观察、证据有效键和复用边界>

进入Review前冻结稳定内容对象/section identity、candidate与依赖manifest、验证上限和任务卡可变区；逐轮记录delta、受影响层、停止线和最终owner回传。

## 执行、审核与Git记录

<过程证据、额外发现路由、审核结论和真实Git/外部结果>

## 交接/下一步

唯一下一动作：<唯一角色和动作>
```

Codex等宿主需要直接消息闭环时，在核心卡顶追加其适配页定义的actor/notifier、回传和direct-loop字段，并给范围摘要追加对应尾段。未实际使用多任务通信时不得填充占位字段。

## checker边界

有持久卡时由AI调用项目固定版本的`scripts/check-task-card.ps1`。进入Review、Git收口或关闭前，从git status/diff或冻结manifest独立得到本任务actual，并以`-ObservedActualPath`逐卡传入。checker只核对UTF-8/结构、profile字段、核心范围摘要、expected/actual、观察路径、生命周期，以及存在时的宿主actor/notifier一致性；它不扫描Git归属、不识别owner、不判断可达性、设计或风险选择，也不授予审核、Git、阶段或外部权限。

1.3.0格式的`机械摘要`可作为`CRITICAL`兼容输入；历史正文中的exact数字不参与current判断。无摘要legacy卡只报告`LEGACY_UNCHECKED`，不要求全量迁移。

## repo-local控制面任务附加字段

涉及`.ai-workspace`、register或upgrade的`CRITICAL`卡还必须明确：`controlPlaneLayout=repo-local`或`central-legacy`、项目Git顶层身份、固定Framework版本、发现优先级、期望布局与临时对象清理边界。register只能创建全新repo-local项目；upgrade的来源与目标布局必须相同。

中央legacy搬到repo-local不是Framework命令。需要时由项目owner另建一次性项目卡，冻结实时源清单、声明允许转换和项目仓候选验证；项目仓提交并冷恢复通过前中央保持唯一权威，中央删除由后继卡单独授权。Framework能力卡不得把该项目操作扩成通用跨仓事务或恢复产品。
