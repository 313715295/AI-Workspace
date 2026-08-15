<!-- FRAMEWORK-MANAGED:BEGIN -->
# {{DISPLAY_NAME}} 会话入口

项目ID=`{{PROJECT_ID}}`；控制面位于Git根`.ai-workspace/`；固定Framework=`{{FRAMEWORK_VERSION}}`。本文件是唯一入口，聊天、旧任务final和记忆只作定位。

## 1. 定位

1. 严格UTF-8读取同目录`project.json`；验证schema 3、repo-local布局、`repositoryRoot=..`、项目ID、pin和`frameworkCapabilities={}`（本A-C+G候选不实现knowledge selector）。
2. 严格读取同目录canonical `controller.json` schema 1；验证同一projectId、`controllerEpoch>=1`、`state=CURRENT`并复算整个文件`bytes|SHA256`。它是current controller唯一真相。
3. 从已挂载workspace唯一定位同时包含`README.md`和`framework/versions/{{FRAMEWORK_VERSION}}/RECOVERY_CORE.md`的AI-Workspace。0个或多个候选均停止。
4. 固定版本目录缺失或不完整时fail closed；不得从CURRENT、tag、HEAD、网络或`framework/drafts/`补洞。
5. repo-local与中央legacy并存时repo-local为唯一入口；身份冲突停止。

下文`<FW>`表示唯一定位的`framework/versions/{{FRAMEWORK_VERSION}}`，不是提交到项目的绝对路径。

## 2. 恢复与加载

1. 读取`.ai-workspace/project.json`、`.ai-workspace/controller.json`和`<FW>/RECOVERY_CORE.md`。
2. 轻量读取`.ai-workspace/STATUS.md`、`.ai-workspace/tasks/README.md`和分配任务顶部current元数据，确定`role/profile/phase`；这一步只路由，不能用摘要替代完整任务。
3. 运行`<FW>/scripts/resolve-load-plan.ps1 -Role <role> -Profile <profile> -Phase <phase> -HostName <host>`。没有任务时按真实恢复职责选择；无法判断风险时向上选择。
4. 按loader返回的有序paths完整读取模块；不得只读摘要或自行省略。
5. 完整读取项目`PROJECT.md`、`REVIEW_PROFILE.md`、`RELATIONSHIPS.md`、`STATUS.md`、tasks index、分配任务及任务列出的业务权威/实现。
6. 复证真实Git顶层、HEAD/index/actual、其他owner、protected visibility/read/hash/diff/index/write和current authorization package。PROJECT_CONTROLLER包必须把唯一controller path交给checker复算；DOMAIN_OWNER包不消费controller条件字段。

同一健康会话且基线可证明时可WARM重绑；只读变化对象，不重复未变化核心/模块。controller identity/epoch、host资源能力、phase、工具或context continuity变化会使相关cache失效。任何身份、影响或权限冲突升级FULL_COLD。温重绑不继承旧任务权限。

## 3. 开始动作前

回报恢复模式与基线、唯一owner、目标、profile/可达性、exact/forbidden、验证、Git/external、保护边界、current授权和唯一下一动作。

无有效授权包时默认只读。项目owner在权限等级内签发阶段包；用户只确认产品结果、重大方案/公共合同和external。授权机械预检按阶段批次执行，连续writer lease内不逐工具调用重复；失效条件或Review/Git/external边界必须重验。

有卡任务在Review、Git或关闭前运行`<AI-Workspace>/framework/versions/{{FRAMEWORK_VERSION}}/scripts/check-task-card.ps1`并传入机器观察actual、当前host的`AvailableQuality`和`AvailableTool`。不满足资源最低能力时fail closed，不把更低组合静默记为通过。checker不判断设计、Git owner或授权；Review和authorization分别使用对应模块与checker。
<!-- FRAMEWORK-MANAGED:END -->

<!-- PROJECT-CUSTOM:BEGIN -->
项目特有稳定入口补充只写在本区；不得复制通用Framework流程。upgrade逐字保留本区。
<!-- PROJECT-CUSTOM:END -->
