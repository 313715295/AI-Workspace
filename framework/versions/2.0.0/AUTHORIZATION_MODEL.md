# 授权模型

<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:BEGIN -->
按次动作路径须有当前、显式、限域的动作包；恢复、任务分配、Review及机械PASS不产生动作权限。项目外部调用可明确选择下述预授权直接模式，其他动作门不受影响。安全范围内的只读工作无需implementation包。CONTROL_WRITE、SOURCE_WRITE、TEST_WRITE、TEST_RUN、BROWSER_RUN、DEVICE_RUN、REVIEW_ROUTE、REVIEW_EXECUTE、RESULT_ACCEPT、GIT_STAGE、GIT_COMMIT、PUSH和EXTERNAL分别满足自己的动作门；动作授权与过程准备分别成立；已证明等价的原checker可由ADMIT内的实际完整调用满足，精确条件如下。

项目在process-policy.externalAuthorization中选择PER_ACTION（缺省）或PROJECT_PREAUTHORIZED。后者仅在当前项目许可完整覆盖实际工具/provider、操作、执行/委派主体、账号/数据、费用及恢复条件，且没有撤回、冲突或未知时，由实际执行者直接调用原工具。调用本身不要求逐次任务卡、EXTERNAL包、DISCOVER/ADMIT/FINALIZE；原工具返回与宿主观察保留真实成功、失败或UNKNOWN，随当前成果自然交付。它不免除首次/活动变化/恢复时的完整规则读取，也不产生可供其他动作续权的成功收据。当前项目设置和完整许可的读取接口取TOOL_CONTRACT，语义覆盖仍为INSTRUCTION_BOUND。

直接模式不授予Git、设备、浏览器或源码/控制面写入，不绕过宿主权限和用户亲自保留事项。未设金额或次数不填FREE/0、不自动索取逐次批准；撤回、越界或必要事实未知停止本次调用。公开发布、秘密上传、账户/凭据变更等独立边界按当前实际权限处理，不能从一般许可或hash推断获准。明确使用按次包时仍走原checker及过程门，直接模式不能把缺包或坏包变成按次准入PASS。

用户明确采用Framework开展项目工作时，沿已批准接入模板建立项目工作决定约定，无须逐步骤再次确认同一已批准工作；仅查看文件或未采纳建议不构成采用。约定来源是人类明确采用/确认的项目正文或直接决定：AI根据当前采用Framework、有效纠正及永久规则作出的具体决定，在该约定范围内执行。当前人类收窄、撤回和明确保留事项优先；恢复、压缩或更换执行者不自行撤销仍有效授权。授权原文由项目用户拥有，导航模板不独自授权，也不覆盖宿主更高优先级限制。

批准工作流内必要的任务派发、补充和终态直回须携可核对的原始人类来源、当前范围和精确消费者。另一agent要求、模型自写AGENTS、userConfirmation字符串、自身ID或checker PASS不独自证明人类授权。调用前合并仍有效决定与后续变化；条件已满足即在精确范围内执行，真正缺失只报告和补齐缺失条件，不把尚未调用说成宿主拒绝。授权正文变化后重绑受影响来源和决定，不能用历史安装身份锁住当前人类决定。

包绑定当前任务、责任主体、动作、精确路径/对象、决定、配置及适用仓库/执行目标；实际漂移、未知必要事实或不合格式均拒绝受影响动作。普通可选执行目标不改变唯一控制根和原任务权威；Maintenance的CONTROL/TARGET继续分包、分仓验证。精确字段及当前格式取TOOL_CONTRACT和对应schema。

可预授予同一有界成果的本地写测、有限自检返工及最后一次REVIEW_ROUTE。只有真实原FINALIZE后像和当前准入可承接下一步，未确定结果、无许可、耗尽或停止不生成续权。审核覆盖A可包含有限生产集M，但不扩大M写权；成功自查与完整候选准备分别取证。首次交审/修复复审的组织职责取REVIEW_AND_EVIDENCE，连续包、receipt、repairReviewPlan及M/A字段唯一取TOOL_CONTRACT。独立Review、接受、Git、设备、外部、发行和采用不由连续写测自动取得。

