# Framework 1.16.0 migration matrix

| Source | Target | 必需行为 |
|---|---|---|
| new project | explicit stable 1.16.0 | 读取 `ADOPTION_PROFILE.json`；要求 PowerShell 7、Controller ID 与 project-selected budget；在首个 repository write 前完整 render/validate/bind 可恢复 transaction；创建 schema4 config、schema2 corrections、process-policy 与 runtime ignore rule；只投影 managed `AGENTS.md` block，不安装 repo-local Skill |
| 任何旧 pin | 1.16.0 | 当前新基线不声明跨 pin direct source；不得因仓库中仍存在历史目录而自动进入旧版专属迁移分支 |
| root Maintenance 旧 control project | 1.16.0 | 没有旧来源白名单。已完成的1.16/schema4项目使用同 pin 幂等修复；更早结构如未来确需取回，使用Git历史中的专用迁移证据单独处理，不进入日常overlay |
| healthy schema4 1.16.0 | 1.16.0 | 通过 pinned release 校验 backend、project-selected budget、Bootstrap、Controller、corrections、runtime ignore 与 managed AGENTS；返回 already upgraded |
| managed AGENTS 或 repo-local Skill bytes 冲突 | 1.16.0 | preparation 前停止；不得 normalize、delete 或 replace project-owned/unknown bytes |
| 缺少 current actor-bound active task | 1.16.0 | 返回 `ACTOR_BOUND_PROJECT_UPGRADE_ROUTE_REQUIRED`；不得推断 actor 或批量重写 tasks |
| target profile 未声明兼容的 Project Format/capability | 1.16.0 | direct route blocked；不得按发行号猜测兼容性。1.16新基线的兼容集合为空 |
| normative `PROJECT-CUSTOM` | 1.16.0 | 在单独 Review 的 atomic migration 建立唯一 structured carrier 前继续保留其 authority；不得声称 legacy free text 已 compact selection |
| unavailable backend/runtime 或 unsupported platform | 1.16.0 | project write 前 fail closed；不 install、download 或 implicit fallback |
| downgrade | older release | 没有 automatic direct route；需要单独 Review 的 reverse migration |

adoption 由项目拥有，不改变其他 project pin，也不安装 host Skill。唯一 canonical Skill 位于 repository root `skills/ai-workspace-router/SKILL.md`；version 内 `host/skills/ai-workspace-router/SKILL.md` 只是 `VERSION_CONTRACT / REFERENCE_ONLY / NON_INSTALLABLE` 历史。

## Actor-bound upgrade contract

read-only plan 在任何 preparation write 前报告 sealed target canonical/manifest identity、全部 exact path/preimage、每个 live object 的 final identity 或 `ABSENT`、deterministic preparation/recovery paths 与 task-last 顺序。

schema3 package 必须精确绑定 `bundle=ACTOR_BOUND_PROJECT_UPGRADE`、`profile=CRITICAL`、`issuerRole=PROJECT_CONTROLLER`、`actions=[CONTROL_WRITE]`、Controller/task/project、完整 path/preimage set 与 live object 的 `postObjectIdentities`。`POST_OBJECT_DRIFT` 是 invalidator。跨pin兼容只能由 target profile 的 Project Format/capability 声明决定，不使用发行号白名单；1.16新基线没有跨pin direct source。root Maintenance adapter只处理当前sibling topology与overlay，不保留旧来源版本列表。

升级先建立 target projection：target project、Bootstrap、corrections、process-policy、`selectedRulePackBytes` 与 migrated task route 全部就位后，调用 target resolver。只有完整 selected pack 在项目 ceiling 内 PASS 才继续；旧 resolver 的 budget 或两字段格式不能抢先阻塞 target adoption。

apply 时，首写前复检 package，准备并校验 exact old/new/state material，原子提升到 formal recovery，再推进 live non-task objects，最后写 current task。stable/schema2 保持 task write 成功即 transaction terminal、之后零写入。本地候选/schema4 中 task 仍是最后一个 live project object；完整复核全部 live postimages 后，仅将既有 recovery state 的 `transactionComplete` 从 false 原子登记为 true，然后结束。同一授权事务内不得随后 cleanup、改业务/status 或写其他对象；完成记录未成功则试点未准入，按原 exact recovery 续完，不推断成功。

formal recovery 是 forward-only。resume 必须重证 target release、package identity、actor/task/owner、Controller ID/epoch、exact state tree 与 final postimages。live object 只能等于 original preimage 或 declared final identity；unknown/intermediate bytes fail closed。

## Progressive-loading migration

Framework-native rules 使用 schema2 fragments 与 exact Markdown blocks。`DISCOVER` 一次返回完整 selected blocks，并另给只含 binding/obligations 的 compact receipt。`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 复用 receipt。project policy 决定 runtime selected-pack ceiling，absolute cap 固定为 `98304`；不再使用 legacy tier exception。`LOAD_PLAN_RESOLVE` 只处理 non-rule support 与 bounded fallback。

新调用优先使用 schema3 `DISCOVER` 与 schema2 boundary input；旧 schema1/2 输入继续兼容。没有适用任务卡的只读项目讨论可声明 `PROJECT_READ_ONLY`，但只允许 `actionKind=NONE` 以及 PLAN/USER_RESPONSE，不产生 task 或 action authority。

project policy 的既有 inline rule 保持有效；项目可在自身 Review/接受边界内把规则改为 source-bound 文档全文或唯一 marked section。Framework 不自动转换项目文档。来源正文仍由项目拥有，receipt 绑定当前来源；相关来源不可读或区块异常时停止依赖动作，无关来源不阻断当前请求。

临时 actor 不要求批量改现有任务。Owner 可直接执行，也可在同一 task 下签发纯 action package；只有需要长期独立 outcome/context 时才创建 executor task。fresh package 不等于 FULL_COLD，Review 终态后也不需要 Reviewer 删除 package 或等待角色释放。

## 本地试点中的项目规则演进

已完成的试点以 recovery state schema4 区分安装证据与项目当前规则：`objects` 及 old/new 材料保留原事务；`projectionObjects.identity` 保留投影时的全文身份，Bootstrap 另有 `managedIdentity`，只固定 PROJECT-CUSTOM 正文之外的字节。task、PROJECT-CUSTOM、process-policy 和 corrections 的后续合法更新不要求回退到安装时内容；当前 composer 仍严格检查其 schema、唯一权威、规则、预算和当前身份。

这不是免授权入口。项目规则迁移仍由项目按当前任务、全文 preimage、Review 与接受边界实施；只改变试点历史绑定的复核口径。规则改变后旧 DISCOVER receipt 失效，正式交付用当前规则重新 DISCOVER；不得伪造收据或手改试点 state。框架管理区、project pin、候选 canonical/manifest 或其他受管理对象漂移仍停止。

初次试点先保存 `transactionComplete=false`，在包括最后 task 在内的全部 postimages 匹配后登记 true。日常恢复读取这个完成证明，不再读取历史升级任务的 active 或 archive 路径；归档不使安装失效。标记为 false 时，即便旧任务已缺失或已有新业务任务，仍不得准入；原 schema3 授权与 exact old/new 材料负责续完。旧 schema2/3 state 保持旧校验语义，通过既有、明确授权的候选刷新进入 schema4，不新增阶段、迁移脚本或后台同步。后续候选刷新先验证当前规则，再保留现有项目规则并绑定本次实际全文 preimage。
