# AI Workspace Framework roadmap

本文保存 generic release history 与尚未选择的 Framework direction，不是 task board、authorization object、consumer registry 或 project evidence store。

## 当前 1.16.0 local candidate rework

状态：`CANDIDATE / consumable=false / projectPinEligible=false`。这是对 `1.16.0` direct-version payload 的本地候选重作；此前 remote publication 是历史事实，不等于当前 bytes 已 Review、sealed、published 或被任何 consumer 采用。

已选择的 minimum scope：

- 保留自然 task/context/authority boundary 上完整 selected-rule block 的一次加载；unchanged work 复用 compact receipt；uncertainty 或 source drift 重载。
- 分离 task Owner、Work route `taskActor` 与 temporary action grantee；纯 `REVIEW_EXECUTE` 不改任务卡或 candidate，verdict 直接回 Owner。
- 把 selected-pack runtime budget 放入 project `.ai-workspace/process-policy.json.selectedRulePackBytes`；default `32768`，Framework absolute cap `98304`。
- upgrade 使用隔离的 target-before-pin projection：在临时投影中迁移 legacy two-field task route、target policy/corrections/budget，再运行 target resolver；该预检失败不写入项目受管状态。后续 Apply 的完整失败恢复保证仍属于下节待实施规划，不能把预检无写入等同于整个升级原子化。
- compact `DISCOVER` receipt 与 ADMIT/FINALIZE result，保留 source identities、exact scope、obligations 与 categorical gates。
- ephemeral artifact 默认位于 `.ai-workspace/runtime/<task>/<actor>/`；registration/upgrade 幂等追加或复用 `/.ai-workspace/runtime/`，遇到 negation conflict 停止；system temp 只作 reported fallback。
- 唯一 canonical Router Skill 位于 root `skills/ai-workspace-router/SKILL.md`；version payload 只保留 compatibility contract/history。
- human/AI-facing docs 使用中文；machine field、ID、parameter 与 diagnostic token 保持 English。
- release 工作按比例执行：editing 期 affected tests，freeze 时一次 complete suite，一个 independent Source Review；同范围 repair 才做 focused rereview；`OWNER_ACCEPT`、seal、Git publication 与 adoption 分离。

硬边界：SOURCE/TEST/REVIEW/OWNER_ACCEPT/GIT/PUSH/BROWSER/DEVICE/EXTERNAL 独立；protected paths、CRITICAL independent Review、stable immutability、exact Git scope 与 user-decision drift 继续 fail closed。不增加 actor registry、Reviewer pool、handoff/consumption ledger、ACK/heartbeat/poller、service、per-tool hook、Knowledge expansion、新 backend、automatic consumer upgrade 或 three-platform CI。

本节记录候选方向，不复制逐轮测试、Review、项目试点或阻塞状态。精确版本生命周期与候选身份读取该版本的 `VERSION.json`、`RELEASE_MANIFEST.json`；维护工作的当前进度、反馈与证据读取维护项目当前任务。既有测试、审查与试点结果只覆盖各自绑定的快照，不批准后续修改；新反馈也不因曾有试点通过而被忽略。

## 已确认的整体整理规划：暂不实施

状态：`PLAN_CONFIRMED / IMPLEMENTATION_NOT_STARTED / VERSION_UNSELECTED`。本节只保存已确认的整理方向、边界、顺序与验收条件，不授予实施、项目迁移、历史删除、Review、Git 或发布权限。

先处理当前 1.16 候选的实际使用反馈，再由用户决定何时启动本节。方案以当前候选为评估基础，但尚未扩入当前实现范围，也未选择 1.17 或其他新版本。不为等待中的项目反馈猜测根因，不创建占位任务或 draft 树。

### 完整范围与最小方案

