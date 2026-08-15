# AIW-FW-1.6.0-FULL-RELEASE-001 — Framework 1.6.0 全量发行父任务

- 状态：FRAMEWORK_1.6.0_RELEASE_COMPLETE / LIVE_ROOT_ACCEPTED / CURRENT_REMAINS_1.4.1 / ROOT_README_SYNC_ACCEPTED / LOCAL_GIT_CHECKPOINT_COMPLETE / WRITER_NONE / REVIEWER_NONE
- Task schema: 1.5.2
- 档位：CRITICAL；理由：修改共享 Framework 公共治理合同、模块与迁移边界，影响多个项目且失败代价高
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前 actor / writer：NONE / NONE
- Reviewer：NONE；focused formal release Reviewer已给出`APPROVED / 0 finding`并RELEASED。
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=FRAMEWORK_1.6.0_STABLE_RELEASE_001_APPROVED; expected_paths=[framework/drafts/1.6.0/FRAMEWORK_TASK.md]; actual_paths=[framework/drafts/1.6.0/FRAMEWORK_TASK.md]
- Stable release: `framework/versions/1.6.0/RELEASE_MANIFEST.json|688|0E36A79344B27C8CF2291FC11FCBBF94A21A49249FDE0F8C2A48AD1574735F8F`；payload=`37 files / 220698 bytes / EBB00A3EED4BD9E2871DDBD6CE2B12A252614BD36CD42E092187FF35C4E5E30D`；状态=`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE / RELEASE_REVIEW_APPROVED / OWNER_ACCEPTED`
- Phase gate: FALSE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- candidate006 bounded exact5 closure已通过fresh independent final Review=`APPROVED / 0 finding`并由owner接受：quick=`93/93 PASS`、full=`131/131 PASS`、manifest独立复算一致；A-C+G现已冻结，不再写入。Git、release、CURRENT、Pocket采用仍未启动。
- 已实现的减法边界：日常排除替代protected capability矩阵；独占维护窗口替代并发升级支持；恢复材料保留替代脚本内递归自动清理；统一语言并入现有模块且不增加checker/schema/service。Pocket发布后必须先指定项目术语权威，再初始化与启用项目知识。
- candidate004 final Review=`CHANGES_REQUESTED / 1 HIGH(REPEATED) / 1 MEDIUM`：核心机制均成立，但current中文示例仍残留旧保护策略语义，且child把实际byte-identical exact6误写为exact7。owner已裁决`REMOVE + CONTROL_CORRECT`：一次性清查current文档消费者并扩展现有零残留断言，同时按candidate005实际delta修正控制事实；不新增机制或路径。

