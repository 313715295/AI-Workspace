# Framework 1.16.0 migration matrix

| Source | Target | 必需行为 |
|---|---|---|
| new project | explicit stable 1.16.0 | 读取 `ADOPTION_PROFILE.json`；要求 PowerShell 7、Controller ID 与 project-selected budget；在首个 repository write 前完整 render/validate/bind 可恢复 transaction；创建 schema4 config、schema2 corrections、process-policy 与 runtime ignore rule；只投影 managed `AGENTS.md` block，不安装 repo-local Skill |
| healthy schema4 1.14.1 | 1.16.0 | profile 声明的 direct source；绑定 current active adoption task、authenticated actor 与 schema3 `ACTOR_BOUND_PROJECT_UPGRADE` package；允许 task card schema 1.11/1.12 两字段 route 在 target projection 中迁移；移除且仅移除 sealed 1.14.1 repo-local Skill；task 最后写，之后零写入 |
| healthy schema4 1.15.0 / 1.15.1 | 1.16.0 | 使用相同 actor-bound task-last transaction；保留 project facts、Controller、rules 与 corrections；保持 root canonical Router 路线 |
| root Maintenance adapter 接受的既有 control project | 1.16.0 | source allowlist、sibling topology、`frameworkTarget`、legacy template 与 overlay 投影全部由 root `framework/maintenance-overlay/` 和 root upgrader验证；version profile只提供通用 target project contract |
| healthy schema4 1.16.0 | 1.16.0 | 通过 pinned release 校验 backend、project-selected budget、Bootstrap、Controller、corrections、runtime ignore 与 managed AGENTS；返回 already upgraded |
| managed AGENTS 或 repo-local Skill bytes 冲突 | 1.16.0 | preparation 前停止；不得 normalize、delete 或 replace project-owned/unknown bytes |
| 缺少 current actor-bound active task | 1.16.0 | 返回 `ACTOR_BOUND_PROJECT_UPGRADE_ROUTE_REQUIRED`；不得推断 actor 或批量重写 tasks |
| project pin 不在 `directSourceVersions` | 1.16.0 | direct route blocked；先采用受支持 stable intermediate version |
| normative `PROJECT-CUSTOM` | 1.16.0 | 在单独 Review 的 atomic migration 建立唯一 structured carrier 前继续保留其 authority；不得声称 legacy free text 已 compact selection |
| unavailable backend/runtime 或 unsupported platform | 1.16.0 | project write 前 fail closed；不 install、download 或 implicit fallback |
| downgrade | older release | 没有 automatic direct route；需要单独 Review 的 reverse migration |

adoption 由项目拥有，不改变其他 project pin，也不安装 host Skill。唯一 canonical Skill 位于 repository root `skills/ai-workspace-router/SKILL.md`；version 内 `host/skills/ai-workspace-router/SKILL.md` 只是 `VERSION_CONTRACT / REFERENCE_ONLY / NON_INSTALLABLE` 历史。

## Actor-bound upgrade contract

read-only plan 在任何 preparation write 前报告 sealed target canonical/manifest identity、全部 exact path/preimage、每个 live object 的 final identity 或 `ABSENT`、deterministic preparation/recovery paths 与 task-last 顺序。

schema3 package 必须精确绑定 `bundle=ACTOR_BOUND_PROJECT_UPGRADE`、`profile=CRITICAL`、`issuerRole=PROJECT_CONTROLLER`、`actions=[CONTROL_WRITE]`、Controller/task/project、完整 path/preimage set 与 live object 的 `postObjectIdentities`。`POST_OBJECT_DRIFT` 是 invalidator。普通 repo-local source 由 target profile的 direct source list约束；root Maintenance adapter另行验证其 source、layout、topology与overlay，不把这些专属条件写回version contract。

升级先建立 target projection：target project、Bootstrap、corrections、process-policy、`selectedRulePackBytes` 与 migrated task route 全部就位后，调用 target resolver。只有完整 selected pack 在项目 ceiling 内 PASS 才继续；旧 resolver 的 budget 或两字段格式不能抢先阻塞 target adoption。

apply 时，首写前复检 package，准备并校验 exact old/new/state material，原子提升到 formal recovery，再推进 live non-task objects，最后写 current task。task write 成功即 transaction terminal；不得随后 cleanup、改 status 或写 recovery。

formal recovery 是 forward-only。resume 必须重证 target release、package identity、actor/task/owner、Controller ID/epoch、exact state tree 与 final postimages。live object 只能等于 original preimage 或 declared final identity；unknown/intermediate bytes fail closed。

## Progressive-loading migration

Framework-native rules 使用 schema2 fragments 与 exact Markdown blocks。`DISCOVER` 一次返回完整 selected blocks，并另给只含 binding/obligations 的 compact receipt。`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 复用 receipt。project policy 决定 runtime selected-pack ceiling，absolute cap 固定为 `98304`；不再使用 legacy tier exception。`LOAD_PLAN_RESOLVE` 只处理 non-rule support 与 bounded fallback。
