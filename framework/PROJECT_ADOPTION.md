# 项目接入与升级

本文件随包交付，供项目注册、升级、恢复和纠正操作按需查阅。开发仓可维护根级工具；已分发或已绑定运行包保持原字节，修复通过新的分发及项目显式采用交付。内部版本 pin 与命名分发身份分别报告。

## 从用户入口开始

用户包从包内 README/AGENTS 导航，开发仓从 [README](../README.md) 导航。接入和升级由用户需求或已授权任务启动；已有项目按已接入 Router 导航当前治理事实。首次注册尚无 Bootstrap 时，先检查所选版本的 VERSION、RELEASE_MANIFEST、ADOPTION_PROFILE 和 TOOLCHAIN，再运行 [register-project.ps1](../scripts/register-project.ps1) 预览。注册必须显式给出内部 `FrameworkVersion`、项目 `RepositoryPath`、项目 ID 与 `ControllerId`，在已有项目写授权范围内应用并完成下面的宿主接入收尾。用户包目录无需 Git，目标项目必须是 Git 仓库。

升级使用 [upgrade-project.ps1](../scripts/upgrade-project.ps1) 预览及目标版本声明的兼容范围；目标未声明支持当前 Project Format/capability 时停止，不按发行名称推断兼容。普通项目使用版本通用 starter。恢复和动作门禁只由当前项目 Bootstrap 与其 pin 对应的 runtime 合同维护，本入口不复制。

项目资料和标准保存在用户选择的位置，优先直接复用已有文档；共享标准可在本机独立目录由多个项目分别引用。提取、精炼或改造均为可选，不是采用前置条件，不将标准正文抄入 Framework。维护 AI 可按所选版本 TOOL_CONTRACT 的项目标准引用合同，绑定完整文件或唯一标记章节及直接依赖；用户无需手写 JSON。

## 统一数据流

注册、跨 pin 升级、同 pin 受管修复和明确批准的永久规则迁移共用以下顺序：

1. 读取项目真实配置、控制载体、选定发行和根工具依赖。
2. 生成内存目标投影并报告逐对象差异；无差异时不创建事务、不改卡。
3. 在项目写入前完成目标结构、目标 resolver 与独立授权预检。
4. 只写有差异的受管对象；按版本合同应用 pin 与任务卡顺序。1.16 本地候选的 schema4/5 事务在全部 live postimages（task 最后）匹配后，还须登记既有 state 的 `transactionComplete` 标记才结束原事务，不能把 task 写完误报为事务完成。唯一运行合同见 [PROJECT_CONTROL](versions/1.16.0/PROJECT_CONTROL.md)。
5. 对目标有效三源规则和项目格式做 Postcheck；失败时先恢复旧 pin，再恢复其余旧对象。
6. 中断后只按已绑定恢复材料继续回退或完成，不覆盖第三方新字节。
7. 成功结果同时报告 Framework pin、实际 Project Format 和 Root Tool Revision。

初始化只创建必要控制入口、薄项目/Review 指针与 current task 目录；`RELATIONSHIPS.md` 保留为按需模板，不是默认必需对象。注册脚本不判断产品文档权威，也不搬迁、拆分或改写用户资料。初始化 AI 根据用户指定及项目已有入口确认用途后建立引用；已有项目是否精炼历史资料、调整文档结构或迁移永久规则，由项目另行选择，不是采用新版的前置条件。

逻辑提交不是 Git commit，也不承诺多文件瞬时原子。安全保证是：任何未能完成 Postcheck 的尝试都不得开放新的有效行为；能够安全恢复时，旧 pin、旧受管对象和旧有效三源行为全部恢复。

## Project Format 与 capability

Project Format 来自实际 project/controller/corrections/process-policy 等载体 schema，不由 Framework 版本白名单推断。capability 只描述已观察到且格式未必保证的结构能力，不代表功能开关、权限或授权。

相同 Project Format 的普通版本变化不应批量改任务卡。只有当前任务仍缺少目标格式要求的 actor/role/phase 时，才在同一事务中迁移该任务。

## 幂等

- 初次注册：目标不存在时创建；完整相同则返回 ALREADY_REGISTERED。
- 跨 pin：仅投影真实差异。
- 同 pin：无差异返回 NO_CHANGE；受管对象漂移只能在精确授权下修复。
- 重试：先识别现有恢复状态；不得叠加第二事务。
- 升级失败：保留有界恢复材料；恢复完成前禁止普通消费。

已完成采用的 recovery state 保存原安装任务、Owner、actor、授权与材料作为历史证据；后续同 pin 刷新由当前真实任务和新授权独立约束，不改写历史绑定。未完成事务仍只能由原绑定继续恢复。

## 永久规则迁移

