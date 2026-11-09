# 项目接入与升级

本文件随包交付，供项目注册、升级、恢复和纠正操作按需查阅。开发仓可维护根级工具；已分发或已绑定运行包保持原字节，修复通过新的分发及项目显式采用交付。内部版本 pin 与命名分发身份分别报告。

## 从用户入口开始

用户包从包内 README/AGENTS 导航，开发仓从 [README](../README.md) 导航。接入和升级由用户需求或已授权任务启动；已有项目按其采用来源声明的项目入口恢复当前治理事实；目标 navigation3 直接使用项目 Bootstrap，旧 navigation1/2 仍使用原 Skill。首次注册尚无 Bootstrap 时，先检查所选版本的 VERSION、RELEASE_MANIFEST、ADOPTION_PROFILE 和 TOOLCHAIN，再运行 [register-project.ps1](../scripts/register-project.ps1) 预览。注册必须显式给出内部 `FrameworkVersion`、项目 `RepositoryPath`、项目 ID 与 `ControllerId`，在已有项目写授权范围内应用并完成下面的宿主接入收尾。开发中的新根入口以明确项目目录为根，普通项目和用户包不要求Git程序或.git；不自动git init，也不扩大到父仓。旧发行包仍以原随包行为为准。

升级使用 [upgrade-project.ps1](../scripts/upgrade-project.ps1) 预览及目标版本声明的兼容范围；目标未声明支持当前 Project Format/capability 时停止，不按发行名称推断兼容。普通项目使用版本通用 starter。恢复和动作门禁只由当前项目 Bootstrap 与其 pin 对应的 runtime 合同维护，本入口不复制。

navigation3 的 AGENTS 托管区只导航本项目 Bootstrap，用户正文置于 `AI-WORKSPACE-USER-DECISION` 区。旧托管约定和区外无标签约定在原位置承接，已有用户区保持原文；分散约定保持原先相对次序，后续收窄或撤回继续有效。刷新现有入口不补默认授权，未知混合托管定制在写入前报告具体冲突并保留原文件。标签本身不证明授权，缺标签也不撤销决定。首次新建入口使用已明确采用的模板约定；注册、刷新、升级都沿同一投影保留完整前后像和原回滚/恢复，原 FINALIZE 完成后才切换入口。Bootstrap纠正兼容区不是加载开关，其存在不表示有生效纠正。

当前两个根入口在专用 `pwsh -NoProfile -NonInteractive -File <入口>` 文本进程中逐条保留已有字符串，最终对象以完整紧凑 JSON 表示，数组不经过宿主表格省略。预览文字、WRITESET、WhatIf 与状态 JSON 可逐行并存，整段输出不一定是单个 JSON 文档。重定向的标准输出和错误使用该进程存活期间的 managed UTF-8 writer；未重定向的流保留宿主 writer。可选完整宿主参数仅支持 NoLogo、Text InputFormat/OutputFormat 及标准 ExecutionPolicy；缩写、NoExit、交互 File、Command/EncodedCommand、非 Text 格式、未知宿主选项和宿主 API 不进入此表示边界。通过 `&`、dot-source 或包装脚本调用时保留原对象、异常和调用者生命。

此边界内的未处理终止错误在原事务与 scope 清理后，以完整原因、异常、调用位置及已拥有的注册/清理错误写入重定向 stderr，退出码仍为非零；入口已有的 stdout JSON 和显式退出码保持。PowerShell 5 对当前 PowerShell 7 业务先返回运行环境拒绝。解析、参数绑定、必需入口模块缺失、进程终止及断管仍可能只有宿主错误或不完整输出。输出运输失败不改变已完成事务，不应据此重做 Apply；恢复依据实际 journal/state。这里说明两个根入口的窄表示，不给其他 CLI 增加统一输出格式。

项目资料和标准保存在用户选择的位置，优先直接复用已有文档；共享标准可在本机独立目录由多个项目分别引用。提取、精炼或改造均为可选，不是采用前置条件，不将标准正文抄入 Framework。维护 AI 可按所选版本 TOOL_CONTRACT 的项目标准引用合同，绑定完整文件或唯一标记章节及直接依赖；用户无需手写 JSON。

普通运行已采用固定包时，核真实当前完成链与独立固定绑定、manifest原始身份和声明，以及本次实际消费的实现/catalog/规则及必要依赖；不递归扫描未消费测试、历史或其他包成员，也不重新hash本次未使用的历史register工具。未观察成员不声称健康，不凭manifest制造全包Facts，不加跨请求缓存、TTL或新Proof。首次/新来源采用、完整资格、构包和ZIP/分发验证仍完整核包，轻量观察不能供给这些完整消费者。

## 既有项目的要求与工作承接

接入对象是当前真实项目及其有效要求，不由行业、目录或注册者身份决定。先定位项目边界、受支持固定包、当前责任和仍有效用户决定，区分现行要求、候选建议、业务事实、研究资料与历史证据；标题、日期和普通链接本身不证明规范效力。

在原接入方案或任务中比较原要求与框架的触发条件、责任、动作、例外、证据及继续条件。完整覆盖的重复义务退出，部分覆盖保留实际增量，冲突明确解决，依据不足保留未知。注册器只管理声明范围，保留入口管理区外原始文字，不会自动理解并消除旧入口冲突；必要正文调整纳入原接入授权，不能因新入口生成而丢弃旧有效要求，也不建立永久对照台账。

来源可读取、项目已采用和当前任务命中分别验证。优先直接引用用户指定的完整正文，只有确有需要才精炼或按唯一标记章节组织。同一文件的不同完整章节可以分别采用并按共同实际条件命中；各项按当前 pin 的读取模式绑定身份，具体身份和漂移边界取所选版本 TOOL_CONTRACT 的项目标准引用合同，保留语义条件、例外和顺序。每项声明必需的正文依赖并核对完整、无环的有序组装；普通互链只导航，不因两文互链就制造循环依赖。实际必读正文漏配或无法表达时保留缺口，不删除必要依赖伪造成功。生产者、同一成果的审核者和接受者读取同一适用专业要求；项目选择条件须包含真实审核/验收工作分类，不能用伪implementation请求补命中。是否启用知识引用不影响规范加载责任。

基础注册、原要求承接、可选标准采用和可选知识引用分别按实际前提推进。不启用 KNOWLEDGE_REFERENCE 也可完成接入；已有研究资料不必搬迁、建索引或成为规范。选择可选软件标准时，沿已有 policy 采用及完整正文加载机制验证，本包新正文不会自动更新其他项目的标准来源。正文、来源绑定及采用须按现有项目授权协调变更，来源变化使受影响旧包/收据失效；不能反复重签包掩盖未闭合原动作。

当前仍有成果责任的工作由真实任务卡承接，独立成果才分任务，不按每个业务阶段造卡。任务保存当前目标、责任、范围、结果和必要资料引用；研究、历史审核和项目数据留在适当原位置。历史不补造授权或框架审核，新候选不自动继承旧通过。频繁变化的业务事实按任务读取，不无区别地纳入固定规范源；不用全档案扫描、迁移全部记录或补历史任务证明接入完整。

基础控制面成功只报告 CONTROL_PLANE_READY；接入任务另说明有效要求承接、宿主真实加载和已验证工作范围。STATUS 提供实际任务 ID/链接和当前配置入口，不镜像任务 role、phase、writer/reviewer。有首卡时在 REGISTER 投影前绑定它，没有首卡的受支持分支如实表示尚无当前任务。按所采用入口恢复，健康续作不一律 FULL_COLD。后续整合未完成时如实保留阶段与下一动作，中断沿已完成阶段和原事务恢复，不把独立阶段称为可一起原子回滚。

