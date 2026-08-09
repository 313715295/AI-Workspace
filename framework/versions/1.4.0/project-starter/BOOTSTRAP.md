<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} 会话入口

本文件是项目会话接入协作体系的唯一入口。项目ID为`{{PROJECT_ID}}`；控制面固定在项目Git根的`.ai-workspace/`，项目根由同目录`project.json.repositoryRoot`相对解析；固定Framework版本为`{{FRAMEWORK_VERSION}}`。

## 定位项目与Framework

1. 先以本文件父目录确认为`.ai-workspace`，严格UTF-8读取`project.json`；要求`schemaVersion=2`、`controlPlaneLayout=repo-local`、`repositoryRoot=..`、项目ID和Framework pin完整一致。
2. 从当前宿主已经挂载的workspace根中，唯一定位同时包含`README.md`和`framework/versions/{{FRAMEWORK_VERSION}}/GOVERNANCE.md`的`AI-Workspace`。0个或多个候选均保持`NOT_READY`并请求补齐/消歧；不得把本机绝对Framework路径写入项目Git。
3. 固定版本目录缺失或不完整时fail closed；不得从`framework/CURRENT`、tag、当前HEAD或网络猜测历史版本内容。
4. 若中央legacy `projects/{{PROJECT_ID}}`与本repo-local控制面并存，本文件是唯一项目入口，中央副本只读冻结；ID或repository身份冲突时停止并交owner。

下文用`<AI-Workspace>`表示第2步唯一定位出的Framework仓根，不是需要提交的本机路径。

## 选择恢复模式

恢复模式、基线和升级条件只由固定Framework的`GOVERNANCE.md`§10与`WORKFLOW_PLAYBOOK.md`§1定义：首次进入或基线不可证明时使用`FULL_COLD_RECOVERY`；同一健康会话且基线可证明时可用`WARM_TASK_REBIND`。增量核对冲突时升级完整冷恢复；温重绑不继承旧任务权限。

## FULL_COLD_RECOVERY：按顺序读取

1. `.ai-workspace/project.json`，确认项目ID、项目根、repo-local布局和固定Framework版本。
2. `<AI-Workspace>/framework/versions/{{FRAMEWORK_VERSION}}/GOVERNANCE.md`。
3. 同版本`WORKFLOW_PLAYBOOK.md`：至少读取§0、档位选择和任务相关章节。
4. 同版本`REVIEW_CHECKLIST.md`：按`MICRO / STANDARD / CRITICAL`使用；执行者用于自检但不能冒充所需独立批准，承担`CRITICAL`审核职责时全文读取。
5. 当前宿主存在版本化适配页时读取对应文件；Codex读取同版本`HOST_ADAPTER_CODEX.md`。宿主适配只补工具与消息机制，不改变核心治理。
6. 任务卡选择评审视角时读取同版本`PERSPECTIVE_LENSES.md`。
7. `.ai-workspace/PROJECT.md`、`REVIEW_PROFILE.md`、`RELATIONSHIPS.md`和`STATUS.md`。
8. `.ai-workspace/tasks/README.md`及分配给自己的`.ai-workspace/tasks/active/<TASK-ID>.md`。只有满足`MICRO`全部准入条件且owner能同turn闭合时可无持久卡执行；其他没有有效任务卡时只做只读调查。
9. 任务卡列出的项目权威资料与相关实现；摘要不能替代原文。

完整冷恢复或温重绑后必须先说明：恢复模式与基线、唯一owner/调度者、目标、档位与风险、exact/forbidden、验证、Git与外部权限、保护边界和唯一下一动作。只有实际挂载临时角色时才增加资源、审核人与消息闭环字段。

有卡任务进入Review、Git收口或关闭前，由AI从git status/diff或冻结manifest取得本任务actual pathset，以`-ObservedActualPath`逐卡运行`<AI-Workspace>/framework/versions/{{FRAMEWORK_VERSION}}/scripts/check-task-card.ps1`。checker只核对声明、观察路径和生命周期一致性，不识别Git owner、不判断设计或授权。`MICRO`无持久卡不运行checker；legacy无摘要只标`LEGACY_UNCHECKED`。

## 开始工作前回报

- 已读资料、仍为`UNVERIFIED`的信息和权威冲突；
- 恢复模式；温重绑时列出实际增量读取集、未重复读取对象和基线成立理由；
- 真实项目仓与`.ai-workspace`状态，以及其他owner/用户字节；
- 目标、非目标、档位、风险、问题可达性和pre-mortem；
- 计划、验证、精确写入路径、Git/外部权限和升级条件。

不满足无卡`MICRO`准入、没有任务卡或没有文件所有权时不得写入。项目资料只补充稳定身份和项目例外；唯一完整流程仍由固定Framework持有。
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
项目特有的稳定入口补充只能写在本区；不得复制通用Framework流程，不得修改上方受管区。升级工具逐字保留本区。
<!-- PROJECT-CUSTOM:END -->
