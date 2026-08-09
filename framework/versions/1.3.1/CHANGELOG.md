# v1.3.1 变更说明

## 发布边界

Framework 1.3.1是从已发布`v1.3.0`创建的新版本目录和新tag。1.3.0在公开tag之前曾有内部冻结候选增量，这些增量已经包含在公开的1.3.0基线中；公开`v1.3.0`目录、commit与tag未被改写。1.3.1首次发布后、尚无外部项目消费发布仓时，用户明确授权把本页记录的异步等待与latest-only兼容修正直接纳入1.3.1；内容批准不等于tag已移动，只有release owner可在独立发行门更新`v1.3.1`。现有项目只有显式更新`project.json.frameworkVersion`才启用1.3.1；新项目使用激活后的`framework/CURRENT`。

## 三档工作强度

- 新增`MICRO`：仅用于健康owner会话可同turn闭合的单领域低风险工作；默认不创建完整任务卡、临时执行者或独立审核者。无持久卡时，当轮仍必须明确目标、exact/forbidden、验证、Git/外部权限和结果；跨turn、阻断或扩面立即升级。
- 新增`STANDARD`：普通单领域功能、缺陷或跨turn工作使用紧凑卡；只保留必要目标/边界/验收/权限/下一动作，独立审核按风险触发。actor/notifier/direct loop只在真实挂载多角色时出现。
- `CRITICAL`保留1.3.0的完整范围闭包、稳定审核对象、独立审核、actor/notifier、direct loop、证据有效键与外部生命周期门，用于公共合同、复杂状态机、核心循环、持久状态、平台/runtime、账号/发布、不可逆或高缺陷代价任务。
- 所有档位继续要求唯一owner、工作树保护、exact/forbidden、真实HEAD/index/diff、必要验证及Git/push/外部权限分离。档位不会降低这些底线。

## 恢复、审核与checker

- `FULL_COLD_RECOVERY`仍用于首次进入或基线不可证明；它是首次建立可信基线的成本，不是每任务默认。同一健康会话默认按档位`WARM_TASK_REBIND`并重新取得权限。
- `MICRO`由owner自检并承担结果；无独立触发条件的`STANDARD`可由领域owner实施并聚焦审核；`CRITICAL`保留与方案设计者及实质写入者不同的合格最终审核者和direct-loop停止线。
- checker移入版本目录`scripts/check-task-card.ps1`，项目pin决定所用实现，避免未来root脚本变化静默改变已pin项目。
- 新`范围摘要`支持`MICRO / STANDARD / CRITICAL`必要字段；1.3.0`机械摘要`仍作为`CRITICAL`兼容输入，不反向修改1.3.0。
- checker只验证任务卡结构化声明、机器观察actual、生命周期以及已声明actor/notifier的一致性。它不扫描Git归属、不识别owner、不判断设计或风险选择，也不授予审核、Git、阶段或外部权限。

## 示例、测试与轻量观察

- 新增`EXAMPLES.md`，分别展示一个自然`MICRO`、`STANDARD`和`CRITICAL`任务，以及向上升级的明确条件。
- 新增PowerShell 5.1可运行测试，覆盖三个profile正例、声明升级、缺字段、path越界、observed身份、历史文本污染、notifier边界和project-starter pin/Bootstrap定位。
- 1.3.1分级首轮只从10–20个自然关闭任务的既有记录中提取准备耗时、恢复模式、审核角色数、返工、冲突/缺陷拦截和恢复耗时。允许缺失值；不增加每任务报告、第二流程、指标平台或为取得样本制造任务。停止线到达后在既有框架维护任务中作`KEEP / ADJUST / REJECT`。

## 异步等待修正

- 独立任务会话默认通过主动消息回传，不调用`wait_threads`或等价轮询维持进度感。只有用户明确要求同步等待、当前turn必须消费结果且预计一次有界等待可完成、或主动回传疑似丢失三类例外，才允许对同一触发事件和同一目标做一次有界等待或即时快照。
- 超时或状态没有实质变化后不得立即再等待，直到外部状态变化或用户新指令。为ACK、普通进度、idle或“看看是否完成”而等待统一记录为执行偏差，不建立新状态或报告流程。

## 兼容性

- 1.0.0、1.1.0、1.2.0和1.3.0目录保持不可变。
- Framework语义绑定的checker、tests、templates和examples随版本；跨版本工作区入口`register-project.ps1`与`upgrade-project.ps1`保留在根`scripts`。root checker只兼容已发布1.3.0 Bootstrap，不是未来默认。
- 1.3.0项目继续使用原root checker合同；升级到1.3.1时，root upgrade以持久可恢复事务迁移pin与目标Bootstrap/checker定位，不声称跨文件原子。只有完整提交或完整回滚后才清理事务材料；中断或回滚失败保留新旧配对与状态，下一次调用先恢复或续作，无法安全迁移则明确拒绝而不静默遗留半升级。
- 开发`AI-Workspace`可保留全部版本目录；`AI-Workspace-Releases`默认分支只保留`framework/CURRENT`所指最新版本与通用根入口，历史版本只存在于annotated tag，不在latest-only下载中重复携带。
- latest-only Git检出缺少项目所pin的旧目录时，root upgrade只读当前仓库本地`v<旧版本>`tag中的对应Bootstrap starter并执行原有严格渲染/一致性门；非Git/zip、缺tag、tag不完整或模板不匹配均fail closed，不联网、不从当前HEAD替代旧模板。
- 根`register-project.ps1`可通过显式`-FrameworkVersion 1.3.1`消费新starter；`framework/CURRENT`激活由发布owner在独立批准后单独完成。
