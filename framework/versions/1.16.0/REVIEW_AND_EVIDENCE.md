# Review 与 evidence

<!-- AIW-REQUIREMENT:PR_CRITICAL_REVIEW_INDEPENDENCE:BEGIN -->
## 风险跟随 action

public contract change、candidate payload、Controller/long-lived owner switch、material scope 的 Git integration，以及 profile 要求的 external action，都需要 independent Review。

mechanical formatting、canonical projection 与 release-field sealing 在不改变已 Review 的 public contract 或 candidate payload 时，可以使用直接 checker evidence。

Review 不授予 write、Git、push 或 external capability。

独立审核使用可见 APPLICATION_TASK，绑定真实审核主体、当前候选身份与精确范围、原始材料及可追溯 verdict。新的独立审核任务新建会话；同一审核继续及修复复审复用仍独立且上下文可用的原会话。复制新名称、继承 writer 判断或返回摘要不能证明独立性。分派者核对材料完整、上下文可用及结果可复证。

交审顺序由本块唯一确定，按实际依赖连续收口：先完成本轮生产/自测 FINALIZE、候选冻结及最终消费者所需材料；以最终当前任务和候选校验分派者自己的 `REVIEW_ROUTE` 准入（非 Owner writer 使用初始明确预授予的连续包及真实后像收据），以真实新委派构造 `REVIEW_ROUTE + HANDOFF` 的增量 IntentEnvelope，执行一次 DISCOVER、读取返回的组织、Review 与 HOST 必要完整正文并 ADMIT，之后才准备接收者的纯 `REVIEW_EXECUTE` 包。已针对同一交审目标取得且仍健康的选择/正文可复用，生产正文和证据也按有效范围复用；SOURCE_WRITE/TEST_RUN 的旧选择不能替代新委派，亦不为形式重做完整恢复或拆出纯记账模型轮次。只有 Owner、Work route、范围、决定等包绑定的任务事实真实变化且必须先更新，才由有权者完成当前卡更新；仅产物从未生成变为已生成，以生产 FINALIZE 和冻结材料作为精确候选，不因卡内仍有生产前叙述要求临时 writer 向 Owner 索卡更新或改写原生产链。Owner 消费终态时按 TASK 维护卡片。随后以**最终当前**任务身份、候选、范围、原始证据及资源安排生成和校验待发送材料。已有合格 Reviewer 用真实已知 ID 直接签精确纯 Review 包、checker/DISCOVER/ADMIT 后一次发送；新建且 ID 未知时准备限域不可执行的待绑定原件，创建提示一次给齐完整材料、原件路径/身份/委派编号，由接收者据初始委派和宿主自身 ID 自绑定并完成原 checker/DISCOVER/ADMIT。原 Owner 已在 `repairReviewPlan` 授权的临时 writer 可在生产完成后承担上述有界准备，仍保留原 Owner/issuer 与生产 FINALIZE 证据，不重写父包或重跑未变生产。writer 交齐材料后结束当前轮，原范围内真实 finding 仍回该 writer 按当前修复包续作；无 Owner 下一动作不发送“审核进行中”的中间终态。发送后若任务、候选或范围真实变化，按影响重绑旧包，不为省一次消息放宽独立性或身份核对。接收者只承担自身审核成果，不另派审核者；不得以反向索包代替完整初始委派。ADMIT 的 REVIEW_CARRIER_QUALIFIED 与 REVIEW_MATERIALS_BOUND 记录可见载体、独立性和材料事实，仍为 INSTRUCTION_BOUND。

对未变化的 domain task，DOMAIN_OWNER 可以直接选择 independent Reviewer，并签发纯 `REVIEW_EXECUTE` package；PROJECT_CONTROLLER 不是强制签名或 delivery hop。临时 Reviewer 只成为 action grantee，不改写 task Owner、Work route actor、task identity 或 candidate bytes。CRITICAL scope 下，task owner、issuer、candidate writer 与 material solution contributor 必须被机械排除；合格 cross-domain writer 仍是 writer/contributor，不改变 task ownership。`OWNER_ACCEPT` 是之后的 domain/product gate，不是 Review。