只有用户明确选择的项目过程规则才从 legacy PROJECT-CUSTOM 成对迁入 process-policy。迁移同时移除旧运行正文，但保留项目事实、定位与非过程扩展。准备态不会成为正常规则来源；成功前后都只能有一份有效规则，失败则恢复原组合。

process-policy 可以显式引用项目内文件或当前受支持宿主上的本机绝对文件。target-before-pin 预检只把项目内来源快照复制到临时 projection；项目外来源在原位置只读复核 identity，既不写入 projection，也不进入采用 transaction。预检、失败恢复与采用都不得修改标准来源文件。

## Root Tool Revision

根工具 revision 由真实入口、导入的公共模块及会影响投影的模板/合同文件按 ordinal 路径和整文件 identity 计算。它与 Framework pin、Project Format 一起进入采用结果和恢复证据，但不新增第二个项目 pin 或永久台账。


## 宿主接入收尾

接入、升级或根级 Skill 变更交付时，由该次 Owner 或已指定的宿主接入执行者核对实际安装的 Router 与本次已接受、兼容所用项目 pin 的仓库 canonical Skill。当前宿主已使用 Router 时，相同则不写；有差异就在已有宿主写授权内同步，并回读字节身份。仓库 Skill 已更新、项目采用成功或 Root Tool Revision 匹配，都不能代替实际安装副本的核对。

同一宿主供多个项目使用时只收尾一次，不逐项目重复安装。Router 安装、宿主可发现及与采用版本兼容均属于接入收尾。缺失、不可发现或不兼容时，在宿主写授权内安装或修复兼容副本，按宿主支持的方式使其可发现后继续；不转为无 Skill 的正常 Bootstrap 路线。注册和升级脚本本身不安装全局 Skill，也不从项目写授权推导宿主写权限。

同步后按宿主支持的发现与加载方式使用，并在既有交付结果中简记安装位置、来源身份及兼容可发现／已同步／待处理状态；磁盘副本一致不等于运行中会话已重载正文。只有宿主接入未完成时保留该项，不重开已完成的项目采用事务，不新增同步服务或台账。

## 试点与发布

STABLE 封存与已审 Snapshot 分发不同。可变开发候选本身不能作为已发布运行包；只有已冻结、通过适用验证和独立审核的精确 Snapshot 才可按分发资格使用。项目通过真实预览和授权显式采用，Snapshot 不自动等同 STABLE 或项目接受。

### 固定分发运行来源

运行包位置沿用使用者指定或已授权选择的目录；接入不默认迁移、复制发行包，也不规定按项目独占或多项目共享。位置尚未确定时，在执行部署前补齐；已有有效指定或选择授权不重复确认。发布 ZIP 本身不包含消费者解压、部署或接入动作。

命名分发包解压到独立目录，保留 PACKAGE_MANIFEST.json 和原文件字节。注册或显式升级将 distributionId、完整包 contentIdentity、manifestIdentity 与 runtimeRoot 写入既有 adoption state；版本 pin 仍由 project.json.frameworkVersion 决定。日常恢复从该已绑定目录加载。目录被替换、包内文件漂移或升级事务未完成时拒绝运行，不转回开发仓库 HEAD。

同版本 snapshot 切换也须经过 root upgrade-project.ps1 的真实 preview、精确 schema3 preimage/postimage 授权与 Apply。旧运行目录保留到切换及恢复验证完成。若中断，使用仍健康的旧包 root upgrader、原授权与当前 transaction identity，通过 RecoverRuntimeAdoption 选择 COMPLETE 或 ROLLBACK；前者先验证目标包，后者从原事务保存的字节回滚，不执行损坏目标。既有事务关闭后不能用同一恢复入口反向切换。


BOOTSTRAP project-custom 迁移至 process-policy 是同一精确 CONTROL_WRITE 的来源迁移；managed 区域保持不变。若动作已实际准入后写到一半，ProjectRuleRecoveryPlanPath 指向绑定原 DISCOVER、原 ADMIT 输入/结果和两个载体原/目标字节的恢复材料。root upgrader 先复证原动作与所有 live 字节，再在恢复当下创建事务；第三方状态、缺失原准入、扩大范围均拒绝，最终仍由原 FINALIZE 收口。材料格式由 root helper 校验，不改变 compact receipt schema。
## 原过程的跨命名包收口

同版本不同命名 snapshot 的采用，使用已验证的新根工具显式接入原过程边界。此路线仅覆盖既有 fixed-runtime refresh 的 `CONTROL_WRITE`，精确写集为采用 state、实际改变的 AGENTS / Bootstrap 管理投影及显式批准的纠正当前记录/完整历史；其他项目规则迁移另行完成。支持 schema2 DISCOVER / schema1 compact 与 schema3 DISCOVER / schema2 compact。普通项目的原 version resolver 命令保持 fail closed，不会透明追认跨包旧收据。