| 问题 | 已确认方向 |
| --- | --- |
| 版本更新与项目采用耦合 | 区分版本内运行规则、根级发布/接入工具和项目自有数据。根级工具可独立修复，不强制更换项目 pin；运行规则变化仍需按项目采用边界加载和验证。根级 Router 的变更也须保持兼容，不能因位于根级就视为无影响。 |
| 根级工具独立更新后的运行身份 | 工具自动报告 `Framework Pin + Project Format + Root Tool Revision`，采用结果保留实际执行工具身份。复用现有 manifest/hash，将修订绑定到实际工具及依赖内容，不只记录手填版本号或单个入口脚本；不新增第三个项目 pin、逐任务填写或版本台账，也不要求根级工具更新后所有项目重新采用。 |
| 项目结构合同跟随发行版本变化 | 项目格式合同独立于 Framework 发行号；多个发行可以共用同一格式。格式版本声明基础结构保证，capability 只描述确实可独立变化的结构能力并核对实际数据，不重复声明格式已保证的内容。结构能力、功能启用和动作授权保持分离；不逐字段扩张 capability，不堆叠来源发行白名单，也不把结构匹配当作运行行为兼容证明。 |
| 注册、升级、同版本修复重复实现 | 共用现状读取、目标投影、差异计划、写前验证、按差异写入及写后检查。首次接入、已有项目升级和同版本修复是同一机制的不同输入；无差异时不改受管文件，不制造持久化事务或任务卡变化。 |
| 升级失败与用户扩展保留（优先） | 准备和预检阶段不写项目受管状态；Apply 的可捕获失败，包括写后检查失败，应恢复旧 pin、旧受管状态并验证旧有效规则仍可加载。逻辑提交点表示升级成功生效，不是 Git commit，单纯把 pin 放到最后写不足以保证原子性。进程被终止或断电时保留恢复材料，恢复完成前不得按混合状态继续工作；不承诺跨文件瞬时物理原子性。写入只覆盖声明的受管对象或区域，保留项目身份、事实、有效纠正及永久扩展；冲突在应用前报告，不能只保留文件却使规则失效。 |
| 内部模块化 | 对外保持单一 Framework 版本和项目 pin，内部按实际职责记录模块修订及依赖，发行固定完整组合。优先复用现有元数据，不建立动态模块下载、任意版本混装或包管理器；模块化不改变规则区块渐进加载流程。 |
| 脚本膨胀 | 用公共函数或少量内聚模块承载现状读取、目标投影、Diff、Preflight、Apply、Postcheck，入口只组织步骤；旧格式转换集中隔离。统一底层能力而非把三套大脚本拼成一个，不要求六个独立脚本，不建立通用迁移引擎或插件层；以减少重复和耦合为验收目标，而不是文件搬家或按大小拆分。 |
| 测试重复和串行前置依赖 | 场景独立建立前置条件；按变更模块和受影响依赖选择测试，支持测试组、案例及失败集合重跑。保留真实缺陷行为回归，替换脆弱的源码形状断言、删除确证重复；不直接从第 N 条依赖前序状态的断言续跑。 |
| 历史版本及兼容负担 | 在已确认没有外部使用的维护前提下，以整理后的当前候选作为新的支持基线。先解除现有项目、根级工具和测试对旧目录的依赖，再移除当前树及发行包中的旧版本与无消费者的兼容分支；保留 Git 历史，不重写历史。 |
| 项目纠正格式迁移 | 现有项目在自身 authority 下完成迁移，保留纠正 ID、原因、规则、边界、证据和有效行为。完成并验证后，不再为已退出的旧格式长期保留兼容支线；项目记录不复制进 Framework。 |
| 普通使用者下载包 | 只提供一个可解压使用的用户 ZIP，包含目标版本完整有效载荷、必要根级工具及依赖、canonical Router、中文 AI 指令、许可证与完整性信息。不包含真实项目状态、runtime 临时文件、Git 仓库或历史版本集合；不另做维护者包。 |
| 主动退出 | 可以说明有界退出与数据保留方式，但不把卸载再安装作为正常升级机制；本次不建设完整卸载系统。共享的宿主 Router 不能随一个项目退出被删除。 |
| 规划维护 | 通用方向只在现有 ROADMAP 保存，版本变化进入对应 CHANGELOG，当前执行状态由维护任务持有；不增设第二规划台账，不在 ROADMAP 复制逐轮 Review/试点状态。 |

### 比例性与不做项

Proportionality: existing=partial; classification=mixed; minimum_sufficient_fix=复用现有接入与恢复机制，统一受管投影、独立格式合同、依赖测试、支持基线和单一用户交付包; added_machinery=内部公共实现与现有元数据扩展，新增外部流程角色/服务/台账为0; escalation_trigger=重复升级阻塞、历史版本分支和验证重复已经在实际使用中发生。

不新增 actor registry、Reviewer pool、handoff/consumption ledger、服务、队列、后台轮询、per-tool hook、动态依赖管理器、自动升级、维护者下载包、完整卸载系统或额外平台 CI。不把普通讨论、实施或 Review 变成运行升级脚本的理由；幂等重跑只用于明确的接入、采用或受管状态修复。失败恢复、工具身份、格式能力和 ZIP 前置验证合并进这次整理，不拆成五套流程或五次发行；不为任意并发读取者引入全目录快照与统一指针架构。

### 启动后的依赖顺序

