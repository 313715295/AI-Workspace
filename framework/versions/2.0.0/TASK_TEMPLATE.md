# 任务模板

只填当前事实，替换 `<...>`；历史与详细测试引用原报告。MICRO同轮能闭合时可不建持久卡；跨轮、阻塞或扩面用STANDARD。授权JSON示例在 EXAMPLES.md，完整协议取 TOOL_CONTRACT / AUTHORIZATION_MODEL。先稳定卡正文再签外置包；不要把包正文、locator或identity回填卡造成 taskIdentity 自引用。旧inline包仅作既有格式兼容。

```markdown
# <TASK-ID> — <标题>

- Task schema: 2.0.0
- 状态：<READY|IN_PROGRESS|REVIEW|APPROVED|BLOCKED|CLOSED>
- Profile: <MICRO|STANDARD|CRITICAL>; reason=<实际风险和复杂度>
- Owner: <唯一Owner>
- Work route: actor=<HOST_AUTHENTICATED_TASK_ID>; role=<ROLE>; phase=<PHASE>
- Range summary: profile=<PROFILE>; lifecycle=<ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED>; expected_paths=[<a>|<b>]; actual_paths=[<实际路径>]
- Writer / reviewer / authorization: <当前状态>
- Stable candidate: <NONE或稳定成果入口>
- Git / push / external: <分别列状态>

## Current

- 目标与实际增量：<用户成果、当前行为到目标行为>
- 权威/责任实现/直接消费者：<必要专业入口>
- exact / forbidden：<范围及保护>
- 实现判断：<根因/当前机制、最小充分路线与质量/总成本、重要失败恢复/未解假设；已有充分结论引用即可>
- 验收与关键反例：<当前行为到目标增量、直接消费者及能推翻错误方案的验证依据、必要独立/用户门，不凑数量>
- 当前结果/阻塞与证据上限：<只留current；详细报告入口>
- 唯一下一动作：<actor的具体动作或恢复触发>
```

只有实际发生才加：组织/资源选择及必要理由、QUERY影响引用、术语变化、写后产物/Git去向。采用专家工作时，在原目标/交付/责任说明中写明专业问题、预期结论与验收、实际消费者及后续责任；资源选择含Owner消费结论的能力，不新增固定专家栏或每任务表单。健康结论复用，无新结果不写卡。

CRITICAL补独立Reviewer、用户决定入口、稳定候选及必要依赖、范围变化触发；Range summary在lifecycle后增加 `current_exact=<稳定候选>`。实际重大方案或新增流程机制时在方案填写 `Proportionality` 的 existing / classification / minimum_sufficient_fix / added_machinery / escalation_trigger；普通CRITICAL卡无需补不适用套话。需要审核且范围、writer及Reviewer已明确时默认配置repairReviewPlan，首次交审和局部修复复审直接衔接。独立审核、实质决定和最终Owner接受仍保留。不要求固定Review轮数、卡片字节或反例数量。

有多阶段要求时，在本卡使用唯一 `aiw-acceptance-plan` JSON block，结构见 ACCEPTANCE_PLAN_SCHEMA.json。每阶段仅含 id、kind、requiredBy、dependsOn、candidateRef、evidenceRefs；requiredBy 引用已采用要求/当前决定，candidateRef 内联引用已有产物集合，不要求额外创建清单。未产生候选/证据时保留空数组，不能填假身份或 PASS。

可选五阶段预设为 DESIGN → DESIGN_REVIEW → SELF_CHECK → RESULT_REVIEW → RESULT_ACCEPT。只保留实际需要的阶段；用户门按真实要求放在内部接受之前或之后，不统一前置。普通单成果不强制此区块。不适用在当前要求正文给出依据并省略对应阶段，不创建 NOT_APPLICABLE 伪成功证据。

旧矩阵迁移须逐项保留真实要求与责任：TECHNICAL_EVIDENCE 对应 SELF_CHECK；领域/平台检查按实际要求保留检查证据或 RESULT_REVIEW；PROJECT_SIGNOFF 对应 RESULT_ACCEPT；USER_FINAL_GATE 对应其后 USER_DECISION。项目确实要求用户先决定时，显式改依赖为 USER_DECISION → RESULT_ACCEPT。迁移后删除重复矩阵，不能让两份顺序并存。
关闭时追加：

```markdown
- Closure outcome: <SUCCESS|CANCELLED|SUPERSEDED>
- Closure evidence: <验收或取消/替代决定入口>
- Remaining obligations: <NONE或未完成成果的明确去向/承接任务>
- Artifact disposition: <保留/移交/Git去向>
- Writer / reviewer / authorization: NONE / NONE / NONE
```

SUCCESS须完成适用验收；取消/替代不冒称成功，等待/阻塞保持active。先闭合文档/产物动作，再单卡更新；Owner消费结果并释放权限，按项目档案规则归位。侧边栏归档与业务完成分开，不为等待Review的健康执行者往返归档。

设计关联可在原验收/实现说明中列“权威设计 → 负责实现 → 直接消费者 → 测试”；必要时在接点使用 @design-contract 定位原文，标记不复制语义或宣称通过。已有充分关联直接引用，不要求新增表格或全库标记。
