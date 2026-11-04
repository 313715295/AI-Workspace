# Codex host profile

<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:BEGIN -->
资源判断唯一取TASK的PR_TASK_RESOURCE_SELECTION。Codex核对当前真实可用model、其支持的effort及实际接受结果；同名effort不证明跨模型等价。下列六项是任务匹配建议，不是能力排名、用量配额或效果保证。Controller/Owner可从gpt-6.1-sol / xhigh起步，健康人类指定配置继续有效。

| 请求配置 | 任务条件 |
|---|---|
| gpt-6.1-sol / high | 范围明确的完整实现、成熟修复、证据清楚的验证或局部审核。 |
| gpt-6.1-sol / xhigh | 常规复杂设计、多文件实现调试及能理解专业证据的Owner工作。 |
| gpt-6.1-sol / max | 结构较明确的困难完整工作或复杂整合；问题识别/跨域判断不足时重新判断model。 |
| gpt-6-astra / high | 专业理解、问题识别和综合判断要求较高，范围与主要约束明确、推理工作量适中的有界设计、调查、实现或独立审核，不限于建议。 |
| gpt-6-astra / xhigh | 有界重大设计、困难根因调查、较强综合判断的实现或独审；长推导、多项未知、约束耦合或验证深度增加时可直接选择。 |
| gpt-6-astra / max | 多合同、高耦合、多项未知下的深入推演，须由实际工作量支持。 |

初始可直接选择足够配置，无须较低配置先失败；max不保证优于xhigh，Astra/high不保证强于Sol/max或更低总成本。历史配置、试验和当时费率只支持原事实，不冒充本表实测。

新任务在实际宿主调用中落实已选model/effort，分别记录requested和accepted；省略参数不说成宿主拒绝，prompt不证明物理切档。omitted/rejected/normalized/ignored、接受未知、host移动或能力实变时复查；健康配置不要求peer握手。临时覆盖沿其用途与退出边界处理，不擅改长期责任绑定；不满足能力时报RESOURCE_CAPABILITY_REQUIRED，不静默降质。

计量复用原日志、实际运行和交付验收记录，由最后消费者在自然收尾提取必要配置、首交/返工、耗时及费用覆盖。未知不填零，不为补齐数据另开模型回合；pack bytes或resolver延迟不替代模型收益。
<!-- AIW-REQUIREMENT:PR_CODEX_RESOURCE_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:BEGIN -->
通用终态、消费者、Controller例外和等待取TASK；本块只映射Codex真实投递。优先turn boundary，安全例外可立即steer；缺真实性/送达信号如实限制为capability ceiling或REPORT_CHANNEL_UNAVAILABLE，不建heartbeat或投递台账。

发送前核对原始人类工作流来源、精确消费者及后续收窄/撤回；另一任务要求本身不提供消息授权。原生final仅对绑定USER消费者使用PREPARE，跨任务PREPARE只是READY_TO_SEND，不能用USER替代真实接收者或宣称已送达。

实际发送后在同一工具编排保存完整原始返回并OBSERVE：非错误MCP text JSON中唯一匹配threadId表示宿主受理；明确拒绝为FAILURE，无可确定结果为UNKNOWN。按TOOL_CONTRACT同时核对当前消费者与返回原字节；未知/失败停止依赖发送，不制造未来回执、ACK或额外登记回合，重试资格只取真实宿主明确有界信号。发送受理不等于对方执行、审核或接受。
普通USER答复能否省机械收口，取当前同时必选的RECOVERY_CORE / PR_PROCESS_REQUIREMENTS_PROGRESSIVE_BOUNDARIES完整条件。

该普通USER例外不改变真实跨任务PREPARE/发送/OBSERVE、人类来源、精确消费者或拒绝/未知规则，也不为Review、接受或责任终态制造成功。

<!-- AIW-REQUIREMENT:PR_COMPACT_NON_INTERRUPT_DELIVERY:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:BEGIN -->
按RECOVERY的已绑定backend/TOOLCHAIN取得精确operation入口，健康调用复用。已知独立读查同批执行；有依赖且无需新语义判断的机械步骤连续编排，逐门检查实际结果，失败停依赖链。新事实、语义取舍或真实失败才返回模型，不自动填授权、Review或接受PASS；记录、交付与必要归档在原自然收尾完成。

新有限成果、新独审按TASK默认新建可见会话；同一原成果或同审有界修复复审可续仍健康、合格的原会话。创建时同一次实际调用落实选定model、effort、环境和宿主支持的精确起点，使用标题参数，并核对真实thread ID、配置及读取基线。clientThreadId不作正式主体。当前未提交材料、隔离需要和用户指定影响起点，不因“独审”或Git名称自动强制worktree；宿主不支持与用户没授权分别报告，不静默换环境。明确controlRoot及executionTarget的初始指令优先于执行目录内历史复制入口，实际authority/保护仍由当前工具核对。

已知接收者直接使用真实ID。新建未知ID时，创建提示一次交齐完整工作/验收/候选/消费者、可核对的原始人类来源和待绑定原件路径、identity、delegationId；原件不可执行。接收者从自己的真实初始委派核对原件，AUTHORIZATION_RECEIVER_BIND读取宿主CODEX_THREAD_ID，仅按原模板绑定自身，不能改Owner/issuer/范围/动作/候选。该关系为INSTRUCTION_BOUND，不声称工具能认证初始提示；缺失/不符只读停止。具体assignment/receiverBinding字段唯一TOOL_CONTRACT；健康续作复用有效绑定，不默认创建后补包。

宿主明确要求创建后首次进度观察时，在取得真实可用ID后仅做一次立即快照，未就绪结束本轮；超时/commentary不触发继续等待。当前命令必要等待与peer等待分开，后者遵循TASK。显示标题仅在主题/职责实变时按真实ID更新，不发送指令，不改变Owner、范围、权限或贡献历史；不靠恢复改名让已关闭/归档有限会话默认接新成果。有限成果已交付、原结果已消费且无后续职责时，实际收尾责任人在已有权限内用宿主归档并核对真实结果；待验收、返修及真实长期职责保留，任务卡与会话归档分别确认。实际交审依赖顺序唯一取REVIEW_AND_EVIDENCE。
<!-- AIW-REQUIREMENT:PR_CODEX_TOOL_OPERATION_RESOLUTION:END -->

<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:BEGIN -->
本目标使用navigationContractVersion=3的PROJECT_BOOTSTRAP入口。项目AGENTS只导航明确项目的.ai-workspace/BOOTSTRAP.md；Bootstrap按项目pin及原采用记录绑定固定来源和TOOLCHAIN，不要求新Skill、安装发现或兼容转发。宿主AGENTS可见、文件可读和实际正文已读分别核对。

首次项目工作、压缩或换主体按RECOVERY取得当前必要完整正文；健康上下文按RECOVERY复用，同活动普通范围或本地配套操作变化只重验当前准入与适用要求，不为每次action/final重载。无关会话不启动项目恢复。

旧nav1/nav2项目及在途采用继续使用各自原固定入口，原FINALIZE完成后才读新AGENTS/Bootstrap；部分文件变化不代表切换完成。旧Skill仅在真实依赖结束且有宿主权限时退役，不建消费者登记或每项目副本。输入/证据仍取当前TOOL_CONTRACT，导航本身不授权。
<!-- AIW-REQUIREMENT:PR_CODEX_ROUTER_REACTIVATION:END -->
