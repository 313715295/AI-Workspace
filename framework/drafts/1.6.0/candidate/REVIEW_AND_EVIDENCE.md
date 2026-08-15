# 审核、验证与证据

本模块用于方案验证、候选自检、聚焦审核和独立Review。Review判断设计与行为是否正确；checker只判断结构声明是否一致，两者不能互相替代。

## 1. 审核场景、责任与结论

- 场景A：审计现有对象。先定性、建立有限注意力地图并完整读取审核对象，再提出finding。
- 场景B：审核刚完成的修改。从actual diff、稳定candidate和验证证据开始，穿透直接上下游。

`MICRO`由owner自检并承担结果，不虚构独立批准。`STANDARD`由领域owner做聚焦审核，只有风险、争议、复发、上下文污染或任务明确要求时挂载独立Reviewer。`CRITICAL`的公共合同、复杂状态机、重大玩家体验和高失败代价对象由未参与方案实质设计及候选写入的合格Reviewer给最终独立结论。

独立Reviewer若做实质修改，本轮失去唯一最终批准资格。Review只拥有指定维度结论权，不授予范围、写入、Git、阶段或external动作。

结论只有`APPROVED / CHANGES_REQUESTED / BLOCKED`。`APPROVED`要求0架构偏差、0机械偏差，并明确验证范围、未验证项和残余风险。

Review verdict与阶段验收是两件事。对`Phase gate: TRUE`的CRITICAL父任务，技术审计/Review形成稳定证据；领域owner做产品或设计合同完整性核对，适用的runtime/platform owner确认运行边界，最后由项目主控签署阶段ready并闭合用户最终门。技术Review与用户试玩没有固定先后：低成本试玩可先拦截产品反例，高风险或高准备成本对象可先Review再试玩。同一stable candidate上的既有用户结论在项目签署后直接复用，不再重复询问；最终`CONFIRMED`的candidate必须等于任务`current_exact`。若技术证据无争议，不为这条验收链机械增加第二名fresh Reviewer。

## 2. 深度选择和pre-mortem

按影响范围、行为复杂度、依赖数量、可观察性和失败代价选择深度。

- MICRO：最直接失败方式1项及对应验证。
- STANDARD：1–3项最可能严重失败及对应检查；只执行与风险直接相关的审核维度。
- CRITICAL：至少3项，覆盖职责/合同、生命周期/失败恢复和真实运行影响；执行所有适用审核维度。

“不适用”可以简短记录原因，不为明显不适用项生产长篇证明。不能以减少文字为由跳过适用的独立性、公共合同、直接行为或运行证据。

## 3. 审核输入门

审核开始前确认：

1. task、profile、目标/非目标、owner、作者、Reviewer与Git closer；
2. exact/contingency/forbidden、保护路径及其他dirty边界；
3. 权威输入、改前行为、目标行为和不变相邻行为；
4. actual diff、stable content object/section identity、candidate与依赖manifest、验证上限；
5. 作者执行的命令、结果、失败、未验证和额外发现；
6. 可达性分类与证据强度；
7. 用户试玩/产品确认是否是本候选必要门；
8. 直接闭环的允许返工、轮次上限和升级停止线。

输入不足或对象漂移时`BLOCKED`，不能用作者总结、聊天或旧批准补齐。热任务卡的纯状态/actor/审核记录变化不自动使稳定内容批准失效；必须分类actual delta。

## 4. 方案审核十二视角

CRITICAL检查所有适用项；STANDARD只选能改变本任务判断的项；MICRO不机械运行清单但仍检查actual直接冲突。

1. 核心目标与玩家/用户体验。
2. 架构分层与依赖方向。
3. 单一真相、唯一写入者和所有权。
4. 简洁性与最少状态/路径。
5. 同类扩展是否通过稳定扩展点而非复制分支。
6. 隐藏消费者、隐式字段和跨层耦合。
7. 当前无消费者的过度设计、兼容层和服务。
8. 时间、事件、持续状态与恢复语义。
9. 同类命令、错误、枚举、数据形状和命名统一。
10. 新旧内容、数据流和生命周期整体自洽。
11. 方法/模块职责、抽象层次、SRP/CQS与拆分质量。
12. 持久字段的消费者、跨tick必要性、写入/更新/清理/销毁。

方案写得完整或测试变绿不能代替这些职责判断。

## 5. 文档验证

适用维度：最新设计、模块归属、上下游一致、内容完整、生命周期闭环、数据流、结构格式和冲突。

机械四层：

1. 严格UTF-8、无BOM/NUL/U+FFFD、LF、结尾、围栏/注释、尾随空白、链接和`diff --check`。
2. 搜索旧概念在current有效范围是否清除；历史说明明确排除。
3. 核实新概念的定义、引用、模板、映射和示例一致。
4. 重新读取改动与重点上下游，用真实场景走通引用、数据流和生命周期。

场景A完整阅读对象；场景B确认作者按档位读取足够上下游并由Reviewer复读actual重点。

