# Framework 1.4.1 → 1.5.0 语义迁移矩阵（RELEASE EVIDENCE）

本文件是开发、Review与发行证据，不进入项目运行时加载计划。它防止“缩短上下文”被误用为删除质量门。所有1.4.1稳定章节必须归入`KEEP / ADJUST / REMOVE / RELEASE_ARTIFACT`之一，并有1.5.0唯一落点。

## 1. 状态定义

- `KEEP`：语义不变，迁入一个完整运行时模块。
- `ADJUST`：目标与安全底线保留，但降低重复读取、重复验证、过度审核或主控瓶颈。
- `REMOVE`：确认没有净收益的机制，不建立兼容影子。
- `RELEASE_ARTIFACT`：不属于日常恢复模块，但必须在模板、脚本、starter、示例或发布测试中闭合。
- `COVERED`：1.5.0已有完整落点。
- `PLANNED`：矩阵冻结但模块尚未完成，1.5.0不得进入Review。

## 2. GOVERNANCE.md

| 1.4.1章节 | 处置 | 1.5.0落点 | 状态与说明 |
|---|---|---|---|
| §1适用模型 | KEEP | `RECOVERY_CORE.md`、`TASK_AND_SCOPE.md` | COVERED；两层长期责任、单owner、事实权威保留 |
| §2角色与权限 | ADJUST | `AUTHORIZATION_MODEL.md`、`TASK_AND_SCOPE.md` | 主控/分管/执行/审核保留；增加领域owner阶段签发权，用户只守产品/重大方案/external门 |
| §3决策与问题路由 | ADJUST | `AUTHORIZATION_MODEL.md`、`TASK_AND_SCOPE.md` | 本域常规自治；跨域/公共合同回主控；产品/重大方案/external回用户 |
| §4任务生命周期 | ADJUST | `TASK_AND_SCOPE.md` | 三档保留；热卡current/history分离；普通控制变更不使用whole-file身份阻断 |
| §5文件加载分层 | ADJUST | `RECOVERY_CORE.md`、`LOAD_MANIFEST.json` | 由全文/相关章节人工选择改为公共核心+完整模块的确定性并集 |
| §6风险、档位与审核深度 | KEEP | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md` | 四维风险、可达性、独立审核触发保留 |
| §7外部工具、账号与发行 | KEEP | `GIT_AND_EXTERNAL.md` | 阶段状态、官方来源、秘密与授权分离保留 |
| §8 Git与并行写入 | KEEP | `GIT_AND_EXTERNAL.md`、`HOST_CODEX.md` | 单Git closer、精确stage、默认不建worktree保留 |
| §9委派与独立性 | ADJUST | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md`、`HOST_CODEX.md` | 独立性与主动回传保留；取消默认多会话与owner逐轮转述 |
| §10会话交接与关闭 | ADJUST | `RECOVERY_CORE.md`、`HOST_CODEX.md` | FULL/WARM保留；新主控先恢复；不因idle/final机械FULL_COLD或wait |
| §11质量底线 | KEEP | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md` | 根因、单一真相、直接覆盖和整体自洽保留 |
| §12试点、证据复用与降本 | ADJUST | `REVIEW_AND_EVIDENCE.md`、`FRAMEWORK_RELEASE.md` | 自然样本和退出门保留；禁止逐任务指标与永久试点 |
| §13 repo-local项目控制面 | KEEP | `PROJECT_CONTROL.md` | 发现、严格文本、register/upgrade边界保留 |

## 3. WORKFLOW_PLAYBOOK.md

| 1.4.1章节 | 处置 | 1.5.0落点 | 状态与说明 |
|---|---|---|---|
| §0唯一端到端流程 | ADJUST | `TASK_AND_SCOPE.md` | 保留事实→方案→实施→验证→审核→Git；阶段授权包替代逐动作审批 |
| §1启动与事实基线 | ADJUST | `RECOVERY_CORE.md`、loader | FULL/WARM保留；减少固定文档重复全文加载 |
| §2注意力与理论建构 | KEEP | `TASK_AND_SCOPE.md` | 搜索只建图，结论回原文/producer/consumer |
| §3权威与冲突裁决 | KEEP | `TASK_AND_SCOPE.md` | current权威优先，冲突fail closed并路由 |
| §4档位与改前准备 | ADJUST | `TASK_AND_SCOPE.md` | exact/forbidden与pre-mortem保留；强度按档位，不机械完整manifest |
| §5方案内容标准 | KEEP | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md` | 目标行为、数据流、生命周期、失败路径、非目标保留 |
| §6安全网与测试 | KEEP | `REVIEW_AND_EVIDENCE.md` | 变更前安全网、直接覆盖、相邻回归保留 |
| §7实施纪律 | KEEP | `TASK_AND_SCOPE.md` | 根因、单路径、禁止无关清理/兼容分支 |
| §8额外问题边界 | KEEP | `TASK_AND_SCOPE.md` | 分类路由，不无限扩面 |
| §9关系图与影响沉淀 | ADJUST | `TASK_AND_SCOPE.md` | 只在长期consumer需要时沉淀，不机械同步全图 |
| §10修改后验证和审核 | ADJUST | `REVIEW_AND_EVIDENCE.md` | 档位相称；用户反例失效READY；Review前机械preflight |
| §11文档、状态与交接 | ADJUST | `TASK_AND_SCOPE.md` | 热卡收薄、history carrier、结果导向汇报 |
| §12外部动作与发行 | KEEP | `GIT_AND_EXTERNAL.md` | 外部阶段分离，不互相推定 |
| §13 Git收口 | KEEP | `GIT_AND_EXTERNAL.md` | 单closer、真实HEAD/index/diff、精确stage |
| §14沟通标准 | ADJUST | `TASK_AND_SCOPE.md`、`HOST_CODEX.md` | 用户只看结果/剩余/操作/证据上限，控制细节留任务对象 |
| §15动态资源与执行载体 | ADJUST | `HOST_CODEX.md`、`TASK_AND_SCOPE.md` | 质量等级保留；不默认新会话/worktree；用自然样本监测返工率 |
| §16会话健康与轮换 | ADJUST | `RECOVERY_CORE.md`、`HOST_CODEX.md` | 质量自检保留；主控先恢复；无消费者的旧会话及时释放 |
| §17任务关闭、试点、证据复用 | ADJUST | `TASK_AND_SCOPE.md`、`REVIEW_AND_EVIDENCE.md` | manifest只在稳定边界；试点必须退出；热卡current/history分离 |
| §18 repo-local发现/register/upgrade/迁移 | KEEP | `PROJECT_CONTROL.md` | 项目控制专项，不让普通执行者默认加载 |

