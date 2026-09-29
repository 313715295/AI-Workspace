# Project control

<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:BEGIN -->
项目 repo-local `.ai-workspace/project.json.frameworkVersion` 是唯一 version-selection authority。Framework root 不保存 consumer record，也没有 global default selector。

## Registration

root `scripts/register-project.ps1` 要求显式 exact version 与 Controller ID。任何项目写入前必须校验：

用户明确要求采用 Framework 开展项目工作即确认使用。注册生成 AGENTS 的框架管理内容及用户工作决定约定，升级按目标模板替换；区外项目约定、额外限制和撤回保留。正常模板更新不重复确认已获用户决定，纯只读评估不执行注册。正文和边界取 AUTHORIZATION_MODEL。

- target `VERSION.json` 为 `STABLE`、consumable 且 pin-eligible；
- target `RELEASE_MANIFEST.json` 匹配 canonical payload，且 source Review 为 approved；
- target `project-starter` inventory 精确；
- 明确的destination项目目录、非reparse路径归属与既有control-plane condition安全；普通repo-local不要求Git，Maintenance拓扑和实际Git另行验证；
- selected version 的 `TOOLCHAIN.json` 精确，`pwsh` 满足唯一 official `powershell7` backend，且该 backend 声明当前 host platform。

工具只物化 selected version 的 `project-starter`。对 `2.0.0`，starter 写入 `frameworkToolBackend=powershell7`、空 `.ai-workspace/process-policy.json`、单一 project-config locator，以及兼容字段 `selectedRulePackBytes`；旧默认数字保留历史格式，不是用户配额或运行上限。starter 是可复用 project process，registration 不发明第二套流程。

存在本地Git元数据时，registration对项目根`.gitignore`做幂等投影：复用已有等价 `.ai-workspace/runtime` rule；不存在时只追加 `/.ai-workspace/runtime/`；相反 negation 必须 fail closed。该写入与 control-plane material 同属可恢复 transaction，并保留原 newline style。无Git元数据时不生成或读取.gitignore，不自动建立Git仓。
<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:END -->

<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:BEGIN -->
## Upgrade

root `scripts/upgrade-project.ps1` 要求 caller 提供 `RepositoryPath`、`ControllerId` 与 exact `ToVersion`。跨版本入口只接受健康 project4 / 固定 1.16.0-snapshot.12 到已审固定 2.0.0 候选，具体顺序取 MIGRATION_MATRIX；写入前校验双方来源，并保留：

- project ID 与 display name；
- 当前 repo-local 或 Maintenance sibling layout 与 repository root；
- Controller ID、epoch 与 state；
- routine exclusions 与 capabilities；
- Bootstrap project custom region。

升级将 project4/旧单索引投影为 project5/index3，保留 backend、排除集合及既有项目事实。PowerShell 7 与 declared platform 必须可用；backend 由项目配置决定，不复制进 authorization package。配置或主体变化使原有无关动作包失效。

范围导航先返回声明路径，不要求预先准入。随后旧健康 runtime 执行真实 DISCOVER；根 PREPARE 在隔离目录组合目标 project、Controller、任务、Bootstrap/AGENTS、policy、corrections 和所需项目标准，返回目标完整规则及精确投影。读取正文并完成两端义务后，原 runtime 执行真实 ADMIT。目标预检只是机械观察，不能替代旧准入、项目决定或精确写入包；目标规则包大小不构成准入门，真实旧失败仍如实保留。

只有声明的 managed objects 会改变。工具不搜索 consumers，不修改 source/product file，不 stage/commit/push，也不更新其他项目。

`2.0.0` starter 以 current task 的 actor/role/phase Work route 作为 loader input，并用唯一 process-policy carrier 保存 permanent project-specific process rules。它不把 task state 移入 Framework root，不创建 consumer record，也不把 task index 变成第二 authority。

local candidate pilot 在 project preflight 前重算 payload，要求 manifest、完整套件及独立 Source Review 绑定同一候选。跨版本桥先写旧 state 的恢复链接，当前任务为最后 live object，读回全部后像后只登记原事务 COMPLETE。目标 schema6 state 的 majorTransition 必须链接真实完成事务，单独的 transactionComplete=true 不足以准入。中断按原证据续完或逆序回退，第三方字节拒绝；原 FINALIZE 完成后才开展新任务。日常恢复不依赖历史升级任务留在原路径，但必须保留仍被当前 state 引用的事务材料。

实际 project mutation 的 schema3 authorization 必须额外绑定当次 `canonical + manifestIdentity`；candidate 或 manifest 任一字节变化都会拒绝旧 package。