1. 按既有 upgrader preview 取得写集，普通项目可用原 schema1 或 schema2 过程包，Maintenance 必须使用 schema2；在旧健康 runtime 执行真实 DISCOVER，读取完整规则。保存 schema2 ADMIT boundary input，尚不执行 ADMIT。PREPARE 与最终收口复用同一包格式、身份、动作及范围检查，不到安装完成后才发现格式不适用。
2. 对同一个升级预览调用 `upgrade-project.ps1 -AdoptionProcessMode PREPARE -CurrentProcessInputPath <原ADMIT输入> -ExpectedCurrentProcessInputIdentity <identity>`，其余 project、目标 WorkspaceRoot、actor/task、LocalCandidatePilot 参数与真实 preview 相同，禁止 `-Apply`。保存返回的完整 JSON；它包含实际投影、目标命名包身份与同一动作的目标完整规则。读取其中 selectedRuleBlocks 的 fullText，完成原/目标准备义务，并把 `ADOPTION_TARGET_RULES_LOADED|<该JSON的文件identity>` 加入原 ADMIT input 的 preparationReceipts。
3. 普通项目通过 `upgrade-project.ps1 -AdoptionProcessMode ADMIT_ACTION`，提供上述 CurrentProcessInputPath/当前 identity、`-AdoptionPreparationPath/-ExpectedAdoptionPreparationIdentity`、project/version/actor 参数及 `-DeleteProcessInputOnExit`。根入口重验准备投影，原版本入口仅执行一次真实 ADMIT，成功 JSON 内保留原输入和目标准备证据；保存这个结果。正文读取与准备完成仍是 INSTRUCTION_BOUND，机械 PASS 不证明模型 attention。
4. 使用独立 schema3 包执行原 upgrader Apply。实际事务 COMPLETE 后，普通项目以 `-AdoptionProcessMode FINALIZE_OUTPUT` 提供原 FINALIZE boundary、`-AdmitResultPath/-ExpectedAdmitResultIdentity`、原 schema3 `-AuthorizationPackagePath/-ExpectedAuthorizationPackageIdentity`、`-ExpectedAdoptionTransactionIdentity`。FINALIZE 输入保留原/目标 preparationReceipts，提供双方结果义务、每项 OBJECT_POSTIMAGE 与适用 deliveryReceipts。

收口不执行 Apply、恢复或 live 写入。它核对原准入、双方固定包、实际采用事务、精确前后像及当前完整组合；第三方来源漂移、未完成事务、缺失原输入证据、缺准备或无效来源组合均拒绝。正常清理仅删除有界 runtime 内的本次 boundary input。原 compact、成功 ADMIT 与准备材料留至最后消费者完成，不从 DISCOVER 或新的 ADMIT 补造历史。后续任务/项目规则变化应在原采用流程收口之后进行；历史采用成功与无法收口的旧过程分别记录，不重新采用以制造成功。

## 纠正整组生命周期

在现有 upgrade-project 入口使用 -ProjectCorrectionLifecyclePath 与 -ExpectedProjectCorrectionLifecycleIdentity；默认仅生成预览。-Apply 还须给 CurrentProcessInputPath/ExpectedCurrentProcessInputIdentity，引用当前 CONTROL_WRITE 的 ADMIT 输入；入口重新准入后才调用原投影事务。预览不是授权。新能力须由实际采用的 runtime 支持，旧版本未知生命周期字段时拒绝转换，不能删除字段后偷偷复活。

计划 schemaVersion=1，operation 为 INSTALL/REGISTER_HISTORY/REVISE/PAUSE/RESUME/UNINSTALL；绑定 correctionId、expectedCorrectionsIdentity、decisionLocator、forbiddenPaths、record、installation、installationRelativePath、transactionRelativePath 和 impact。INSTALL 提供完整 schema2 record；REGISTER_HISTORY 保持旧 record 不改（record=NOT_APPLICABLE）。REVISE 提供不含 lifecycle/history 的完整新 record；只改正文/selector 时 installation/installationRelativePath 为 NOT_APPLICABLE，保持原效果及状态；替换效果时提供新 installation，活动状态在同一投影逆向旧效果并正向新效果，暂停状态保存新归属但不应用效果。无安装归属的旧记录可独立暂停/卸载：record=NOT_APPLICABLE；不处置附带效果时installation/installationRelativePath=NOT_APPLICABLE，当前生命周期保存这一未知安装事实。处置有证据的效果时提供实际installation；明确当前移除则在同一installation结构增加effectDirection=CURRENT_REMOVAL，changes的before是本次实际当前内容、after是明确移除结果，不补造旧安装前像。原installation、history及transaction各自保留真实用途，暂停后恢复反向本次移除。已有归属的PAUSE/RESUME/UNINSTALL仍读取原安装证据；未知效果不声称已逆转。