已有有效外部授权按当前责任与精确动作映射，继续遵守原停止和恢复条件；Controller 普通 EXTERNAL 包与免费 TASK_OWNER 路线保持各自限制。预算、额度、供应商操作和业务状态归项目，不因接入新增框架预算模块或外部动作类型。报告实际完成状态、限制和责任，Owner 接受不冒充用户接受，不要求用户为仍有效决定重复确认。

## 新项目首次候选接入

从目标项目目录启动会话，提供明确运行包目录和采用目标。默认注册仍只接受合格 STABLE。固定命名的 2.0 CANDIDATE 只有在该包确实包含首次注册支持、ADOPTION_PROFILE 允许注册/试点、完整 payload 与当前源码证明及独立 Source Review 绑定一致时，才可显式 `-LocalCandidatePilot` 注册。release manifest schema2 保持 completeSuite 原语义；schema3 校验有限 Qpre、PREPACKAGE_PASS 及被审 manifest 原字节投影。不得从开发根、任意工具副本或旧包借用资格；PACKAGE_MANIFEST schema2 与实际执行工具必须绑定同一 runtimeRoot/内容。

AI 根据“完成本项目接入并开始治理”的原始目标准备首张真实有限任务，填清 ID、Owner、宿主 actor、Work route、profile、精确范围和验收。通过现有任务检查器后，将 `InitialTaskPath`、`ExpectedInitialTaskIdentity`、`InitialTaskRelativePath` 成组交给注册入口；最后一个参数为 `.ai-workspace/tasks/active/<task-id>.md`。这是首次 root REGISTER 在控制面缺失时的受限初始化，不是无限期 Root 占位任务，不要求用户再填写授权表。用户尚未决定业务工作时，不能把猜测的产品目标写入首卡。稳定注册可继续原调用；2.0 稳定注册可选择同一首卡参数组。

```powershell
# 从目标项目启动；路径和值由 AI 从当前真实目标形成
pwsh -File <固定运行包>/scripts/register-project.ps1 -ProjectId <id> -DisplayName <name> -RepositoryPath <项目目录> -FrameworkVersion 2.0.0 -ControllerId <当前宿主actor> -WorkspaceRoot <固定运行包> -LocalCandidatePilot -InitialTaskPath <已准备首卡> -ExpectedInitialTaskIdentity <length|SHA256> -InitialTaskRelativePath .ai-workspace/tasks/active/<task-id>.md
```

先预览；沿同一对象、任务和决定以 `-Apply` 应用。预览与 WhatIf 不创建控制面或事务；registrationId 保持确定绑定，可显式携带预览 ID。Apply 把首卡、入口和 schema7 REGISTER-origin state 放入同一真实 REGISTER 事务，state 最后写入；私有目标检查通过后才登记 journal COMPLETE。失败使用原投影回退，第三方字节拒绝覆盖。完成后通过正常 rule/support 读取证明可工作；此最后检查失败报告 REGISTERED_RUNTIME_VALIDATION_FAILED，保留已闭合事务，不谎称成功或反向回滚闭合事务。

完成证明由原 REGISTER journal、其中 state 的实际后像及固定 registrationId 建立。`transactionComplete=true` 或 SELF_PROJECTION_BOUND 字符串单独均非完成证据。普通加载不接受 APPLYING、缺失 journal、迁移目录或漂移的固定包。首卡此后可正常修改、关闭或归档，项目规则也可在当前授权下演进；历史安装内容不永久冻结今天的任务和规则。

注册完成和宿主接入收尾之后，AI 用这张任务完成真实 DISCOVER、读取完整规则、当前 scoped package/checker、ADMIT、有限项目事实 CONTROL_WRITE 与 FINALIZE。NONE 仍只读。后续业务任务、控制写入及同 pin 刷新继续按当前任务授权；不从首次初始化推导持续写权。schema7 项目刷新沿下述原过程 PREPARE/ADMIT/schema3 Apply/FINALIZE/恢复链，保持 REGISTER origin，并使用独立 refresh journal。

## 统一数据流

注册、跨 pin 升级、同 pin 受管修复和明确批准的永久规则迁移共用以下顺序：

1. 读取项目真实配置、控制载体、选定发行和根工具依赖。
2. 生成内存目标投影并报告逐对象差异；无差异时不创建事务、不改卡。
3. 在项目写入前完成目标结构、目标 resolver 与独立授权预检。
4. 只写有差异的受管对象；按版本合同应用 pin 与任务卡顺序。1.16 本地候选的 schema4/5 事务在全部 live postimages（task 最后）匹配后，还须登记既有 state 的 `transactionComplete` 标记才结束原事务，不能把 task 写完误报为事务完成。唯一运行合同见 [PROJECT_CONTROL](versions/1.16.0/PROJECT_CONTROL.md)。
5. 对目标有效三源规则和项目格式做 Postcheck；失败时先恢复旧 pin，再恢复其余旧对象。
6. 中断后只按已绑定恢复材料继续回退或完成，不覆盖第三方新字节。
7. 成功结果同时报告 Framework pin、实际 Project Format 和 Root Tool Revision。

2.0初始化只创建必要控制入口、稳定项目资料入口与current task目录，不生成专门REVIEW_PROFILE或RELATIONSHIPS。旧版本仍按其自身starter物化；旧项目已有文件不按名称删除，其有效要求在项目迁移中纳入标准、任务或普通资料后才解除固定依赖。PROJECT保存稳定目标/责任及标准知识入口，policy保存采用，任务保存当前成果，STATUS保存全局阶段，index只定位。已知taskId直接读卡和必要项目事实。注册脚本不判断产品文档权威，也不搬迁或改写用户资料。

普通项目无本地Git元数据时不生成或改写.gitignore，不把忽略是否生效作为运行门；有本地Git元数据时按既有规则投影runtime忽略项，元数据存在本身不证明Git身份。实际Git操作及Maintenance sibling CONTROL/TARGET仍按原门验证Git top。预检使用普通隔离目录，只有Maintenance特殊拓扑夹具需要Git。恢复继续校验原精确前后像和事务身份。

所选版本的可选标准和preset只提供通用来源。项目沿自己的决定将展开的规则写入自身policy；未采用不载入，采用信息不回传、不由Framework或Maintenance集中登记。2.0版本说明导航到standards/README.md中的软件正文及纯数据展开入口，旧版包不因此包含或启用这些新能力。

逻辑提交不是 Git commit，也不承诺多文件瞬时原子。安全保证是：任何未能完成 Postcheck 的尝试都不得开放新的有效行为；能够安全恢复时，旧 pin、旧受管对象和旧有效三源行为全部恢复。

既有固定来源的日常检查和同包升级先验证当前采用的真实完成链及独立 distribution binding，再逐次验证完整包字节，使用 FIXED_ADOPTED_SOURCE；首次或显式新来源仍走完整源码资格。schema6 必须关联当前 state 实际后像的最新 UPGRADE/REFRESH 和原准入，schema7 保留原 REGISTER 及刷新关系；stable 注册只使用自身 COMPLETE REGISTER、投影及根工具身份。仅有 transactionComplete、旧 major origin 或弱 binding helper 不足以进入固定来源路径。原证据缺失/不支持时沿原完整验证或恢复，漂移和在途事务仍拒绝。首次注册的预检上下文没有已完成采用资格。

同一根动作内的完整资格结果只在同一 reader/runspace 的私有内存复用，消费前仍检查全部相关实际字节、成员和路径边界，动作结束、失败、异常、取消及模块重载后释放。它不缓存当前项目规则或权限，不把包验证、源码资格、分发接受和项目采用合为一项。