## 4. REVIEW_CHECKLIST.md

| 1.4.1章节 | 处置 | 1.5.0落点 | 状态与说明 |
|---|---|---|---|
| §1审核场景 | KEEP | `REVIEW_AND_EVIDENCE.md` | 审计与delta审核区分 |
| §2风险四维与深度 | KEEP | `REVIEW_AND_EVIDENCE.md` | 影响/复杂度/依赖/可观察性保留 |
| §3 Pre-mortem | ADJUST | `REVIEW_AND_EVIDENCE.md` | MICRO 1项、STANDARD 1–3、CRITICAL至少3；必须对应检查 |
| §4输入与所有权 | KEEP | `REVIEW_AND_EVIDENCE.md` | owner、exact、independence、actual、stable candidate保留 |
| §5十二项方案审核 | ADJUST | `REVIEW_AND_EVIDENCE.md` | 保留12个视角；CRITICAL执行所有适用项，不为明显不适用项生产长篇证明 |
| §6文档八维 | KEEP | `REVIEW_AND_EVIDENCE.md` | 按对象类型完整适用项 |
| §7文档四层机械验证 | KEEP | `REVIEW_AND_EVIDENCE.md` | 严格文本、旧概念、新概念、重点穿透 |
| §8代码六层验证 | KEEP | `REVIEW_AND_EVIDENCE.md` | 静态、diff、旧/新概念、行为、质量及风险相称回归 |
| §9平台/发行十项 | KEEP | `GIT_AND_EXTERNAL.md` | 只在相关任务加载，避免普通功能被发布级防御阻断 |
| §10证伪型检查点 | KEEP | `REVIEW_AND_EVIDENCE.md` | 结论必须可证伪 |
| §11行为声明一致性 | KEEP | `REVIEW_AND_EVIDENCE.md` | 权威声明→实现→直接证据 |
| §12评审视角 | ADJUST | `REVIEW_AND_EVIDENCE.md`、可选lenses | 只选能改变判断的视角，不模拟人格 |
| §13偏差等级 | KEEP | `REVIEW_AND_EVIDENCE.md` | 架构/机械阻断，卫生可延期，建议不得降级伪装 |
| §14输出模板 | ADJUST | `REVIEW_AND_EVIDENCE.md` | 默认紧凑verdict；只输出适用检查与未验证，不复制整套清单 |
| §15失败学习 | KEEP | `REVIEW_AND_EVIDENCE.md`、`FRAMEWORK_RELEASE.md` | 流程缺口进入新Framework版本，不停留聊天 |
| §16架构趋势 | ADJUST | `REVIEW_AND_EVIDENCE.md` | 仅项目趋势可选，不形成批准分数或指标平台 |
| §17 repo-local专项 | KEEP | `PROJECT_CONTROL.md` | 只供控制面/Framework任务加载 |

