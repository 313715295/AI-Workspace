# Project control

<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:BEGIN -->
项目 repo-local `.ai-workspace/project.json.frameworkVersion` 是唯一 version-selection authority。Framework root 不保存 consumer record，也没有 global default selector。

## Registration

root `scripts/register-project.ps1` 要求显式 exact version 与 Controller ID。任何项目写入前必须校验：

用户明确要求采用 Framework 开展项目工作即确认使用。注册预览将该决定投影到 AGENTS 管理导航段之外的用户区，实际注册一并保存持续委托；不增加独立的委托确认门。纯只读评估不执行注册，不把模板存在当采用。已有用户决定与自定义正文保留，升级只替换管理导航段，不重新生成用户委托；后续明确限制优先。正文和边界取 AUTHORIZATION_MODEL。

- target `VERSION.json` 为 `STABLE`、consumable 且 pin-eligible；
- target `RELEASE_MANIFEST.json` 匹配 canonical payload，且 source Review 为 approved；
- target `project-starter` inventory 精确；
- destination Git top、path 与既有 control-plane condition 安全；
- selected version 的 `TOOLCHAIN.json` 精确，`pwsh` 满足唯一 official `powershell7` backend，且该 backend 声明当前 host platform。

工具只物化 selected version 的 `project-starter`。对 `1.16.0`，starter 写入 `frameworkToolBackend=powershell7`、空 `.ai-workspace/process-policy.json`、单一 project-config locator，以及兼容字段 `selectedRulePackBytes`；旧默认数字保留历史格式，不是用户配额或运行上限。starter 是可复用 project process，registration 不发明第二套流程。

registration 还对 repository root `.gitignore` 做幂等投影：复用已有等价 `.ai-workspace/runtime` rule；不存在时只追加 `/.ai-workspace/runtime/`；相反 negation 必须 fail closed。该写入与 control-plane material 同属可恢复 transaction，并保留原 newline style。
<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:END -->

<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:BEGIN -->
## Upgrade

root `scripts/upgrade-project.ps1` 要求 caller 提供 `RepositoryPath`、`ControllerId` 与 exact `ToVersion`。写入前校验 target release，接收 migration matrix 声明的健康 schema3 source，并保留：

- project ID 与 display name；
- repo-local layout 与 repository root；
- Controller ID、epoch 与 state；
- routine exclusions 与 capabilities；
- Bootstrap project custom region。

升级到 `1.16.0` 时，还投影 target starter 的项目级 backend、`selectedRulePackBytes` 与 runtime ignore rule，并在 recovery 或 project mutation 前要求 PowerShell 7 与 declared platform。backend 由所有任务继承，不复制进 authorization package；既有 `projectConfigIdentity` binding 会在该字段变化时使 package 失效。

