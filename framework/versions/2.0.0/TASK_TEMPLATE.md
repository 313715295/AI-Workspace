# 任务模板

只填当前事实，替换 `<...>`；新结果替换过时“当前”，过程、历史与详细测试引用原件，不逐阶段追加流水。旧消费者结束至下一授权前是自然更新点；整卡在途绑定继续按原合同保留，不为可变卡建立字段身份或台账。新请求先按稳定成果subject、项目taskCards和当前人类决定选择REQUIRED/OMIT，未设策略沿LEGACY。REQUIRED使用本卡；OMIT的有限写入、多步或有成果门请求使用PROJECT_WORK内联原请求、Owner和必要计划；普通无副作用只读与许可覆盖且无成果门的工具分别用PROJECT_READ_ONLY、PROJECT_EXTERNAL。profile反映风险与复杂度，不单独决定建卡。已有TASK沿原卡完成，不批量迁在途任务。授权JSON示例在 EXAMPLES.md，完整协议取 TOOL_CONTRACT / AUTHORIZATION_MODEL。先稳定卡正文再签外置包；不要把包正文、locator或identity回填卡造成 taskIdentity 自引用。旧inline包仅作既有格式兼容。

```markdown
# <TASK-ID> — <标题>

- Task schema: 2.0.0
- 状态：<READY|IN_PROGRESS|REVIEW|APPROVED|BLOCKED|CLOSED>
- Profile: <MICRO|STANDARD|CRITICAL>; reason=<实际风险和复杂度>
- Owner: <唯一Owner>
- Work route: actor=<HOST_AUTHENTICATED_TASK_ID>; role=<ROLE>; phase=<PHASE>
- Range summary: profile=<PROFILE>; lifecycle=<ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED>; expected_paths=[<a>|<b>]; actual_paths=[<实际路径>]
- Writer / reviewer / authorization: <当前状态>
- Git / push / external: <分别列状态>

## Current

- 目标与实际增量：<用户成果、当前行为到目标行为>
- 权威/责任实现/直接消费者：<必要专业入口>
- exact / forbidden：<范围及保护>
- 实现判断：<根因/当前机制、最小充分路线与质量/总成本、重要失败恢复/未解假设；已有充分结论引用即可>
- 验收与关键反例：<当前行为到目标增量、直接消费者及能推翻错误方案的验证依据、必要独立/用户门，不凑数量>
- 当前候选、结果/阻塞与证据上限：<候选不冒充接受；只留current；详细报告入口>
- 唯一下一动作：<actor的具体动作或恢复触发>
```

只有实际发生才加：组织/资源选择及必要理由、QUERY影响引用、术语变化、写后产物/Git去向。采用专家工作时，在原目标/交付/责任说明中写明专业问题、预期结论与验收、实际消费者及后续责任；Controller或Owner直接组织和消费，资源选择按委派后本人持续职责与消费结论的能力，不新增固定专家栏或每任务表单。健康结论复用，无新结果不写卡。

进入 REVIEW lifecycle 时，将已有候选入口写为唯一 `- Stable candidate: <稳定成果入口>`，供原任务检查器核对；它引用当前候选，不追加阶段流水。

仅当影响现行契约/说明：列受影响完整正文及基线、合并后候选和维护者、适用审核/接受与生效去向；结果说明已完成维护或仍待真实前置。时序取TASK_AND_SCOPE；无此影响不加字段。

LEGACY的CRITICAL或实际选中/另有必需独审时，补独立Reviewer、用户决定入口、稳定候选及必要依赖、范围变化触发；Range summary在lifecycle后增加 `current_exact=<稳定候选>`。方案取舍写在原“实现判断”或已有方案中，不另设Proportionality行/五字段。需要审核且范围、writer及Reviewer已明确时，按原合同配置repairReviewPlan并直接衔接首次交审和局部修复复审；独立审核、实质决定和最终Owner接受仍保留。不要求固定Review轮数、卡片字节或反例数量。