## 6. 代码验证六层

1. 语法、类型、lint或编译；不适用时说明。
2. 文件完整性、生成边界、实际diff和命中数量。
3. 删除/改名的接口、字段、错误码、魔法字符串和旧入口清除。
4. 新入口、消费者、失败/清理路径和direct tests到位。
5. 代码与设计的输入输出、状态所有权、调用顺序、错误和相邻行为一致。
6. 热路径分配/GC、死代码、命名、统一契约、重复/复杂条件、魔法值、断言、职责、复杂度和helper拆分质量。

随后运行任务需要的回归、构建、性能、browser、视觉、device或长跑验证。构建不替代runtime，截图不替代交互，单元测试不替代设计审核。

## 7. 行为声明与证伪

从权威提取“必须、触发、写入、读取、中断、顺序、禁止、单一”等声明，建立有限定义—producer—consumer—test表。逐条回答：实现是否存在、条件和退出是否完整、谁是唯一写入者、是否有直接证据。

审核不能只写“已检查”或“0问题”。至少主动寻找：

- 状态/错误/字段定义与所有消费者不一致；
- 生命周期异常退出和清理遗漏；
- 多writer、无人读、无人写或旧入口残留；
- 新增同类功能必须修改多处导致的分叉；
- finding若发生时的玩家或系统影响。

项目若有玩家试玩门，browser/self-check只能作为候选准备证据。用户反例使旧READY和基于该READY的待审状态失效；修复必须回到current candidate并由同一用户门复验。

## 8. Manifest、证据有效键与delta

manifest只在writer release、试玩候选、Review、commit/version freeze或疑似drift生成；普通编辑过程不反复全量生成。

CRITICAL证据有效键由内容对象、direct dependencies、fixture、工具链、环境和命令构成。等价未漂移时复用，相关输入漂移时只重跑受影响层；无法证明影响面时才完整相关复审。

候选变化分类：

- 内容/依赖/范围/权限/公共合同：重审受影响层；
- 纯状态、审核记录或可证明known-exact：刷新变化对象，未影响批准继续有效；
- 影响面或identity不明：fail closed。

控制卡whole-file变化不自动等于内容漂移；Review绑定稳定content section和依赖，不绑定持续追加热卡全部字节。

## 9. 偏差、返工和Review轮次

- 架构偏差：目标、职责、依赖、所有权、公共合同或行为合同错误；阻断批准。
- 机械偏差：遗漏、实现错误、测试缺口、旧概念、文档/代码不一致或工具完整性问题；阻断批准。
- 卫生偏差：不影响current合同的局部整洁；可当批修或记录真实owner/trigger延期。
- 建议：可选优化，不得把架构/机械问题降级包装。

范围内`CHANGES_REQUESTED`可按预授权直返一次或任务定义轮次，不是新写权。`RANGE_GATE_REQUIRED`、产品/跨域/owner/权限/质量冲突、同一finding复发或轮次上限立即停回owner。不得用Review循环代替产品/范围决策。

## 10. 紧凑审核输出

默认输出：

```text
task / reviewer / scenario / profile
verdict: APPROVED | CHANGES_REQUESTED | BLOCKED
stable candidate and delta class
findings: severity + object + evidence + impact + completion condition
applicable checks and actual results
unverified / residual risks
Git recommendation and exact paths
next actor / stopline / owner return
```

只输出实际适用的方案、文档、代码、平台或运行检查，不复制整份空清单。控制面保留详细manifest与命令；用户报告只保留结论、剩余和是否需操作。

## 11. 失败学习与试点

后续缺陷出现时回看：当时范围是否已包含、哪个检查点失效、是候选变化还是漏检、应修任务还是Framework。流程缺口必须进入新Framework版本或项目规则，不能只停留聊天。

流程/资源试点预先冻结问题、自然样本、停止线、判定和稳定落点，到线必须`KEEP / ADJUST / REJECT`。只从自然关闭任务提取准备耗时、恢复模式、审核角色、返工、冲突/缺陷拦截和恢复耗时；允许缺失值，不新增逐任务报表或指标平台。

模型/资源下调的接受条件是质量与总成本：缺陷率和显著返工不得上升，准备与执行成本才有意义。样本不足时维持较高质量档，不用低质量任务制造样本。

## 12. A-C+G专项证据

- remote：逐项ledger、部分成功、成功项不可变重试、head/config drift、protected exclude、secret-safe receipt与补偿失败原receipt保留。
- resource：common合同无host alias；当前adapter满足minimum/tools；unsupported与silent downgrade负键。
- task：source/report、主动terminal回传、一次有界wait、terminal-only archive和user decision handoff。
- controller：canonical identity、successor FULL_COLD ACCEPT前后、epoch原子切换、旧PROJECT_CONTROLLER包STALE、DOMAIN_OWNER兼容、cache失效、queue suppression、exception单次复证重路由与state dedup。