## Project Format 与 capability

Project Format 来自实际 project/controller/corrections/process-policy 等载体 schema，不由 Framework 版本白名单推断。capability 只描述已观察到且格式未必保证的结构能力，不代表功能开关、权限或授权。

相同 Project Format 的普通版本变化不应批量改任务卡。只有当前任务仍缺少目标格式要求的 actor/role/phase 时，才在同一事务中迁移该任务。

## 幂等

- 初次注册：目标不存在时创建；候选重复注册须核对真实 COMPLETE REGISTER、项目及同一固定分发后才返回 ALREADY_REGISTERED，不再依赖临时首卡来源或首卡仍在 active。不同运行包须显式同 pin 刷新。
- 跨 pin：仅投影真实差异。
- 同 pin：无差异返回 NO_CHANGE；受管对象漂移只能在精确授权下修复。
- 重试：先识别现有恢复状态；不得叠加第二事务。
- 升级失败：保留有界恢复材料；恢复完成前禁止普通消费。

已完成采用的 recovery state 保存原安装任务、Owner、actor、授权与材料作为历史证据；后续同 pin 刷新由当前真实任务和新授权独立约束，不改写历史绑定。未完成事务仍只能由原绑定继续恢复。

## 永久规则迁移

只有用户明确选择的项目过程规则才从 legacy PROJECT-CUSTOM 成对迁入 process-policy。迁移同时移除旧运行正文，但保留项目事实、定位与非过程扩展。准备态不会成为正常规则来源；成功前后都只能有一份有效规则，失败则恢复原组合。

process-policy 可以显式引用项目内文件或当前受支持宿主上的本机绝对文件。target-before-pin 预检只把项目内来源快照复制到临时 projection；项目外来源在原位置只读复核 identity，既不写入 projection，也不进入采用 transaction。预检、失败恢复与采用都不得修改标准来源文件。

已采用支持此能力的固定版本后，本项目专业正文与引用的联合更新沿版本TOOL_CONTRACT双动作分支：SOURCE_WRITE正文与CONTROL_WRITE载体分别准入，保留完整目标及原两份ADMIT。写包只含实际改变对象，按docs→改变的policy→改变的config原子写/读回，原前后像识别已知prefix并可续。新日常批次不强制全局journal、进度游标或双pending提交；allNew后各原FINALIZE取得真实结果，两份均成功才整批完成；已成功成员不重写/重跑，未完成员沿原件补收口。任一正式成功后不自动回退。Maintenance CONTROL正文仍仅当前Controller精确例外，TARGET独立。真实联合写段保留必要保护，普通读/预览/纯F不取写锁；已有真实journal按原固定工具恢复，不删除历史或热改包。候选资格、分发和显式采用仍独立。

## Root Tool Revision

根工具 revision 由真实入口、导入的公共模块及会影响投影的模板/合同文件按 ordinal 路径和整文件 identity 计算。它与 Framework pin、Project Format 一起进入采用结果和恢复证据，但不新增第二个项目 pin 或永久台账。


## 宿主接入收尾

目标TOOLCHAIN声明PROJECT_BOOTSTRAP/navigation3时，注册/升级/刷新统一投影项目AGENTS到本项目BOOTSTRAP，并读回该入口与实际固定来源。核对宿主提供的项目入口和模型实际读取；磁盘一致不等于当前正文已加载。新目标不要求Router Skill安装、发现或新兼容层。

用户授权与项目自定限制属于项目用户拥有的正文。升级承接当前真实授权原文、后续决定及区外内容，导航管理区按目标模板更新；新注册由人类明确采用决定生成已批准约定，不要求已有AGENTS或逐项二次确认。未知混合custom先保留并在原准备范围解决，不能猜测删除或静默扩大授权。

旧nav1/nav2项目继续使用原固定包声明的兼容Skill；原准入、Apply/恢复和原FINALIZE先完成，再读取新AGENTS/Bootstrap。部分文件更新不说明切换成功。仍需旧入口的宿主不自动卸载、不改原Skill；实际依赖结束且已有宿主权限才自然退役，不登记消费者或建立每项目副本。项目写授权不自行产生宿主安装/卸载权限。

交付结果只报告实际入口/来源、可发现与实际读取范围及缺口；健康连续使用不逐工具重读，不为接入记录新增服务或台账。

## 试点与发布

STABLE 封存与已审 Snapshot 分发不同。可变开发候选本身不能作为已发布运行包；只有已冻结、通过适用验证和独立审核的精确 Snapshot 才可按分发资格使用。项目通过真实预览和授权显式采用，Snapshot 不自动等同 STABLE 或项目接受。

2.0 schema3 的 SOURCE_QUALIFIED 是源码入口资格：reader 验当前完整载荷、Qpre 的 PREPACKAGE 原执行证据、所需实际根工具与 Mreview→Msealed 的严格投影，便携证明不访问原测试机器路径，也不授权跨 root 复用旧执行。它不代表最终分发已验收。按 FRAMEWORK_RELEASE 的 S0–S5，builder 只构建 BUILT_UNVERIFIED 的新 ZIP；实际完整性及隔离注册/同版本升级 smoke 的 Gpost 结果 Qpost 保存在包外，Z 与内置 manifest 不再改变。发行 Owner 接受精确 Z/Qpost 并满足发行门之后才具备 DISTRIBUTION_READY。S4 隔离验证在已有测试权限内使用公开入口和候选原准入条件，不伪造分发接受；真实消费者采用仍独立授权。

### 固定分发运行来源

运行包位置沿用使用者指定或已授权选择的目录；接入不默认迁移、复制发行包，也不规定按项目独占或多项目共享。位置尚未确定时，在执行部署前补齐；已有有效指定或选择授权不重复确认。发布 ZIP 本身不包含消费者解压、部署或接入动作。

命名分发包解压到独立目录，保留PACKAGE_MANIFEST.json和原文件字节。注册/显式升级固定distributionId、完整包contentIdentity、manifestIdentity与runtimeRoot，版本pin仍由project.json决定。日常恢复核真实采用完成链、独立绑定、manifest原字节及声明和当前实际消费实现/catalog/选中规则/依赖，不遍历未消费测试或历史，也不证明全包健康。真正首次/新来源、完整LocalCandidate消费者、qualification/build/ZIP及分发仍核完整包；实际已消费成员或绑定漂移、事务未完拒绝，不转回开发HEAD。

同版本 snapshot 切换也须经过 root upgrade-project.ps1 的真实 preview、精确 schema3 preimage/postimage 授权与 Apply。旧运行目录保留到切换及恢复验证完成。升级前明确三个来源：负责原准入及回退后正常运行的旧固定包、执行本次升级和恢复的固定兼容接入工具、拟采用的目标固定包。旧 snapshot.3 的 upgrader 不认识新的 UPGRADE_FORMAT_TRANSITION，不能仅凭 Framework 版本号相同将它用作该事务恢复入口。

旧来源按其自身 reader 和原合同观察，目标规则与投影由目标所属模块解释，执行工具只编排其支持的组合。旧 reader 未声明新的日常轻观察函数时，使用该旧来源自己的完整验证路径；不要求旧包补入后来模块或用执行工具的同名 reader 替代。目标 profile 明列 snapshot.16 的真实 REGISTER 起点及 snapshot.17 后续采用，已有累积对象适配链继续复用。JSON 对象成员合法换序不构成值漂移；字段、类型、值、数组次序和原始前后像仍分别严格核对。

