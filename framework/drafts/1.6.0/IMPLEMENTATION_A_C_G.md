# AIW-FW-1.6.0-A-C-G-001 — Framework 1.6.0 A-C + G 第一阶段实现

- 状态：NON_CURRENT / A_C_G_CANDIDATE_005_REJECTED / SUPERSEDED_BY_LEAN_SCOPE / NON_CONSUMABLE / AUDIT_ONLY / NO_ACTION / WRITER_NONE / REVIEWER_NONE
- Task schema: 1.5.2
- 档位：CRITICAL；理由：共享Framework公共合同、授权/Git/主控轮换与多项目starter消费者，失败代价高
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前 actor / writer：NONE / `NONE`
- Reviewer：Review-5=`/root/fw_160_acg_review_5(CHANGES_REQUESTED / RELEASED)`；Review-4=`/root/fw_160_acg_review_4(CHANGES_REQUESTED / RELEASED)`；Review-3=`/root/fw_160_acg_review_3(CHANGES_REQUESTED / RELEASED)`；Review-2=`/root/fw_160_acg_review_2(CHANGES_REQUESTED / RELEASED)`；Review-1=`/root/fw_160_acg_review_fresh2(CHANGES_REQUESTED / RELEASED)`；old=`/root/fw_160_acg_implementation_review(INTERRUPTED_BEFORE_VERDICT / RELEASED)`
- 资源选择：当前host高质量frontier reasoning与完整本地工具能力；理由=跨模块/脚本/迁移负键且需长上下文；失效=工具不可用、上下文断裂或第三职责路径
- Range summary: profile=CRITICAL; lifecycle=ACTIVE; current_exact=A_C_G_CANDIDATE_005; expected_paths=[framework/drafts/1.6.0/candidate/AUTHORIZATION_MODEL.md|framework/drafts/1.6.0/candidate/CHANGELOG.md|framework/drafts/1.6.0/candidate/EXAMPLES.md|framework/drafts/1.6.0/candidate/FRAMEWORK_RELEASE.md|framework/drafts/1.6.0/candidate/GIT_AND_EXTERNAL.md|framework/drafts/1.6.0/candidate/HOST_CODEX.md|framework/drafts/1.6.0/candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md|framework/drafts/1.6.0/candidate/PERSPECTIVE_LENSES.md|framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/candidate/project-starter/.gitattributes|framework/drafts/1.6.0/candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/candidate/project-starter/project.json|framework/drafts/1.6.0/candidate/project-starter/PROJECT.md|framework/drafts/1.6.0/candidate/project-starter/RELATIONSHIPS.md|framework/drafts/1.6.0/candidate/project-starter/REVIEW_PROFILE.md|framework/drafts/1.6.0/candidate/project-starter/STATUS.md|framework/drafts/1.6.0/candidate/project-starter/tasks/README.md|framework/drafts/1.6.0/candidate/PROMPTS.md|framework/drafts/1.6.0/candidate/README.md|framework/drafts/1.6.0/candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/candidate/REVIEW_AND_EVIDENCE.md|framework/drafts/1.6.0/candidate/scripts/check-authorization.ps1|framework/drafts/1.6.0/candidate/scripts/check-task-card.ps1|framework/drafts/1.6.0/candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/candidate/STATIC_COMPARISON.md|framework/drafts/1.6.0/candidate/TASK_AND_SCOPE.md|framework/drafts/1.6.0/candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/candidate/tests/run-hotfix-tests.ps1|framework/drafts/1.6.0/candidate/VERSION.json|framework/drafts/1.6.0/candidate/CONTROLLER_SCHEMA.json|framework/drafts/1.6.0/candidate/REMOTE_TRANSACTION_SCHEMA.json|framework/drafts/1.6.0/candidate/project-starter/controller.json|framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1|framework/drafts/1.6.0/candidate/scripts/check-remote-transaction.ps1|framework/drafts/1.6.0/root-scripts/register-project.ps1|framework/drafts/1.6.0/root-scripts/upgrade-project.ps1]; actual_paths=[framework/drafts/1.6.0/candidate/AUTHORIZATION_MODEL.md|framework/drafts/1.6.0/candidate/CHANGELOG.md|framework/drafts/1.6.0/candidate/EXAMPLES.md|framework/drafts/1.6.0/candidate/FRAMEWORK_RELEASE.md|framework/drafts/1.6.0/candidate/GIT_AND_EXTERNAL.md|framework/drafts/1.6.0/candidate/HOST_CODEX.md|framework/drafts/1.6.0/candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md|framework/drafts/1.6.0/candidate/PERSPECTIVE_LENSES.md|framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/candidate/project-starter/.gitattributes|framework/drafts/1.6.0/candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/candidate/project-starter/project.json|framework/drafts/1.6.0/candidate/project-starter/PROJECT.md|framework/drafts/1.6.0/candidate/project-starter/RELATIONSHIPS.md|framework/drafts/1.6.0/candidate/project-starter/REVIEW_PROFILE.md|framework/drafts/1.6.0/candidate/project-starter/STATUS.md|framework/drafts/1.6.0/candidate/project-starter/tasks/README.md|framework/drafts/1.6.0/candidate/PROMPTS.md|framework/drafts/1.6.0/candidate/README.md|framework/drafts/1.6.0/candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/candidate/REVIEW_AND_EVIDENCE.md|framework/drafts/1.6.0/candidate/scripts/check-authorization.ps1|framework/drafts/1.6.0/candidate/scripts/check-task-card.ps1|framework/drafts/1.6.0/candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/candidate/STATIC_COMPARISON.md|framework/drafts/1.6.0/candidate/TASK_AND_SCOPE.md|framework/drafts/1.6.0/candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/candidate/tests/run-hotfix-tests.ps1|framework/drafts/1.6.0/candidate/VERSION.json|framework/drafts/1.6.0/candidate/CONTROLLER_SCHEMA.json|framework/drafts/1.6.0/candidate/REMOTE_TRANSACTION_SCHEMA.json|framework/drafts/1.6.0/candidate/project-starter/controller.json|framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1|framework/drafts/1.6.0/candidate/scripts/check-remote-transaction.ps1|framework/drafts/1.6.0/root-scripts/register-project.ps1|framework/drafts/1.6.0/root-scripts/upgrade-project.ps1]
- Stable candidate: A_C_G_CANDIDATE_005
- Phase gate: FALSE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 目标：仅作为被Review拒绝且已被lean范围取代的`A_C_G_CANDIDATE_005`审计载体，保留原exact39、测试与Review provenance，不再提供实现、返工、Review或发行权限。
- 非目标：任何candidate写入、remediation、Review-6、D-E/F/H、INTEGRATION、发行、Git、CURRENT、项目pin或Pocket采用。
- successor范围权威：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md|31760|0AA6430E1ED14AA0AE18275B6FDBAFA60B451DAA6F04E35903C836BF3AFB6FC2`；新lean candidate必须等待父任务重新范围审核与owner acceptance，本卡不传递旧授权或旧candidate身份。
- baseline：`framework/versions/1.5.2/RELEASE_MANIFEST.json|699|840130FCC94485BC358796152DAB3619756BECA4E8FDB253EA9133964CA783B3`，source commit=`f238746d8f145bc14f003221fffcc94fa442a9ab`；已发布1.5.2零修改。
- root script source：`scripts/register-project.ps1|22358|6AE4FD80FB25653FA4606961EED8CD1B652F4A791E9D445C04E9B473E83CC6B1`；`scripts/upgrade-project.ps1|48080|679F4D0B2519EA4777566ED5A48F89F6AD0451DB489EFDAF6A5C6BB8F9F43C9B`。只复制到draft root-scripts并在那里改。
- baseline copy规则：所有既有candidate路径先逐字复制1.5.2对应文件；随后仅按A-C+G和DRAFT非可消费状态修改。未涉及分片的副本保持baseline语义；`VERSION/FRAMEWORK_RELEASE/RELEASE_MANIFEST`必须明确DRAFT/NOT_CONSUMABLE，不能冒充发行。
- exact：仅Range summary列出的39个destination；所有preimage均为NEW。writer不得写任务卡或父卡。
- forbidden：`framework/versions/**`、`framework/CURRENT`、live `scripts/register-project.ps1`与`scripts/upgrade-project.ps1`、README/PLAN/VERSION/TASK父控制对象、任何项目repo/pin、Git stage/commit/push、网络/external。
- public DTO：remote transaction schema与controller schema只能各有一个真相；`.ai-workspace/controller.json`是controller current truth，STATUS/index仅locator；DOMAIN_OWNER包不得被controller epoch误伤。
- migration：只在draft root-script copies实现register/upgrade候选；必须覆盖controller.json epoch1、legacy controller包STALE、domain-owner兼容、partial remote ledger、失败恢复与不自动改项目。
- 验证：运行candidate自身direct tests；覆盖remote partial/retry/head drift/protected exclude/compensation，controller issuer三等/current-stale-forged/cache/rotation/queued suppression/domain-owner兼容，task routing/dedup/wait/archive，host-neutral resource unsupported/no-silent-downgrade，strict/inventory/loader现有回归。
- 证据上限：本阶段不证明D-E/F/知识自然样本/完整迁移/发行/项目采用；candidate测试PASS也不授权Git或release。
- pre-mortem 1：机械复制留下STABLE/1.5.2自指向而伪装candidate。检查：version/release/manifest与全树版本引用审计。
- pre-mortem 2：controller epoch误伤DOMAIN_OWNER包。检查：current/stale controller正反例与旧domain-owner合法包回归。
- pre-mortem 3：remote rollback虚构撤销远端。检查：ledger保留receipt并只允许另授权compensation。
- pre-mortem 4：直接改live root scripts或已发布目录。检查：末次actual path inventory和Git diff只允许exact destination。
- pre-mortem 5：为复用方便顺手实现D/E/F/H。检查：新职责/新路径立即RANGE_GATE，停止writer。
- 当前结果：`A_C_G_CANDIDATE_005`已冻结，actual exact39/expected exact39/diff=0；相对candidate004仅remediation-4 exact6改变、范围外漂移=0。full direct suite=`RESULT 136/136 passed|scope=A-C+G|lifecycle=DRAFT_NOT_CONSUMABLE`，skip-root direct=`105/105`，baseline compatibility=`1/1`，strict=`39/39`，syntax=`scripts 9/9`，JSON=`concrete 5/5 + templates 2`；Review-5=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM`，writer/reviewer均已释放，RANGE_GATE=NONE。
- 兼容修复：direct复跑曾发现candidate register把`CURRENT=1.4.1`错误要求为VERSION.json布局；已限定1.4.0/1.4.1 schema2兼容路径并新增CURRENT/1.5.2注册回归，最终全绿。
- 证据上限：仅证明candidate静态/direct与隔离临时仓迁移；不构成独立Review、完整INTEGRATION、release、live root替换、CURRENT/project pin消费或真实remote外部动作。D/E/F/H、knowledge selector、Git/external仍关闭。
- 唯一下一动作：NONE；successor动作只在父任务的新范围审核链中产生。

## Fresh implementation review verdict

- verdict：`CHANGES_REQUESTED`；findings=`9 HIGH / 1 MEDIUM`；reviewer=`/root/fw_160_acg_review_fresh2(RELEASED)`；candidate=`A_C_G_CANDIDATE_001` exact39末复证无漂移。
- HIGH 1：remote事务未把ledger声明与现场local HEAD、去凭据endpoint fingerprint、refspec及authorization identity逐字绑定。
- HIGH 2：protected exclude仅拦截evidence位于protected路径内，未拦截evidence祖先范围覆盖protected后代，也未绑定实际采集receipt。
- HIGH 3：`COMPENSATION`事务未强制独立补偿授权，且PRIMARY仍可能携带`COMPENSATE_REF`。
- MEDIUM 4：资源选择失效门只验证标签存在，未绑定current phase/host/context或稳定adapter result identity，也未约束枚举。
- HIGH 5：user-decision handoff未绑定来源任务一致性，也未强制`USER_DECISION_CHANGE`等必要invalidator。
- HIGH 6：controller authorization未绑定projectId、规范controller locator及完整controller schema。
- HIGH 7：route checker允许未知route/message类型，并可能把stale ACK/DECISION包装为exception通过。
- HIGH 8：root upgrade在替换live对象前不复证冻结preimage，存在覆盖并发修改且回滚丢字节风险。
- HIGH 9：central legacy、重复upgrade及controller epoch>1后的register兼容/幂等闭包不足。
- HIGH 10：migration未解析授权包角色，可能把DOMAIN_OWNER包误列入controller撤销清单。
- 证据上限：上述结论来自exact39静态参数/数据流、schema与入口闭包审核；Reviewer未运行candidate tests、真实remote、Git、external、项目采用或任何写入。1.5.2、live root与exact39均末复证无漂移。

## Remediation closure

- exact15包实际修改14个direct producer/consumer/docs/tests；`CONTROLLER_SCHEMA.json`复证无需字节修改。没有第16个实现路径、第三职责路径或D/E/F/H泄漏。
- remote：现场local/remote head、endpoint fingerprint、refspec、authorization identity、evidence scope/excludes/receipt逐字绑定；protected路径双向重叠拒绝；PRIMARY禁止补偿action；COMPENSATION强制不同的独立授权locator+identity并现场复证。
- resource/handoff：phase、host class、context identity、adapter result identity现场绑定；phase/host/枚举失效负键与handoff source/user decision/locator invalidators已补。
- controller/route：PROJECT_CONTROLLER包绑定projectId与规范controller locator并执行完整schema；route/message枚举及合法组合冻结，stale ACK/decision/authorization不能包装成exception。
- migration：每次live replace前复证preimage；DOMAIN_OWNER输入拒绝进入revocation ledger；rotated register、重复upgrade、四来源repo-local及central拓扑边界明确；未知并发字节保留并停止。
- writer evidence：full direct=`120/120`；skip-root=`96/96`；hotfix=`1/1`；strict/syntax/JSON/inventory/exact39全部PASS；1.5.2与live root scripts零漂移。该证据不等于独立Review、release、真实remote、Git或项目采用。

## Review-2 verdict

- verdict：`CHANGES_REQUESTED / 3 HIGH / REPEATED`；reviewer=`/root/fw_160_acg_review_2(RELEASED)`；candidate=`A_C_G_CANDIDATE_002` exact39末复证无漂移。
- HIGH 1：stale decision/authorization仍可同时改写outer `messageClass`与`routeClass`为`EXCEPTION`并自报revalidation后通过；必须绑定不可变original envelope identity/class与current task stable identity，且原始ACK/decision/authorization无论外层包装都拒绝。
- HIGH 2：upgrade target在old material冻结前由live bytes派生，首次读取到事务copy之间仍有TOCTOU窗口；必须从冻结材料派生target，或冻结首次读取identity并在copy/replace前逐次复证，且补首次读取后漂移负键。
- HIGH 3：`ALREADY_UPGRADED`只部分检查revocation ledger；必须严格验证完整字段集、类型、枚举、条目identity与canonical/known schema，补tampered-ledger负键，同时允许合法current controller epoch大于1。
- 其余Review-1的7项已闭合；本轮没有D/E/F/H、knowledge职责泄漏，没有1.5.2、live root、CURRENT、project pin、Git、remote或external写入。
- 证据上限：上述结论来自exact39静态producer/checker/schema/迁移数据流复证；Reviewer未运行candidate tests、Git、remote或external。原`REVIEW_EXECUTE`包已消费失效，不得复用。

## Review-3 verdict

- verdict：`CHANGES_REQUESTED / 2 HIGH / 1 LOW`；reviewer=`/root/fw_160_acg_review_3(RELEASED)`；candidate=`A_C_G_CANDIDATE_003` exact39末复证无漂移；`RANGE_GATE=NONE`。
- HIGH 1：remote primary/compensation authorization只把identity与现场观察绑定，未把locator逐字绑定；`authorizationLocator`也未被严格类型检查或纳入idempotency key。需增加现场primary+compensation locator观察、类型门、幂等键组成与两类locator drift负键。
- HIGH 2：`ALREADY_UPGRADED`对legacy entry identity仍只做格式与canonical自证，没有从现场legacy locator或独立冻结证据复算真实bytes identity。需补真实来源复算与“格式合法但值被篡改”的canonical ledger负键，同时保留current controller epoch 2正例。
- LOW：父卡Review门残留`fresh Review-2=ACTIVE`，与current Review-3冲突；随本verdict控制写机械同步。
- 已确认闭合：stale decision/auth包装与upgrade TOCTOU；其余Review-1回归未见退化。候选继续`DRAFT / NOT_CONSUMABLE`，D/E/F/H/knowledge无职责泄漏，1.5.2/live root/CURRENT零漂移。
- 证据上限：Reviewer只做静态exact39审查，未运行candidate tests、Git、remote、external或release。原Review-3包已消费失效，不得复用。

## Remediation-3 closure

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REMEDIATION-3.authorization.json|1846|36A4C97FCE818BA147A5DB589B626D838E5315502089C9F174A58723BB821F8F`；`CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`，writer=`NONE`。
- remote：primary与compensation authorization locator+identity均由现场观察逐字绑定；locator严格string类型并进入幂等键，主/补偿locator漂移负键均拒绝。
- migration：`ALREADY_UPGRADED`从每个ledger locator重读legacy载体并复算bytes identity；canonical但伪造的identity负键拒绝，合法current controller epoch 2正例保留。
- evidence：full direct=`129/129`；skip-root=`101/101`；hotfix=`1/1`；strict=`39/39`；syntax=`9/9`；JSON=`5/5 + templates 2`；exact39、changed5、outside drift 0；1.5.2与live root零漂移。
- 证据上限：仅candidate direct/static与隔离临时repo迁移；不是独立Review、release、真实remote、Git、CURRENT、project pin或项目采用。

## Review-4 verdict

- verdict=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM`；reviewer=`/root/fw_160_acg_review_4(RELEASED)`；candidate=`A_C_G_CANDIDATE_004` exact39末复证无漂移；`RANGE_GATE=NONE`。
- HIGH 1：compensation authorization locator+identity未进入无歧义幂等键，也未进入previous-ledger retry冻结字段；可在retry更换补偿授权并沿用旧key。现有`|`拼接本身还能由合法DTO分段碰撞。需改为canonical/length-prefixed或hash key，绑定primary与compensation授权及presence，并补retry与碰撞负键。
- HIGH 2：首次upgrade在冻结legacy PROJECT_CONTROLLER载体后，Apply与revocation落盘前未再次复证locator+identity；并发漂移时可成功写入旧identity。需在Apply前和ledger落盘前复证全部载体，漂移/缺失/迁移进入recoverable fail-closed，并补两个时序负键。
- MEDIUM：remote checker对`sourceTransactionId`、`originalReceipt`等补偿DTO字段使用字符串强转，未落实唯一schema的真实JSON string类型与相应约束。至少补numeric负键并让checker/schema一致。
- 已确认Review-3两个finding本体闭合，缺口位于其后续幂等/retry与事务时序；Review-1/2其他回归未见退化。Reviewer未运行candidate tests、Git、remote、external或release。

## Consumed Review-4 authorization

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW-4.authorization.json|10144|04364603368F2BEFDA84F6F654E9829DF207C0DBB393E64C23CBFDC353E56028`
- `CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`；原action=`REVIEW_EXECUTE`，reviewer已返回上述verdict并释放；不得复用为返工、重审、test、Git或release。

## Remediation-4 closure

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REMEDIATION-4.authorization.json|2080|5D62320EEAE0763651691EF660E5220943590F35F455D0819C3F382883009BCA`；`CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`，writer=`NONE`。
- remote：幂等键改为ordered canonical frozen-input JSON的SHA-256，逐字包含primary与compensation authorization locator+identity及presence；retry也冻结两项补偿授权字段。分隔符碰撞与补偿授权retry漂移负键均拒绝。
- DTO：schema将idempotency key收敛为64位SHA-256；checker落实transaction/source ID、receipt/refspec/error class与original receipt的真实类型/长度/格式门，numeric source/original receipt负键拒绝。
- migration：全部legacy载体在Apply入口及revocation落盘前各复算一次冻结identity；inventory后漂移在事务前停止，事务中漂移触发recoverable rollback，载体缺失/迁移与canonical假identity均拒绝。
- evidence：full direct=`136/136`；skip-root=`105/105`；hotfix=`1/1`；strict=`39/39`；syntax=`9/9`；JSON=`5/5 + templates 2`；exact39、changed6、outside drift 0；1.5.2与live root零漂移。
- 证据上限：仅candidate direct/static与隔离临时repo迁移；不是独立Review、release、真实remote、Git、CURRENT、project pin或项目采用。

## Review-5 verdict and consumed authorization

- verdict=`CHANGES_REQUESTED / 2 HIGH / 1 MEDIUM`；reviewer=`/root/fw_160_acg_review_5(RELEASED)`；candidate=`A_C_G_CANDIDATE_005` exact39末复证无漂移；`RANGE_GATE=NONE`。
- HIGH 1：previous ledger未绑定冻结bytes identity且未完整复验，旧`SUCCEEDED`可被篡改为`FAILED/UNKNOWN`后重新尝试不可逆remote动作。
- HIGH 2：draft root register/upgrade仍运行整仓Git status且没有可靠protected allow/exclude接口，不能在安全摘要失败时诚实保留`UNVERIFIED`。
- MEDIUM：PRIMARY携带`sourceTransactionId`时checker未落实唯一schema的真实string/pattern门，numeric值可被机械接受。
- 已确认Review-4的canonical幂等键、补偿授权retry冻结与legacy inventory两阶段复证本体闭合；1.5.2、live root、CURRENT与exact39无漂移。Reviewer未运行candidate tests、Git、remote、external或release。
- 原package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW-5.authorization.json|10144|485AA565A9827028CACA52C77DEB72EB7B373CAB30D0C94CAFA3E980FD14CBFD`已`CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`，不得复用为返工、Review-6、test、Git或release。

## Remediation-2 closure

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REMEDIATION-2.authorization.json|1840|9FBE9316BAB20773A966CEE6D0C95CD66FB1ADF14DA1B8AF7AC38D6DF1DDB782`
- `CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`；原actor/writer=`/root`，actions=`SOURCE_WRITE / TEST_WRITE / TEST_RUN`，exact5；writer已释放。
- stale route：original envelope的locator+外部observed identity+original class与current task locator+现场identity+task ID已绑定；双重改写decision class的负键拒绝，current task漂移负键拒绝。
- upgrade：project/Bootstrap首次严格读取identity成为冻结preimage，Apply前与old copy后复证；首次读取后漂移负键拒绝。`ALREADY_UPGRADED`严格校验canonical完整ledger；未知字段负键拒绝，合法current controller epoch 2通过。
- evidence：full direct=`125/125`；skip-root=`98/98`；hotfix=`1/1`；strict=`39/39`；syntax=`9/9`；JSON=`5/5 + templates 2`；exact39、changed5、outside drift 0；1.5.2与live root零漂移。
- 证据上限：仅candidate direct/static与隔离临时repo迁移；不是独立Review、release、真实remote、Git、CURRENT、project pin或项目采用。

## Candidate-2 remediation-2 preimages (audit only)

- `framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md|1879|171E8E1EC60106A9745B975A8FCFF0626FA064BA67695267CAF6378A748D2547`
- `framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md|6914|0D70F795B87B2EAA6CBAA1EE8E05AD5FF2B5203B2E20D3E66A3CB2B65B60D41C`
- `framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1|10383|A875A1C40DFA7B6142F1FA913059BB3B6927FE724FF043A64951D11ECD3DA1BC`
- `framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1|50684|C1042EA11AE31ED958A62CC4BFB4860929253B5B463F7246ED60B7C8B36CFF1C`
- `framework/drafts/1.6.0/root-scripts/upgrade-project.ps1|22224|EDE016EF088442D6837C6E9525B83EB8008FC76BD67625A1D6B4081D0AFA579C`

## Consumed Review-3 authorization

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW-3.authorization.json|9330|8D0CD37CC10C856DC07833BF22AF8A68040C02C486C420BF45A24935553F5FA4`
- `CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`；原action=`REVIEW_EXECUTE`，reviewer已返回`CHANGES_REQUESTED / 2 HIGH / 1 LOW`并释放；不得复用为返工、重审、test、Git或release。

## Stable candidate identity manifest

`A_C_G_CANDIDATE_005`：

- `framework/drafts/1.6.0/candidate/AUTHORIZATION_MODEL.md|7237|770CB80F54E0EDC8136C71EC93284A8D0AF804F52522AFD3A1C8B7E32F7F335B`
- `framework/drafts/1.6.0/candidate/CHANGELOG.md|1241|A07507DD39AE6183958E4AAA28C7005C61B3D82150A2C4F420912CCA2D365258`
- `framework/drafts/1.6.0/candidate/EXAMPLES.md|6148|0F5D7909E32E4C7EF4C0E5B941C440FA46F1C8CA01BCA0F8377C6B5F73A561F0`
- `framework/drafts/1.6.0/candidate/FRAMEWORK_RELEASE.md|1368|B70363DF464686CBE13395BD127137ECB58ABDDDCE61577402387CACE7F90B6B`
- `framework/drafts/1.6.0/candidate/GIT_AND_EXTERNAL.md|5937|0A198066A9357B3C1239D1EC3C6821948FF3EE8B5DC2AC91700EE90DA7285041`
- `framework/drafts/1.6.0/candidate/HOST_CODEX.md|4771|2018078AE17B03E26A1C627B554BA0FE92367D642DD308DA294AC6E88C006305`
- `framework/drafts/1.6.0/candidate/LOAD_MANIFEST.json|1160|C376CF4D561F6B41D05E86F827ABA2ABD1B1F541318877257094B9E180694E5F`
- `framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md|2793|C0742FCB71CE8212BC38B88D3B70AC6872650A964B62E3CC5A8A1CB79DD5FCCA`
- `framework/drafts/1.6.0/candidate/PERSPECTIVE_LENSES.md|1808|54A5C448A92EE72A822924A9389B413F949154ED38102711E037C2713785FADC`
- `framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md|7821|DF09E15C80C08E928DA1082D3C9238BFF5B4557AC821FDCD81F41CB540BA7CD5`
- `framework/drafts/1.6.0/candidate/project-starter/.gitattributes|81|22743A2F0D26EF3D1C5A0941DDDB2A67C2A7D339383793911E677310B4A7E73B`
- `framework/drafts/1.6.0/candidate/project-starter/BOOTSTRAP.md|3618|60BB2BE22B1FBF2E9D572DB7ACD5B6815892A8ED0600E1BA5D140196BA8F6FA3`
- `framework/drafts/1.6.0/candidate/project-starter/project.json|239|EC301CB9C3AB3A921BE9E8273760908D8F73E008CC6146E721EF1623BFF46AF4`
- `framework/drafts/1.6.0/candidate/project-starter/PROJECT.md|1867|0B747C9E784DA1DA7513059EFAD35908257BA306BB4983D7C2A34242078F792B`
- `framework/drafts/1.6.0/candidate/project-starter/RELATIONSHIPS.md|491|4A908CD3406C1EFA8C255B273987DBE193158E2C1610C4F52203DF0D721F3AD0`
- `framework/drafts/1.6.0/candidate/project-starter/REVIEW_PROFILE.md|1785|851509EA105A5F2EEED8FD2E3853F4C1C8A0FB076F2D00D307F411EB4472FA87`
- `framework/drafts/1.6.0/candidate/project-starter/STATUS.md|1539|45895E44E951173786A66D0CE0A49506BAB59D5B6031E9DF2ACBDC0C2F09CF47`
- `framework/drafts/1.6.0/candidate/project-starter/tasks/README.md|791|4C02FBC9362202FB3CAC72C39C511734227A1E9246497EB451296541330955B8`
- `framework/drafts/1.6.0/candidate/PROMPTS.md|3345|FE08E9D814F90AD1857AD1F376A3AE11270C273F1074920418B2036BAD15E787`
- `framework/drafts/1.6.0/candidate/README.md|1599|3CDFF027512D1F06145527CFDE3C7EB51BF083CC6A12FFEF334EF7ADC4ED197C`
- `framework/drafts/1.6.0/candidate/RECOVERY_CORE.md|10886|8AFE2D16B47D0C0167ABEACAB99512A4249F4CC2FE5728240FFD51A4D60DD28B`
- `framework/drafts/1.6.0/candidate/RELEASE_MANIFEST.json|793|EDB7587482D67E2B8E8B9E9BF5A431D66F9958C6D2941819E841B1D01F75B0CB`
- `framework/drafts/1.6.0/candidate/REVIEW_AND_EVIDENCE.md|10028|393AF7049ECBAE54ECDA7B61D828CCCCAD39EC3DD8FCD9A49768B4AF20887DF8`
- `framework/drafts/1.6.0/candidate/scripts/check-authorization.ps1|17065|FE232F047B10D8C4F1263DD4A4B7BD8E7FAE2EA46BFD1B13C515AE8B40D8ABD6`
- `framework/drafts/1.6.0/candidate/scripts/check-task-card.ps1|25654|936D6A720C1A4C80F90358FF293DD05C8BB2EB2EF9F0BADF95A3BB6B7FF46EB7`
- `framework/drafts/1.6.0/candidate/scripts/resolve-load-plan.ps1|3324|789CC426130D7AABC5F8CA8964AB3383CE832A48BB0858A5DE3D8B0882DC1137`
- `framework/drafts/1.6.0/candidate/STATIC_COMPARISON.md|1070|9434A1A2F96E5D98049659F022491EDF03FEFA24A20E0461EDA51521A8B0A41A`
- `framework/drafts/1.6.0/candidate/TASK_AND_SCOPE.md|12386|BA54BD142E5E81EB0A9860B5984D3CF4FC08C2C7CFAF3161C1BE11D11F4D00D7`
- `framework/drafts/1.6.0/candidate/TASK_TEMPLATE.md|9975|4218128DD674496307B181DB340C326237BDF18717584DD440DAC4DA35A90625`
- `framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1|68350|B7501BCC06A15C6E16C93A6A249A1E863A6B7E54A92A40B4B0EA8C58AA7C6C9C`
- `framework/drafts/1.6.0/candidate/tests/run-hotfix-tests.ps1|889|B76D2BB754D86DAAFD5BFB8887F09F26F3B0E57232D63DAF27DCECA6181F29B3`
- `framework/drafts/1.6.0/candidate/VERSION.json|286|9DA7800DD0C2781EE577D7B655766CAA2A50136DDE5C14555B444935A2FB7A37`
- `framework/drafts/1.6.0/candidate/CONTROLLER_SCHEMA.json|727|57EB41DD8FC34D4FC86C0DB12F826A21091FFFE2C7FF6282FD0F74B0D459CB1E`
- `framework/drafts/1.6.0/candidate/REMOTE_TRANSACTION_SCHEMA.json|5303|6F6958066907C184B0E6BE41A85A40E0427ACE9B33C061C7A9C790E4449C742E`
- `framework/drafts/1.6.0/candidate/project-starter/controller.json|128|22AE70C2A723A61D935778755DD0663712853132A4746AD0F293087DC09FEB55`
- `framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1|15575|9E4BA115C0744DA2BF8394ECEF0FE1A03FF01E4386889A454451FA2F0A59D10E`
- `framework/drafts/1.6.0/candidate/scripts/check-remote-transaction.ps1|23660|32990FDE7C5D4BCCFA08B59B95CAF4F119FC165E7440029E6C4C18F62A1C0F95`
- `framework/drafts/1.6.0/root-scripts/register-project.ps1|27308|0777C5FF318101621D65056644BF5AC933E0CBF37735A35B5A1AEEB8699CDB6B`
- `framework/drafts/1.6.0/root-scripts/upgrade-project.ps1|27735|985B7C64B8C173A6414A96B7946C3EEFB2489B0E293B14C3C49463CEB5D15A49`

## Consumed remediation authorization

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REMEDIATION.authorization.json|4068|F521987D78C03C5DA251C0377A566E20E9143F5AE0C234F4EBB5552BC772717B`
- `CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`；原actor/writer=`/root`，actions=`SOURCE_WRITE / TEST_WRITE / TEST_RUN`，exact15；writer已释放。不得复用为Review、D-E/F、Git、release或项目采用。

## Consumed Review-2 authorization

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW-2.authorization.json|9314|285E6FA12E0C2FD1D95C20E522277D134F5C37F43FF00D0F8AD431CACCE5AFA3`
- `CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`；原action=`REVIEW_EXECUTE`，reviewer已返回`CHANGES_REQUESTED / 3 HIGH / REPEATED`并释放；不得复用为返工、重审、test、Git或release。

## Consumed review authorization

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW-FRESH2.authorization.json|10181|55A1E812B18C0312B9F0FA4965EA4D45A1AFC6B791A1767FA0AFBA778333D9F4`；`CONSUMED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`
- 原action=`REVIEW_EXECUTE`；reviewer已返回`CHANGES_REQUESTED`并释放；不得复用为返工、重审、test、Git或release。

## Interrupted review authorization (audit only)

- package=`.tmp/AIW-FW-1.6.0-A-C-G-REVIEW.authorization.json|10189|5084B70F7B02559A1F654EB55698AB977B740152999C2C491258AAC65CBD6D08`；`REVOKED / NON_CURRENT / AUDIT_ONLY / NO_ACTION`
- 原action=`REVIEW_EXECUTE`；reviewer在verdict前中断；exact39候选未变，但旧包不得恢复、重发或视为审核通过。


## Consumed implementation authorization (audit only)

- NON_CURRENT / AUDIT_ONLY / NO_ACTION；原writer lease已随实现完成和writer释放而消费，不得复用为Review、返工、Git或release。

```authorization-package-history
{
  "schemaVersion": 1,
  "frameworkVersion": "1.5.2",
  "taskId": "AIW-FW-1.6.0-A-C-G-001",
  "profile": "CRITICAL",
  "lifecycle": "CONSUMED",
  "owner": "019ffe25-9941-7490-808a-a5fbd8bbe23a",
  "issuer": "019ffe25-9941-7490-808a-a5fbd8bbe23a",
  "issuerRole": "DOMAIN_OWNER",
  "grantee": "/root/fw_160_acg_writer",
  "bundle": "IMPLEMENT_LOCAL",
  "decisionClass": "ROUTINE_LOCAL",
  "userConfirmation": "NOT_REQUIRED",
  "reviewIndependence": "NOT_APPLICABLE",
  "delegatedGitCloser": false,
  "actions": [
    "SOURCE_WRITE",
    "TEST_WRITE",
    "TEST_RUN"
  ],
  "exactPaths": [
    "framework/drafts/1.6.0/candidate/AUTHORIZATION_MODEL.md",
    "framework/drafts/1.6.0/candidate/CHANGELOG.md",
    "framework/drafts/1.6.0/candidate/EXAMPLES.md",
    "framework/drafts/1.6.0/candidate/FRAMEWORK_RELEASE.md",
    "framework/drafts/1.6.0/candidate/GIT_AND_EXTERNAL.md",
    "framework/drafts/1.6.0/candidate/HOST_CODEX.md",
    "framework/drafts/1.6.0/candidate/LOAD_MANIFEST.json",
    "framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md",
    "framework/drafts/1.6.0/candidate/PERSPECTIVE_LENSES.md",
    "framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md",
    "framework/drafts/1.6.0/candidate/project-starter/.gitattributes",
    "framework/drafts/1.6.0/candidate/project-starter/BOOTSTRAP.md",
    "framework/drafts/1.6.0/candidate/project-starter/project.json",
    "framework/drafts/1.6.0/candidate/project-starter/PROJECT.md",
    "framework/drafts/1.6.0/candidate/project-starter/RELATIONSHIPS.md",
    "framework/drafts/1.6.0/candidate/project-starter/REVIEW_PROFILE.md",
    "framework/drafts/1.6.0/candidate/project-starter/STATUS.md",
    "framework/drafts/1.6.0/candidate/project-starter/tasks/README.md",
    "framework/drafts/1.6.0/candidate/PROMPTS.md",
    "framework/drafts/1.6.0/candidate/README.md",
    "framework/drafts/1.6.0/candidate/RECOVERY_CORE.md",
    "framework/drafts/1.6.0/candidate/RELEASE_MANIFEST.json",
    "framework/drafts/1.6.0/candidate/REVIEW_AND_EVIDENCE.md",
    "framework/drafts/1.6.0/candidate/scripts/check-authorization.ps1",
    "framework/drafts/1.6.0/candidate/scripts/check-task-card.ps1",
    "framework/drafts/1.6.0/candidate/scripts/resolve-load-plan.ps1",
    "framework/drafts/1.6.0/candidate/STATIC_COMPARISON.md",
    "framework/drafts/1.6.0/candidate/TASK_AND_SCOPE.md",
    "framework/drafts/1.6.0/candidate/TASK_TEMPLATE.md",
    "framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1",
    "framework/drafts/1.6.0/candidate/tests/run-hotfix-tests.ps1",
    "framework/drafts/1.6.0/candidate/VERSION.json",
    "framework/drafts/1.6.0/candidate/CONTROLLER_SCHEMA.json",
    "framework/drafts/1.6.0/candidate/REMOTE_TRANSACTION_SCHEMA.json",
    "framework/drafts/1.6.0/candidate/project-starter/controller.json",
    "framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1",
    "framework/drafts/1.6.0/candidate/scripts/check-remote-transaction.ps1",
    "framework/drafts/1.6.0/root-scripts/register-project.ps1",
    "framework/drafts/1.6.0/root-scripts/upgrade-project.ps1"
  ],
  "objectIdentities": [
    {
      "path": "framework/drafts/1.6.0/candidate/AUTHORIZATION_MODEL.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/CHANGELOG.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/EXAMPLES.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/FRAMEWORK_RELEASE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/GIT_AND_EXTERNAL.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/HOST_CODEX.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/LOAD_MANIFEST.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/MIGRATION_MATRIX.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/PERSPECTIVE_LENSES.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/PROJECT_CONTROL.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/.gitattributes",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/BOOTSTRAP.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/project.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/PROJECT.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/RELATIONSHIPS.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/REVIEW_PROFILE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/STATUS.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/tasks/README.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/PROMPTS.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/README.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/RECOVERY_CORE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/RELEASE_MANIFEST.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/REVIEW_AND_EVIDENCE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/scripts/check-authorization.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/scripts/check-task-card.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/scripts/resolve-load-plan.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/STATIC_COMPARISON.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/TASK_AND_SCOPE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/TASK_TEMPLATE.md",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/tests/run-framework-tests.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/tests/run-hotfix-tests.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/VERSION.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/CONTROLLER_SCHEMA.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/REMOTE_TRANSACTION_SCHEMA.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/project-starter/controller.json",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/scripts/check-controller-route.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/candidate/scripts/check-remote-transaction.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/root-scripts/register-project.ps1",
      "identity": "NEW"
    },
    {
      "path": "framework/drafts/1.6.0/root-scripts/upgrade-project.ps1",
      "identity": "NEW"
    }
  ],
  "invalidatesOn": [
    "TASK_CHANGE",
    "OWNER_CHANGE",
    "GRANTEE_CHANGE",
    "ACTION_CHANGE",
    "PATHSET_CHANGE",
    "OBJECT_DRIFT",
    "USER_DECISION_CHANGE"
  ]
}
```

## History locator

- parent=`framework/drafts/1.6.0/FRAMEWORK_TASK.md|7867|34FD78AC029DA094880B73635639366A9698645B0429B7DCB0EEE634D96A4A02`
