# AIW-FW-1.6.1-KNOWLEDGE-ENTRY-ID-001 — 1.6.1 Entry ID补丁实现

- 状态：`FRAMEWORK_1.6.1_RELEASE_COMPLETE / LIVE_ROOT_ACCEPTED / CURRENT_REMAINS_1.4.1 / STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE / WRITER_NONE / REVIEWER_NONE`
- Task schema: 1.5.2
- 档位：`CRITICAL`
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前actor / writer：`NONE / NONE / RELEASED(/root/fw_161_live_root_writer)`
- Reviewer：`NONE`；focused live-root Reviewer `/root/fw_161_live_root_review` 已 `APPROVED / 0 finding / RELEASED`
- Stable candidate: `FRAMEWORK_1.6.1_LIVE_ROOT_EXACT6`
- Resource requirement: minimum=FOCUSED_HIGH; requiredTools=[filesystem|shell]; continuity=SAME_CONTEXT_IMPLEMENT; finalReview=FRESH
- Range summary: profile=CRITICAL; lifecycle=REVIEW; current_exact=FRAMEWORK_1.6.1_LIVE_ROOT_EXACT6; expected_paths=[framework/drafts/1.6.1/FRAMEWORK_TASK.md|framework/drafts/1.6.1/IMPLEMENTATION_ENTRY_ID.md|README.md|INITIALIZATION.md|scripts/register-project.ps1|scripts/upgrade-project.ps1]; actual_paths=[framework/drafts/1.6.1/FRAMEWORK_TASK.md|framework/drafts/1.6.1/IMPLEMENTATION_ENTRY_ID.md|README.md|INITIALIZATION.md|scripts/register-project.ps1|scripts/upgrade-project.ps1]
- Phase gate: FALSE
- Git / CURRENT / release / Pocket adoption：`CLOSED / CLOSED / CLOSED / CLOSED`

## Implementation contract

- baseline=`framework/versions/1.6.0`，稳定包与live root在本任务期间只读。
- functional delta只允许：现有knowledge checker的可选`EntryId`精确选择、direct tests、相关知识/宿主/发行说明，以及既有root register/upgrade对1.6.1的同拓扑兼容。
- mechanical delta只允许：1.6.0→1.6.1版本投影、DRAFT元数据与manifest重算。
- checker必须先完成全索引、全部CURRENT reference/authority复证，再做选择；无参数保留1.6.0前三条行为。
- upgrade复用唯一`.framework-upgrade-transaction`；不得新增事务引擎、并发模型、自动清理、ledger、cache、search/ranking或第二knowledge入口。

## Verification

- direct positives：单选、三选、稳定排序、无参数兼容。
- direct negatives：重复、unknown、non-current、空/非法、超过3个；未选择CURRENT漂移仍全局失败。
- compatibility：1.6.0 stable及live root零漂移；1.4.1/1.5.x→1.6.0回归；1.6.0→1.6.1 preview/apply/repeat/recovery；controller/custom block保持。
- closure：strict UTF-8/LF、JSON、PowerShell syntax、inventory、load成本与manifest canonical。

## Current authorization

- current package=`NONE`；live-root Review包已消费删除；Framework本任务不再授权写入，CURRENT、Pocket采用与Git仍另门。
- Review-1 verdict=`CHANGES_REQUESTED / exact3 bounded findings / reviewer RELEASED`。
- 不授权Review/Git/release/CURRENT/Pocket。

## Frozen result

- stable candidate=`FRAMEWORK_1.6.1_ENTRY_ID_CANDIDATE_001`。
- manifest=`framework/drafts/1.6.1/candidate/RELEASE_MANIFEST.json|641|271DF8A8D8DD4DC0A247549EDA3007A4082194F147C9325F038FFEC24F39E664`。
- payload=`37 files / 210525 bytes / 0D5DFDFA2EBF0C3ECBDFF82132C05A23778548F1F1A2BD3FEF5A5485516D241B`；candidate inventory=`exact38`。
- baseline comparison=`exact18 byte-identical / exact20 functional+mechanical delta`；root candidate exact3只存在于draft，live root零漂移。
- RECOVERY_SIMPLIFY_V2 target functional=`127/127 PASS`；quick=`84/84 PASS`，含manifest quick=`85/85 PASS`；manifest重算后的final full=`128/128 PASS`。PowerShell syntax exact8、strict UTF-8/LF、JSON、inventory exact38、stable1.6.0/live root/CURRENT zero-drift与manifest canonical均PASS。
- 实际闭合：active transaction在任何普通`ToVersion`分派前唯一发现；显式恢复与commit-catch统一调用同一Recover签名并传ControllerId/requested target。CREATE→1.6.0验证冻结new controller；1.6.0→1.6.1/NONE验证current controller；旧generic NONE保持稳定恢复合同；矩阵外与target mismatch fail closed。CREATE/NONE OLD/MIXED/NEW、prep-only、active+prep、preview、显式恢复、commit-catch与old generic NONE均有direct coverage，且未新增schema/helper truth/transaction/service/lock/ledger。
- V2 root upgrade=`framework/drafts/1.6.1/root-scripts/scripts/upgrade-project.ps1|53289|6FE409A562A8D773C5A96D2B42E9E206DF8B6547326FA873D1A8C2349747DBC9`；writer=`RELEASED`；fresh final Review=`APPROVED / 0 finding / reviewer RELEASED`，owner已接受。
- evidence ceiling：isolated active-transaction fixtures、draft脚本验证与fresh静态Review；不是stable release、live-root替换、CURRENT、Pocket采用、自然查询或Git证据。

## Stopline

任何schema/loader拓扑/capability形状变化、自然语言检索/排名、第二入口/事务、自动服务或exact43外职责路径，立即停止并回owner，不得补条件链。