本次格式迁移使用与实际 Apply 相同根工具依赖身份的 `scripts/upgrade-project.ps1 -RecoverRuntimeAdoption`，提供原授权及其身份、当前事务身份和原 actor，并选择 `-AdoptionRecoveryDirection COMPLETE` 或 `ROLLBACK`。工具身份复用目标投影中原 ADMIT 绑定的 rootToolRevision/rootToolDependencies；Apply 核对实际执行目录，恢复入口从自身所在目录核对同一依赖字节。工具可以位于目标目录，或该精确固定分发的独立完好副本，不要求新建升级项目或永久项目配置。升级准备材料应保留实际命令路径、固定分发身份及原准入材料。工具自身或其依赖不可用时，须先从精确信任的固定分发恢复可运行工具，不能声称无工具恢复或改用任意旧/新脚本。

COMPLETE 验证目标完整包并执行目标投影检查；ROLLBACK 仍校验原准入、授权、旧运行包、Controller/任务、投影前像和第三方漂移，并核对保存的目标身份与原准入一致，但不读取或执行损坏的目标载荷。对象恢复后最后恢复被替换的原 journal，旧包据此恢复原有运行能力。既有事务关闭后不能用同一恢复入口反向切换；恢复旧 journal 后新事务的旧身份不再是当前身份，改由旧包正常恢复，不重放该回滚命令。

原 journal 不存在时，回滚必须先在既有 upgrade-recovery 位置保存本次终态和必要恢复材料，再精确结束本次 active journal，使未改旧 reader 观察到原路径不存在。保留与结束之间的中断沿同一原事务继续；历史保存失败、active journal 身份漂移或第三方内容均停止，不能把遗留 ROLLED_BACK 文件当作旧来源恢复可用。


BOOTSTRAP project-custom 迁移至 process-policy 是同一精确 CONTROL_WRITE 的来源迁移；managed 区域保持不变。若动作已实际准入后写到一半，ProjectRuleRecoveryPlanPath 指向绑定原 DISCOVER、原 ADMIT 输入/结果和两个载体原/目标字节的恢复材料。root upgrader 先复证原动作与所有 live 字节，再在恢复当下创建事务；第三方状态、缺失原准入、扩大范围均拒绝，最终仍由原 FINALIZE 收口。材料格式由 root helper 校验，不改变 compact receipt schema。
当前 2.0 核心采用并原收口后，日常标准/方法来源维护走 目标 2.0 版本 TOOL_CONTRACT.md「项目来源配置的受限普通采用」定义的 config+policy 普通动作。原固定版本准备完整候选、真实 ADMIT，按 policy→config 写入并原 FINALIZE；它不使用 MajorAdoptionOverrides，也不切 pin。可选知识引用首次启用仅允许当前Controller的精确实际变更包（config-only时不写policy）将缺失或合法disabled变为enabled；不允许关闭、删除或其他能力切换，backend、保护与布局保持。中断时同一个 ProjectRuleRecoveryPlanPath 入口支持合同定义的 schema2 计划和 boundary3 evidenceRefs，COMPLETE/ROLLBACK 均消费原候选与实际准入。回滚可在目标来源离线时恢复原字节；第三方状态零写拒绝，无 journal 的全后像不补造历史事务。原 Bootstrap 迁移的 schema1 计划继续保留。

## 原归档动作完成验证

适用事实：项目仍采用完整固定 TC3/2.0.0 来源；原普通单一 CONTROL_WRITE 已通过真实 checker/ADMIT，所有已审成果和 active 删除后像已完成，原 FINALIZE 仅因旧结果模块读取删除路径而实际返回 EVIDENCE_OBJECT_MISSING。旧 package、规则、任务及采用状态保持原样。不是新采用、回滚或补写入口，不以项目名、文件数量或 snapshot 标签获得兼容资格。

项目原 Owner 核对当下有效的原始人类完成决定及保护范围，使用另经真实测试、独立审核/接受而形成的新合格固定分发的 `scripts/upgrade-project.ps1`：提供 ProjectId、ToVersion=2.0.0、RepositoryPath、ActorRouteActor，以及成对 `OriginalTaskArchiveFinalizePlanPath`/`ExpectedOriginalTaskArchiveFinalizePlanIdentity`。`OriginalTaskArchiveForbiddenPath` 提供当前禁止访问的 literal 相对路径。默认只预检；`CompleteOriginalTaskArchive` 才执行原 FINALIZE 并写新证据。与 Apply、LocalCandidatePilot、RecoverRuntimeAdoption、ProjectRuleRecovery、AdoptionProcessMode、纠正、WorkspaceRoot 及其他升级参数互斥；由实际脚本所在新固定根验证工具身份，不能重定向到源码或散装模块。

计划 CreateNew 保存于原项目控制目录，严格 schema1 字段为：schemaVersion、kind=ORIGINAL_TASK_ARCHIVE_FINALIZE、originals、deletedTasks、completionDecisionRef、oldDistribution、newDistribution、rootToolRevision、rootToolDependencies、outputDirectory。所有 ref 为绝对 `{path,identity}`，identity 是真实 length|SHA256。originals 恰含原 discoverReceipt compact、admitInput、admitResult、finalizeInput、finalizeResult、objects 六引用；原件不复制改写或补造。objects 原数组逐项为 path、operation、oldIdentity、newIdentity、candidatePath、activation：原 WRITE 或 DELETE_AFTER_ARCHIVE_AND_FULL_HISTORY_WRITTEN，原前像/已审后像、WRITE 完整候选路径，删除候选 NOT_APPLICABLE。旧缺失前像 MISSING 对应原包 NEW；删除后像仅 MISSING。activation 只是原说明，不授予权限。

deletedTasks 恰覆盖实际删除，逐项 `{activePath,archivePath,historyRef}`；必须同名 active/archive，完整旧卡 history 身份等于原 package 及 objects 的删除前像。completionDecisionRef 是当下实际原始人类完成决定，调用者负责核对来源/语义/撤回，工具不声称由文件认证用户。oldDistribution/newDistribution 各为现行四字段 distributionId/contentIdentity/manifestIdentity/runtimeRoot；旧绑定须等于实际采用记录，新绑定须等于当前执行工具完整分发及真实候选资格。

新工具的 rootToolRevision/rootToolDependencies 取现有 `Get-AiwRootToolRevision` 与 `Get-AiwProjectAdoptionToolDependency UPGRADE -AdditionalDependencyPath`：增量包含该分发全部非 tests 的版本文件；schema3 仅排除经完整 reader 验证的精确 Qpre 资格附件，根依赖仍沿原合同。完整包校验后，比较旧/新实际运行 ps1/psm1/schema/json 和根 State/Projection/Overlay/CorrectionLifecycle 依赖集合及字节；仅版本 ResultEvidence/WorkflowDelivery 两模块允许本次已审差异。新增或变化的 resolver/composer/helper/schema 拒绝，不能自动适配；新增 ReleaseValidation helper 也不豁免。原 composer 复证所有 sourceBindings，包括原 implementation/content/effective set 和在用采用完成证明；原 ADMIT decision 用原导出函数重算，原 failed FINALIZE 和当前全组后像均绑定。

outputDirectory 为原项目 runtime/<task>/<原 actor-storage>/下尚不存在的单层安全目录，父目录已存在。预检零写；完成只创建该目录内新的实际 command、raw FINALIZE output 和 result。新独立子进程传入完全未改的原 FINALIZE 输入，原 frameworkRoot/source bindings 仍指向旧采用来源；实际执行路径及新模块/依赖、两分发身份在新结果显式报告。结束前再核对原材料、来源、所有成果/删除/history 和完整包。失败或未知不宣称完成，保留实际退出码/原始输出；不写任务、pin/state、既有成果、历史、原失败、Git，不补 active、不 fresh 准入或重做采用。只有真实 PASS 后，原动作才完成，后续新分发采用另按项目当前治理单独授权。该证据为 INSTRUCTION_BOUND，authorityGranted/projectWritePerformed/userAuthorizationProven=false；测试模拟资格不能作为现场分发资格。