有多阶段要求时，在本卡使用唯一 `aiw-acceptance-plan` JSON block，结构见 ACCEPTANCE_PLAN_SCHEMA.json。每阶段基本字段为 id、kind、requiredBy、dependsOn、candidateRef、evidenceRefs；需消费历史原成功时，按 TOOL_CONTRACT 使用现有可选 evidenceConsumption，DESIGN / USER_DECISION 不携该字段。requiredBy 引用已采用要求/当前决定，candidateRef 内联引用已有产物集合，不要求额外创建清单。未产生候选/证据时保留空数组，不能填假身份或 PASS。

可选五阶段预设为 DESIGN → DESIGN_REVIEW → SELF_CHECK → RESULT_REVIEW → RESULT_ACCEPT。只保留实际需要的阶段；用户门按真实要求放在内部接受之前或之后，不统一前置。LEGACY且无其他阶段要求的普通单成果可省略此区块；启用质量策略时按TOOL_CONTRACT的plan2要求执行。不适用在当前要求正文给出依据并省略对应阶段，不创建 NOT_APPLICABLE 伪成功证据。

旧矩阵迁移须逐项保留真实要求与责任：TECHNICAL_EVIDENCE 对应 SELF_CHECK；领域/平台检查按实际要求保留检查证据或 RESULT_REVIEW；PROJECT_SIGNOFF 对应 RESULT_ACCEPT；USER_FINAL_GATE 对应其后 USER_DECISION。项目确实要求用户先决定时，显式改依赖为 USER_DECISION → RESULT_ACCEPT。迁移后删除重复矩阵，不能让两份顺序并存。
关闭时将当前合并的Writer / reviewer / authorization行替换为下面三项RELEASED，移除旧关闭别名，仅生成这一套字段：

```markdown
- Closure outcome: <SUCCESS|CANCELLED|SUPERSEDED>
- Closure basis: <验收或取消/替代决定入口>
- Output disposition: <正式成果保留或移交位置>
- Git disposition: <READY|DEFERRED|EXCLUDED>; <依据、实际责任和必要触发>
- Unresolved obligations: <NONE或TRANSFERRED: 未完成成果的明确去向/承接任务>
- Writer: RELEASED
- Reviewer: RELEASED
- Authorization: RELEASED
```

CANCELLED/SUPERSEDED另保留`Closure decision: <真实决定路径>#<length|SHA256>`及`Unfinished work: <实际未完项>`；SUPERSEDED必须明确承接。旧完整模板及合法双填只作读取兼容，新卡不双填。LF/CRLF均可，身份始终取原字节。

关闭释放当前有限成果的活跃Owner责任，历史签认和已移交未解义务仍保留。同一未完成成果、同审有界修复复审及原事必要补正按TASK继续；新有限成果按其组织规则处理，不靠复用聊天扩展旧目标。卡选择与新成果责任分别核对，不按每个功能强制建卡。SUCCESS须完成适用验收；取消/替代不冒称成功，等待/阻塞保持active。先闭合文档/产物动作，再单卡更新；Owner消费结果并释放权限，按项目档案规则归位。侧边栏归档与业务完成分开，不为等待Review的健康执行者往返归档。

设计关联可在原验收/实现说明中列“权威设计 → 负责实现 → 直接消费者 → 测试”；必要时在接点使用 @design-contract 定位原文，标记不复制语义或宣称通过。已有充分关联直接引用，不要求新增表格或全库标记。

## 可选显式质量计划

未启用qualityAssurance的项目保本模板LEGACY行为，不强制新plan。启用后从原持久要求和完整单仓成果subject调用QUALITY_PLAN_PREPARE，QA1沿原subject投影，QA2保domain、发起workType和deliverableType三维，将返回plan2在本原卡一次绑定，保用户/专业额外阶段；后续自然补真实candidateRef/evidenceRefs并fresh包。真零可说明未验证结果及用途，不填假SELF/VERDICT/ACCEPTED；pending和未完成用户门不能SUCCESS。精确格式、来源维护启用及历史消费取TOOL_CONTRACT。
