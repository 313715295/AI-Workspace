# {{DISPLAY_NAME}} 会话入口

本文件是项目会话接入协作体系的唯一入口。项目ID为`{{PROJECT_ID}}`，源码仓位置由`project.json`持有，固定Framework版本为`{{FRAMEWORK_VERSION}}`。

## 选择恢复模式

恢复模式、基线和升级条件只由固定Framework的`GOVERNANCE.md`§10与`WORKFLOW_PLAYBOOK.md`§1定义：首次进入或基线不可证明时使用`FULL_COLD_RECOVERY`并执行下列完整读取；同一健康会话且基线可证明时可用`WARM_TASK_REBIND`，只增量读取新任务卡、变化权威/current、actual与HEAD/index、其他owner/保护边界和重新授权。增量核对冲突时升级完整冷恢复；温重绑不继承旧任务权限。

## FULL_COLD_RECOVERY：按顺序读取

1. `project.json`，确认项目ID、源码路径和固定Framework版本。
2. `../../framework/versions/{{FRAMEWORK_VERSION}}/GOVERNANCE.md`。
3. 同版本的`WORKFLOW_PLAYBOOK.md`：至少读取§0和任务风险对应章节。
4. 同版本的`REVIEW_CHECKLIST.md`：执行者用于自检但不能自批；承担审核职责时全文读取。
5. 任务卡选择评审视角时读取同版本`PERSPECTIVE_LENSES.md`。
6. `PROJECT.md`、`REVIEW_PROFILE.md`、`RELATIONSHIPS.md`和`STATUS.md`。
7. `tasks/README.md`及分配给自己的`tasks/active/<TASK-ID>.md`；没有有效任务卡时只做只读调查。
8. 任务卡列出的项目权威资料与相关实现；摘要不能替代原文。

完成完整冷恢复或温重绑后必须能说明：恢复模式与基线、唯一长期owner/调度者、当前角色与资源、任务ID与风险、审核人、exact/contingency/forbidden范围、Git与外部权限、保护边界和唯一下一动作。current exact只读任务卡唯一机械摘要；Review通知方是向owner发送阶段消息的角色，停止线后owner自己冻结并委派时为`NONE`。新建/实质修改任务卡进入Review、Git收口或关闭前，由AI从git status/diff或manifest取得本任务actual pathset，以`-ObservedActualPath`逐卡运行根目录`scripts/check-task-card.ps1`。legacy无摘要只标`LEGACY_UNCHECKED`。不能回答或机械检查失败时保持`NOT_READY`，不得靠聊天记忆补齐。

## 开始工作前回报

- 已读资料、仍为`UNVERIFIED`的信息和权威冲突；
- 恢复模式；温重绑时列出实际增量读取集、未重复读取对象和基线成立理由；
- 真实源码与协作目录状态，以及其他owner/用户字节；
- 目标、非目标、风险与pre-mortem；
- 计划、验证、精确写入路径、Git/外部权限和升级条件。

没有任务卡或文件所有权时不得写入。项目资料只补充稳定身份和项目例外；唯一完整流程仍由固定Framework持有。
