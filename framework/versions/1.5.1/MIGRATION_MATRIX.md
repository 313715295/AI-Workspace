# Framework 1.5.0 → 1.5.1 patch迁移矩阵（STABLE RELEASE EVIDENCE）

本文件只用于Framework开发、Review和发行证据，不进入项目运行时加载计划。1.5.1不重写1.5.0稳定目录；它只修复“技术证据可被误当成阶段验收”的机械漏放，并保持普通任务成本不变。

## 1. 语义与机械落点

| 1.5.0对象 | 处置 | 1.5.1落点 | 状态与说明 |
|---|---|---|---|
| `TASK_AND_SCOPE.md`长期责任 | ADJUST | 同文件阶段验收段 | COVERED；技术证据、领域合同、runtime/platform、项目签署和用户最终门职责分离 |
| `REVIEW_AND_EVIDENCE.md`Review verdict | ADJUST | 同文件§1 | COVERED；明确Review批准不是阶段批准，无争议证据不机械增加第二Reviewer |
| `TASK_TEMPLATE.md`CRITICAL模板 | ADJUST | `Phase gate`与条件式矩阵 | COVERED；仅推进项目/多领域里程碑的父任务启用，普通MICRO/STANDARD/CRITICAL不增加矩阵 |
| `scripts/check-task-card.ps1`schema | ADJUST | schema `1.5`兼容 + `1.5.1`新门 | COVERED；既有1.5任务无需迁移，新1.5.1 CRITICAL必须声明Phase gate |
| 阶段验收顺序 | ADD | task checker | COVERED；项目签署必须等待技术/领域/runtime前置，用户门必须等待项目签署，CLOSED必须闭合 |
| N/A适用性 | ADD | task checker | COVERED；领域或runtime/platform不适用必须有原因，避免制造空审核 |
| 项目签署owner | ADD | task checker | COVERED；`Project phase signoff`的controller必须等于任务唯一Owner |
| 授权模型 | KEEP | `AUTHORIZATION_MODEL.md`与checker | COVERED；阶段验收不新增写权、Review权、Git或external权 |
| 恢复与loader | KEEP_VERSION_BUMP | `VERSION.json`、`LOAD_MANIFEST.json`、loader | COVERED；按需加载模块集合不增加，首次加载只承担少量文本delta |
| starter inventory | KEEP | `project-starter/**` | COVERED；不新增项目文件或第二状态系统 |
| 根register/upgrade | KEEP | 根`scripts/register-project.ps1`、`scripts/upgrade-project.ps1` | COVERED；跨版本实现不改，PATCH默认只做1.5.0→1.5.1 smoke；完整集成复用1.5.0发行证据 |
| 1.5.0稳定目录 | KEEP_IMMUTABLE | `framework/versions/1.5.0/**` | COVERED；零原位修改 |
| 发行manifest | RELEASE_ARTIFACT | `RELEASE_MANIFEST.json` | COVERED；固定inventory、bytes、canonical、来源候选、Review与发行复验 |

## 2. 兼容与项目迁移

- schema `1.5`任务卡继续由1.5.1 checker按原规则验证，不要求补`Phase gate`或批量改history。
- schema `1.5.1`的MICRO/STANDARD无新增字段；普通CRITICAL只增加一行`Phase gate: FALSE`。
- 只有真正承担项目/多领域阶段推进的CRITICAL父卡使用`Phase gate: TRUE`及六行矩阵（五个验收状态加固定顺序）。
- 已有项目升级只更新Framework pin与Bootstrap受管区；稳定项目资料、自定义区和历史卡不重建。
- Pocket Legion在W1整阶段闭环后、W2开始前另立升级任务，从1.4.0直接比较并升级到稳定1.5.1；不先临时pin 1.5.0。

## 3. 正反例与完成状态

PATCH热修主门由`tests/run-hotfix-tests.ps1`覆盖；`tests/run-framework-tests.ps1`保留为影响面扩大时的完整回归，当前已额外通过但不是每个patch的默认发行门。

热修direct覆盖：

- schema1.5 CRITICAL兼容；
- schema1.5.1 STANDARD零阶段矩阵成本；
- CRITICAL必须声明Phase gate，FALSE无需矩阵；
- TRUE允许自然PENDING，也能按序闭合；
- 缺领域项、N/A无理由、项目签署者错误、前置未闭合、用户门过早、用户candidate缺失/不等于`current_exact`、CLOSED未闭合均拒绝；
- STABLE可显式pin元数据、稳定目录inventory兼容、受影响loader计划、授权版本、strict文本与1.5.0→1.5.1 smoke。

- `current_status=STABLE_RELEASED`
- 当前：hotfix direct tests覆盖31项；Pocket W1自然样本已完成并修正用户证据复用及candidate绑定语义；fresh聚焦Review-2已APPROVED。
- 后续动作：Framework commit/push、`CURRENT`切换与Pocket项目升级仍分别授权；稳定发行不自动推进其中任何一项。