installation 保存 schemaVersion=1、correctionId、decisionLocator、dependsOn、changes。每项改动可为 FILE（path、beforeExists/afterExists、beforeBase64/afterBase64）或 TEXT（path、before/after、prefix/suffix）。FILE 只适合专属对象或整文件精确前像；共享文档/JSON属性/AGENTS 用带唯一上下文的 TEXT 区块，不整文件回滚。不得把未经证实的旧内容填进 before。先按当前全部对象计算投影，任何冲突都不写；报告具体路径并允许调用者先解决不相关对象的其他任务。

安装证据位于 .ai-workspace/upgrade-recovery/corrections/<ID>/<batch>/installation.json，事务必须是同 ID 下尚不存在的 <batch>/state.json，预览即核验此静态路径及 reparse 边界；已有事务走原恢复。每次变更同时保存完整 priorRecord/决定到同批 history.json，当前 record 只引用其 locator/identity，完整历史与安装效果归属各自独立；均进入当前 exact 写集。事务记录完整前后像，写后验证完整三源组合，记录实际大小；无效组合整组回滚。进程中断保留原事务，责任主体按当前授权绑定该事务及全组对象后调用既有 Resume-AiwProjectProjectionRollback；它是事务原语，不自行授予恢复权限，第三方改动仍拒绝。恢复后重新准入原操作，不另造恢复台账。impact 在原操作内保存 stoppedObligations、independentObligations、inFlightEffects 数组及 recovery/semanticAssessment 说明；工具不证明隐含语义影响。

AGENTS 的 FRAMEWORK 区包含项目授权正文，普通与Maintenance模板解释一致。用户可正常编辑管理区，日常解析绑定当前正文；重复接入不覆盖当前决定。升级按目标模板更新管理区，区外内容保持原字节，实际事务绑定当前原始前后像并防止并发覆盖。旧 USER-DECISION 声明、标记及其他区外内容均保持原始字节，不额外迁移或删除。已知项目若把必要扩展放进原管理区，在本次升级准备中移到区外；后续不把管理区手工修改作为独立项目内容保留。

规则包旧budget字段仅为兼容数据，不是用户配额。新注册、重复注册、same-pin、跨包采用和后像核验不因所选正文超过32/64/96KiB而拒绝，也不自动调额；旧字段保留不等于保留硬门。原预算repair参数对当前正常runtime为NO_CHANGE。旧runtime真实失败只沿既有限域授权过渡，不伪造旧收据或热改发行包。完整选择、去重、来源／身份／授权和回滚义务保持，真实大小供当前工作分析。

## 采用时处置旧纠正

不再使用中央项目 ID 映射的新运行包不会自动忽略旧记录。旧包曾精确抑制的记录必须逐项说明完整覆盖后退役，或保留项目增量。固定包同 pin 刷新可提供 `-AdoptionCorrectionsPlanPath` 和 `-ExpectedAdoptionCorrectionsPlanIdentity`；计划 schemaVersion=1，包含 expectedCorrectionsIdentity 和 changes 数组。每项为 correctionId、decisionLocator、record、historyRelativePath。record=NOT_APPLICABLE 表示从当前集合退役；否则提供不含 lifecycle/history 的完整新 record，原安装归属保持。活动/暂停且有归属的记录不能据此退役，须先按实际效果完成卸载。

historyRelativePath 使用 `.ai-workspace/upgrade-recovery/corrections/<ID>/<batch>/history.json`，不得覆盖已有材料。原完整 record 与本次决定、退役/修订操作随当前记录和采用 state 进入同一精确投影；目标预检、Apply、Postcheck、中断恢复和回退覆盖整组。旧包的覆盖判断只由旧包本身计算，目标运行不读取中央表；缺少任何旧抑制记录的显式处置则预览拒绝。局部覆盖是否完整由项目 Owner/独立 Review 判断，工具不证明语义等价。

## 材料与收尾

统一存放、保留和清理条件见所采用版本 TOOL_CONTRACT；本入口按需导航，不要求日常恢复加载整个历史。升级恢复、在用包及原过程收口证据留至最后消费者释放；正式结果不能长期只依赖可清理 runtime 内唯一材料。原任务自然收尾处理证据持久归属、有效引用和已知临时集合，不按目录大小或任务关闭推定可删。

## 采用与过程材料

upgrade-recovery 中仍有效的采用 state/distributionBinding 用于定位当前运行来源；未完成事务的前像、授权和恢复材料保留到原事务收口。已完成事务、纠正 history/installation 和原验证证据保留为历史，不再充当当前任务权限。runtime 中也可能保存仍有消费者的收据或证据；只清理已完成用途且无有效引用的临时输入，不按目录名称批量删除。
