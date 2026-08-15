# AIW-FW-1.6.0-A-C-G-MINIMAL-001 — Framework 1.6.0 minimal A-C + G rebuild

- 状态：APPROVED / OWNER_ACCEPTED / CANDIDATE_006 / WRITER_NONE / REVIEWER_NONE
- Task schema: 1.5.2
- 档位：CRITICAL；理由：共享Framework公共合同、项目配置schema、授权主控绑定、受保护路径Git入口与根迁移事务，影响多项目且失败代价高
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前 actor / writer：NONE / NONE
- Reviewer：`/root/fw_160_acg_review_4`（candidate006 final Review / APPROVED / 0 finding / RELEASED）
- Resource requirement: minimum=FOCUSED_HIGH; requiredTools=[filesystem|shell]; continuity=SAME_CONTEXT_IMPLEMENT; finalReview=FRESH
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=MINIMAL_A_C_G_CANDIDATE_006_APPROVED; expected_paths=[framework/drafts/1.6.0/minimal-candidate/AUTHORIZATION_MODEL.md|framework/drafts/1.6.0/minimal-candidate/CHANGELOG.md|framework/drafts/1.6.0/minimal-candidate/CONTROLLER_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/EXAMPLES.md|framework/drafts/1.6.0/minimal-candidate/FRAMEWORK_RELEASE.md|framework/drafts/1.6.0/minimal-candidate/GIT_AND_EXTERNAL.md|framework/drafts/1.6.0/minimal-candidate/HOST_CODEX.md|framework/drafts/1.6.0/minimal-candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/MIGRATION_MATRIX.md|framework/drafts/1.6.0/minimal-candidate/PERSPECTIVE_LENSES.md|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONFIG_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/minimal-candidate/project-starter/.gitattributes|framework/drafts/1.6.0/minimal-candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/minimal-candidate/project-starter/controller.json|framework/drafts/1.6.0/minimal-candidate/project-starter/project.json|framework/drafts/1.6.0/minimal-candidate/project-starter/PROJECT.md|framework/drafts/1.6.0/minimal-candidate/project-starter/RELATIONSHIPS.md|framework/drafts/1.6.0/minimal-candidate/project-starter/REVIEW_PROFILE.md|framework/drafts/1.6.0/minimal-candidate/project-starter/STATUS.md|framework/drafts/1.6.0/minimal-candidate/project-starter/tasks/README.md|framework/drafts/1.6.0/minimal-candidate/PROMPTS.md|framework/drafts/1.6.0/minimal-candidate/README.md|framework/drafts/1.6.0/minimal-candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/REVIEW_AND_EVIDENCE.md|framework/drafts/1.6.0/minimal-candidate/scripts/check-authorization.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/check-task-card.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/invoke-protected-safe-git.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/minimal-candidate/STATIC_COMPARISON.md|framework/drafts/1.6.0/minimal-candidate/TASK_AND_SCOPE.md|framework/drafts/1.6.0/minimal-candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/minimal-candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/minimal-candidate/VERSION.json|framework/drafts/1.6.0/minimal-root/INITIALIZATION.md|framework/drafts/1.6.0/minimal-root/scripts/register-project.ps1|framework/drafts/1.6.0/minimal-root/scripts/upgrade-project.ps1]; actual_paths=[framework/drafts/1.6.0/minimal-candidate/AUTHORIZATION_MODEL.md|framework/drafts/1.6.0/minimal-candidate/CHANGELOG.md|framework/drafts/1.6.0/minimal-candidate/CONTROLLER_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/EXAMPLES.md|framework/drafts/1.6.0/minimal-candidate/FRAMEWORK_RELEASE.md|framework/drafts/1.6.0/minimal-candidate/GIT_AND_EXTERNAL.md|framework/drafts/1.6.0/minimal-candidate/HOST_CODEX.md|framework/drafts/1.6.0/minimal-candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/MIGRATION_MATRIX.md|framework/drafts/1.6.0/minimal-candidate/PERSPECTIVE_LENSES.md|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONFIG_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/minimal-candidate/project-starter/.gitattributes|framework/drafts/1.6.0/minimal-candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/minimal-candidate/project-starter/controller.json|framework/drafts/1.6.0/minimal-candidate/project-starter/project.json|framework/drafts/1.6.0/minimal-candidate/project-starter/PROJECT.md|framework/drafts/1.6.0/minimal-candidate/project-starter/RELATIONSHIPS.md|framework/drafts/1.6.0/minimal-candidate/project-starter/REVIEW_PROFILE.md|framework/drafts/1.6.0/minimal-candidate/project-starter/STATUS.md|framework/drafts/1.6.0/minimal-candidate/project-starter/tasks/README.md|framework/drafts/1.6.0/minimal-candidate/PROMPTS.md|framework/drafts/1.6.0/minimal-candidate/README.md|framework/drafts/1.6.0/minimal-candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/REVIEW_AND_EVIDENCE.md|framework/drafts/1.6.0/minimal-candidate/scripts/check-authorization.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/check-task-card.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/invoke-protected-safe-git.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/minimal-candidate/STATIC_COMPARISON.md|framework/drafts/1.6.0/minimal-candidate/TASK_AND_SCOPE.md|framework/drafts/1.6.0/minimal-candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/minimal-candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/minimal-candidate/VERSION.json|framework/drafts/1.6.0/minimal-root/INITIALIZATION.md|framework/drafts/1.6.0/minimal-root/scripts/register-project.ps1|framework/drafts/1.6.0/minimal-root/scripts/upgrade-project.ps1]
- Stable candidate: `framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|626|E6B2637DE470F81D96FD9E9934AA53BA4716B75202106D8302F4FB1A02188547`；candidate006 payload=`34 files / 180511 bytes / 057D18A156C444DF4D81649979F4E4E2098945CFE766B646E594C41D44783590`；状态=`APPROVED / OWNER_ACCEPTED / DRAFT_NOT_CONSUMABLE`
- Phase gate: FALSE
- A-C+G implementation gate：APPROVED / OWNER_ACCEPTED；Framework release gate仍FALSE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 目标：从immutable Framework 1.5.2与current stable root建立全新的minimal候选，只实现减法PLAN保留的A-C+G合同与D/E短规则；candidate004及更早实现树只作审计输入。
- 唯一范围权威：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md|33399|26CD64F422139EAC9E8FBFAA318521DB3E6D47F8EC23BA1D094D65B44906103F`。
- 父任务：`framework/drafts/1.6.0/FRAMEWORK_TASK.md`；本卡只保存本实现范围、证据上限、停止线和current状态，不复制PLAN全文。
- 用户决定：2026-08-15用户接受减法方案，并明确允许按既定顺序推进；常规控制、实现、测试与收口无需逐次确认，出现停止线再回报。
- Route-004用户决定：2026-08-15用户确认`routineExcludedPaths`只承担日常不展示/不操作，不再承载六能力安全策略；升级只在独占维护窗口串行运行，取消第二套并发事务和脚本内递归自动清理；统一语言通用规则并入现有模块，Pocket术语权威与知识初始化进入1.6发布后的采用顺序。candidate002与Route-003 partial delta不得继续局部补条件。
- baseline release：`framework/versions/1.5.2/RELEASE_MANIFEST.json|699|840130FCC94485BC358796152DAB3619756BECA4E8FDB253EA9133964CA783B3`；31-file payload=`194871 bytes / canonical 3DB3DB7DD90780C0E66203C5F31A4D77B9FDCDCEB206E3A9743C2EE2156A6AA0`。
- root sources：`INITIALIZATION.md|7183|3FE6D6C28582862E1EC54BB9E233DACE092B3177A64A71DF23205379927CE810`；`scripts/register-project.ps1|22358|6AE4FD80FB25653FA4606961EED8CD1B652F4A791E9D445C04E9B473E83CC6B1`；`scripts/upgrade-project.ps1|48080|679F4D0B2519EA4777566ED5A48F89F6AD0451DB489EFDAF6A5C6BB8F9F43C9B`。
- redesign base：`A_C_G_MINIMAL_CANDIDATE_001`保持reviewed preimage；current `A_C_G_MINIMAL_CANDIDATE_002`在同一minimal树完成重建，未从旧`candidate/** / lean-candidate/**`回流。
- inventory：candidate exact35=`stable exact32 - tests/run-hotfix-tests.ps1 + new exact4`；root draft exact3；implementation未写本卡、父卡、PLAN、draft根VERSION、live root或stable版本。
- candidate005完成后预期byte-identical exact5：`PERSPECTIVE_LENSES.md / project-starter/.gitattributes / project-starter/RELATIONSHIPS.md / project-starter/tasks/README.md / scripts/check-task-card.ps1`。
- candidate005完成后预期modified-from-baseline exact26：其余shared stable对象；其中`project-starter/PROJECT.md`因旧“保护路径”第二真相改为日常排除locator，`project-starter/REVIEW_PROFILE.md`因统一语言Review语义变更，`RELEASE_MANIFEST.json`在writer release时生成。
- current new exact4：`CONTROLLER_SCHEMA.json / PROJECT_CONFIG_SCHEMA.json / project-starter/controller.json / scripts/invoke-protected-safe-git.ps1`；已删除的`ProtectedPolicy.psm1`不属于final inventory。
- omitted exact1：`tests/run-hotfix-tests.ps1`不进入1.6 inventory；仍适用的task/auth/load/register/upgrade兼容负键并入唯一`tests/run-framework-tests.ps1`。
- 实现结果：candidate006唯一runner快速门`93/93 PASS`、完整门`131/131 PASS`；新增负键证明所有literal元字符在Git启动前返回`UNVERIFIED`，register拒绝非空capability。旧target两对象与1.6三对象仍共用同一事务/恢复引擎。该证据不替代独立Review或真实项目采用。
- Route-004 working range仍以exact39封闭所有current直接消费者与待删除对象；owner必须先完成只读consumer/pathset冻结，再把精确delta、final exact38、验证和停止线写回本卡。至少覆盖Git/config/starter/Bootstrap/recovery/docs/manifest/tests/root register+upgrade以及统一语言的`TASK_AND_SCOPE / REVIEW_AND_EVIDENCE / TASK_TEMPLATE`，不得漏掉直接消费者。
- Route-004 implementation exact24已冻结，final inventory=`candidate exact35 + root exact3 = exact38`；`scripts/ProtectedPolicy.psm1`是唯一删除对象，不新增路径：
  - `minimal-candidate/AUTHORIZATION_MODEL.md|6105|A2FC6CE3E6CEF1F02BD567F69881B5861F16B5670C681E1A098135991A6445D2`
  - `minimal-candidate/CHANGELOG.md|1288|CFD26185FD00E32E845DCF64774D3A9C54F425679868E636C6131D6E34BFEC1B`
  - `minimal-candidate/EXAMPLES.md|6081|326D16037A811E46801070013DE87F9A9932175F88014D4F0283FBBAD84534B0`
  - `minimal-candidate/FRAMEWORK_RELEASE.md|2165|A4624B1D854F6E244003F0331D975C0A16E8598130588BBA3256736676B827B5`
  - `minimal-candidate/GIT_AND_EXTERNAL.md|5851|5E3E15C163050E9E9AF1C1E4238B03B2EEBD604D71C82489D5A953748E2AC6CC`
  - `minimal-candidate/MIGRATION_MATRIX.md|1667|8921A291999E7BA50A23885E13C0F6280F677FB2E995E555D80FCA843AEF7F7D`
  - `minimal-candidate/PROJECT_CONFIG_SCHEMA.json|1506|67B07D82BFAD595D9C1B01273281C962593F43F26629AF2AB81FF1274E05E96B`
  - `minimal-candidate/PROJECT_CONTROL.md|5919|3A8EBF21F093ECD4127230ADE6606749A4A01F10C31F3469FF98005F19FDEA05`
  - `minimal-candidate/project-starter/BOOTSTRAP.md|3815|5F09A6A37C892F899EDF7680E814E98F936ED87FCF2A5ABAF22B3CD56B4E6A58`
  - `minimal-candidate/project-starter/project.json|263|938086DA9DC6AEA95FDB8BA6E7E56518A9BFFBB572C126B0FC92A0A48C05B613`
  - `minimal-candidate/project-starter/REVIEW_PROFILE.md|1785|851509EA105A5F2EEED8FD2E3853F4C1C8A0FB076F2D00D307F411EB4472FA87`
  - `minimal-candidate/project-starter/STATUS.md|1202|8ACAB4D925F41C47FC1C16F24A5C2C7DCA656C83C03AC74B5839709EC40D966F`
  - `minimal-candidate/README.md|1004|5F4355E6A880438F5B8696022AA4DEC09A0AF95AC861D1573F3397834A9F7EAF`
  - `minimal-candidate/RECOVERY_CORE.md|10126|F351D7D456F284FD4B343B1FD7FF4C14DBE4D5A6DA017E061FBA87A46A01695A`
  - `minimal-candidate/RELEASE_MANIFEST.json|626|711C270FBFC46677ECA9B90416CD348ECFB3E8F73F52969EB53024AA1284E07A`
  - `minimal-candidate/REVIEW_AND_EVIDENCE.md|9732|0F34B2F25F9BB21127E4FF887B456A5072987FD02D4E01F0500D164CEC81E56E`
  - `minimal-candidate/TASK_AND_SCOPE.md|12273|8D7A2AB2F8B0E908C4C6744872678E4207EE4A42B9542EDA3C159FB4668EFAE4`
  - `minimal-candidate/TASK_TEMPLATE.md|7521|ED00D0765C3DE3E98A8CE49336A910B8EEE1F6F54DC03B44E3BC107079A36526`
  - `minimal-candidate/scripts/invoke-protected-safe-git.ps1|6922|B10CA2F3F57052F56BA53DA18FA15324FC17031AD10D3FDDF2BB4410F360CFFF`
  - `minimal-candidate/scripts/ProtectedPolicy.psm1|3734|05ABE63FBA080F39E4EF0F61495B7D296EF0275308106E3EA851D1C8D3206EA4|DELETE`
  - `minimal-candidate/tests/run-framework-tests.ps1|36309|9904CD1898EBE3E8A6115C68AC9C52D3A267FCB4BFA6AACC770DD19945E40FCD`
  - `minimal-root/INITIALIZATION.md|8041|A7E5D868B0852780E12867DCD8A763C1DC36EE9E3823B6E1AFC2BA2182946942`
  - `minimal-root/scripts/register-project.ps1|24462|EFA339C94E6344184B46B3BC46805435DA7DB963C186134ACD761F398A4D86BA`
  - `minimal-root/scripts/upgrade-project.ps1|72096|28AABFFDF179B3362ED1910033354CDFDA1C24C099DF933DB1770EBE7F6D52BB`
- partial delta：`scripts/ProtectedPolicy.psm1`的positive segment改动与`minimal-root/scripts/register-project.ps1`的staging保留尚未测试/Review，不是新路线producer；实现时按Route-004整体替换或删除，不保留其设计权威。
- 唯一下一动作：回父任务按已批准顺序打开knowledge F独立实现范围；A-C+G不再写。Git、release、CURRENT与Pocket采用仍分别关闭。

### Route-004 implementation closure

- `routineExcludedPaths`已成为唯一日常排除配置；`ProtectedPolicy.psm1`已删除，deny矩阵、glob保护语义、第二策略真相均不存在。它不提供保密或source授权；常规入口默认排除，只有exact exclusion可显式覆盖，失败返回`UNVERIFIED`。
- 1.4.1/1.5.0/1.5.1/1.5.2到1.6.0只在独占维护窗口串行迁移`project.json / BOOTSTRAP.md / controller.json`；无第二并发事务、capture/quarantine双树或脚本内递归自动清理。完成或回滚材料移动到唯一recovery目录，等待项目FULL_COLD后另行exact housekeeping。
- 统一语言治理已并入现有`TASK_AND_SCOPE / REVIEW_AND_EVIDENCE / TASK_TEMPLATE / PROJECT_CONTROL`：仅`BIND / CHANGE`声明canonical term、authority locator、跨文档/代码/UI映射与alias退出；不新增checker、schema、service或常规任务负担。
- Pocket发布后采用顺序已冻结为：`pin/control schema → routine exclusions → 项目术语权威 → 项目知识初始化 → 显式启用知识能力 → 去重瘦身 → FULL_COLD → 恢复任务与自然采样`。
- candidate005唯一runner最终`129/129 PASS`；覆盖四来源preview/apply/repeat、旧target共享事务恢复、三对象断点回滚、未知live bytes保留、遗留preparation保留、reparse拒绝、结构化日常排除、exact覆盖、Git失败`UNVERIFIED`、全部current Markdown旧保护策略术语零残留、strict/inventory/manifest、1.5.2/live roots/CURRENT零漂移。真实release、CURRENT、Pocket采用、真实remote仍未授权或验证。
- final inventory=`candidate exact35 + root exact3 = exact38`；root identities：`INITIALIZATION.md|8665|F8CC1FB4F2E7591D6E335CE0B20A15048303B7BE922D531E7EDF9C8A7B84D361`、`register-project.ps1|24196|AB32A0EB4AE29EF229E76CC85C2AD95901D73D4E3E0F6DE9528FBC4E81D74097`、`upgrade-project.ps1|46405|E55A72A4EC420C182AE3E5956449D67B6E5216DADCC6B79C5E36C47FC3842EB1`。
- writer与Reviewer均已释放；candidate005 implementation/test/Review authorization在本控制同步后删除。唯一下一动作=ROUTE_STOP下的owner/user路线裁决；Git、release、CURRENT、knowledge F与Pocket采用继续关闭。

### Route-004 final Review verdict 与 owner 裁决

- verdict=`CHANGES_REQUESTED / 2 HIGH(REPEATED) / 1 MEDIUM`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact38、child/parent/auth末次复证无漂移，Review只读且未运行candidate tests/Git/external。
- HIGH 1：`CHANGELOG / FRAMEWORK_RELEASE / STATIC_COMPARISON`仍把已删除protected-policy写成current合同。owner=`REMOVE`：仅删除三处current旧合同并增加零有效旧术语测试，不恢复module/schema/checker/service。
- HIGH 2：`upgrade-project.ps1`仍并存`.framework-upgrade-transaction`与`.framework-1.6-upgrade-transaction`两套状态/恢复/提交实现。owner=`REDESIGN`：保留唯一`.framework-upgrade-transaction`骨架并参数化为2/3对象；1.6复用同一state/material/recovery/commit，删除全部`Minimal16`函数、目录与fixture；完成/回滚材料保留，不递归自动清理，不增加wrapper/ledger/capture/quarantine。
- MEDIUM：配置producer只做结构存储，真正path规范由bounded consumer使用时校验。owner=`SIMPLIFY`：删除本卡对producer canonical健康门的夸大；register/upgrade不新增共享validator，safe-Git继续在use-site失败为`UNVERIFIED`。
- remediation仍限制在原exact24；不得新增路径或职责。完成后重新生成manifest、运行唯一runner并冻结candidate004；再做一次fresh独立final Review。Git、release、CURRENT、knowledge F与Pocket采用继续关闭。

### Candidate004 final Review verdict 与 owner 裁决

- verdict=`CHANGES_REQUESTED / 1 HIGH(REPEATED) / 1 MEDIUM`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact38末次复证无漂移，Review只读且未运行candidate tests/Git/external。
- HIGH / REPEATED：`EXAMPLES`仍有“schema3保护策略/受保护边界/覆盖保护对象”中文旧合同，而零引用断言只扫描三份英文文档。owner=`REMOVE`：对current candidate全部Markdown做一次语义清查，exact9只改既有直接消费者、runner与manifest；不新增路径、module、schema、checker、service或流程节点。
- MEDIUM：本卡把实际byte-identical exact6误写为exact7并错误包含`project-starter/REVIEW_PROFILE.md`。owner=`CONTROL_CORRECT`：按candidate005实际delta同步为exact5，明确`PROJECT.md`与`REVIEW_PROFILE.md`的有意变更，不修改payload去追平错误摘要。
- candidate005 remediation exact9：`EXAMPLES.md / PROMPTS.md / RECOVERY_CORE.md / TASK_AND_SCOPE.md / TASK_TEMPLATE.md / project-starter/PROJECT.md / project-starter/STATUS.md / tests/run-framework-tests.ps1 / RELEASE_MANIFEST.json`。只移除旧保护策略措辞、扩大既有零残留断言、重算manifest；任何新机制或exact38外路径立即停止。

### Candidate005 final Review verdict

- verdict=`CHANGES_REQUESTED / 2 HIGH / 2 MEDIUM / ROUTE_STOP`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact38、child、parent与authorization末次复证无漂移，Review只读且未运行candidate tests/Git/external。
- HIGH / REPEATED：safe-Git使用点仍接受`assets/**`等无法作为literal安全表达的元字符路径，可能漏排除后代却返回`VERIFIED`；`EXAMPLES`同时描述了与actual相反的重叠行为。该类finding复发，禁止继续自动补丁链。
- HIGH：register的`ALREADY_REGISTERED`健康门未拒绝schema明令为空的非空`frameworkCapabilities`，与schema、upgrade和safe-Git消费者不一致。
- MEDIUM / REPEATED：历史控制段仍残留byte-identical exact7；actual独立分类为same exact5 / modified exact26 / new exact4 / omitted exact1。
- MEDIUM：任务冻结的五组load cap中三组低于actual，runner自行放宽阈值后仍报告PASS；owner必须先决定删重复文字以守旧cap，或用证据重新批准统一的新cap。
- candidate005保持`DRAFT / NOT_CONSUMABLE / NON_CURRENT / AUDIT_ONLY`；不授权返工、Review续轮、Git、release、CURRENT、knowledge F或Pocket采用。
- owner/user决定（2026-08-15）：不重新设计；只重开existing exact5=`safe-Git / EXAMPLES / register / runner / manifest`，分别闭合literal元字符拒绝、actual示例、schema3 capability空对象健康门和direct负键。控制卡同步actual exact5与一次性rebaseline load caps。若fresh final Review再次出现同类routine-exclusion finding，直接DEFER该能力，不再补丁。

### Candidate006 bounded closure

- exact5 delta未新增对象或职责：safe-Git在Windows路径API前拒绝`* ? < > " |`；EXAMPLES对齐默认排除/exact override actual；register复用schema3空`frameworkCapabilities`合同；runner新增元字符no-launch与非空capability负键；manifest重算。
- direct evidence：quick=`93/93 PASS`；full=`131/131 PASS`；首次full在功能均已`UNVERIFIED/no launch`时因系统异常reason不同未通过组合断言，随后仅把框架元字符门移到Windows路径API前，fresh full PASS。不得把首次失败隐去或解释为candidate通过。
- manifest独立复算=`34 files / 180511 bytes / 057D18A156C444DF4D81649979F4E4E2098945CFE766B646E594C41D44783590`；manifest identity=`626|E6B2637DE470F81D96FD9E9934AA53BA4716B75202106D8302F4FB1A02188547`。
- writer已释放；唯一下一动作=fresh independent final Review exact38。若同类routine-exclusion finding再次复发，直接DEFER该能力，不再返工。

### Candidate006 final Review 与 owner acceptance

- verdict=`APPROVED / 0 finding`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；stable 1.5.2 authorization、child/parent task checker、exact38 identities与manifest末次复证均PASS。
- reviewer独立确认literal元字符no-launch、EXAMPLES actual、register空capability、direct负键、baseline exact5与五角色load caps全部对齐；唯一upgrade事务、无递归自动清理、统一语言现有模块、Pocket采用顺序及DRAFT/no-leakage回归成立。
- owner=`ACCEPTED`；A-C+G candidate006自此冻结，不再接受control/source/test写入。该接受不授权Git、release、CURRENT、Pocket采用、knowledge F或真实外部动作。

## Scope closure

- producer：唯一implementation writer；只从stable 1.5.2和上列current root exact3读取。旧draft树不得成为源码、模板、helper或测试producer。
- direct consumers：loader；project Bootstrap；project/controller config readers；authorization pre-tool gate；Git/external owner；root register/upgrade；root initialization说明；唯一framework test runner；后续integration/release owner。
- A：project.json schema3仅保存`routineExcludedPaths: string[]`；它是日常恢复/搜索/Git不展示不操作合同，不是source权限或零内部读取安全承诺。Git入口接受固定config identity、操作枚举与bounded positive pathset，自动应用排除；无法可靠排除则`UNVERIFIED`。无deny矩阵、glob语义、`ProtectedPolicy.psm1`或第二路径语言。
- simple multi-remote：任务直接冻结stable candidate、唯一Git closer、remote/ref清单和一次阶段授权；每remote最多一次尝试并记录`SUCCEEDED / FAILED / UNKNOWN`。不建立DTO、schema、checker、ledger、自动retry或compensation。
- B：保持四个质量档；任务只写非默认minimum/tools/continuity，host dispatch选择实际资源。无binding文件、resolver、digest、capability snapshot或authorization资源字段；资源不足保持未分配，不静默降级。
- C/G：保留direct-owner/no-poll/terminal-only/exception-only、controller pull、single terminal reporter、no ACK chain与state dedup文本合同。`controller.json`是current controller/epoch唯一机器真相；PROJECT_CONTROLLER授权绑定controller ID/epoch/whole-file identity，DOMAIN_OWNER分支不承担controller字段。
- D/E：只在现有`PROJECT_CONTROL / TASK_AND_SCOPE / REVIEW_AND_EVIDENCE / HOST_CODEX`补短规则。实际peer复用才核project/domain/owner/role/lineage；问题不等于决定；建议变化必须给出新事实或明确纠错；同类finding复发必须`SIMPLIFY/REMOVE/DEFER/REDESIGN`；无真实调用消费者的checker不算已交付能力；统一语言只在`BIND / CHANGE`时绑定canonical term、authority locator、跨语言/代码映射和alias退出，不新增checker/schema/service。
- root migration：register对1.6要求ControllerId并生成schema3 project/controller；CURRENT仍为旧版本或显式1.4/1.5时保持兼容。1.4.1/1.5.0/1.5.1/1.5.2→1.6在独占维护窗口复用现有可恢复事务骨架处理project.json、BOOTSTRAP.md、controller.json；schema2来源只消费冻结的routine-exclusion migration输入；不扫描source、不枚举旧授权、不建第二事务引擎或脚本内自动清理。
- controller rotation：本阶段机械闭合controller identity与旧epoch授权拒绝；消息路由继续诚实标为文本/host边界，不用route checker声称宿主硬强制。
- F boundary：`frameworkCapabilities={}`仅为schema3空、不可启用的预留字段；knowledge module/schema/selector/content/common与Pocket初始化全部不在本任务。

## Verification

- baseline：候选byte-identical exact5与stable源逐字一致；其他对象只能从stable/current root派生；1.5.2、CURRENT、live roots零漂移。
- project-config：`routineExcludedPaths`只在schema/register/upgrade承担字符串数组、非空字符串与大小写去重等结构门；它不是权限或canonical-path证明。每个bounded consumer在使用时校验自身可接受的repo-relative literal路径，无效则`UNVERIFIED`。不得存在deny字段、policy module或glob保护语义。
- routine-safe Git：真实Git顶层、固定config identity、bounded positive pathset、日常排除不出现在输出/动作、exact单路径例外、命令失败`UNVERIFIED`、禁止整仓暂存和广泛retry；不宣称Git内部零metadata观察。
- authorization：1.6 DOMAIN_OWNER正例保持；PROJECT_CONTROLLER缺失/错误controller path、ID、epoch、identity、JSON类型或状态均拒绝；1.5.x包由frameworkVersion门拒绝；Review/write互斥与strict JSON回归保留。
- register兼容：默认`CURRENT=1.4.1`与显式1.5.2无需ControllerId；显式1.6缺ControllerId拒绝，合法1.6生成starter exact9、schema3 config和epoch1 controller；partial/reparse/unknown inventory fail closed。
- upgrade兼容：旧目标行为保持；四个直接来源版本分别做preview/apply/repeat；routine-exclusion migration identity漂移、managed/custom marker冲突、unknown/reparse与中断均no-success并保留恢复材料。只验证独占串行合同下的OLD/COMPLETED/INTERRUPTED恢复，不模拟合同禁止的并发控制写。
- interruption：测试runner可在隔离fixture的明确替换点终止进程并验证恢复；生产脚本不得增加环境变量/test-only bypass，也不得为测试引入capture/quarantine或对抗性并发状态机。
- routing/remote/resource：只做文档、模板、fixture和旧机制零有效引用验证；没有真实host/remote执行时不得声称机器强制或真实外部成功。
- old-tree exclusion：新candidate/root/loader/manifest/tests零import、零调用、零路径引用旧`candidate/** / lean-candidate/** / root-scripts/** / lean-root-scripts/**`。新有效代码不得出现`RemoteTransaction / PreviousLedger / COMPENSATION / RemoteBatch DTO / resourceBinding / check-controller-route / check-remote-batch / resolve-resource-binding / controller-revocations / check-peer-task-reuse`。
- strict/inventory：UTF-8/LF、JSON、PowerShell syntax、candidate expected/actual、manifest canonical、starter inventory、root draft exact3和removed hotfix runner absence。
- load topology：A-C+G不新增loader模块；`check-task-card.ps1`与Task schema 1.5.2保持逐字兼容。按current完整模块集合一次性rebaseline并与runner共用的成本上限：RECOVERY_CORE-only≤10905 bytes；DOMAIN_OWNER standard plan+implement+verify≤45000；EXECUTOR standard plan+implement≤36693；REVIEWER critical review≤38000；CONTROLLER critical recover+plan≤51000；FRAMEWORK_MAINTAINER full≤60479。后续超限先删重复文字，不由runner自行放宽，也不新增summary模块。
- evidence ceiling：direct/static/isolated fixture PASS不等于独立Review、真实Git remote、release、CURRENT更新、project pin或Pocket采用。

## Risk and stopline

- pre-mortem 1：旧candidate helper回流。检查：source locator与old-tree zero-consumer；命中即停止。
- pre-mortem 2：日常排除再次膨胀为安全系统。检查：无deny能力、policy module、glob语言或跨消费者大矩阵；source权限仍由任务授权承担。命中即删除/推迟该机制，不再自动返工。
- pre-mortem 3：根脚本改变旧版本注册/升级。检查：CURRENT1.4.1、显式1.5.2和旧target回归先于1.6正例。
- pre-mortem 4：三对象事务用生产test hook换取可测性。检查：脚本零test env/bypass，watchdog只存在test runner。
- pre-mortem 5：把文本route/remote/resource合同冒充机器强制。检查：没有真实consumer的能力只给静态证据上限，不添加checker。
- range stop：第40个working路径、任何deny/policy module/第二路径语言、第二升级事务引擎、capture/quarantine双树、递归自动清理、术语checker/schema/service、公共DTO/ledger/第二truth、新route/resource/remote checker、Task schema变化、loader模块增加、live root/stable/CURRENT/Pocket写入或真实Git/remote/external动作。
- Review stop：writer释放并冻结manifest后只允许一个fresh独立Review；最多一次合并bounded remediation和一次final Review。同类finding再次出现必须回owner做`SIMPLIFY/REMOVE/DEFER/REDESIGN`，不得继续局部补丁链。

## Current authorization

- current package=`NONE`；Route-004控制冻结包与关闭包均已消费失效并删除；actor/writer/reviewer=`NONE / NONE / NONE`。Git、external、release、CURRENT、knowledge F和Pocket权限仍未打开。

## Review-2 verdict

- verdict=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM / 2 REPEATED / ROUTE_STOP`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact39、child、parent与authorization末次复证无漂移。
- HIGH / REPEATED：唯一literal-path validator仍接受`assets/**`等含Windows非法或glob元字符的规则，但它不覆盖`assets/unit.png`；同类protected-policy语义finding再次复发，当前路线停止。
- HIGH / REPEATED：transaction末次inventory复证与递归目录删除之间仍可进入未知并发字节；先检查再递归删除不能证明实际删除对象，当前自动清理策略未闭合。
- MEDIUM：`TASK_AND_SCOPE.md`同时声明单域产品决定由领域owner直接问用户、以及所有产品结果交controller回用户，形成双路由。
- producer runner=`150/150 PASS`，但未覆盖上述两个反例；它不替代独立Review。候选保持`DRAFT / NOT_CONSUMABLE / NO_GIT / NO_RELEASE / NO_PROJECT_ADOPTION`。

## Review-1 verdict

- verdict=`CHANGES_REQUESTED / 2 HIGH / 1 REPEATED`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact38末次复证无漂移。
- HIGH / REPEATED：`PROJECT_CONFIG_SCHEMA.json`未表达register/upgrade/safe-Git实际拒绝的完整protected-path规范，测试矩阵也未消费schema；safe-Git未覆盖跨保护边界rename/copy可能在STATUS/DIFF/INDEX输出原保护路径。按stopline回owner `REDESIGN`，不得继续条件补丁链。
- HIGH：三对象upgrade在replace、controller delete与staging cleanup前缺少足以保留未知并发字节的fresh identity/inventory门；任何未知或漂移必须保留恢复材料并停止。
- evidence ceiling：candidate runner `128/128 PASS`仅证明已建fixture；真实Git、并发时序、release、CURRENT、Pocket与knowledge F仍未验证或打开。

## History locator

- superseded implementation：`framework/drafts/1.6.0/IMPLEMENTATION_A_C_G_LEAN.md|20018|BB4131396FD9D759776B3B2CD2FA16D03064B3306C939597754F0CF041F9C039`，状态=`NON_CURRENT / AUDIT_ONLY / NO_IMPLEMENTATION_AUTHORITY`。
- accepted reduction authority：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md|29101|BC6AA219B729FDD255A0AFCB163AB360EA24BC7072B1CE9DAD66C4CB452934DA`。
