# 任务模板

只填当前事实，替换 `<...>`；历史与详细测试引用原报告。MICRO同轮能闭合时可不建持久卡；跨轮、阻塞或扩面用STANDARD。授权JSON示例在 EXAMPLES.md，完整协议取 TOOL_CONTRACT / AUTHORIZATION_MODEL。先稳定卡正文再签外置包；不要把包正文、locator或identity回填卡造成 taskIdentity 自引用。旧inline包仅作既有格式兼容。

```markdown
# <TASK-ID> — <标题>

- Task schema: 1.16.0
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

只有实际发生才加：组织/资源选择及必要理由、QUERY影响引用、术语变化、写后产物/Git去向。健康结论复用，无新结果不写卡。

CRITICAL补独立Reviewer、用户决定入口、稳定候选及必要依赖、范围变化触发；Range summary在lifecycle后增加 `current_exact=<稳定候选>`。每张CRITICAL卡有一条 `Phase gate: TRUE|FALSE` 和 `Proportionality`：重大方案新增机制时填写 existing / classification / minimum_sufficient_fix / added_machinery / escalation_trigger；真实不适用时填写 `NOT_APPLICABLE; reason=<原因>`。不要求固定Review轮数、卡片字节或反例数量。

只有推进项目/多领域里程碑的父任务使用 `Phase gate: TRUE`，否则FALSE；TRUE时使用以下已有矩阵：

```markdown
## Phase acceptance

- Technical evidence: <PENDING|READY; producer=<id>; evidence=<stable-reference>>
- Domain contract check: <PENDING|ACCEPTED; owner=<id>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Runtime/platform check: <PENDING|ACCEPTED; owner=<id>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Project phase signoff: <PENDING|READY; controller=<必须等于任务Owner>; evidence=<stable-reference>>
- User final gate: <PENDING|CONFIRMED; candidate=<必须等于Range summary的current_exact>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Acceptance order: TECHNICAL_EVIDENCE > DOMAIN_CONTRACT > RUNTIME_PLATFORM > PROJECT_SIGNOFF > USER_FINAL_GATE
```

矩阵按既有顺序闭合，真实不适用给理由；用户确认可引用同一稳定候选上的已完成决定，不重复询问。候选/决定变化重新绑定。

关闭时追加：

```markdown
- Closure outcome: <SUCCESS|CANCELLED|SUPERSEDED>
- Closure evidence: <验收或取消/替代决定入口>
- Remaining obligations: <NONE或未完成成果的明确去向/承接任务>
- Artifact disposition: <保留/移交/Git去向>
- Writer / reviewer / authorization: NONE / NONE / NONE
```

SUCCESS须完成适用验收；取消/替代不冒称成功，等待/阻塞保持active。先闭合文档/产物动作，再单卡更新；Owner消费结果并释放权限，按项目档案规则归位。侧边栏归档与业务完成分开，不为等待Review的健康执行者往返归档。
