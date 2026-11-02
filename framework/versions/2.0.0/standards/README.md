# 可选项目规范

本目录供项目选择，存在于发行包不等于已采用。原生治理、项目纠正和项目规则仍是三个规则来源；软件方法不自动进入原生规则。一个要求只有一个完整正文来源，生产者与审核者使用同一项目已采用正文。

日常过程先核必要全局声明，以本次真实意图选择，再读取完整命中规则及公共条件、有序依赖；未命中的独立外部正文不访问，也不证明健康。实际注册、升级、规则/纠正采用变更和专业发布继续完整验证其目标采用集合。FULL表示本次所需完整正文；不同合法选择闭包可以预载并共享相同完整单元，义务与顺序分别保留。

`presets/software.json` 提供软件设计、实现和验证的声明式来源与选择条件。采用由项目自己决定并在自己的 `process-policy.rules` 保存；Framework、发行包和 Maintenance 不登记其他项目采用情况，也不要求回传。当前 project7/policy3 的公开只读准备入口同时返回完整规则和来源绑定。项目明确选择规则，并为每项作实际适用性决定，例如：

```powershell
Import-Module <FW>/scripts/ProcessRequirementComposition.psm1
$applicability = @{
    SOFTWARE_DESIGN = @{ domain=@('aiw:software'); workType=@('aiw:design','aiw:review','aiw:acceptance') }
    SOFTWARE_IMPLEMENTATION = @{ domain=@('aiw:software'); workType=@('aiw:implementation','aiw:review','aiw:acceptance') }
    SOFTWARE_VALIDATION = @{ domain=@('aiw:software'); workType=@('aiw:verification','aiw:review','aiw:acceptance') }
}
$prepared = New-AiwProcessPresetPreparation -PresetId software -ProjectRoot <PROJECT> `
    -RuleIds SOFTWARE_DESIGN,SOFTWARE_IMPLEMENTATION,SOFTWARE_VALIDATION `
    -Applicability $applicability -DecisionLocator <项目已有采用决定的定位> `
    -ForbiddenPaths <项目当前禁读路径>
```

示例中的占位值须替换为当前固定版本、项目、原决定和保护范围；适用性表是项目决定，不是 preset 自动推断。示例把审核/验收列入三项要求：审核软件成果使用真实 `workType=aiw:review`、`REVIEW_EXECUTE/REVIEW_VERDICT`，接受使用 `aiw:acceptance`、`RESULT_ACCEPT/RESULT_ACCEPTANCE`，再分别填写实际产物与阶段；不能伪装成implementation以命中标准。项目若只审核设计，可按成果范围收窄规则并同时保留实际review分类。`rules` 已采用当前 `BOUND_SOURCE_ITEM` 格式，绑定完整正文、revision、itemIdentity、选择条件和原决定；`sourceBindings` 保留现有绑定并提出所选文件的精确许可。`permissionChanges` 明示新增或扩展许可，既有同名绑定指向其他来源时拒绝。调用者先核对原始决定、实际路径、保护范围及许可提议，再沿项目已有规则修改/验证边界，将候选 config 的 `sourceBindings` 与 policy 的所选 `rules` 一起准备、准入、写入和收口。不能仅追加规则而遗漏来源许可，也不能把同一 ruleId 盲目重复加入。

准备函数不修改项目，不创建授权、索引或采用记录，返回 `authority=false` 和 `projectWritePerformed=false`。`RuleIds` 必须显式非空，可只选其中适用项；未选正文不读取。再次准备只是当前字节的候选重绑，仍由原项目决定和动作边界控制。较低层的 `Expand-AiwProcessPreset` 仅返回来源展开数据，其旧式 source 对象不能直接写入当前 policy3；当前项目应使用上述完整准备入口。

实际采用沿 [项目来源配置的受限普通采用](../TOOL_CONTRACT.md#项目来源配置的受限普通采用)。保存候选 config/policy 后，以真实原 DISCOVER 调用 `New-AiwProjectSourceChangePreparation`，核对其完整许可差异与目标规则，将候选 token 加入原 ADMIT。保留原 ADMIT 输入/结果，按 policy→config 写入，再用同一 compact 和原准入证明 FINALIZE；不能写后重新 DISCOVER 代替收口。该普通两文件动作也支持退出、替换和已启用知识来源维护，支持已启用知识来源维护；项目明确首次选择知识引用时，只有当前Controller签发精确config+policy包才可将缺失或合法disabled变为enabled。除此之外不允许能力启停，pin/backend、保护、布局和其他配置保持原值。

项目补充或替换标准时，在同次 policy 修改中退出旧项并加入完整新项，不保留两个冲突的有效 MUST。可选标准不能覆盖或抑制原生授权、责任、独立审核、真实性和恢复要求。普通文档链接、参考材料和 preset 文件自身均不成为第四权威。

固定来源指向已选择的发行目录或不可变快照。跟随来源由 `decisionLocator` 指向的原项目决定说明授权范围，在实际更新/读取边界比较变化并重新绑定来源和依赖；不增加 `source.updateMode`、后台监听或逐次确认。超出原决定的实质变化只停止受影响项。来源漂移时沿既有 composer 失效/完整正文回退，不能把保守加载误当已经重新采用。

`software/DESIGN.md`、`IMPLEMENTATION.md`、`VALIDATION.md` 是各自要求的唯一正文。内容由已有软件评审视角整理为可执行要求，不引用私有项目事实。治理模块只保留通用责任和导航；其他专业内容按项目需要另选来源。

不确定一份材料是要求、方案、方法还是验证证据时，可参考[产物分类](../knowledge/cross-domain/ARTIFACT_CLASSIFICATION.md)。分类、目录可见或参考方法加载不构成规范采用；只有原项目决定及相应治理边界才能改变当前义务。

需要表达软件行为增量、完整条件与例外、可观察场景或简模板时，可参考[软件行为规格与变更](../knowledge/software/BEHAVIOR_SPEC_CHANGE.md)。该METHOD不加入software preset，也不替代上述三篇已采用标准；规范维护责任仍取TASK_AND_SCOPE。

本项目拥有的 LOCAL_DIRECTORY 专业正文需要原位更新时，沿 [双动作发布](../TOOL_CONTRACT.md#同项目专业正文的双动作发布)：先冻结完整改稿和整文件影响闭包，包含同文件未命中的采用章节；分开授权 docs 的 SOURCE_WRITE 与 config/policy 的 CONTROL_WRITE，再用共同投影目标预读、双准入及原根 APPLY/恢复。读取许可不授写权，新增引用不把产品或外部文件变成可写规范。只替换采用、首次启用知识引用、使用已存在不可变来源仍取旧两载体路径。当前支持限 Windows/PowerShell7 本地项目；两次成员验证通过仍待联合 journal 提交，不能先称发布完成。
