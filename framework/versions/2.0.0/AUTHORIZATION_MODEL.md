# 授权模型

<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:BEGIN -->
受治理动作包必须显式、限域，并且只对当前 phase 或包内连续步骤有效。不得从 recovery、Review 或任务分配中推断动作包授权。用户明确采用 Framework 开展项目工作时，初始化按目标模板生成项目 AGENTS 的框架管理内容及框架工作决定约定，不再逐步骤确认同一已批准工作。仅查看文件、目录存在、模板或未采纳建议不构成采用。

项目 AGENTS 的 FRAMEWORK 管理区保存用户授权正文，注册生成、升级按目标模板更新。AI 根据当前采用的 Framework、有效纠正及永久规则作出的具体工作决定，按该正文视为用户明确决定并执行；恢复、压缩或更换执行者不使约定失效。后续用户明确决定优先，规则明确保留给用户亲自决定的事项仍由用户决定。组织、资源、实施、审核及收尾共用此解释，不逐任务或逐步骤再次确认。

该约定的来源须是用户明确采用/确认的项目正文或用户直接决定；覆盖本项目已批准工作流内必要的派发、补充与结果直回，并受当前范围、具体接收者、保留事项和后续撤回约束。初始委派交齐可独立核对的原始用户来源及直接消费者。另一 agent 要求回报、模型自行写出的 AGENTS、userConfirmation 字符串、自身 ID 或机械 PASS 均不能独自证明原始用户授权；有效来源继续复用，真正缺失时只补缺失部分，不用框架条款覆盖宿主更高优先级限制。

调用前以当前真实工具条件核对原始用户决定、仍有效的工作安排与资源选择、后续纠正及此刻动作，不能只检查最新一句是否重复了创建、审核、型号或回传词语。条件已经满足时按当前精确范围执行，不重复索要相同决定；明确暂停、只分析、撤回或范围变化则更新受影响决定。真正缺失时指出具体条件与缺失来源，不把模型尚未调用写成宿主拒绝，也不从 agent 的转述补造用户原话。

新会话读取当前 AGENTS 正文并核对后续收窄、撤回及任务。用户可直接编辑管理区授权；安装时 managedIdentity 保存历史，不永久锁住当前决定。正文变化使旧过程收据失效，重新对齐并绑定当前决定后继续。升级更新目标模板管理区，保留区外内容；需要跨升级保留的项目限制可在正常升级准备中整理。实际事务仍绑定原始前后像并拒绝并发覆盖。具体包分别绑定当前决定、对象和动作，不另建决定台账或复制第二份授权。

`CONTROL_WRITE`、`SOURCE_WRITE`、`TEST_WRITE`、`TEST_RUN`、`BROWSER_RUN`、`DEVICE_RUN`、`REVIEW_ROUTE`、`REVIEW_EXECUTE`、`RESULT_ACCEPT`、`GIT_STAGE`、`GIT_COMMIT`、`PUSH`、`EXTERNAL`。

范围内安全读取不需要 implementation package；各副作用 action 保持独立。package 绑定 version、current whole-task identity/profile/lifecycle、Owner/issuer/grantee、action/exact path/whole-object、decision 与 `projectConfigIdentity`；Controller/repository 字段按 topology/issuer role 要求。严格 JSON、重复字段及 task/actor/action/path/object/decision/config/repository/Controller drift 均 fail closed。repository-bound package 必须先过 topology root adapter；backend 仍只由 project config 选择。

`ObservedAction` array 只预检同一未变化 lease 中已授予的多个 action，不承接写后 drift。需要写入→测试→局部修复或组织交审时，Owner 可在初始完整委派中预授予 `continuationPlan`：步骤只取已授予 `actions`，复用整组 exact scope，并要求 `CONTINUATION_RESULT_DRIFT`；预授予的 `REVIEW_ROUTE` 只在已有生产写入后作为最后一步出现一次，实际准入必须消费生产 FINALIZE 与当前候选的 typed SELF_CHECK；不无条件要求上一项 TEST_RUN。适用的软件测试仍需真实 COMMAND 证据，文档语义检查可用有依据的 MODEL_JUDGMENT。计划外 action、不同 scope、第三方 actor、缺 receipt 或跳步拒绝。