当前runtime不再因规则包字节数自锁。旧 `-RepairSelectedRulePackBudget` 对正常可运行来源返回NO_CHANGE，不调额或创建事务；仅真实旧runtime预算失败可沿原限域授权桥接，旧失败不能冒称PASS。旧包不热改，采用仍核对真实来源和原授权。
<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:BEGIN -->
PROCESS_REQUIREMENTS_RESOLVE是受治理工作的唯一过程入口。DISCOVER组合sealed原生规则、仍有效纠正和永久项目规则，各自保留authority；动作与输出分别ADMIT_ACTION/FINALIZE_OUTPUT，receipt临时且非权威。调用/选择语义、严格来源校验、预算与临时生命周期只由TOOL_CONTRACT定义。

新项目以`.ai-workspace/process-policy.json`承载规则，selectedRulePackBytes仅保留历史／兼容数据，不限制完整规则包。真实bytes、规则数及选择结果用于查明无关加载、重复和异常增长，不新增阈值、调额或确认门。PROJECT-CUSTOM与policy各自绑定当前来源；不同职责可同时存在，不因两个位置直接拒绝。真正重复的有效正文拒绝，语义冲突由当前任务识别并正常整理，不能静默覆盖；保持唯一语义归属，不强制迁移或新增语义解析器。

项目规则可内联或引用使用者维护的完整标准/唯一marked section及直接依赖。PROJECT_RELATIVE相对当前项目根；ABSOLUTE_FILE为显式本机非reparse绝对文件，可在项目外或独立checkout；省略kind保持PROJECT_RELATIVE。项目自行选择位置，多个项目绑定同一文件即可共享；不设全局注册或强制复制。policy保留selector、kind/locator、whole identity、section、dependency和decision evidence，原使用者拥有正文，读取不授予写权限。

composer按TOOL_CONTRACT在选择前校验所有显式来源与禁读边界，不扫描目录、网络抓取或递归普通链接，未选正文不进模型。来源/章节/依赖漂移使旧receipt失效；正文漂移时不以旧selector/section排除，保守提供当前全文并公开ceiling，等待项目正常重绑。相同物理来源/当前身份/完整块的响应去重保留每条义务与全部依赖；不同来源不合并。

项目维护AI根据用户指定文档、用途、全文/章节和直接依赖生成policy，用户无需手写JSON。直接原文引用已经可用，提炼/拆分是可选项目工作；摘要默认仅导航，替换规范须经原项目规则修改与验证门且保持唯一有效正文。

发行包的可选标准和声明式preset只提供来源，不自动采用。项目按自己的原始决定将所选规则写入自身policy；preset展开后不参与日常组合，也不成为第四权威。补充/替换在同次policy修改中退出旧项并加入新项，不静默抑制原生治理。固定来源、跟随授权与变更边界由现有decisionLocator指向的项目决定表达，不新增更新字段或后台同步。Framework、发行包和Maintenance不记录其他项目采用信息，也不要求回传；自身项目的采用及必要事务证据仍归自身。可用软件正文和数据展开说明见standards/README.md。

三源共用一套当前semanticHints选择语义、原结构轴与显式确定性触发；旧输入格式兼容不形成第二解析器或模式。真实不兼容沿原采用路径预检/转换。新增source字段进入identity，旧receipt及精确吸收映射不得沿用。

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:BEGIN -->
## Tool backend

`TOOL_CONTRACT.md` 定义 language-independent operations，`TOOLCHAIN.json` 把它们映射到 sealed entrypoints。Framework `2.0.0` 只提供 `powershell7`；host/AI 直接解析并调用 entrypoint。不增加 launcher、task-level backend choice、runtime generation 或 automatic installation。未来 backend switch 属于 project-level adoption，只有 release 含第二个 official backend 时才可暴露。
<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:END -->

<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:BEGIN -->
## Controller lifecycle

machine truth 是 `controller.json`。handoff 冻结 old/new identity 与 epoch；有授权时先写 hot projections，最后写 Controller object，并以 `TAKEOVER_COMPLETE` 结束。old read-only grace 可以为 recovery 保留 bytes，但不保留长期 routing authority，也不授权 cleanup。

本块适用于此刻实际进行的 Controller 身份／epoch 移交及其 hot projections；规范语义提示应表达主控交接、接任、切换或任期变更。角色名、当前状态整理、普通任务交接和仅调整 effort 不形成 Controller 移交；取消或条件性未来交接仍按 IntentEnvelope 的当前动作归一化，语义未明则保守加载并核对。
<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:BEGIN -->
## Knowledge capability