## Owner SIMPLIFY design freeze

- 将active transaction发现提升到所有`ToVersion`普通分派之前，并删除legacy/generic两个caller各自恢复的双入口。
- 将冻结state、requested target与controller precondition集中到唯一`Recover-UpgradeTransaction`；显式恢复和commit失败rollback都不得绕过。requested target必须等于冻结`toVersion`。
- 兼容矩阵：`CREATE→1.6.0`验证冻结new controller；`1.6.0→1.6.1/NONE`验证current controller；其他既有generic NONE保持稳定1.6.0恢复合同；矩阵外拒绝。
- `prep-only`、`active+prep`、preview、显式恢复、commit-catch及CREATE/NONE的OLD/MIXED/NEW进入一张测试状态表。显式恢复失败承诺整次零mutation；commit-catch只承诺进入Recover后零新增mutation并保留mixed transaction。
- 无active transaction才进入普通版本路径；existing exact5外不写，不新增第二事务/helper truth/service/lock/ledger。

## Final Review acceptance

- exact43=`APPROVED / 0 finding`；active transaction唯一发现、两个Recover caller共用单一state/target/controller gate，兼容矩阵与双mutation ceiling均经独立静态证伪后成立。
- candidate exact38与manifest保持冻结，任何payload变化都使本批准失效。

## Stable projection result

- stable object=`framework/versions/1.6.1/RELEASE_MANIFEST.json|653|4E5DDDD30AD7EF00B934D63FDC1E0019AF4D5AE92DFBB7D0B0029113E7A49901`；payload=`37 files / 211032 bytes / 67F33F95DC650F9FF5E8CBF55E53F7B19F9A5D6F906DB7DA31D727A73B42FFBD`；状态=`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE / RELEASE_REVIEW_APPROVED / OWNER_ACCEPTED`。
- projection range=`parent + child + stable exact38 = exact40`。相对approved candidate，actual exact8稳定投影delta=`README.md / CHANGELOG.md / STATIC_COMPARISON.md / LOAD_MANIFEST.json / VERSION.json / RELEASE_MANIFEST.json / scripts/resolve-load-plan.ps1 / tests/run-framework-tests.ps1`；其余exact30逐字一致。
- stable manifest保持`sourceCandidate=FRAMEWORK_1.6.1_ENTRY_ID_CANDIDATE_001 / sourceReview=APPROVED / current=1.4.1 / projectPinsChanged=false`；VERSION为`STABLE / consumable=true / currentEligible=false / projectPinEligible=true`。
- stable quick=`84/84 PASS`；stable full applicable=`86/86 PASS`，其中live root仍为approved 1.6.0 exact3，因此1.6.1 root adoption由self-test明确保持`SEPARATE_GATE`，candidate full=`128/128 PASS`继续作为隔离root transaction fixture证据。
- strict UTF-8/LF exact38、rendered JSON exact8、PowerShell syntax stable exact6 + candidate-root exact2 + live-root exact2、inventory exact38、manifest canonical与candidate→stable exact8/identical exact30均PASS；approved candidate、stable 1.6.0、live root与`CURRENT=1.4.1`零漂移。
- evidence ceiling=`immutable stable payload + isolated stable checker fixtures + approved candidate isolated root-transaction fixtures + static identities`；不是fresh formal release Review、live-root替换、CURRENT、Pocket采用、自然查询或Git证据。writer已释放且未自Review。

## Focused formal release Review

- verdict=`APPROVED / 0 finding / reviewer RELEASED`；stable exact38已由owner接受。
- actual projection=`exact8 delta / exact30 byte-identical`；manifest、稳定生命周期、loader/self-test布局及证据上限均独立复证成立。

## Live root adoption result

- approved draft root exact3已逐字投影到live root：`INITIALIZATION.md|9392|B13A307DEF4FC47B32FD1DC1FFF051A5F2063C043131EFC162C7E4BA5539E88F`；`scripts/register-project.ps1|26819|A4463AC6B95BA79BF218B28C7B85C9F94154B96F9B15531B60E458B7EEF4DA0C`；`scripts/upgrade-project.ps1|53289|6FE409A562A8D773C5A96D2B42E9E206DF8B6547326FA873D1A8C2349747DBC9`。
- 根`README.md|8098|EC75296F440647F7948FDC40FC7C3176F273ACF6CEEC58F4E2540961BCE0F7F7`仅同步1.6.1稳定状态、显式Entry ID兼容补丁与采用分门；`framework/CURRENT`保持`1.4.1`。
- Windows PowerShell live-root适用quick=`127/127 PASS`、full=`128/128 PASS`；稳定1.6.0 payload回归=`129/129 PASS`；root syntax、exact6 strict、stable1.6.1 manifest、register/upgrade兼容与stable1.6.0/candidate/CURRENT零漂移均PASS。
- evidence ceiling=`live exact3 byte identity + narrow README + isolated transaction fixtures + static manifests`；不是fresh focused live-root Review、CURRENT、Pocket、自然查询或Git证据。live-root授权包`.tmp/AIW-FW-1.6.1-LIVE-ROOT.authorization.json|1937|90AAE0C21172385DD0A18964A5A507B6C801A97EC61A09D68B1904062E79A90B`已消费删除；writer未自Review并已释放。

## Focused live-root Review

- verdict=`APPROVED / 0 finding / reviewer RELEASED`；live exact3与approved source逐字一致，README与stable/CURRENT边界诚实，owner已接受。

## 唯一下一动作

本Framework实现任务关闭。Pocket 1.6.1采用由Pocket current controller另立/恢复项目任务，显式预览并升级pin/control exact2；CURRENT与Git继续另门。
