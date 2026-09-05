# Project control

<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:BEGIN -->
项目 repo-local `.ai-workspace/project.json.frameworkVersion` 是唯一 version-selection authority。Framework root 不保存 consumer record，也没有 global default selector。

## Registration

root `scripts/register-project.ps1` 要求显式 exact version 与 Controller ID。任何项目写入前必须校验：

- target `VERSION.json` 为 `STABLE`、consumable 且 pin-eligible；
- target `RELEASE_MANIFEST.json` 匹配 canonical payload，且 source Review 为 approved；
- target `project-starter` inventory 精确；
- destination Git top、path 与既有 control-plane condition 安全；
- selected version 的 `TOOLCHAIN.json` 精确，`pwsh` 满足唯一 official `powershell7` backend，且该 backend 声明当前 host platform。

工具只物化 selected version 的 `project-starter`。对 `1.16.0`，starter 写入 `frameworkToolBackend=powershell7`、空 `.ai-workspace/process-policy.json`、单一 project-config locator，以及项目选择的 `selectedRulePackBytes`；缺省值为 `32768`，不得超过 Framework absolute cap `98304`。starter 是可复用 project process，registration 不发明第二套流程。

registration 还对 repository root `.gitignore` 做幂等投影：复用已有等价 `.ai-workspace/runtime` rule；不存在时只追加 `/.ai-workspace/runtime/`；相反 negation 必须 fail closed。该写入与 control-plane material 同属可恢复 transaction，并保留原 newline style。
<!-- AIW-REQUIREMENT:PR_PROJECT_REGISTRATION_EXPLICIT_VERSION:END -->

<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:BEGIN -->
## Upgrade

root `scripts/upgrade-project.ps1` 要求 caller 提供 `RepositoryPath`、`ControllerId` 与 exact `ToVersion`。写入前校验 target release，接收 migration matrix 声明的健康 schema3 source，并保留：

- project ID 与 display name；
- repo-local layout 与 repository root；
- Controller ID、epoch 与 state；
- routine exclusions 与 capabilities；
- Bootstrap project custom region。

升级到 `1.16.0` 时，还投影 target starter 的项目级 backend、`selectedRulePackBytes` 与 runtime ignore rule，并在 recovery 或 project mutation 前要求 PowerShell 7 与 declared platform。backend 由所有任务继承，不复制进 authorization package；既有 `projectConfigIdentity` binding 会在该字段变化时使 package 失效。

对支持的 direct source，升级不得先让 current-pin resolver 决定成败。工具在 system temp 中创建隔离 Git projection，先写入 target project、Bootstrap、corrections、process policy、已迁移的 task `actor + role + phase` route 与项目预算，再调用 target `PROCESS_REQUIREMENTS_RESOLVE/DISCOVER`。只有完整 target selected pack 在项目选择预算内 PASS 时，才可准备实际 transaction。这样 1.11/1.12 两字段任务卡或旧 pin 的较低预算不会形成 target-before-pin deadlock。projection 只产生机械证据，不授予 write，也不替代 actor-bound package、exact object check、protected path、user decision、transaction recovery 或 task-last live-object stop。

只有声明的 managed objects 会改变。工具不搜索 consumers，不修改 source/product file，不 stage/commit/push，也不更新其他项目。

`1.16.0` starter 以 current task 的 actor/role/phase Work route 作为 loader input，并用唯一 process-policy carrier 保存 permanent project-specific process rules。它不把 task state 移入 Framework root，不创建 consumer record，也不把 task index 变成第二 authority。

local candidate pilot 在任何 project preflight 前重算 candidate payload，并要求 manifest 声明、完整套件证据及独立 Source Review evidence 全部绑定同一 canonical。本地候选/schema4 的安装完成由既有 recovery state 的 `transactionComplete=true` 证明：先保存 false，全部 live postimages（task 最后）匹配后，只登记此完成标记并结束原 exact 事务，不追加其他项目工作。未登记成功由原恢复路线续完；不得通过历史升级任务仍在 active、任务缺失或聊天结论猜测完成。日常任务恢复不依赖旧升级任务的位置或全文。

实际 project mutation 的 schema3 authorization 必须额外绑定当次 `canonical + manifestIdentity`；candidate 或 manifest 任一字节变化都会拒绝旧 package。

已经 pin 到当前版本的项目若因 `.ai-workspace/process-policy.json.selectedRulePackBytes` 过小而在 `DISCOVER` 自锁，可使用 root upgrader 的 `-RepairSelectedRulePackBudget`。preview 只报告 configured/required/proposed 并在隔离投影中证明新 policy 可通过；apply 只接受当前 Controller task、精确单一路径 `CONTROL_WRITE` package、实际超限原因和 `<=98304` 的项目选择值，且只替换该字段。正常 resolver 可工作、对象漂移或投影不通过时不得进入该窄通道。
<!-- AIW-REQUIREMENT:PR_PROJECT_UPGRADE_ACTOR_BOUND:END -->

<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:BEGIN -->
## Progressive process requirements

`PROCESS_REQUIREMENTS_RESOLVE` 是所有 Framework-governed work 的唯一入口。`DISCOVER` 组合 sealed Framework requirements、仍有效 corrections 与 permanent project rules，但不合并其 authority。`ADMIT_ACTION` 在独立 action 前校验 preparation；`FINALIZE_OUTPUT` 在最终输出前校验 actual result 与 delivery。source/decision receipt 是 ephemeral、non-authoritative artifact。

