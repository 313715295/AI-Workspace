# 项目接入与升级

本文件是 Framework 根级可维护流程，不属于任何已封存版本。版本目录声明项目运行合同；本流程负责把某个版本投影到具体项目，并可在不改版本载荷时修复根级接入工具。

## 从用户入口开始

用户包从包内 README/AGENTS 导航，开发仓从 [README](../README.md) 导航。已有项目先读取自己的 Bootstrap；首次注册尚无 Bootstrap 时，先检查所选版本的 VERSION、RELEASE_MANIFEST、ADOPTION_PROFILE 和 TOOLCHAIN，再运行 [register-project.ps1](../scripts/register-project.ps1) 预览。注册必须显式给出内部 `FrameworkVersion`、项目 `RepositoryPath`、项目 ID 与 `ControllerId`，在已有项目写授权范围内应用后进入生成的 Bootstrap。用户包目录无需 Git，目标项目必须是 Git 仓库。

升级使用 [upgrade-project.ps1](../scripts/upgrade-project.ps1) 预览及目标版本声明的兼容范围；目标未声明支持当前 Project Format/capability 时停止，不按发行名称推断兼容。Maintenance 的显式 sibling 布局仍由根级工具验证 CONTROL/TARGET 并叠加 maintenance-overlay；普通项目使用版本通用 starter。恢复和动作门禁只由当前项目 Bootstrap 与其 pin 对应的 runtime 合同维护，本入口不复制。

项目资料和标准保存在用户选择的位置，优先直接复用已有文档；共享标准可在本机独立目录由多个项目分别引用。提取、精炼或改造均为可选，不是采用前置条件，不将标准正文抄入 Framework。引用方式与可选处理的用户指引见 [接入已有项目资料和标准](../README.md#接入已有项目资料和标准)。

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

Maintenance 把已审根来源写回其 configured target 时，采用[Maintenance 根来源自更新](FRAMEWORK_RELEASE.md#maintenance-根来源自更新)的有界事务；本文件仍只负责项目 preview、same-pin 刷新与恢复，不另定义根来源授权或收尾语义。

## 宿主接入收尾

接入、升级或根级 Skill 变更交付时，由该次 Owner 或已指定的宿主接入执行者核对实际安装的 Router 与本次已接受、兼容所用项目 pin 的仓库 canonical Skill。当前宿主已使用 Router 时，相同则不写；有差异就在已有宿主写授权内同步，并回读字节身份。仓库 Skill 已更新、项目采用成功或 Root Tool Revision 匹配，都不能代替实际安装副本的核对。

同一宿主供多个项目使用时只收尾一次，不逐项目重复安装。未安装或未配置 Router 的宿主继续使用项目 Bootstrap；首次安装由用户选择。注册和升级脚本本身不安装全局 Skill，也不从项目写授权推导宿主写权限。

同步后按宿主支持的发现与加载方式使用，并在既有交付结果中简记安装位置、来源身份及一致／已同步／未使用／待处理状态；磁盘副本一致不等于运行中会话已重载正文。只有宿主接入未完成时保留该项，不重开已完成的项目采用事务，不新增同步服务或台账。

## 维护与版本关系

根级接入工具可以单独修复并重新运行；只有项目运行合同或版本载荷发生变化时才需要新 Framework 版本。Maintenance sibling 布局、overlay 与目标仓解析只属于根级工具，不能重新塞进版本通用合同。

## 试点与发布

可变候选先在隔离 fixture 完成定向验证，冻结后执行一次完整集成测试和独立 Source Review。只有同一已审快照才可进入明确批准的本地项目试点。试点未完成前不封存、不发布；发布后项目仍按自己的 pin 独立采用。

### 固定分发运行来源

运行包位置沿用使用者指定或已授权选择的目录；接入不默认迁移、复制发行包，也不规定按项目独占或多项目共享。位置尚未确定时，在执行部署前补齐；已有有效指定或选择授权不重复确认。发布 ZIP 本身不包含消费者解压、部署或接入动作。

命名分发包解压到独立目录，保留 PACKAGE_MANIFEST.json 和原文件字节。注册或显式升级将 distributionId、完整包 contentIdentity、manifestIdentity 与 runtimeRoot 写入既有 adoption state；版本 pin 仍由 project.json.frameworkVersion 决定。日常恢复从该已绑定目录加载。目录被替换、包内文件漂移或升级事务未完成时拒绝运行，不转回开发仓库 HEAD。

同版本 snapshot 切换也须经过 root upgrade-project.ps1 的真实 preview、精确 schema3 preimage/postimage 授权与 Apply。旧运行目录保留到切换及恢复验证完成。若中断，使用仍健康的旧包 root upgrader、原授权与当前 transaction identity，通过 RecoverRuntimeAdoption 选择 COMPLETE 或 ROLLBACK；前者先验证目标包，后者从原事务保存的字节回滚，不执行损坏目标。既有事务关闭后不能用同一恢复入口反向切换。

Maintenance 的开发 TARGET 保持 Git 源码职责；内部命名分发额外携带根适配器与维护 overlay，由 build-user-package.ps1 -InternalMaintenance 构建。普通用户包不携带这些维护专用入口。首次从旧开发来源接入固定包也使用显式 root upgrade；后续 TARGET 源码写入由固定 runtime 完成原动作 FINALIZE，不要求开发源码与运行绑定一起变化。

BOOTSTRAP project-custom 迁移至 process-policy 是同一精确 CONTROL_WRITE 的来源迁移；managed 区域保持不变。若动作已实际准入后写到一半，ProjectRuleRecoveryPlanPath 指向绑定原 DISCOVER、原 ADMIT 输入/结果和两个载体原/目标字节的恢复材料。root upgrader 先复证原动作与所有 live 字节，再在恢复当下创建事务；第三方状态、缺失原准入、扩大范围均拒绝，最终仍由原 FINALIZE 收口。材料格式由 root helper 校验，不改变 compact receipt schema。