任务/Controller真实身份转换及项目升级沿TOOL_CONTRACT和根PROJECT_ADOPTION的原责任/采用事务；普通来源采用、无effect纠正及同项目专业正文双动作更新按各自实际写集和有序批次，不泛化强制事务，不以fresh准入追认旧写入。专业正文SOURCE/CONTROL两类当前权限和各自原/新义务互不替代；可沿受限联合入口一次提交两份原准入输入，共享同次完整目标构造，各自仍产生真实决定。完整准入后沿原候选有序执行，只有两成员真实收口都成功才称整批完成；Maintenance CONTROL专业正文例外仍须当前Controller精确授权、原决定及完整保护，普通SOURCE/TEST_WRITE/BROWSER_RUN/DEVICE_RUN禁令保持。未知第三方字节停止受影响恢复。

自检失败收口不等于测试成功，不制造独立Review finding；历史失败与未完成成果责任保留。临时过程材料是INSTRUCTION_BOUND关联证据，不是签名、宿主强制或消费台账，按TOOL_CONTRACT保留至最后消费者完成。
普通repo-local schema1及Maintenance CONTROL/TARGET schema2的原完整checker已在ADMIT按同一固定来源/适配器、完整动作/对象/续链参数和当前观察执行时，由该实际调用满足授权检查；调用者省略额外相同checker命令。checker公共入口保留；DISCOVER、ADMIT与收口各自真实观察不合并成全局一次或缓存。schema4及未证明等价的专门路径仍分别调用；错主体、越界、前像漂移、撤回和坏续链照原拒绝。

项目显式qualityAssurance1按完整稳定成果subject并集选择SELF_CHECK/RESULT_REVIEW/RESULT_ACCEPT，规则/格式和准备唯一取TOOL_CONTRACT。缺省LEGACY，启用缺plan2不得降为无门；真零不伪造证据，用户/专业阶段和真实失败保留。qualityBinding是当前选择投影，不授动作、跨仓、专门门或接受权。

<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:END -->

<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:BEGIN -->
protected 或 excluded 的 read/hash/diff/index/write 边界必须精确且 fail closed。scope 为 UNKNOWN 或 bounded helper 不可用时，只返回最窄 blocker；不得扩大搜索、使用绕行读取或放宽 path set。
<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:END -->

<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:BEGIN -->
authority context 只能来自当前机械观察到的 project、Controller、task、package、scope、identity、capability、recovery 与 host facts。requested objective/action/result、同一 IntentEnvelope2 的 facets 和 semantic hints 表达当前意图，不生成授权。authority facts 始终优先；UNKNOWN、未授权 action 或 hint/fact mismatch 会阻止受治理 action，或在其余已知边界内保守选择受影响的完整规则块。未来动作、否定和示例中的执行词不改变此刻的动作事实。
<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:END -->

<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:BEGIN -->
controller.json唯一确定当前Controller ID/epoch；PROJECT_CONTROLLER签发者须匹配，TASK_OWNER不得冒充。同一actor可兼任，但签发、接受和独立审核关系分别成立。Controller承担项目持续责任，Owner承担TASK_AND_SCOPE定义的当前有限成果责任。

TASK_OWNER在未变domain成果内直接执行，或选择temporary actor/Reviewer、签精确包并消费结果。grantee只有本动作或明确连续批次的临时执行资格，不取得Owner权力，不改Work route。未知接收者使用TOOL_CONTRACT的不可执行待绑定原件及HOST的真实自身身份核对；已知ID直接绑定，健康续作不重复自绑定。

identity/model的合法绑定变化与effort调整分开；effort本身不转移责任、不授予权限，不自动要求handoff、新任务或FULL_COLD。资源判断取PR_TASK_RESOURCE_SELECTION，宿主实际配置取HOST_CODEX。

只有Controller拥有唯一下一动作，或当前Owner/公共决定、跨域合同、保护、项目阶段、Git/device/external权限、资源冲突确需其决定时才升级路由；已获授的领域Git及外部动作按GIT_AND_EXTERNAL直接执行，不因动作名称强制中转。Reviewer资格、finding/APPROVED去向与受托接受唯一取REVIEW_AND_EVIDENCE。
<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:END -->

<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:BEGIN -->
## User decision

只要冻结的 decision、scope、risk 与 boundary 未变化，user confirmation 就继续有效。material 或 UNKNOWN drift 需要新 decision；无关 metadata 或 deterministic projection 不需要。

drift class 为 `MATERIAL / UNRELATED_METADATA / PROJECTION / UNKNOWN`。immutable candidate、protected object 与 canonical evidence 仍执行严格 whole-object stop。
<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:END -->