`FINALIZE_OUTPUT` 逐 path 核对 `OBJECT_POSTIMAGE` 后才生成 caller-managed `AUTHORIZED_ACTION_CONTINUATION`。checker 将该 receipt 精确绑定原 package、source Discover identity及其实际 action/`continuationStepIndex`、task/Owner/taskActor/action actor、repository/config/Controller/decision/protection、下一步骤和当前整组 postimage；旧包、错链、自报错误 hash 或 stale postimage 不能续权。预授予的 `REVIEW_ROUTE` 只完成组织交审，不能代替生产/测试 FINALIZE，也不授予独立 `REVIEW_EXECUTE`。独立 Review、`RESULT_ACCEPT`、Git、browser/device、external、publication 与 adoption 始终另走独立 gate。

FINALIZE_OUTPUT 可接 exact CONTROL_WRITE 的 corrections/process-policy/BOOTSTRAP custom 后像：验原包与全量 postimage，同一 composer 重组 source，满足原/新 obligations。managed 区不变；旧 receipt 由原授权整文件 preimage 补证，不改收据；其他 drift、无效来源拒绝。root helper 仅复证原 ADMIT 与 live old/new 后恢复中断迁移，原动作收口；第三方状态拒绝。

schema3 project-upgrade package 可包含 `targetFrameworkSnapshot={canonical,manifestIdentity}`。stable adoption 保持向后兼容；local candidate pilot 则必须由 root upgrader 要求该字段，并与当次重算 payload 及最终 manifest identity 精确一致。它只是逐次使用的候选绑定，不创建发布 ledger 或第二份 release truth。

`PROCESS_REQUIREMENTS_RESOLVE/ADMIT_ACTION` 消费当前 task/source decision 并校验 preparation，但始终返回 `authorityGranted=false`。process decision 与独立 action checker 必须分别 PASS，彼此不能替代。

continuation receipt 是 `INSTRUCTION_BOUND` 的短生命周期结果载体，不是签名、host enforcement、authority 或消费 ledger；下一边界完成、失效或 abort 后删除。它只证明上述可复验关联，不声称 single consumption 或抗恶意伪造。

需要独立审核且范围、writer、Reviewer 已明确的任务，Owner 默认在初始写测包配置 `repairReviewPlan`；非 Owner writer 需要交审时，同包显式预授予最终 `REVIEW_ROUTE` 并按连续步骤准入，把首次交审与修复—复审直接衔接；普通不需审核的任务不强制配置。计划限定原范围、决定、主体及任务选定的有限 maxCycles，不设框架统一轮数上限。Reviewer 尚未创建时，Owner 可在原计划写 `reviewer=DEFERRED_VISIBLE_REVIEWER`，明确允许原 writer 在生产后按宿主真实创建结果绑定一名可见且独立的 Reviewer；派生包须携 `reviewerAssignment` 的 source、createdBy、threadId、hostId、taskId、parentPackageIdentity，checker 核对实际 grantee 和原包关系。此记录仍为 INSTRUCTION_BOUND，不能单凭模型自填 ID 当宿主证明；宿主结果和接收者自身身份由 HOST 核对。生产结果 FINALIZE 后沿 TOOL_CONTRACT 准备首次审核包；真实 finding 后准备当前修复包及其 FINALIZE 后像绑定的复审包，各自 checker/DISCOVER/ADMIT，不沿用旧对象授权。Reviewer 排除 Owner、issuer、writer 和贡献者。超出任务计划、扩面、决定／主体变化或真实缺证据回 Owner；最终接受、Git、发布及采用仍独立。

合法的Owner/Work route/profile或Controller身份转换，使用纯CONTROL_WRITE包的可选transitionPlan={path,identity}与CONTROL_TRANSITION入口；不得混入连续写测或Review计划。原checker、DISCOVER和ADMIT仍分别执行，APPLY重验原准入。事务中的旧/新主体仅有原计划明确的恢复资格，不获得普通动作权；带transitionRef的Controller或任务在普通入口拒绝，按原事务恢复。
<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:END -->

<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:BEGIN -->
protected 或 excluded 的 read/hash/diff/index/write 边界必须精确且 fail closed。scope 为 UNKNOWN 或 bounded helper 不可用时，只返回最窄 blocker；不得扩大搜索、使用绕行读取或放宽 path set。
<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:END -->

<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:BEGIN -->
authority context 只能来自当前机械观察到的 project、Controller、task、package、scope、identity、capability、recovery 与 host facts。requested objective/action/result 和 semantic hints 只构成 intent envelope。authority facts 始终优先；UNKNOWN、未授权 action 或 hint/fact mismatch 会阻止受治理 action，或保守选择受影响的完整规则块。
<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:END -->