对支持的 direct source，升级不得先让 current-pin resolver 决定成败。工具在 system temp 中创建隔离 Git projection，先写入 target project、Bootstrap、corrections、process policy、已迁移的 task `actor + role + phase` route 与项目预算，再调用 target `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。完整 target source composition、身份和授权校验 PASS 后，才可准备实际 transaction；正文大小不构成准入门。这样 1.11/1.12 两字段任务卡或旧 pin 的较低预算不会形成 target-before-pin deadlock。projection 只产生机械证据，不授予 write，也不替代 actor-bound package、exact object check、protected path、user decision、transaction recovery 或 task-last live-object stop。

只有声明的 managed objects 会改变。工具不搜索 consumers，不修改 source/product file，不 stage/commit/push，也不更新其他项目。

`1.16.0` starter 以 current task 的 actor/role/phase Work route 作为 loader input，并用唯一 process-policy carrier 保存 permanent project-specific process rules。它不把 task state 移入 Framework root，不创建 consumer record，也不把 task index 变成第二 authority。

local candidate pilot 在任何 project preflight 前重算 candidate payload，并要求 manifest 声明、完整套件证据及独立 Source Review evidence 全部绑定同一 canonical。本地候选/schema4 的安装完成由既有 recovery state 的 `transactionComplete=true` 证明：先保存 false，全部 live postimages（task 最后）匹配后，只登记此完成标记并结束原 exact 事务，不追加其他项目工作。未登记成功由原恢复路线续完；不得通过历史升级任务仍在 active、任务缺失或聊天结论猜测完成。日常任务恢复不依赖旧升级任务的位置或全文。

实际 project mutation 的 schema3 authorization 必须额外绑定当次 `canonical + manifestIdentity`；candidate 或 manifest 任一字节变化都会拒绝旧 package。

当前runtime不再因规则包字节数自锁。旧 `-RepairSelectedRulePackBudget` 对正常可运行来源返回NO_CHANGE，不调额或创建事务；仅真实旧runtime预算失败可沿原限域授权桥接，旧失败不能冒称PASS。旧包不热改，采用仍核对真实来源和原授权。
<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:BEGIN -->
PROCESS_REQUIREMENTS_RESOLVE是受治理工作的唯一过程入口。DISCOVER组合sealed原生规则、仍有效纠正和永久项目规则，各自保留authority；动作与输出分别ADMIT_ACTION/FINALIZE_OUTPUT，receipt临时且非权威。调用/选择语义、严格来源校验、预算与临时生命周期只由TOOL_CONTRACT定义。

新项目以`.ai-workspace/process-policy.json`承载规则，selectedRulePackBytes仅保留历史／兼容数据，不限制完整规则包。真实bytes、规则数及选择结果用于查明无关加载、重复和异常增长，不新增阈值、调额或确认门。legacy PROJECT-CUSTOM在独立Review的原子迁移同时建立structured carrier并退役已迁移正文前仍是bound source；empty-source与双载体同规则均拒绝。

项目规则可内联或引用使用者维护的完整标准/唯一marked section及直接依赖。PROJECT_RELATIVE相对项目Git根；ABSOLUTE_FILE为显式本机非reparse绝对文件，可在项目外或独立checkout；省略kind保持PROJECT_RELATIVE。项目自行选择位置，多个项目绑定同一文件即可共享；不设全局注册或强制复制。policy保留selector、kind/locator、whole identity、section、dependency和decision evidence，原使用者拥有正文，读取不授予写权限。

composer按TOOL_CONTRACT在选择前校验所有显式来源与禁读边界，不扫描目录、网络抓取或递归普通链接，未选正文不进模型。来源/章节/依赖漂移使旧receipt失效；正文漂移时不以旧selector/section排除，保守提供当前全文并公开ceiling，等待项目正常重绑。相同物理来源/当前身份/完整块的响应去重保留每条义务与全部依赖；不同来源不合并。

项目维护AI根据用户指定文档、用途、全文/章节和直接依赖生成policy，用户无需手写JSON。直接原文引用已经可用，提炼/拆分是可选项目工作；摘要默认仅导航，替换规范须经原项目规则修改与验证门且保持唯一有效正文。

三源共用一套当前semanticHints选择语义、原结构轴与显式确定性触发；旧输入格式兼容不形成第二解析器或模式。真实不兼容沿原采用路径预检/转换。新增source字段进入identity，旧receipt及精确吸收映射不得沿用。

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:BEGIN -->
## Tool backend

`TOOL_CONTRACT.md` 定义 language-independent operations，`TOOLCHAIN.json` 把它们映射到 sealed entrypoints。Framework `1.16.0` 只提供 `powershell7`；host/AI 直接解析并调用 entrypoint。不增加 launcher、task-level backend choice、runtime generation 或 automatic installation。未来 backend switch 属于 project-level adoption，只有 release 含第二个 official backend 时才可暴露。
<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:END -->

<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:BEGIN -->
## Controller lifecycle

machine truth 是 `controller.json`。handoff 冻结 old/new identity 与 epoch；有授权时先写 hot projections，最后写 Controller object，并以 `TAKEOVER_COMPLETE` 结束。old read-only grace 可以为 recovery 保留 bytes，但不保留长期 routing authority，也不授权 cleanup。
<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:BEGIN -->
## Knowledge capability

Knowledge reference 仍为 optional、project-local、non-authoritative。`DISCOVER` 返回 compact metadata；`QUERY` 在 request scope 最多校验三个 selected IDs。只读 changed-authority impact check 帮助 owning task 在正常 acceptance boundary 刷新或标记 stale entry。不增加 background service 或 automatic write；Knowledge 不能改变 product facts、task authority 或 Framework pin。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:BEGIN -->
## Owner-first project work

project adoption 加载 `1.16.0` starter 与 task contract，但不批量重写 existing task card 或 session。在未变化的 domain task 内，DOMAIN_OWNER 直接选择 temporary actor/Reviewer、签发新的 scoped package 并接收结果。PROJECT_CONTROLLER 只处理 Controller-owned next action，或 owner/public-decision、cross-domain-contract、protected-path、project-phase、Git/device/external、resource-conflict boundary。
<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:BEGIN -->
纠正的日常安装、修订、暂停、恢复和卸载独立于Framework升级。corrections.json保存当前项目权威；效果不佳、总成本、副作用或用户决定改变均可触发处置，不以Framework吸收为必要条件。ACTIVE或未声明生命周期的现有记录参与选择；PAUSED/UNINSTALLED为不生效历史，不用不可能命中的selector假装停用。

操作覆盖该纠正实际引入的整组效果：委托、导航、policy、配置、专属文件和正文。按原installation证明归属，以FILE精确前像或TEXT唯一上下文撤销，保留后来独立决定。依赖、共享、重叠或未知历史只阻断受影响对象；不能声称未知效果已撤下，也不无限阻塞无关工作。暂停可恢复，卸载不由注册或升级复活。原审核、接受、授权及保护边界不变。

每次操作在原upgrade-recovery/corrections/<ID>/<batch>/保存不可变history.json（完整旧record、操作和决定），当前record仅引用最近history的locator/identity；旧record保留此前history及installation引用。installation证明效果归属，history证明正文/状态演进，事务state.json证明恢复，三者不混称。新历史与全部后像同一投影提交，历史失败不得只改当前正文；正常加载不展开历史链。正式历史及原任务/Git证据长期保留，不按临时收据清理。

REVISE在同一投影中替换当前record及已证明的效果，不拆为先卸载再安装的两个事务。只改正文/selector时保留installation及效果；拆合沿原精确整组投影保留每条旧记录和完整义务映射，不新建吸收表或授权语言。REGISTER_HISTORY只登记有证据的旧安装，不自动归档、不补造前像或强制全项目登记。缺归属的既有record可单独修订并保存真实旧正文，但不据此撤销未知文件效果。

先预览静态路径和当前全组对象，再按精确包Apply并重验来源；写后完整三源组合不合法则整组回滚。进程中断复用原事务恢复与当前授权，第三方混合字节拒绝。实际操作参数由根PROJECT_ADOPTION导航，工具不证明隐含语义依赖。
<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:BEGIN -->
Framework发布通用行为、边界、验证和迁移说明，不登记消费者纠正ID或源record hash来抑制项目规则。项目可经授权提供Issue/PR/文件/本机证据，默认不外传。采用时由项目对实际旧有效、旧抑制及停用历史分析：完整覆盖退出重复，部分覆盖保留项目增量，未覆盖保留，冲突定位处理，证据不足说明而非伪称吸收。工具只检查已审精确投影，不代替语义判断。新运行时只按项目当前记录/生命周期选择；对象hash用于漂移、权限和恢复，不证明覆盖。旧中央映射退出前，在旧健康runtime取得真实分类并保存完整来源，显式处置被抑制记录，防止复活。依赖新版本才成立的退出与目标运行绑定同一采用事务，失败回到匹配旧包和完整项目前像；后来独立修改不能被覆盖。当前已知项目优先一次迁移，不建长期双轨、中央/本地吸收台账或任意旧版本转换。暂停/卸载与通用吸收不同，历史持续可追溯。
<!-- AIW-REQUIREMENT:PR_CORRECTION_ADOPTION_ANALYSIS:END -->