新项目使用 `.ai-workspace/process-policy.json`，其中 `selectedRulePackBytes` 由项目在 `1..98304` 内选择。runtime 只按该项目值判断 selected pack，Framework absolute cap 只是上界；不再保留 ordinary/absolute/legacy 三档运行时豁免。

存在真实 PROJECT-CUSTOM rules 的 legacy project，在一个经过独立 Review 的 atomic migration 同时写入 structured carrier 并退役已迁移 normative bytes 前，继续把该 region 作为 bound project-rule source。empty-source claim 与 dual-carrier rule 必须 fail closed。不增加 role、service、registry、poller、ledger 或 executable project DSL。

structured project rule 可直接内联，也可绑定项目现有标准文档的全文或唯一 marked section，并声明有界依赖。来源正文仍由项目拥有；policy 只保存选择器、locator、whole-file identity、section mode、依赖与 decision evidence。composer 在选择前验证来源，未命中的正文不进入模型；来源漂移时旧 selector/section 失效并保守加载当前全文，等待项目按普通规则维护流程重新绑定。不得为此复制第二份规范正文或扫描整个项目。

三源 selectors 使用 `TOOL_CONTRACT.md` 的同一匹配合同：明确声明的确定性触发不再被关键词否决，原结构边界仍逐项匹配；旧字段解释不变，不自动转换项目记录。新增字段改变当前 source identity，旧 receipt 与旧精确吸收映射不得沿用。
<!-- AIW-REQUIREMENT:PR_PROCESS_REQUIREMENTS_THREE_SOURCE_COMPOSITION:END -->

<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:BEGIN -->
## Tool backend

`TOOL_CONTRACT.md` 定义 language-independent operations，`TOOLCHAIN.json` 把它们映射到 sealed entrypoints。Framework `1.16.0` 只提供 `powershell7`；host/AI 直接解析并调用 entrypoint。不增加 launcher、task-level backend choice、runtime generation 或 automatic installation。未来 backend switch 属于 project-level adoption，只有 release 含第二个 official backend 时才可暴露。
<!-- AIW-REQUIREMENT:PR_TOOL_CONTRACT_BACKEND:END -->

<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:BEGIN -->
## Controller lifecycle

machine truth 是 `controller.json`。handoff 冻结 old/new identity 与 epoch；有授权时先写 hot projections，最后写 Controller object，并以 `TAKEOVER_COMPLETE` 结束。old read-only grace 可以为 recovery 保留 bytes，但不保留长期 routing authority，也不授权 cleanup。
<!-- AIW-REQUIREMENT:PR_CONTROLLER_HANDOFF_DIRECTIONAL:END -->

<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:BEGIN -->
## Knowledge capability

Knowledge reference 仍为 optional、project-local、non-authoritative。`DISCOVER` 返回 compact metadata；`QUERY` 在 request scope 最多校验三个 selected IDs。只读 changed-authority impact check 帮助 owning task 在正常 acceptance boundary 刷新或标记 stale entry。不增加 background service 或 automatic write；Knowledge 不能改变 product facts、task authority 或 Framework pin。
<!-- AIW-REQUIREMENT:PR_KNOWLEDGE_REFERENCE_LIFECYCLE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:BEGIN -->
## Owner-first project work

project adoption 加载 `1.16.0` starter 与 task contract，但不批量重写 existing task card 或 session。在未变化的 domain task 内，DOMAIN_OWNER 直接选择 temporary actor/Reviewer、签发新的 scoped package 并接收结果。PROJECT_CONTROLLER 只处理 Controller-owned next action，或 owner/public-decision、cross-domain-contract、protected-path、project-phase、Git/device/external、resource-conflict boundary。
<!-- AIW-REQUIREMENT:PR_OWNER_FIRST_DIRECT_DOMAIN_ROUTE:END -->

<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:BEGIN -->
## Project corrections

`.ai-workspace/corrections.json` 是独立 project authority object；它既不是 task card，也不是 permanent PROJECT-CUSTOM region。task 可以发现或更新 correction，但 task lifecycle 与 chat history 不控制其保留。

每条 record 保存 stable correction ID、introduced-against Framework version/range、observed failure/reason、effective rule、applicability boundary 与 decision/evidence locator。不设 partial-incorporation state。Framework `1.16.0` 保留 historical ID coverage；runtime suppression 只接受 payload-sealed mapping，且必须同时匹配 project-scoped alias、native requirement、catalog identity 与 canonical source-record identity。

effective project rules 是没有被 explicit pinned version 精确吸收的 correction records。incorporated record 继续作为 project evidence 保留，不重复应用也不删除。missing mapping、source drift 与 invalid coverage 会保留 correction；明确 declared conflict 在 pin write 前阻止 adoption。compatibility wrapper 评估只有 historical ID-level coverage 的旧 target 时，报告 `LEGACY_ID_ONLY_RETAINED` 并保持 record effective，不把粗粒度 metadata 当成精确证明。

coverage metadata 不是 semantic proof。release 只有在 effective requirement 已进入 load manifest 可达的 applicable normative modules、被 behavior tests 覆盖，并由 independent Review 对照 original reason/boundary 接受后，才可声明吸收 correction。不创建 correction-to-module registry 或 absorption ledger。

registration 创建一个空 corrections object。upgrade 在 pin projection 前校验并报告 incorporated、still-effective 与 conflicting records；保留 existing correction bytes 与 legacy PROJECT-CUSTOM bytes；对 customized legacy region 不自动添加 structured policy，并在 projection 后复检。采用旧版或 alternate version 时重新评估相同 records，绝不静默退役。
<!-- AIW-REQUIREMENT:PR_CORRECTIONS_V2_COMPATIBILITY:END -->