- 目标：按已接受的减法审计，从stable 1.5.2出发建立新的minimal A-C+G候选；不再修补candidate004，并在A-C+G通过独立Review后继续F。
- 唯一范围权威：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md`。本卡只保存执行状态、对象指针、门和 actor，不复制 A—H 的合同正文。
- 版本状态权威：`framework/drafts/1.6.0/VERSION.json`。当前必须保持 `DRAFT / NOT_CONSUMABLE`。
- 用户入口：`README.md`。它只说明版本路线与草案入口，不承载完整合同。
- 当前结果：用户已选择Route-004减法合同；current plan=`framework/drafts/1.6.0/FRAMEWORK_PLAN.md|33399|26CD64F422139EAC9E8FBFAA318521DB3E6D47F8EC23BA1D094D65B44906103F`。Route-003的positive-policy与register partial delta不是candidate003，也不得继续作为实现基线。
- 用户顺序决定：Framework 1.6.0先交付默认关闭、无知识库/空索引合法的项目级知识基础能力；Pocket发布后按“升级pin/control schema → 配置routine exclusion → 指定项目术语权威 → 初始化知识内容 → 显式启用 → 去重瘦身 → FULL_COLD → 恢复任务与自然采样”采用。两个项目自然证据只约束未来common知识晋升，不阻塞本版发行。
- 当前范围修订：`project.json` schema3只保留`routineExcludedPaths`字符串列表，不再建立protected deny矩阵或`ProtectedPolicy.psm1`；升级只支持current controller主持的独占维护窗口，复用现有恢复骨架并取消第二套`Minimal16`并发事务、capture/quarantine双树和脚本内递归自动清理；保留controller/epoch/PROJECT_CONTROLLER授权、direct-owner/no-poll/terminal-only/exception-only路由和default-off项目知识能力。统一语言作为D/E现有模块短规则闭合，不新增schema/checker/service。
- 经验沉淀：已存在的chat非权威、单一真相、最小机制、producer/consumer/test前置与重复finding停止线不复制第二份；只补三项缺失澄清——建议变化须给出新事实或明确纠错、同类finding复发必须`SIMPLIFY/REMOVE/DEFER/REDESIGN`、无真实调用消费者的checker不算已交付能力或发行证据。
- F current child：`framework/drafts/1.6.0/IMPLEMENTATION_F_KNOWLEDGE.md`；candidate003 exact4 simplify已完成，quick=`130/130`、full=`172/172`，writer/reviewer=NONE/NONE；Review-2两项由最终integration Review复核，不启动F Review-3。
- F bounded remediation：existing checker直接绑定project config唯一opt-in/locator；query-result cache禁止；loader capability说明及locator/date schema一致性闭合。quick=`128/128`、full=`171/171`，未增加服务、常态步骤或第二状态。
- owner stopline裁决已消费：`SIMPLIFY / NO_COMPONENT_REVIEW_3`，没有新模块、checker、service、state或审核链。
- Integration child：`framework/drafts/1.6.0/INTEGRATION_1_6_0.md`；exact41=`minimal-candidate exact38 + minimal-root exact3`，完整集成验证=`172/172 PASS`，candidate/root零写入。
- Final integration Review-1的唯一MEDIUM已用technical exact4闭合：只改README/CHANGELOG/STATIC_COMPARISON及manifest identity，未改脚本、schema、checker、root或新增机制。
- Candidate002验证：quick=`130/130 PASS`、full=`172/172 PASS`，manifest=`37 / 220153 / CF5D9C53...D8465`；writer/reviewer=`NONE/NONE`。
- Final integration Review-2=`APPROVED / 0 finding / RELEASED`；owner已接受candidate002，integration child已关闭。
- Formal projection：approved candidate exact38已机械生成`framework/versions/1.6.0`；相对candidate只有exact8稳定版投影delta=`README / CHANGELOG / STATIC_COMPARISON / LOAD_MANIFEST / VERSION / RELEASE_MANIFEST / resolve-load-plan / run-framework-tests`。其余30项逐字一致。
- Live root：exact3已从reviewed minimal-root逐字替换并保留精确旧字节备份；CURRENT仍为1.4.1。stable quick=`130/130 PASS`、full=`172/172 PASS`；manifest=`37 / 220698 / EBB00A3E...E5E30D`。
- Focused formal release Review=`APPROVED / 0 finding / RELEASED`；owner接受stable exact38与live-root exact3。正式版与approved draft仅有预定exact8稳定投影delta，其余30项逐字一致；stable manifest、strict文本、rendered JSON、PowerShell syntax、stable 1.5.2基线与live-root身份均通过独立复证。
- CURRENT disposition：保持`framework/CURRENT=1.4.1`。1.6.0 current metadata与stable self-test均明确`currentEligible=false`，因此本次不把它设为新项目默认版本；`projectPinEligible=true`仍允许Pocket等已有项目通过独立升级任务显式采用。
- Root README sync：正式版发布后发现根入口仍把1.6.0描述为规划中；已用exact1内容修正为`STABLE / NOT_CURRENT / PIN_ELIGIBLE`及真实知识/采用边界。该同步不改stable version、live root、CURRENT或任何机制。
- Root README focused Review=`APPROVED / 0 finding / RELEASED`；owner接受单文件同步，stable metadata、`CURRENT=1.4.1`、知识能力边界、draft不可消费与稳定版不可原位修改均一致。
- Git inventory：AI-Workspace `main`，HEAD=`f238746d8f145bc14f003221fffcc94fa442a9ab`；current dirty exact172全部位于本次1.6.0发行范围，范围外dirty=`0`，index=`0`。checkpoint保留正式版、live root、控制卡与审计快照；不执行整仓暂存，不含CURRENT变化、tag、push或Pocket文件。
- Local Git checkpoint：exact172已由唯一Git closer精确stage并提交到AI-Workspace `main`，commit=`83431fceda58922885e1a2da0054c247d63bccab`，提交后index/dirty=`0/0`。未使用`git add .`，未改CURRENT，未tag、push或触碰Pocket。
- 唯一下一动作：Framework任务不再启动实现或Review；后续若用户授权remote发布再单独处理push/tag。Pocket采用由Pocket current controller另立项目升级任务，按“升级pin/control schema → routine exclusion → 项目术语权威 → 知识初始化 → 显式启用 → 去重瘦身 → FULL_COLD → 恢复产品任务”推进。

### Minimal implementation Review-1 verdict

- Verdict：`CHANGES_REQUESTED / 2 HIGH / 1 REPEATED`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact38与control identities末次复证无漂移。
- REPEATED：schema、register、upgrade、safe-Git未真正共享同一可证明的protected-path规范，且跨保护边界rename/copy可能把原保护路径带入Git输出；触发`REDESIGN`停止线。
- HIGH：upgrade的replace、controller delete及staging cleanup存在未知并发字节被覆盖或删除的窗口；必须用可验证、可恢复的preimage流程统一闭合。
- Review未授权任何返工、Git、release、CURRENT、knowledge F或Pocket采用。

### Lean scope Review verdict

- Verdict：`CHANGES_REQUESTED / 3 HIGH / 1 MEDIUM`；reviewer=`/root/fw_160_lean_scope_review(RELEASED)`；exact3末次复证无漂移。
- HIGH：protected-safe Git缺少唯一机器可读policy producer/schema/locator、identity与register/upgrade迁移消费者；安全失败必须逐项保持`UNVERIFIED`，不得回退到调用者手填exclude。
- HIGH：`resourceBinding`缺少唯一机器producer/checker与完整失效键；最小binding必须覆盖需求identity、adapter/policy identity、实际能力、选择质量、工具、continuity及phase/context，同时任务卡仍只写`DEFAULT`或例外需求。
- HIGH：D的完整`PEER_TASK_REUSE_PREFLIGHT`触发范围过宽；仅实际复用非current/archived任务、跨项目或project/domain/owner/role/lineage不确定时触发，fresh/current且注册关系明确的跨域handoff继续走C/G紧凑合同。
- MEDIUM：旧`REMOTE_TRANSACTION_SCHEMA`、`check-remote-transaction.ps1`及全部manifest/test/doc有效引用必须作为一个完整拒绝/移除集合，由`REMOTE_BATCH_SCHEMA.json`、`check-remote-batch.ps1`与新测试唯一替换，最终inventory不得并存双合同。
- 已确认：RemoteBatch的诚实`PARTIAL`、fresh batch/fresh authorization、危险动作分包成立；F仍default-off且no-library/empty-index合法；Review轮次限制和hot-current/history分离成立；stable 1.5.2、CURRENT与Pocket pin零漂移。

### Candidate008 final scope Review verdict

- Verdict：`CHANGES_REQUESTED / 1 MEDIUM / REPEATED`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；exact3末次复证无漂移。
- 重复finding：PLAN只冻结旧事务有效引用替换exact4，但actual公共有效载体还包括`candidate/AUTHORIZATION_MODEL.md`、`candidate/EXAMPLES.md`、`candidate/STATIC_COMPARISON.md`、`candidate/REVIEW_AND_EVIDENCE.md`、`candidate/MIGRATION_MATRIX.md`，继续承载旧RemoteTransaction retry/compensation/ledger语义。实际替换集合至少为exact9；按exact4实现会留下双合同。
- 最窄技术闭合：把上述exact5纳入有效引用替换集合或明确迁为不可消费审计历史，并对inventory/loader/manifest/root/checker/tests做旧`RemoteTransaction / PreviousLedger / COMPENSATION`零有效引用复证。
- 停止线：该finding与candidate007的MEDIUM同类且本轮是final范围Review；不得现场返工或继续Review链，须回owner重新决定范围路线。
- 其余无新增confirmed finding：project.json protected-policy单一producer、短期resource binding、D风险触发、C/G handoff、knowledge default-off、DRAFT/NOT_CONSUMABLE及stable/CURRENT/Pocket pin零漂移均成立。

## Stable authority and candidate

`REDUCTION_AUDIT_DECISION_010` 精确绑定：

- `README.md|7871|A476E40386EB8EFB61994E3C47FB2AC1556B7478CC8911CE5DCB31CC6694A257`
- `framework/drafts/1.6.0/FRAMEWORK_PLAN.md|30596|543EBA9381A342FDFF7300F50A4617037A7380C6D96761F921F1D0A0B21A6B15`
- `framework/drafts/1.6.0/VERSION.json|210|14B09CD9603164E78036F677818F51348A4393B9DA12D27D0ABA76CD46D109D3`

该 exact3 是已接受的减法审计及本次stopline重设计决定，不是实现候选、Review对象或发行候选。实现范围由current child exact39另行冻结并由owner绑定。

## Scope closure

- 本轮 producer：Framework maintainer owner，只负责冻结任务入口与审核输入。
- 本轮 direct consumers：fresh independent Framework reviewer；审核通过后才可能由 owner 签发后续实现任务。
- tests / runner-manifest / docs：本轮不运行、不写入；审核必须确认规划已覆盖后续完整 inventory、loader/manifest、迁移矩阵、兼容性与集成测试责任。
- conditional contingency：Lineage-001的`NO_REVIEW_3`永久保留，Lineage-002与knowledge range lineage均已闭合且不复活。用户本次明确重开lean范围，current exact3是新候选；Reviewer必须同时证伪“减重造成安全缺口”和“默认流程仍强制展开高风险字段”。若发现第三职责路径、公共合同漂移或需要扩大inventory，立即RANGE_GATE，不顺手改候选。
- forbidden：`framework/versions/**` 已发布目录、`framework/CURRENT`、任何项目 pin、Pocket Legion 项目文件、register/upgrade/slimming、Git stage/commit/push、外部发布。

## Design and risk

- 单一真相：范围只在 `FRAMEWORK_PLAN.md`；执行状态只在本卡；版本可消费性只在 `VERSION.json`。README 仅路由。
- 生命周期：`DRAFT_CONTROL` → 独立范围审核 → owner 接受 → 分阶段实现 → 集成与迁移闭包 → fresh 最终独立候选审核 → 发行；项目采用与项目瘦身在发行后另行授权。
- 失败恢复：不得回到candidate004或更早候选逐项补丁；新的最小重建只有在owner冻结完整producer/consumer/test/migration范围后才能实施，任何新职责路径或同类finding复发都返回`SIMPLIFY/REMOVE/DEFER/REDESIGN`，不得顺延补丁链。
- pre-mortem 1：把 Pocket Legion 的项目特例复制进通用合同，导致 Framework 臃肿。检查：每项能力必须说明跨项目语义与项目特例保留边界。
- pre-mortem 2：知识流程在自然样本不足时提前进入发行候选。检查：以规划 F 的双项目证据门为准；样本计数留在各项目 pilot 卡，不在本卡复制第二状态。
- pre-mortem 3：只补文档而漏掉 loader、template、checker、测试和迁移矩阵。检查：范围审核逐项核对完整 inventory 与 direct consumer。
- pre-mortem 4：把 1.5.2 或项目 pin 原位修改成“升级”。检查：所有 released-version、CURRENT 和 project-pin 路径在本轮显式 forbidden。
- 适用审核视角：公共合同一致性、跨项目可复用性、最小机制/去臃肿、授权与路由安全、版本兼容与迁移、失败恢复、证据可审计性。

## Review and user gates

- 用户重大方案门：CONFIRMED；用户已接受日常排除、独占串行升级、无复杂自动清理和统一语言治理，并允许按顺序自主推进。当前写入只持久化控制决定，不等于Git、发行、CURRENT或Pocket采用批准。
- 范围独立 Review：Lineage-001=`CHANGES_REQUESTED / NO_REVIEW_3`；Lineage-002 Review-2=`APPROVED / 0 FINDING / RELEASED`；knowledge range Review-2=`APPROVED / 0 FINDING / RELEASED`。这些旧verdict只保留历史边界；`SCOPE_REVIEW_CANDIDATE_007`=`CHANGES_REQUESTED / 3 HIGH / 1 MEDIUM`，`SCOPE_REVIEW_CANDIDATE_008` final=`CHANGES_REQUESTED / 1 MEDIUM / REPEATED`，两名reviewer均已释放。
- 实现授权：NONE；原`SOURCE_WRITE / TEST_WRITE / TEST_RUN` exact39 lease已消费失效，old child已关闭，不得复用。无new candidate、PLAN、live root scripts、Git或external权限。
- A-C+G独立实现Review：Review-1=`CHANGES_REQUESTED / 9 HIGH / 1 MEDIUM`；Review-2=`CHANGES_REQUESTED / 3 HIGH / REPEATED`；Review-3=`CHANGES_REQUESTED / 2 HIGH / 1 LOW`；Review-4=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM`；Review-5=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM`，对应reviewer均已释放。`A_C_G_CANDIDATE_005`保持冻结；不启动Review-6，先回owner做统一机制与减重闭包。
- Lean A-C+G实现Review：Review-1对candidate001=`CHANGES_REQUESTED / 5 P1 + 1 P2`；final Review对candidate002=`CHANGES_REQUESTED / 3 P1 + 1 P2`；final Review-2对candidate003=`CHANGES_REQUESTED / 2 P1 / REPEATED`；final Review-3对candidate004=`CHANGES_REQUESTED / 1 P1 / REPEATED`，reviewer均已释放。candidate004现为`NON_CURRENT / AUDIT_ONLY`，停止线已消费；不得再追加补丁或Review链。
- 用户试玩：NOT_APPLICABLE；Framework 公共治理合同不以 Pocket Legion 单次试玩代替跨项目证据和独立 Review。
- stopline：scope/object/owner 漂移、知识证据不足、公共合同新增、兼容或迁移无法闭合、出现第三职责路径、Reviewer 参与候选写入、任何 released-version/CURRENT/project-pin 写入。

## Current authorization

- current package=`NONE`；Route-004控制冻结包与关闭包均已消费失效并删除；actor/writer/reviewer=`NONE / NONE / NONE`。Git、push、external、release、CURRENT和project pin继续NONE/CLOSED。

## History locator

- Review-1：candidate=`SCOPE_REVIEW_CANDIDATE_001`（README 7604|2200D8...A2F83；PLAN 12317|3EF825...12C；VERSION 187|4DFDD3...DE951）；reviewer=`/root/fw_160_scope_review_fresh`；verdict=`CHANGES_REQUESTED`；findings=`4 HIGH / 2 MEDIUM`；只读、exact身份末复证不变。
- Bounded remediation：仅`FRAMEWORK_PLAN.md`与`VERSION.json`，current结果由`SCOPE_REVIEW_CANDIDATE_002`承载；Review-1 authorization不传递到Review-2。
- Review-2：candidate=`SCOPE_REVIEW_CANDIDATE_002`（README 7604|2200D8...A2F83；PLAN 19899|16F73A...A0A2A；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_scope_review_fresh`；verdict=`CHANGES_REQUESTED`；findings=`2 HIGH / REPEATED`；exact4身份末复证不变；只读且未运行实现/test/Git/external。
- User range reopen：用户明确同意按owner建议只重开上述两项缺口；Lineage-001不复活、不启动Review-3。current范围由`SCOPE_REVIEW_CANDIDATE_003`承载，等待新reviewer。
- Lineage-002 Review-1：candidate=`SCOPE_REVIEW_CANDIDATE_003`（README 7604|2200D8...A2F83；PLAN 22726|BC3B6D...CD4E；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_range_lineage2_review`；verdict=`CHANGES_REQUESTED / 2 HIGH`；exact4末复证不变；只读且未运行实现/test/Git/external。
- Lineage-002 bounded remediation：仅`FRAMEWORK_PLAN.md`，current结果由`SCOPE_REVIEW_CANDIDATE_004`承载；Review-1 authorization不传递到Review-2。
- Lineage-002 Review-2：candidate=`SCOPE_REVIEW_CANDIDATE_004`（README 7604|2200D8...A2F83；PLAN 25705|D1802B...A154；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_range_lineage2_review`；verdict=`APPROVED / 0 FINDING`；exact4末复证不变；owner accepted；只读且未运行候选实现/test/Git/external。
- Knowledge range Review-1：candidate=`SCOPE_REVIEW_CANDIDATE_005`（README 7785|F8649C...5EB8B；PLAN 26671|B6ACD3...5B50B9；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_knowledge_scope_review`；verdict=`CHANGES_REQUESTED / 1 HIGH`；exact3末复证不变；只读且未运行test/Git/external。
- Knowledge bounded remediation：仅PLAN 26671|B6ACD3...5B50B9 → 27332|A968AE...425C；README/VERSION不变；candidate=`SCOPE_REVIEW_CANDIDATE_006`，等待same-lineage Review-2。
- Knowledge range Review-2：candidate=`SCOPE_REVIEW_CANDIDATE_006`（README 7785|F8649C...5EB8B；PLAN 27332|A968AE...425C；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_knowledge_scope_review`；verdict=`APPROVED / 0 FINDING`；exact3末复证不变；owner accepted；只读且未运行test/Git/external。
- Lean scope Review：candidate=`SCOPE_REVIEW_CANDIDATE_007`（README 7871|A476E4...A257；PLAN 31760|0AA643...6FC2；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_lean_scope_review`；verdict=`CHANGES_REQUESTED / 3 HIGH / 1 MEDIUM`；exact3末复证不变；只读且未运行candidate test/Git/remote/external。
- Lean unified remediation：仅PLAN按四项finding一次性修订，README/VERSION不变；current exact3冻结为`SCOPE_REVIEW_CANDIDATE_008`，等待fresh独立final范围Review。candidate007 Review授权不传递，candidate005不复活。
- Lean final scope Review：candidate=`SCOPE_REVIEW_CANDIDATE_008`（README 7871|A476E4...A257；PLAN 35857|78563D...4F2C；VERSION 210|14B09C...09D3）；reviewer=`/root/fw_160_acg_review_4`；verdict=`CHANGES_REQUESTED / 1 MEDIUM / REPEATED`；exact3末复证不变；只读且未运行candidate test/Git/remote/external。Review轮次停止，回owner裁决。
- Owner clean-baseline route：只读库存确认旧事务相关对象exact12，其中schema/checker exact2、有效消费者exact10；选择整体排除旧candidate/root树并从stable 1.5.2建立独立lean roots，不再开启范围Review链。current exact3=`CLEAN_BASELINE_ROUTE_009`，等待机械baseline/pathset冻结。
- Lean A-C+G mechanical range：card=`framework/drafts/1.6.0/IMPLEMENTATION_A_C_G_LEAN.md|11877|4F5FA0FFBDBFE82D91C0B4B9AB5D83EBECCA550279006180D4355738F99DB218`；exact42=`stable exact32 + new exact8 + root exact2`，task checker PASS，writer/reviewer=`NONE/NONE`。下一门为fresh单一implementation authorization。