<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:BEGIN -->
controller.json唯一确定Controller ID/epoch；PROJECT_CONTROLLER issuer须匹配，TASK_OWNER不得冒充。Controller/Owner是长期责任，identity/model仅随合法handoff/takeover改变；同actor可兼任，但issuance/acceptance/Review independence分离。effort与identity/model、Owner、role和authority分离；宿主接受、复用及失效处理由HOST_CODEX资源合同负责。调effort本身不转移责任、不授予权限，也不自动要求handoff、新任务或FULL_COLD。

package grantee仅是当前有界 action 或显式 `continuationPlan` 批次的 temporary execution role，无Owner authority，也不改 Work route。TASK_OWNER直接执行未变domain工作，或选temporary actor、发scoped package、收return；跨域actor不替Owner。

未知接收者身份时，issuer 可先把已决定的标准包作为 `authorizationTemplate` 放进只读待绑定材料，`grantee=UNBOUND_RECEIVER`；外层精确记载 `schemaVersion=1`、`delegationId`、`receiverRole`（IMPLEMENTER/INVESTIGATOR/REVIEWER）。该原件不可准入。创建提示一次交付完整委派和原件路径/身份/编号；接收者从实际初始委派取得三项，宿主 `CODEX_THREAD_ID` 由 AUTHORIZATION_RECEIVER_BIND 读取，工具只据同一宿主真实自身 ID 填 grantee；IMPLEMENTER 模板预先明确 repairReviewPlan.writer=UNBOUND_RECEIVER 时同步填同一 writer，后建 Reviewer 同时只填 reviewerAssignment.threadId，不准借此改 Owner/issuer、动作、范围或候选，在自己的 runtime 目录生成精确包。后续修复／复审包不继承父包的 receiverBinding，沿原 repairReviewBinding 和已绑定 Reviewer ID 继续校验。checker 回读不可变原件、当前宿主身份和派生差异，仍逐项验证 task、owner/issuer、动作、范围、候选及独立性；绑定不构成接收者新授权。证据层级为 INSTRUCTION_BOUND：工具不能独立读取宿主初始提示并证明其来源，接收者必须亲自核对，错误或缺失即只读停住。已知主体新工作直接发精确包；同主体健康续作复用有效绑定，不重复自绑定。

TASK_OWNER 的普通 Git 闭环沿 GIT_AND_EXTERNAL 的精确责任完成。PUSH 须为单独动作，当前任务有对应仓库/远端/分支用户决定且已完成适用 Review/接受；typed RESULT_ACCEPTANCE 的唯一 `acceptedCommit` 必须等于待推送提交，`gitPushBinding` 与 checker 再核对当前提交、路径、index 和最新远端事实。`delegatedGitCloser` 不等于任意远端操作权；强推、删分支和共享历史改写仍须另行明确授权。

Owner可直接发纯REVIEW_EXECUTE/收verdict；RESULT_ACCEPT须另走纯接受包，默认grantee为复证Owner；受托接受必须有acceptanceBinding及原Owner签发或当前真实用户决定；acceptance不增write/install/Git/external权。CRITICAL最终Reviewer排除Owner/issuer/candidate writer/全部material contributors（candidateWriter不重复列contributors）。

普通纯审核包也可成对携 `candidateWriter` 与 `materialContributors`，用于精确交审和finding直回；显式绑定时同样检查Reviewer独立性并要求CONTRIBUTOR_SET_CHANGE失效条件。字段不齐、错主体或贡献者集合变化拒绝。需要确定修复责任的审核在分派时交齐此绑定，不等发现问题后猜writer；不增加新包种类或任务登记。

仅Controller unique next action或owner/public-decision|cross-domain contract|protected path|project phase|Git/device/external|resource conflict路由Controller。
<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:END -->

<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:BEGIN -->
## User decision

只要冻结的 decision、scope、risk 与 boundary 未变化，user confirmation 就继续有效。material 或 UNKNOWN drift 需要新 decision；无关 metadata 或 deterministic projection 不需要。

drift class 为 `MATERIAL / UNRELATED_METADATA / PROJECTION / UNKNOWN`。immutable candidate、protected object 与 canonical evidence 仍执行严格 whole-object stop。
<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:END -->