Knowledge reference 仍为 optional、project-local、non-authoritative。`DISCOVER` 返回 compact metadata；`QUERY` 在 request scope 校验显式选择的 IDs，不设统一数量配额。只读 changed-authority impact check 帮助 owning task 在正常 acceptance boundary 刷新或标记 stale entry。不增加 background service 或 automatic write；Knowledge 不能改变 product facts、task authority 或 Framework pin。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:BEGIN -->
## Owner-first project work

project adoption 加载 `2.0.0` starter 与 task contract，但不批量重写 existing task card 或 session。在未变化的 domain task 内，TASK_OWNER 直接选择 temporary actor/Reviewer、签发新的 scoped package 并接收结果。PROJECT_CONTROLLER 只处理 Controller-owned next action，或 owner/public-decision、cross-domain-contract、protected-path、project-phase、Git/device/external、resource-conflict boundary。

涉及责任身份的组合转换按TOOL_CONTRACT的CONTROL_TRANSITION处理；发现原任务或Controller的transitionRef时先恢复原事务。旧主体只保留计划内恢复权；完成证明持久保存后再清标记，不用fresh授权追认旧写入。
<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:BEGIN -->
纠正的日常安装、修订、暂停、恢复和卸载独立于Framework升级。corrections.json保存当前项目权威；效果不佳、总成本、副作用或用户决定改变均可触发处置，不以Framework吸收为必要条件。ACTIVE或未声明生命周期的现有记录参与选择；PAUSED/UNINSTALLED为不生效历史，不用不可能命中的selector假装停用。

操作覆盖该纠正实际引入的整组效果：委托、导航、policy、配置、专属文件和正文。按原installation证明归属，以FILE精确前像或TEXT唯一上下文撤销，保留后来独立决定。依赖、共享、重叠或未知历史只阻断受影响对象；不能声称未知效果已撤下，也不无限阻塞无关工作。暂停可恢复，卸载不由注册或升级复活。原审核、接受、授权及保护边界不变。

每次操作在原upgrade-recovery/corrections/<ID>/<batch>/保存不可变history.json（完整旧record、操作和决定），当前record仅引用最近history的locator/identity；旧record保留此前history及installation引用。installation证明效果归属，history证明正文/状态演进，事务state.json证明恢复，三者不混称。新历史与全部后像同一投影提交，历史失败不得只改当前正文；正常加载不展开历史链。正式历史及原任务/Git证据长期保留，不按临时收据清理。

REVISE在同一投影中替换当前record及已证明的效果，不拆为先卸载再安装的两个事务。只改正文/selector时保留installation及效果；拆合沿原精确整组投影保留每条旧记录和完整义务映射，不新建吸收表或授权语言。REGISTER_HISTORY只登记有证据的旧安装，不自动归档、不补造前像或强制全项目登记。缺归属的既有record可独立修订、暂停或卸载并保存真实旧记录；lifecycle.installation=NOT_APPLICABLE明确安装历史未知，不因此维持旧正文有效。已证明归属的效果按真实原记录处置；用户明确指定移除的效果在现有installation记录中以effectDirection=CURRENT_REMOVAL保存本次真实移除前后像，不声称这是历史安装before。未知效果如实保留未证明/未逆转，不能冒称整组恢复。

先预览静态路径和当前全组对象，再按精确包Apply并重验来源；写后完整三源组合不合法则整组回滚。进程中断复用原事务恢复与当前授权，第三方混合字节拒绝。实际操作参数由根PROJECT_ADOPTION导航，工具不证明隐含语义依赖。
<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:BEGIN -->
Framework发布通用行为、边界、验证和迁移说明，不登记消费者纠正ID或源record hash来抑制项目规则。项目可经授权提供Issue/PR/文件/本机证据，默认不外传。采用时由项目对实际旧有效、旧抑制及停用历史分析：完整覆盖退出重复，部分覆盖保留项目增量，未覆盖保留，冲突定位处理，证据不足说明而非伪称吸收。工具只检查已审精确投影，不代替语义判断。新运行时只按项目当前记录/生命周期选择；对象hash用于漂移、权限和恢复，不证明覆盖。旧中央映射退出前，在旧健康runtime取得真实分类并保存完整来源，显式处置被抑制记录，防止复活。依赖新版本才成立的退出与目标运行绑定同一采用事务，失败回到匹配旧包和完整项目前像；后来独立修改不能被覆盖。当前已知项目优先一次迁移，不建长期双轨、中央/本地吸收台账或任意旧版本转换。暂停/卸载与通用吸收不同，历史持续可追溯。
<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:END -->