正常 Review 闭环只有一次纯分派与一次可用终态。Reviewer 在发送 verdict 前完成 candidate identity、范围、finding 与 evidence ceiling 的收尾；finding 直接交仍有修复动作的 writer，局部复审沿原计划。APPROVED 由 Reviewer 携 writer 交审前备齐的候选、验收映射、测试、限制与产物去向引用一次交原 Owner 接受，不再让 writer 转报相同通过结果。发送后 package 按终态失效，Reviewer 不修改 Owner 的任务卡、STATUS/index，不删除 Owner 的 package，也不等待“释放/ACK”。Owner 只在唯一任务卡记录当前结论并关闭后续 writer/acceptance route；STATUS 与 task index 仅保存定位、lifecycle 或 routing 投影。详细 finding 只保留一份 canonical evidence；实际问题须有原因、影响、最小修正及必要定位，不凑编号或数量。送达及失败仅按 PR_FINAL_OUTPUT_CURRENT_RESULT，不生成反向授权。

## Candidate freeze

stable candidate 标识 repository、parent/baseline、exact files、byte identities、canonical payload、known dirty/index state、writer release 与 evidence ceiling。canonical immutable evidence 只存一次并由其他对象引用；不要在 mutable card 之间复制，也不要增加 field-level manifest。

适用且主体、范围已确定的任务默认按 AUTHORIZATION_MODEL 配置 repairReviewPlan。首次交审由已完成的生产 FINALIZE 绑定当前候选；finding 本身不授权 repair，实际修复/复审沿计划准备当前包并各自准入，无须 Owner 纯中转。same-scope repair 使用新 writer package，更新 affected freeze，由同一个仍独立的 Reviewer 做 focused rereview。局部 finding 只重开受影响范围，复验实际修复、直接消费者及必要相邻回归；未受影响的原完整 Review 和验证证据保留，不因整文件身份变化重跑无关范围，不复用旧授权或 stale receipt。contract、path 或 impact set 扩大时回 Owner 处理所需 full Review；同一审核仍按当前独立性与上下文判断是否复用会话。提出 finding 不自动成为 writer/contributor，未准入结论不冒充正式审核，测试通过不能取消有效质量 finding。

release 声明已吸收某条 project correction 时，Review 必须把原始 correction reason、effective rule 与 applicability boundary 对照实际 normative modules 与 behavior tests。原生规则 ID、changelog 声明或近似措辞本身不是 acceptance evidence。通用吸收不登记项目身份；项目采用时独立判断完整覆盖、部分覆盖或继续保留，混合义务保留项目增量与完整历史。
<!-- AIW-REQUIREMENT:PR_CRITICAL_REVIEW_INDEPENDENCE:END -->

<!-- AIW-REQUIREMENT:PR_EVIDENCE_CEILING_DISCIPLINE:BEGIN -->
## Evidence ceiling

direct fixture 可以证明 generic contract、failure case、canonical manifest 与 anonymous project preservation。可选 post-release project observation 可以提供来源项目中的实际 invocation、false-block/leak 与 cost evidence，但不阻塞 release，也不证明 universal semantic correctness、model attention、browser/device state、remote publication 或 external claim。

official PowerShell 7 backend 必须在每个声称支持的平台保持 timestamp string 与 normalized result。`1.16.0` 只声称 Windows。以后若声称 Linux 或 macOS，必须有对应实际 conformance result；missing platform/runtime 是显式 evidence ceiling，不得伪造 PASS。
<!-- AIW-REQUIREMENT:PR_EVIDENCE_CEILING_DISCIPLINE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_ACCEPT_SEPARATE:BEGIN -->
`OWNER_ACCEPT` 是 current task owner 对 exact reviewed result 的独立 product/domain acceptance。Reviewer approval 不等于 `OWNER_ACCEPT`；owner acceptance 也不会追溯改变 Reviewer independence，或授予 implementation、Git、push、external authority。

该规则由接受动作触发，不因 Work phase、角色标签或 Profile 不同而漏加载。动作前绑定范围内所需的 Review 或允许的直接证据；输出前确认实际接受记录。`OWNER_ACCEPTANCE` 结果必须使用 `OWNER_ACCEPT` 动作，不能改成 `NONE` 或记录写入动作来代替准入。机械检查验证当前 Owner、授权、对象身份与所需回执，不声称已经证明 Review 内容或接受判断的语义正确性。

Framework 测试可用 `tests/run-framework-tests-summary.ps1 -EvidencePath <新文件>` 运行并显示成功摘要。完整逐项输出写入该文件并给出字节身份；失败、未知、跳过、未运行与证据上限均在摘要中计数，失败细节随摘要显示。审核和接受仍读取完整证据及实际退出码，摘要不替代原始测试记录。
<!-- AIW-REQUIREMENT:PR_OWNER_ACCEPT_SEPARATE:END -->