## 原过程的跨命名包收口

同版本不同命名 snapshot 的采用，使用已验证的新根工具显式接入原过程边界。此路线覆盖既有 fixed-runtime refresh 的 `CONTROL_WRITE`；基本写集为采用 state 与实际改变的 AGENTS / Bootstrap 管理投影，明确的采用纠正计划可加入其当前记录、完整历史、安装证据及声明的效果对象。旧来源严格支持其 schema2 DISCOVER / schema1 compact、schema3 DISCOVER / schema2 compact 与 TC3 input4/compact3；当前 TC4 使用既有 input5/compact4。原件按各自来源分派，不转换成新的执行意图。普通项目的原 version resolver 命令保持 fail closed，不会透明追认跨包旧收据。

原来源 O、执行接入工具 X 与原准备所选目标 T 分别绑定：原 decision 和旧来源闭包由 O 解释；目标快照、组装、支持、内容、闭包及送达由 T 的实际 owning module 执行，不能仅把目标目录传给环境中的同名旧命令。snapshot.16 的真实 REGISTER 使用 project config6 与采用 state7，升级走6→7 FORMAT，保原 REGISTER journal 和原 state 前像；snapshot.17 的 project7 按其实际起源刷新，不能混淆两种 schema。已完成的 same-pin 事务可由经审核并取得资格的新 X 执行 FINALIZE-only，仍采用 T，保持原输入、授权、准入、事务及全部项目前后像原字节；不改原 rootToolRevision/rootToolDependencies。此完成态只读收口不延伸到未完成恢复或 FORMAT/major：后者仍校验原工具依赖，FORMAT 的 originalFinalize 持久化语义保持。

1. 按既有 upgrader preview 取得写集，普通项目可用原 schema1 或 schema2 过程包，Maintenance 必须使用 schema2；在旧健康 runtime 执行真实 DISCOVER，读取完整规则。保存 schema2 ADMIT boundary input，尚不执行 ADMIT。PREPARE 与最终收口复用同一包格式、身份、动作及范围检查，不到安装完成后才发现格式不适用。
2. 对同一个升级预览调用 `upgrade-project.ps1 -AdoptionProcessMode PREPARE -CurrentProcessInputPath <原ADMIT输入> -ExpectedCurrentProcessInputIdentity <identity>`，其余 project、目标 WorkspaceRoot、actor/task、LocalCandidatePilot 参数与真实 preview 相同，禁止 `-Apply`。保存返回的完整 JSON；它包含实际投影、目标命名包身份与同一动作的目标完整规则。新prepared2的selectedRuleBlocks保完整B，显式selectedObligations是当前O（含空义务行），严格O⊆B，正文行P/R与O一致或在B-only为空；旧prepared1按原冻结行P/R读取，不缺省成空或用今日policy重算。读取B的fullText，完成原/目标O准备义务，并把 `ADOPTION_TARGET_RULES_LOADED|<该JSON的文件identity>` 加入原 ADMIT input 的 preparationReceipts。
3. 普通项目通过 `upgrade-project.ps1 -AdoptionProcessMode ADMIT_ACTION`，提供上述 CurrentProcessInputPath/当前 identity、`-AdoptionPreparationPath/-ExpectedAdoptionPreparationIdentity`、project/version/actor 参数及 `-DeleteProcessInputOnExit`。根入口重验准备投影，按原 receipt 绑定的 O 调用其实际拥有的 Boundary core 一次并消费真实 exitCode/output；旧来源未声明此 core 时保持原脚本分支。成功 JSON 内保留原输入和目标准备证据；保存这个结果。不得以 X/T 同名模块代替 O、注入变量、Force 重载或新子进程绕过来源句柄。正文读取与准备完成仍是 INSTRUCTION_BOUND，机械 PASS 不证明模型 attention。
4. 使用独立 schema3 包执行原 upgrader Apply，同时提供原 `-AdmitResultPath/-ExpectedAdmitResultIdentity`。新根工具在写入前重验该结果内的原 ADMIT、PREPARE、投影、目标分发与 schema3 包，并把 ADMIT 结果身份绑定进采用事务。实际事务 COMPLETE 后，普通项目以 `-AdoptionProcessMode FINALIZE_OUTPUT` 提供原 FINALIZE boundary、同一 ADMIT 结果、原 schema3 `-AuthorizationPackagePath/-ExpectedAuthorizationPackageIdentity`、`-ExpectedAdoptionTransactionIdentity`。旧成功结果未内嵌原 ADMIT 输入时，另提供仍保留的 `-AdmitInputPath/-ExpectedAdmitInputIdentity`；不得重建该输入。FINALIZE 输入保留原/目标 preparationReceipts，提供双方结果义务、每项 OBJECT_POSTIMAGE 与适用 deliveryReceipts；送达由采用版本的绑定消费者和宿主回执机制验证，未确认送达不能结清。

已经完成写入、但旧根工具未在 Apply 强制绑定 PREPARE/原 ADMIT 的历史刷新，仅当原采用 state 的 rootToolRevision 与保留的旧固定包实际根工具修订均属于已核实的旧桥修订、事务没有新式 ADMIT 绑定、原 ADMIT 输入和结果均仍可核对、实际写集仅为采用 state、目标版本 payload 与规则来源未变、state 其他字段保持且政策投影只对齐原 DISCOVER 已绑定的当前政策身份时，允许只读结清原动作。仍须完整核对旧过程包、schema3 包、双方固定分发、完成事务、逐对象前后像、当前来源及适用送达；任何新根工具产生的无 PREPARE 事务、新规则、新受管投影写入或无法证明的准备义务均拒绝。旧工具虽提供 PREPARE 入口，原动作实际没有使用它；此恢复例外不替代以后刷新在真实 ADMIT 前进行 PREPARE。

收口不执行 Apply、恢复或 live 写入。它核对原准入、双方固定包、实际采用事务、精确前后像及当前完整组合；第三方来源漂移、未完成事务、缺失原输入证据、缺准备或无效来源组合均拒绝。正常清理仅删除有界 runtime 内的本次 boundary input。原 compact、成功 ADMIT 与准备材料留至最后消费者完成，不从 DISCOVER 或新的 ADMIT 补造历史。后续任务/项目规则变化应在原采用流程收口之后进行；历史采用成功与无法收口的旧过程分别记录，不重新采用以制造成功。

## 普通 SOURCE 的跨采用原收口

已在固定 O 的 TC3/TC4、2.0.0 下真实准入并写入的单步 SOURCE，可以在一次 FORMAT 或同版本 refresh 已真实完成且原采用 FINALIZE 成功后，由合格固定工具 X 显式完成原 FINALIZE。目标 T 仍是已采用来源。此入口只读消费原件，不重新 DISCOVER/ADMIT、不回写旧失败或收据，也不产生后继写权；当前普通 version resolver 仍按原来源拒绝不匹配的收据。

