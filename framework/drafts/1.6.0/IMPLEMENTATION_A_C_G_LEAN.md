# AIW-FW-1.6.0-A-C-G-LEAN-001 — Framework 1.6.0 clean-baseline A-C + G 实现范围

- 状态：SUPERSEDED_BY_REDUCTION_AUDIT / A_C_G_LEAN_CANDIDATE_004_NON_CURRENT_AUDIT_ONLY / NO_REMEDIATION / NO_IMPLEMENTATION_AUTHORITY / WRITER_NONE / REVIEWER_NONE
- Task schema: 1.5.2
- 档位：CRITICAL；理由：共享Framework公共合同、授权/Git安全、资源绑定、主控轮换、starter与根迁移事务，失败代价高
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前 actor / writer：OWNER / `NONE`
- Reviewer：Review-1=`/root/fw_160_lean_impl_review_1(CHANGES_REQUESTED / RELEASED)`；final Review=`/root/fw_160_lean_impl_final_review(CHANGES_REQUESTED / RELEASED)`；final Review-2=`/root/fw_160_lean_impl_final_review_2(CHANGES_REQUESTED / RELEASED)`；final Review-3=`/root/fw_160_lean_impl_final_review_3(CHANGES_REQUESTED / RELEASED)`；四者均未参与candidate写入
- Resource requirement: DEFAULT
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=A_C_G_LEAN_CANDIDATE_004_AUDIT_ONLY; expected_paths=[framework/drafts/1.6.0/IMPLEMENTATION_A_C_G_LEAN.md]; actual_paths=[framework/drafts/1.6.0/IMPLEMENTATION_A_C_G_LEAN.md]
- Stable candidate: `NONE`；audit-only manifest=`framework/drafts/1.6.0/lean-candidate/RELEASE_MANIFEST.json|667|EC66C8ABB6D0328BA9EFBAB97180A5C27A70F8654C95476BFF1FADB17C737AC9`
- Phase gate: FALSE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 目标：仅作为已停止的`A_C_G_LEAN_CANDIDATE_004`历史审计载体；不再授予实现、返工、Review、Git或发行权威。
- 唯一范围权威：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md|29101|BC6AA219B729FDD255A0AFCB163AB360EA24BC7072B1CE9DAD66C4CB452934DA`；新的最小实现范围将由owner另行只读冻结，本卡不是其producer。
- baseline release：`framework/versions/1.5.2/RELEASE_MANIFEST.json|699|840130FCC94485BC358796152DAB3619756BECA4E8FDB253EA9133964CA783B3`；scope fileCount=`31`、totalBytes=`194871`、canonical=`3DB3DB7DD90780C0E66203C5F31A4D77B9FDCDCEB206E3A9743C2EE2156A6AA0`。lean-candidate先建立包括manifest自身在内的stable exact32逐字副本；副本建立完成不等于1.6.0功能candidate。
- root baseline：`scripts/register-project.ps1|22358|6AE4FD80FB25653FA4606961EED8CD1B652F4A791E9D445C04E9B473E83CC6B1`；`scripts/upgrade-project.ps1|48080|679F4D0B2519EA4777566ED5A48F89F6AD0451DB489EFDAF6A5C6BB8F9F43C9B`。只复制到lean-root-scripts后修改。
- historical exact42：stable exact32副本、A-C+G新增exact8、root副本exact2，只用于重建失败路径和Review finding审计，不得复用为新范围或授权路径集。
- historical new exact8：`CONTROLLER_SCHEMA.json / PROJECT_CONFIG_SCHEMA.json / REMOTE_BATCH_SCHEMA.json / project-starter/controller.json / scripts/check-controller-route.ps1 / scripts/check-remote-batch.ps1 / scripts/invoke-protected-safe-git.ps1 / scripts/resolve-resource-binding.ps1`；其中多项已被减法审计决定删除或推迟。
- old-tree exclusion：`framework/drafts/1.6.0/candidate/**`、`root-scripts/**`与`IMPLEMENTATION_A_C_G.md`只能读作`NON_CURRENT / AUDIT_ONLY`证据；禁止复制、import、loader/manifest引用、测试调用或发行消费。旧树中的RemoteTransaction exact2+有效消费者exact10不逐文件返工。
- forbidden：`framework/versions/**`、`framework/CURRENT`、live `scripts/register-project.ps1`与`scripts/upgrade-project.ps1`、旧candidate/root树、父控制对象、任何项目repo/pin、Git stage/commit/push、网络/remote/external。

## Superseded A-C + G contracts

- 本节以下实现、修复和Review记录全部是`AUDIT_ONLY`历史证据，不构成当前合同或下一candidate基线。
- 减法审计保留：schema3 protected policy、bounded protected-safe Git、controller/epoch/PROJECT_CONTROLLER授权、默认直达协调与default-off项目知识能力。
- 减法审计删除或推迟：RemoteBatch DTO/checker/ledger、resource-binding文件/解析器/digest/授权耦合、controller-route JSON/checker、legacy revocation ledger、peer-reuse checker/carrier与公共slimming模板。
- D/E只允许在现有公共模块中形成短规则；H是Pocket采用后的项目任务。新的实际producer/consumer/test/migration集合必须由父任务另签，不得从本卡继承。

## Implementation result

- candidate identity：`framework/drafts/1.6.0/lean-candidate/RELEASE_MANIFEST.json|667|EC66C8ABB6D0328BA9EFBAB97180A5C27A70F8654C95476BFF1FADB17C737AC9`；scope=`39 files / 255465 bytes / canonical 306DADB942FF0FDA55D90BFCE90F2F76BC7C376E1F107D99C430076AEC2E188D`。
- direct suite：`RESULT 86/86 passed|scope=A-C+G|lifecycle=DRAFT_NOT_CONSUMABLE`；baseline compatibility：`RESULT 2/2 passed|scope=baseline-1.5.2-compatibility`。
- exact/inventory：lean candidate exact40与lean root exact2闭合，授权exact42全部存在；strict UTF-8/LF、JSON、PowerShell语法、release canonical、old-tree zero-consumer均PASS。
- stable zero drift：1.5.2 release manifest及其`31 files / 194871 bytes / canonical 3DB3DB7DD90780C0E66203C5F31A4D77B9FDCDCEB206E3A9743C2EE2156A6AA0`复算一致；live register/upgrade及`CURRENT=1.4.1`未改变。
- evidence ceiling：仅direct/static/隔离fixture与机械identity证据；不是独立Review、真实remote/Git、release、CURRENT或项目采用。candidate继续`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`。
- writer/reviewer：`NONE / NONE`；实现writer已释放，不再写candidate/root candidate。

## Independent Review-1 verdict

- verdict：`CHANGES_REQUESTED / 5 P1 + 1 P2`；Reviewer已释放，未写入、未运行candidate tests、未执行Git/remote/external/Pocket。
- P1 resource binding semantic：authorization checker只复证自洽digest，未重新证明minimum quality、required tools与continuity；需以唯一resolver语义重算或共享验证并增加自洽伪造负键。
- P1 resource binding output：resolver的OutputPath可覆盖任意已有/绝对/输入路径；需限定为repo-relative、fresh、非reparse的指定control temp locator并原子写入。
- P1 protected-safe Git：operation capability映射不完整且未证明ProjectRoot是真实Git顶层；需partial-deny与nested-root负键，任何相关deny均不得进入pathset。
- P1 controller route：sourceTaskId/responsibleReporter未绑定current task/owner，epoch 0仍可走stale exception；需current task/owner实证与epoch>=1负键。
- P1 upgrade admission：需严格schema2/duplicate/unknown、完整managed+custom marker/order、project/control/input no-reparse，并移除生产脚本可由外部环境开启的non-Git测试旁路，测试改用真实临时Git fixture或非发行注入层。
- P2 evidence：manifest仍写direct `53/53`，actual已为`54/54`；完成实质返工后统一为最终实际计数并重算canonical/identity。
- bounded remediation exact8：`scripts/check-authorization.ps1`、`scripts/resolve-resource-binding.ps1`、`scripts/invoke-protected-safe-git.ps1`、`scripts/check-controller-route.ps1`、lean root `register-project.ps1`与`upgrade-project.ps1`、`tests/run-framework-tests.ps1`、`RELEASE_MANIFEST.json`。不得增加第二resource matrix/route ledger、ACK链、自动retry/compensation或新职责路径。

## Remediation-1 result

- resource binding：authorization checker会从current task、policy与capability重新计算最低质量、必需工具、continuity与canonical core；自洽伪造的quality/tool/continuity降级均被负键拒绝。resolver输出只允许fresh repo-relative `.tmp/resource-bindings/*.json`，拒绝绝对路径、已有目标、输入碰撞、escape与reparse，并以fresh临时文件原子落盘。
- protected-safe Git：STATUS/DIFF/INDEX按Git可能消费的全部read-side capability取并集；任一相关deny即不进入pathset。执行数据命令前复证ProjectRoot就是实际Git顶层；partial-deny与nested-root负键均PASS，无广泛fallback。
- controller route：current task header与Owner是sourceTaskId/responsibleReporter的现场真相，original/target epoch均要求`>=1`；跨任务、非owner reporter与epoch-zero负键均PASS，不增加route ledger或ACK链。
- root migration：register/upgrade生产路径不再接受non-Git环境旁路；source schema2拒绝unknown/duplicate字段，Bootstrap要求managed+custom marker完整且有序，project/control/input链拒绝reparse，测试使用真实隔离Git fixture并证明拒绝时no-write。
- evidence closure：完整candidate suite最终`70/70`、baseline compatibility`2/2`；manifest的direct计数、39-file bytes与canonical已刷新。exact42、strict UTF-8/LF、JSON、PowerShell syntax、old-tree zero-consumer、stable 1.5.2与live roots/CURRENT零漂移均复证PASS。
- flow-weight ceiling：返工只修改冻结exact8；没有新增第二真相、ledger、ACK chain、自动retry/compensation、后台轮询或默认持久化字段。candidate仍为`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`。

## Final independent Review verdict

- verdict：`CHANGES_REQUESTED / 3 P1 + 1 P2`；final Reviewer已释放，全程只读，未运行candidate tests、Git、remote/external、release、CURRENT或Pocket。
- P1 resource consumption：quality/tool/continuity已能复算，但authorization checker尚未接收trusted observed phase/host/context identity；内部自洽的旧binding仍可能跨实际phase/context消费。最窄修复仅在既有checker加入三项现场比较和phase/context stale负键。
- P1 repeat-upgrade health：already-pinned 1.6.0分支可跳过non-leaf/reparse revocation，对schema3 project/controller/ledger也缺exact/duplicate/type门。最窄修复复用现有strict helper，在同一health branch fail closed并补no-write负键。
- P1 transaction final snapshot：多对象replace各自成功后，删除恢复材料前未再次复证exact4全部destination仍为NEW；早期对象可在后续replace期间漂移。最窄修复为删除transaction前一次existing exact4 final scan和确定性漂移负键。
- P2 template locator：`TASK_TEMPLATE.md`仍示例`.tmp/<TASK-ID>.resource-binding.json`，与resolver唯一合法`.tmp/resource-bindings/*.json`冲突；修正文档单行并增加静态兼容断言。
- owner decision：四项均收益显著且不需要新角色、审批门、ledger、ACK、轮询、后台服务或默认字段，允许最后一次bounded remediation exact5：`scripts/check-authorization.ps1`、lean root `upgrade-project.ps1`、`TASK_TEMPLATE.md`、`tests/run-framework-tests.ps1`、`RELEASE_MANIFEST.json`。若fresh final Review仍出现同类复发或需要第六职责路径，立即停止自动返工并升级用户。

## Remediation-2 result

- resource consumption：authorization checker新增trusted `ObservedPhase / ObservedHost / ObservedContextIdentity`，与binding现场逐字比较；缺失或phase/host/context stale均fail closed，既有quality/tool/continuity重算保持不变。
- repeat-upgrade health：already-pinned分支对schema3 project/controller/revocation做exact field、duplicate、type、protected-rule与regular-leaf/no-reparse验证；revocation可诚实absent，但任何存在的directory/reparse/unknown/duplicate/tamper均拒绝且no-write。
- final transaction snapshot：四次replace后、删除恢复材料前复证exact4 destination全部为NEW；早期对象在后续replace期间漂移时保留transaction并fail closed，恢复到已冻结NEW材料后可`RECOVERED_COMMITTED`。
- template：resource binding locator统一为`.tmp/resource-bindings/<TASK-ID>.resource-binding.json`，静态contract断言与resolver唯一合法目录一致。
- verification：完整suite最终`81/81`、baseline compatibility`2/2`；manifest计数、39-file bytes/canonical、exact42、strict/JSON/PowerShell syntax、old-tree zero-consumer、stable 1.5.2与live roots/CURRENT零漂移均复证PASS。
- flow-weight：只修改冻结exact5，不增加角色、审批、ledger、ACK、轮询、自动retry/compensation、后台服务或默认持久化字段；candidate继续`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`。

## Final independent Review-2 verdict

- verdict：`CHANGES_REQUESTED / 2 P1 / REPEATED`；Reviewer已释放，全程只读，未运行candidate tests、Git、remote/external、release、CURRENT或Pocket。
- P1 resource task identity：resolver与authorization checker尚未把`ResourceTaskPath`内的Task ID/Owner绑定到package TaskId/Owner；内部自洽的decoy低资源任务卡仍可能为真实高资源任务静默降配。最窄闭合只允许在既有resolver/checker解析exact task header，并补TaskId/path及Owner/path错配负键。
- P1 repeat-upgrade protected policy：already-pinned健康门尚未复用`Normalize-RelativePath`并按规范化path唯一；`../outside`或同一路径不同deny仍可能被误报`ALREADY_UPGRADED`。最窄闭合只允许在既有helper中要求stored path等于canonical repo-relative path、按OrdinalIgnoreCase去重，并补两类no-write负键。
- 已闭合：final exact4 snapshot与`TASK_TEMPLATE` resource binding locator；其余Review-1回归未见confirmed finding，默认C/G仍为轻量直达路径。
- stopline：两项均为同类finding复发；不得自动签第三次remediation或继续Review链。candidate003保持`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`，返回owner/用户决定。

## User decision after stopline

- 用户已于2026-08-15明确同意按owner建议执行最后一次局部修复：仅闭合resource task identity与repeat-upgrade protected policy两项，并在写权释放后进行一次fresh独立Review。
- exact5固定为`resolve-resource-binding.ps1 / check-authorization.ps1 / upgrade-project.ps1 / run-framework-tests.ps1 / RELEASE_MANIFEST.json`；不得增加角色、审批、ledger、ACK、轮询、自动retry/compensation、后台服务、默认字段或第六职责路径。
- 若fresh独立Review再次发现同类问题，停止本候选路线并返回用户重新裁剪，不再追加补丁轮次。

## Final remediation result

- resource task identity：resolver在生成binding前解析TaskPath首行Task ID并与参数逐字匹配；authorization checker从current ResourceTaskPath复证Task ID与Owner分别等于package taskId/owner。自洽decoy Task ID与Owner错配均被明确拒绝。
- repeat-upgrade protected policy：already-pinned健康门复用`Normalize-RelativePath`，要求stored path等于canonical repo-relative path，并以OrdinalIgnoreCase按规范化path唯一；`../outside`与同path不同deny均拒绝且no-write。
- regression adjustment：原controller授权正例不再把package owner错误改成controller，而是保留任务卡owner并只把issuer切为current controller；新门未被放宽。
- verification：最终完整suite=`86/86`，baseline compatibility=`2/2`；release inventory=`39 files / 255465 bytes / canonical 306DADB942FF0FDA55D90BFCE90F2F76BC7C376E1F107D99C430076AEC2E188D`；candidate仍为`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`。
- flow-weight：修改仅在既有resolver、authorization checker、repeat-upgrade health branch、tests与manifest内；无新角色、审批门、ledger、ACK、轮询、自动retry/compensation、后台服务或默认持久化字段。

## Final independent Review-3 verdict

- verdict：`CHANGES_REQUESTED / 1 P1 / REPEATED`；Reviewer已释放，全程只读，未运行candidate tests、Git、remote/external、release、CURRENT或Pocket。
- repeated protected-policy predicate：upgrade的`Normalize-RelativePath`仍接受含Git pathspec元字符的路径，例如`assets/[draft].png`；migration producer与already-pinned health因此可接受并返回`ALREADY_UPGRADED`，而唯一safe-Git consumer会拒绝同一路径并返回`UNVERIFIED`。
- impact：升级脚本可能宣告项目健康，但实际安全Git入口不可用；这与Review-2的producer/health/consumer canonical policy不一致属于同类finding。
- 已闭合且未见新增finding：resource Task ID/Owner绑定、phase/host/context、final exact4 snapshot、template locator、controller route、RemoteBatch、旧事务零有效引用及轻量flow-weight。
- stopline：同类finding再次出现，candidate004保持`DRAFT / NOT_CONSUMABLE / projectPinEligible=false`；不得自动追加补丁或Review轮次，返回owner/用户重新裁剪候选路线。

## Verification and evidence ceiling

- baseline门：lean exact32与stable 1.5.2逐文件identity一致，lean root exact2与live stable root逐字一致；在任何功能编辑前冻结一次结果。
- direct正反例：RemoteBatch逐remote授权/head/refspec/fingerprint、PARTIAL、fresh retry、旧DTO拒绝、危险action分包；protected sentinel不进入status/diff/index pathset；DEFAULT/exception resource binding及全部失效键；coordination默认/例外、controller rotation/stale suppression/dedup与DOMAIN_OWNER回归。
- inventory门：expected/actual exact42一致；lean loader/manifest/root/tests不引用旧candidate/root；lean树对`RemoteTransaction / PreviousLedger / COMPENSATION`零有效语义，允许明确拒绝旧DTO的负键。
- migration门：root preview/apply覆盖已规划的1.4.1/1.5.0/1.5.1/1.5.2来源、schema3 project/controller/protected policy、冻结preimage、失败恢复和不自动改真实项目。
- strict门：UTF-8/LF、JSON、PowerShell语法、load plan、draft/not-consumable、baseline compatibility与完整candidate direct suite。
- 证据上限：direct/static/隔离fixture PASS不等于独立Review、真实remote、Git、release、CURRENT或项目采用；writer释放并冻结manifest后才路由唯一fresh独立实现Review。

## Risk and next action

- pre-mortem 1：从旧candidate复制helper导致旧事务语义回流。检查：old-tree destination/source审计与lean零有效引用。
- pre-mortem 2：baseline复制后直接宣称candidate完成。检查：baseline identity与功能candidate identity分开记录，VERSION/manifest保持DRAFT/NOT_CONSUMABLE。
- pre-mortem 3：保护策略迁移前根脚本扫描source。检查：pre-config control allowlist与protected sentinel负键。
- pre-mortem 4：资源减重变成静默降级。检查：minimum/tool/fresh与全部binding失效键负例。
- pre-mortem 5：controller epoch机制误伤DOMAIN_OWNER或恢复旧ACK链。检查：issuer分支与stale decision/auth/ACK/queue正反例。
- consumed authorizations：implementation=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-IMPLEMENT.authorization.json|7848|EAC46049356D856238B519CCF1975A667B1C98438E514CF3DB5F6703677CAE56`；Review-1=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-REVIEW-1.authorization.json|9954|35FABD3E13A888F58BAF3E8E21B78014EA8BE3BC01DCA74208460FC171453751`；remediation-1=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-REMEDIATION-1.authorization.json|2510|A3A98383B07D94E18E0324FDE73168242A91FDCA13758E1B8513D97040950F3C`；final Review=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-FINAL-REVIEW.authorization.json|9911|E36D822426F8996D1DD6D663D1045F9F5A05C96CDF25571E6F7C4CD3019CC9BC`；remediation-2=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-REMEDIATION-2.authorization.json|1759|DEA1B7C5494EF9B59AABC05CFEAB22FCCF502DF5CA14EFC0E8C0EB37A2CCBECD`；final Review-2=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-FINAL-REVIEW-2.authorization.json|9913|0950F0D674036BC8DB41D1147CBFA8F1BDD39E03039510B14002F24B6895E2F3`；final remediation=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-FINAL-REMEDIATION.authorization.json|1858|C4C97FD76969637CAEF60DF2502D6CEA487E957F9222654C362FDA93AF8A8EB5`；final Review-3=`.tmp/AIW-FW-1.6.0-A-C-G-LEAN-FINAL-INDEPENDENT-REVIEW-3.authorization.json|10412|0F488E702ACCAF17C6FA2B1D4617678DAF7AC9E1A37ADDB32D804739D665D396`。均已消费失效，不得复用；current package=`NONE`，writer/reviewer=`NONE/NONE`。
- 唯一下一动作：`NONE`。父任务将另行只读冻结新的最小实现范围；本卡不得产生writer、reviewer、authorization或下游handoff。D-E/F、INTEGRATION、Git、release与Pocket采用继续关闭。