1. 一次确认具体实现范围、模块边界、格式合同和新的支持基线；此前保持本节待实施，不改变当前候选处理。
2. 优先建立预检无写入、部分 Apply 写入失败、写后检查失败和中断恢复的关键行为测试，再统一注册/升级共用实现；失败恢复验证须覆盖旧有效行为，不只检查 pin。
3. 拆分测试场景和依赖选择；实现期运行受影响测试。本次共用机制与测试组织重构，在候选冻结后完成一次完整验证；以后按实际影响复用绑定不变的证据，不宣称复用等于重跑。
4. 删除旧兼容代码和历史目录之前，用目标文件白名单生成临时用户 ZIP，在隔离测试项目中做新注册、受支持升级、同目标幂等重跑及恢复冒烟验证，暴露对 Framework `.git`、开发者 checkout 或旧目录的隐式依赖。它复用同一打包与测试能力，只是前移的轻量检查，不新增发布阶段，也不代表外部分发或真实项目采用。实现及相应审查、验证通过后，各项目仍须在自己的授权边界完成纠正迁移和接入验证；两方面前提齐备后才清理。
5. 清理后重新生成并验证最终实际用户 ZIP，确认隐式依赖已解除；项目自身的 Git 和工具运行时要求仍明确保留。
6. 保持既定顺序：候选实现 → 测试与独立审查通过 → 明确授权的本地试点 → 稳定后发布。试点反馈先判断根因；快照不变时复用证据，变更时只按实际影响补验证和相应审查，不逐问题自动追加小版本。

### 完成条件与证据边界

- 同目标重复执行不产生受管文件差异；同结构升级不做无意义的任务卡和配置重写。
- 逻辑提交前的普通失败恢复到旧 pin + 旧受管状态 + 旧有效行为；后者包括旧版本规则、仍有效纠正及永久项目规则的加载验证。异常中断可从保留材料恢复；恢复无法完成或发现并发修改时明确阻止混合状态继续执行，不覆盖第三方修改、不宣称回滚成功。
- 用户扩展及仍有效纠正继续正确加载，不只是原始文件仍在。
- 测试可按受影响模块及依赖选择，不漏跨模块集成；共用底层改变时相应扩大验证。
- 普通用户只需一个 ZIP 和中文 AI 指令；新包不要求手动拼装全部旧版本目录，也不声称已覆盖未经测试的平台。
- 工具执行及采用结果能定位实际 `Framework Pin + Project Format + Root Tool Revision`；用户包包含相应工具及依赖的修订与完整性信息，不用同名不同内容静默替换。根级工具独立修复不必改变项目 pin，结构能力匹配也不授予动作权限。
- 清理后当前项目、工具和测试不再暗中依赖旧目录；有价值的回归作为当前场景保留。
- 保留自然边界完整命中规则加载、连续工作复用、紧凑义务前置、上下文不确定时重载、过程 JSON 精简/清理及独立动作门禁，不另起流程体系。

本节是主控评估后的规划记录，不是独立 CRITICAL Review 结论，也不是实现完成、迁移完成、候选试点或发行证明。

## Future admission triggers

只有 project evidence 显示当前 minimum 无法安全表达真实失败时，才考虑后续版本：

- host-authenticated enforcement 只有在 host 提供可测试信号且机械 preflight 不足时才评估；
- Knowledge budget 只有在自然 DISCOVER/QUERY 使用证明 compact metadata 与三 ID 上限不足时才评估；
- project/model quality、rework、time/cost samples 保持 project-local，Framework 只可接收 anonymized conclusion；
- actor registry、Reviewer pool、handoff ledger、wait/ACK protocol、background service 或第二 status truth 需要新的 proportionality result 与 direct failure evidence。

future item 只有在 user 或 authorized maintainer 明确选择 version、scope、owner、evidence 与 Review route 后才进入 release，不预建 placeholder draft tree。

## Release history

### 1.16.0 — 先前 publication lineage

历史 remote refs 曾发布旧的 stable `1.16.0` payload。当前 local bytes 已重新进入 CANDIDATE，不能把历史 publication 当作当前 candidate 的 Review、seal、publication 或 adoption evidence。

### 1.15.1 — bounded current-pin adoption bridge

stable、consumable；保留单一 composer，并只对 exact 1.14.x `SELECTED_RULE_PACK_BUDGET_EXCEEDED` 提供受限 bridge。项目 adoption 仍独立。

### 1.15.0 — rule-block progressive loading 与 root navigation

stable、consumable；从完整 metadata catalog 选择 exact canonical Markdown blocks，保留 `LOAD_PLAN` support/fallback，引入 host-global navigation-only Router 与 actor-bound task-last upgrade。

### 1.14.1 — bounded loading 与 proportional release

stable、consumable；catalog 只作 internal resolver input，固定 Framework-controlled context budget 与 Windows LF checkout policy，明确 affected tests、一次 freeze suite、independent Source Review 与 separate `OWNER_ACCEPT`。

### 1.14.0 — prompt-bound navigation 与 bounded domain external

stable、consumable；引入 `AuthorityContext`、`IntentEnvelope`、schema2 corrections、repo-local Router 与严格 DOMAIN_OWNER local external batch。

### 1.13.0 — progressive process requirements

stable、consumable；建立唯一 `PROCESS_REQUIREMENTS_RESOLVE` front door、`DISCOVER / ADMIT_ACTION / FINALIZE_OUTPUT` 与三源 composer。

更早版本的完整历史以 immutable version payload、Git history 与对应 release metadata 为准；本 roadmap 不复制旧版规范。