调用 X 的 `scripts/upgrade-project.ps1`，提供 ProjectId、ToVersion=2.0.0、RepositoryPath、ActorRouteActor、AdoptionProcessMode=FINALIZE_OUTPUT；CurrentProcessInputPath/ExpectedCurrentProcessInputIdentity 指向原 SOURCE FINALIZE 输入，AdmitInputPath/ExpectedAdmitInputIdentity 和 AdmitResultPath/ExpectedAdmitResultIdentity 指向原 SOURCE 的真实准入。AuthorizationPackagePath/ExpectedAuthorizationPackageIdentity 指向原采用 schema3 包，AdoptionFinalizeResultPath/ExpectedAdoptionFinalizeResultIdentity 指向其真实成功结果，ExpectedAdoptionTransactionIdentity 绑定唯一当前 COMPLETE journal。OriginalSourceForbiddenPath/OriginalSourceProtectedPath 补充当下仍有效的保护。Maintenance 可从 X 的根过程前门提交相同原件，用 AdoptionAuthorizationPackagePath/ExpectedAdoptionAuthorizationIdentity 绑定采用包，并以 OriginalSourceRepositoryPath 明确 CONTROL 根。入口先按明确根核对载体保护，再读输入及原收据；该根必须匹配原收据，不提供替代权威。原件均须保留于当前项目内，输入不自动清理。

O 自己解释原包、规则组合、准入决定、后像及 typed/delivery 证据；T 自己核实完成采用，FORMAT 还须已有 originalFinalize；X 验证自身完整固定包后连接两者。原 SOURCE 与采用写集不得重叠，原 Controller、任务、人类区外约定和来源许可必须仍保持，当前保护并集继续适用。原来源合同、完整义务或实际候选无法保持时具体拒绝。仅支持 SAME_ROOT/维护拓扑及一个原单步 SOURCE；continuation、联合发布、repair binding、多次采用或改过来源许可的动作不由此入口承接。真实测试、独审和资格形成的新分发才可用于现场，合成测试资格不授予采用能力。

同一固定pin且没有采用事务时，若AGENTS在原SOURCE准入/写入之后、原FINALIZE之前改变，普通原resolver仍拒绝来源漂移；不能把未完动作当历史成功，或虚构一次采用。上述X完成入口可显式选择`CompleteOriginalSourceAfterAgentsChange`，与采用包/采用FINALIZE/采用事务参数互斥，复用同一原SOURCE FINALIZE、原ADMIT输入/成功结果、原授权及原消费者链，不重新准入或执行原写入。

本分支另带`OriginalAgentsPreimagePath/ExpectedOriginalAgentsPreimageIdentity`，必须是原AGENTS完整原始字节且身份等于原compact的projectAgentsIdentity；`ExpectedCurrentAgentsIdentity`绑定调用者实际完整读取的当前AGENTS；`CurrentCompletionDecisionPath/ExpectedCurrentCompletionDecisionIdentity`指向当前明确有限完成决定的普通原件，`CurrentCompletionPermission`须根据两份完整AGENTS、原决定及后续限制实质判断为`CURRENT_AND_COVERED`。`WITHDRAWN`或`UNKNOWN`拒绝；缺前像报`ORIGINAL_SOURCE_AGENTS_PREIMAGE_REQUIRED`，缺原准入报`ORIGINAL_SOURCE_ADMISSION_REQUIRED`，缺当前决定或当前AGENTS绑定分别具体拒绝。不是让用户重新批准既有有效授权：原明确约定足够时沿其作当前有限决定；只有真实撤回、冲突或保留事项才由实际有权者决定。文件身份和参数不能自动理解授权语义或证明模型已读，仍为INSTRUCTION_BOUND，不创建成功证书、证明台账或新服务。

本分支只允许projectAgentsIdentity变化：固定分发/runtime、task/Controller、config、corrections、policy/custom、完整要求与来源许可、当前精确候选及原结果义务都须保持。先应用当前与原保护并集，再用原全文临时视图交O重算原规则和义务；当前AGENTS、当前决定及全部原件在末尾再次逐字节复核。原失败、包、compact、准入、FINALIZE输入均不改，产品和控制载体零写，无continuation。缺失现场原件只能报告具体不足及原责任，不能从反馈摘要、后来的成功或新准入补造。Maintenance前门用同名有限输入及OriginalSourceRepositoryPath进入同一消费者；实际现场仍须有真实验证、独审及资格形成的固定X，不从开发HEAD或夹具取得现场采用权。

同一固定pin、未发生采用、但原SOURCE之后已有一次完整双成员专业规则发布时，同一X完成入口可改为提供 RulePublicationInputPath/ExpectedRulePublicationInputIdentity，引用原公开完成写者保存的任一成员 publication-complete-input.json。工具沿该输入原ADMISSIONS引用取得双D/A/包、candidate/plan、冻结前后像和双F原件，不扫描目录、要求全局journal、重开已归档发布任务或让调用者复制整棵引用树。发布生产者的历史成功只读核验；真正Apply/恢复仍核当前发布任务、Controller与可达状态。

本有限分支要求同一原pin、单次已完成发布、config前后像相同，原SOURCE policy等于该发布前像、当前policy等于后像，且原SOURCE写集不与发布对象重叠。原SOURCE的A、冻结O、实际后像、typed evidence、delivery、当前actor/task/Controller/保护继续由O的原算法消费；prepared旧格式与旧21不得交今日组合身份重新解释。原义务中P/R为空的规则仍核完整正文、selector及有序依赖，操作选择退场不删除原冻结义务。

调用者复用 CurrentCompletionDecisionPath/ExpectedCurrentCompletionDecisionIdentity 和 CurrentCompletionPermission，并按实际完整现行规则与成果判断 CurrentRuleEffect=UNCHANGED|CONFORMS|WORK_REQUIRED|UNKNOWN。UNCHANGED要求完整适用事实不变；有变化但原成果已符合完整现行要求时可明确CONFORMS。新增机械门、WORK_REQUIRED、UNKNOWN或许可撤回拒绝成功，既有决定足够时不新增报告或用户审批。该判断为INSTRUCTION_BOUND，不由空P/R或旧PASS推定；普通无漂移完成沿原入口，不增加本分支材料。

此分支与AGENTS及跨采用参数互斥，不承接混合AGENTS变化、配置许可变更或多次发布链。原发布boundary携带独立typed evidenceRefs或裸typed gate的形态明确拒绝；原plan固定的assurance原件仍读取。历史USER/NATIVE_RESPONSE的PREPARE只保READY_TO_SEND上限，TASK_MESSAGE须有真实宿主成功原件；正在完成的原SOURCE仍由原delivery消费者核验。产品、任务、采用、原失败与收据均零写；只有已验证、独审并取得分发资格的固定X才可现场使用。

上述AGENTS分支也可结清真实未完成的原动作：新的停止FINALIZE输入仍引用原compact及成功ADMIT，显式带`continuationDisposition=STOP`，typed SELF须为`FAIL`或`INCOMPLETE`，完整M按实际字节或`MISSING`绑定。除原单步SOURCE外，只额外支持原`SOURCE_WRITE → REVIEW_ROUTE`批次的SOURCE停止，可保留原repairReviewPlan；不执行、派生或恢复后续交审。原准入准备、原结果义务、当前许可与保护、原/当前AGENTS及决定的要求保持。未提供STOP不能借本例外完成混合包；PASS自查不能冒充失败停止。

停止收口的`actionOutcome`保留真实`FAIL`／`INCOMPLETE`，全部原件与当前候选核验且必要送达成立后才返回`successorState=STOPPED`，无continuationReceipt；结构PASS仅证明该停止终态可核对，不代表SOURCE成果成功，也不能作为HISTORICAL_SUCCESS。TASK_MESSAGE的PREPARE只返回BLOCKED及未送达事实，实际发送后用另存的OBSERVE输入和完整原宿主返回完成同一停止收口，不回改原失败输入。已生成原件、次数、费用与UNKNOWN继续由原任务保存；后续补齐只能按当前真实权限前向完成，不能重放生成或以新SOURCE追认旧成功。