## 5. 宿主、模板与发行材料

| 1.4.1对象 | 处置 | 1.5.0落点 | 说明 |
|---|---|---|---|
| `HOST_ADAPTER_CODEX.md` | ADJUST | `HOST_CODEX.md` | 主动回传、禁止轮询、任务复用保留；增加worktree成本门、紧凑pre-tool结果和资源梯度 |
| `TASK_TEMPLATE.md` | RELEASE_ARTIFACT | `TASK_TEMPLATE.md` | 已覆盖：MICRO可无卡；STANDARD紧凑；CRITICAL完整；内嵌阶段授权和hot/history边界 |
| `PROMPTS.md` | RELEASE_ARTIFACT | `PROMPTS.md` | 已覆盖：启动提示调用Bootstrap/loader，不复制完整流程 |
| `EXAMPLES.md` | RELEASE_ARTIFACT | `EXAMPLES.md` | 已覆盖：无卡MICRO、领域owner STANDARD、CRITICAL用户门、external与worktree分离 |
| `PERSPECTIVE_LENSES.md` | ADJUST/OPTIONAL | `PERSPECTIVE_LENSES.md` | 已覆盖：仅Review或任务明确选择时加载 |
| `project-starter/BOOTSTRAP.md` | RELEASE_ARTIFACT | `project-starter/` | 已覆盖：schema2固定inventory；核心→轻路由→loader→项目/current |
| `scripts/check-task-card.ps1` | ADJUST | `scripts/check-task-card.ps1` | 已覆盖原型：新卡范围/生命周期/授权一致；legacy不强迁；与授权checker分离 |
| `tests/run-framework-tests.ps1` | RELEASE_ARTIFACT | `tests/run-framework-tests.ps1` | COVERED；所有load组合、授权正反例、迁移覆盖、稳定发布状态、starter、注册、升级和失败回滚进入发行测试 |
| 根register/upgrade | RELEASE_ARTIFACT | 根`scripts/register-project.ps1`、`scripts/upgrade-project.ps1` | COVERED；现有跨版本实现无需语义改写，已通过显式1.5注册、CURRENT仍1.4.1、1.4.1→1.5.0升级与managed-conflict零mutation测试 |

## 6. 明确删除或停止推广的过度防御

1. 普通控制文档更新使用whole-file identity作为内容漂移硬门。
2. 每个会话、每个任务或每个工具调用重复FULL_COLD、manifest和授权脚本。
3. 每个新会话默认创建worktree、branch或独立index。
4. `MICRO / STANDARD`机械配置独立Reviewer、完整CRITICAL卡或十二项长报告。
5. 独立任务通过`wait_threads`/等价轮询维持进度感。
6. 每次脚本PASS返回详细JSON、全manifest或大段SHA到模型上下文。
7. 用户逐文件、逐测试、逐Review轮次授权；用户门只守产品结果、重大方案/公共合同和external。
8. 主控代替领域owner签发全部本地阶段动作或重复领域验收。
9. 为迁移1.5批量改写所有legacy任务卡、历史正文或archive。
10. 为试点建立逐任务报表、长期指标平台或为凑样本制造任务。

## 7. 不得因降本删除的硬门

1. 唯一owner/调度者、单writer与其他owner字节保护。
2. 项目身份、Framework pin、保护路径和固定版本发现。
3. exact/forbidden与producer/direct consumer/test/runner/docs影响闭包。
4. 公共合同、持久状态、复杂状态机和重大玩家体验的方案与独立Review。
5. 用户试玩优先于最终审核；反例使旧READY失效。
6. Git closer、stage/commit/push/external分离。
7. 真实运行/设备/平台证据不被静态测试或截图冒充。
8. stable版本不可原位修改，项目pin只通过独立升级任务改变。

## 8. 当前覆盖与下一门

- 已覆盖：通用恢复核心、任务/范围、审核/证据、Git/external、项目控制、Framework发行、分级授权、Codex宿主适配、确定性loader原型和授权checker原型。
- 已完成：逐行覆盖复核、运行时加载成本核对、模板/starter/task checker迁移、授权路径硬门返工、独立聚焦Review与发行回归测试。
- `current_status=RELEASE_INTEGRATION_COMPLETE`：1.5.0进入显式opt-in稳定库存；`CURRENT`仍为1.4.1。
- Pocket对比前：不得改变Pocket pin；Pocket就绪后按当时真实状态做1.4.0/1.4.1/1.5.0对比。
