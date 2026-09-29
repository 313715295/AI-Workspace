# 可选项目规范

本目录供项目选择，存在于发行包不等于已采用。原生治理、项目纠正和项目规则仍是三个规则来源；软件方法不自动进入原生规则。一个要求只有一个完整正文来源，生产者与审核者使用同一项目已采用正文。

`presets/software.json` 提供软件设计、实现和验证的声明式来源与选择条件。采用由项目自己决定并在自己的 `process-policy.rules` 保存；Framework、发行包和 Maintenance 不登记其他项目采用情况，也不要求回传。只读展开可使用当前版本 composer：

```powershell
Import-Module <FW>/scripts/ProcessRequirementComposition.psm1
$rules = @(Expand-AiwProcessPreset -PresetId software -ProjectRoot <PROJECT> `
    -DecisionLocator <项目已有采用决定的定位> -ForbiddenPaths <项目当前禁读路径>)
```

函数仅返回普通 project-policy rule 对象，绑定本目录完整来源、当前身份、选择条件及原项目决定；不修改项目，不创建授权、索引或采用记录。调用者核对原始决定、实际路径和保护范围后，沿原项目的规则修改/验证边界将所选项纳入 policy。允许只选其中适用项；再次展开不是再次采用，不能把相同 ruleId 盲目追加。

项目补充或替换标准时，在同次 policy 修改中退出旧项并加入完整新项，不保留两个冲突的有效 MUST。可选标准不能覆盖或抑制原生授权、责任、独立审核、真实性和恢复要求。普通文档链接、参考材料和 preset 文件自身均不成为第四权威。

固定来源指向已选择的发行目录或不可变快照。跟随来源由 `decisionLocator` 指向的原项目决定说明授权范围，在实际更新/读取边界比较变化并重新绑定来源和依赖；不增加 `source.updateMode`、后台监听或逐次确认。超出原决定的实质变化只停止受影响项。来源漂移时沿既有 composer 失效/完整正文回退，不能把保守加载误当已经重新采用。

`software/DESIGN.md`、`IMPLEMENTATION.md`、`VALIDATION.md` 是各自要求的唯一正文。内容由已有软件评审视角整理为可执行要求，不引用私有项目事实。治理模块只保留通用责任和导航；其他专业内容按项目需要另选来源。