新建采用 journal 的缺失前像会明确保存；ROLLBACK 先 create-only 保存并读回终态历史，再精确移除 active journal，以便未改旧入口恢复。历史 journal 没有该显式缺失前像事实时，仍保留原 ROLLED_BACK 行为，不推定删除资格。

## 纠正整组生命周期

在现有 upgrade-project 入口使用 -ProjectCorrectionLifecyclePath 与 -ExpectedProjectCorrectionLifecycleIdentity；默认仅生成预览。-Apply 还须给 CurrentProcessInputPath/ExpectedCurrentProcessInputIdentity，引用当前 CONTROL_WRITE 的 ADMIT 输入；入口重新准入后，按实际效果选择普通有序写入或原投影事务。预览不是授权。新能力须由实际采用的 runtime 支持，旧版本未知生命周期字段时拒绝转换，不能删除字段后偷偷复活。

计划 schemaVersion=1，operation 为 INSTALL/REGISTER_HISTORY/REVISE/PAUSE/RESUME/UNINSTALL；绑定 correctionId、expectedCorrectionsIdentity、decisionLocator、forbiddenPaths、record、installation、installationRelativePath、transactionRelativePath 和 impact。INSTALL 提供完整 schema2 record；REGISTER_HISTORY 保持旧 record 不改（record=NOT_APPLICABLE）。REVISE 提供不含 lifecycle/history 的完整新 record；只改正文/selector 时 installation/installationRelativePath 为 NOT_APPLICABLE，保持原效果及状态；替换效果时提供新 installation，活动状态在同一投影逆向旧效果并正向新效果，暂停状态保存新归属但不应用效果。无安装归属的旧记录可独立暂停/卸载：record=NOT_APPLICABLE；不处置附带效果时installation/installationRelativePath=NOT_APPLICABLE，当前生命周期保存这一未知安装事实。处置有证据的效果时提供实际installation；明确当前移除则在同一installation结构增加effectDirection=CURRENT_REMOVAL，changes的before是本次实际当前内容、after是明确移除结果，不补造旧安装前像。原installation、history及transaction各自保留真实用途，暂停后恢复反向本次移除。已有归属的PAUSE/RESUME/UNINSTALL仍读取原安装证据；未知效果不声称已逆转。

installation 保存 schemaVersion=1、correctionId、decisionLocator、dependsOn、changes。每项改动可为 FILE（path、beforeExists/afterExists、beforeBase64/afterBase64）或 TEXT（path、before/after、prefix/suffix）。FILE 只适合专属对象或整文件精确前像；共享文档/JSON属性/AGENTS 用带唯一上下文的 TEXT 区块，不整文件回滚。不得把未经证实的旧内容填进 before。先按当前全部对象计算投影，任何冲突都不写；报告具体路径并允许调用者先解决不相关对象的其他任务。

安装证据位于 .ai-workspace/upgrade-recovery/corrections/<ID>/<batch>/installation.json，每次变更保存完整priorRecord/决定至同批history.json，当前record引用其locator/identity。无实际安装效果时先保存历史及归属证据，再原子替换carrier并读回，不取得项目WRITE、不建state.json；中断留下未引用历史可以保留，无效或第三方现场拒绝覆盖。有实际效果时保留同ID批次state.json、完整前后像及原投影恢复，写后验证完整三源组合，失败按原已拥有片段恢复，第三方改动仍拒绝；已有真实事务按原固定工具和授权恢复。history/installation与实际变化carrier/effects按各自真实写集授权。impact继续保存stoppedObligations、independentObligations、inFlightEffects及recovery/semanticAssessment；工具不证明隐含语义。

AGENTS的FRAMEWORK管理区只承载目标导航；当前人类工作约定与必要项目限制位于用户拥有区。升级将旧管理区中已确认授权原文和需保留的自定文字按原投影完整承接，保留原区外字节、后续收窄及撤回；未知归属不猜删。新注册沿明确采用决定生成已批准约定。日常以当前人类正文为准，安装managedIdentity不永久冻结授权；实际事务仍绑定完整前后像并拒绝并发覆盖。

规则包旧budget字段仅为兼容数据，不是用户配额。新注册、重复注册、same-pin、跨包采用和后像核验不因所选正文超过32/64/96KiB而拒绝，也不自动调额；旧字段保留不等于保留硬门。原预算repair参数对当前正常runtime为NO_CHANGE。旧runtime真实失败只沿既有限域授权过渡，不伪造旧收据或热改发行包。完整选择、去重、来源／身份／授权和回滚义务保持，真实大小供当前工作分析。

## 采用时处置旧纠正

不再使用中央项目 ID 映射的新运行包不会自动忽略旧记录。旧包曾精确抑制的记录必须逐项说明完整覆盖后退出，或保留项目增量。固定包同 pin 刷新和受支持的跨版本/格式采用可提供 `-AdoptionCorrectionsPlanPath` 与 `-ExpectedAdoptionCorrectionsPlanIdentity`。旧 schemaVersion=1 保持原记录/历史合同：顶层 expectedCorrectionsIdentity、changes，每项 correctionId、decisionLocator、record、historyRelativePath；record=NOT_APPLICABLE 从集合退役，完整新 record 不含 lifecycle/history，原安装归属保持。schema1 仍拒绝直接退役 ACTIVE/PAUSED 记录。

schemaVersion=2 使用相同顶层字段，每项严格为 correctionId、operation（UNINSTALL 或 REVISE）、decisionLocator、record、installation、installationRelativePath、historyRelativePath、effectPaths、impact。record/installation/impact 沿上面的生命周期语义；未知安装归属用 NOT_APPLICABLE，明确当前移除用实际 CURRENT_REMOVAL 证据。effectPaths 必须精确等于该项原/新安装效果路径的并集，声明自身不授予权限。范围导航只校验有限路径，不读取效果；完整投影先核原 exact scope 和保护集合，再读取归属及效果。保留有效依赖拒绝指向已退出纠正，退出按 dependent-before-dependency 计算，互不重叠的 TEXT 共用一个工作视图，无法证明的共享归属或整文件覆盖拒绝。

组计划复用生命周期纯算法，将效果、完整 priorRecord/history、新 installation 与基础格式及目标模板合成为唯一后像；不会先卸载、逐项 Apply，或采用后补效果。基础必需配置、Bootstrap、AGENTS 和控制载体不能删除；计划与 MajorAdoptionOverrides.corrections 互斥。安装/历史使用同 ID 的有限批次路径且不得覆盖旧材料。文件创建、删除和二进制 bytes 进入同一原采用事务；内部投影缺失为 MISSING，公开新对象前像为 NEW，公开删除后像为 ABSENT，不相互宽松替代。旧流程只从 previousDistribution.runtimeRoot 取得，目标包无需带旧版本目录。目标完整有效集合预检拒绝回填已删除来源，包括 live/cache；真实旧准入、完整目标规则、封闭 schema3、COMPLETE、恢复及原 FINALIZE 消费同一组计划和后像，完成原收口后才进行新版本恢复。

historyRelativePath 使用 `.ai-workspace/upgrade-recovery/corrections/<ID>/<batch>/history.json`，不得覆盖已有材料。原完整 record 与本次决定、退役/修订操作随当前记录和采用 state 进入同一精确投影；目标预检、Apply、Postcheck、中断恢复和回退覆盖整组。旧包的覆盖判断只由旧包本身计算，目标运行不读取中央表；缺少任何旧抑制记录的显式处置则预览拒绝。局部覆盖是否完整由项目 Owner/独立 Review 判断，工具不证明语义等价。

## 材料与收尾

统一存放、保留和清理条件见所采用版本 TOOL_CONTRACT；本入口按需导航，不要求日常恢复加载整个历史。升级恢复、在用包及原过程收口证据留至最后消费者释放；正式结果不能长期只依赖可清理 runtime 内唯一材料。原任务自然收尾处理证据持久归属、有效引用和已知临时集合，不按目录大小或任务关闭推定可删。

## 采用与过程材料

upgrade-recovery 中仍有效的采用 state/distributionBinding 用于定位当前运行来源；未完成事务的前像、授权和恢复材料保留到原事务收口。已完成事务、纠正 history/installation 和原验证证据保留为历史，不再充当当前任务权限。runtime 中也可能保存仍有消费者的收据或证据；只清理已完成用途且无有效引用的临时输入，不按目录名称批量删除。

## 2.0 知识配置

2.0普通项目与Maintenance目标配置都使用ADOPTION_PROFILE声明的当前project格式（本目标为schema7）。能力结构由目标版本同一KnowledgeSources校验；来源由项目自行管理，不在Framework记录消费者采用。新注册不自动启用知识引用。项目明确选择时，由 Controller 沿 目标 2.0 版本 TOOL_CONTRACT.md「项目来源配置的受限普通采用」 准备精确 config/policy 后像及来源许可，支持缺失声明或合法 disabled 到 enabled；保留旧配置真实准入、目标规则/能力、旧新义务和原动作收口。中断按原事务恢复，不以直接改配置后的新 DISCOVER/QUERY 追认；关闭、删除或任意能力切换不在本分支。启用后，未选中来源只验证声明结构，不要求目录在线；选择时才验证索引、内容和当前保护范围。公开 QUERY/FULLTEXT 仅验证所选条目的参考读取，不赋予规范效力。包内可选方法说明位于目标版本knowledge/README.md。

已有project4与单索引不能仅改schema数字后继续使用。snapshot.12到2.0的唯一根桥将目标project格式、index3、当前任务及有效规则纳入精确事务，具体范围、项目映射和恢复顺序取目标2.0分发内的MIGRATION_MATRIX.md。实现候选尚须整版验证和独立审收，不能把结构校验或隔离fixture当作live采用；旧固定运行包保持可恢复。

跨版本操作沿用上面的PREPARE、真实旧ADMIT、schema3 Apply和原FINALIZE，普通与Maintenance分别走原健康版本入口。第一次查询只提供项目/目标/当前任务参数，返回UPGRADE_SCOPE_ONLY供构造旧DISCOVER，不生成后像或准入。需要项目自定映射时，用MajorAdoptionOverridesPath/ExpectedMajorAdoptionOverridesIdentity绑定当前配置和任务，明确taskText/policy/corrections；目标预检不能替项目判断语义覆盖。两个版本state链接同一事务，链接仍有效时该runtime材料不得清理；目标state的true标记须与真实COMPLETE共同核验。其余项目、旧历史证据及任务不批量重写。

## 已完成外部调用的历史结果补充

新合格固定运行包的`upgrade-project.ps1 -CompleteOriginalExternalResult`只读取旧固定来源和已存在的调用证据，返回补充历史结果。它不采用或热改旧包，不执行provider、不恢复旧任务writer、不创建新的外部准入。原任务可已关闭/释放，当前policy可已演进；原selectedObligations仍按原收据核对，不以今日policy重算过去。此窄入口支持2.0 compact4/input5、repo-local schema1纯EXTERNAL包、externalBinding2的单一operation批次，以及因DISCOVER_SOURCE_DRIFT拒绝的原FINALIZE。其他历史形状不静默泛化。

调用仅带`ProjectId`、`ToVersion=2.0.0`、`RepositoryPath`、真实`ActorRouteActor`、`CompleteOriginalExternalResult`、`OriginalExternalCompletionInputPath`、`ExpectedOriginalExternalCompletionIdentity`，及必要`OriginalExternalForbiddenPath[]`；与Apply、采用事务、SOURCE完成及其他操作参数互斥。调用者按项目当前许可作只读历史完成决定；不要求逐次再次批准仍有效的人类约定。新固定X读取原O的原始准入，项目不必为了本次记录先更改当前pin。

输入为一个严格对象：`schemaVersion=1`、`kind=ORIGINAL_EXTERNAL_RESULT_COMPLETION`、`projectId`；`originalAdmission`与`originalFinalize`各为`{inputRef,resultRef}`；另有`originalProjectConfigRef`、`toolObservationRef`、`completionDecisionRef`、`completionPermission=CURRENT_AND_COVERED`及`invocationAssessment`。所有ref为`{path,identity}`，使用真实现存原件，不扫描发现或重写旧文件。引用限同一项目根并服从当前与原保护；原固定运行包另按原来源身份核验。旧schema3 FINALIZE可以没有evidenceRefs；本窄分支不承接typed审核/接受、continuation或跨任务投递。

`invocationAssessment={permissionAtInvocation,changeTiming,operationIds,rationale}`：permissionAtInvocation为CURRENT_AND_COVERED/WITHDRAWN/UNKNOWN；changeTiming为NO_RELEVANT_CHANGE/BEFORE_EXECUTION/AFTER_EXECUTION/UNKNOWN；operationIds必须与原有序单operation对应，rationale说明实际原许可、原返回和后续变化。BEFORE_EXECUTION或AFTER_EXECUTION还必须携`changeEvidenceRef`指向已存在的时点证据。该语义判断是INSTRUCTION_BOUND，不能从hash、当前时间或已成功调用反推当时必然获准。相关撤回发生在调用前时不得发新调用；完成后的撤回不抹去原返回，后续请求另取当前许可。

原工具观察需已有outcome、非负整数calls/retries；SUCCESS/FAILURE/UNKNOWN分别保留，其他原值保rawToolOutcome并按UNKNOWN处理，不猜供应商协议。成功至少发生一次调用，实际次数/重试须处于原单operation批次的界限。原配置前像身份须等于原compact；仅sourceBindings中既有绑定的allowedPaths新增可机械分类为SOURCE_ALLOWED_PATHS_ADDED_ONLY，其他变化保持RELATED_OR_UNKNOWN并由当前完成判断说明影响。当前policy身份同时记录，不要求等于过去；原任务不重开。原工具输入的历史后像只与原包/原F核对，不读取当前私有Key或要求今日工具源码仍是旧版本。

返回的核对status与工具actionOutcome分开：事实完整且当时许可有据时可PASS，失败工具仍为FAILURE；未知时点/消费/当时许可或超原次数保持INCOMPLETE及真实原返回。结果引用原FAIL、原ADMIT、原工具观察和当前完成决定，始终`successorState=NONE`、`authorityGranted=false`、`futureExecution=NOT_GRANTED`、`taskExecutionReopened=false`。它不是把原FINALIZE改成PASS，也不是可移植的执行或成功验收凭证；既有普通历史成功reader继续要求其原完整证据。缺原成功准入、错关系、原件漂移、坏输入或保护拒绝时FAIL，原文件及已经发生的调用事实继续保留。

先前已成功但因无关来源许可新增而收口失败的snapshot20调用，由项目当前合法责任者用此显式入口引用原compact/包/ADMIT、原失败、配置真实前像和原工具观察完成补充记录；不重发请求、不恢复已释放权限。没有足够原件时保留具体缺项和真实结果，不重建“当时PASS”。
