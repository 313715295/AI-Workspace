# AIW-FW-1.6.1-KNOWLEDGE-ENTRY-ID-001 — Knowledge显式Entry ID兼容补丁

- 状态：`FRAMEWORK_1.6.1_RELEASE_COMPLETE / LIVE_ROOT_ACCEPTED / CURRENT_REMAINS_1.4.1 / STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE / WRITER_NONE / REVIEWER_NONE`
- Task schema: 1.5.2
- 档位：`CRITICAL`；理由=修改跨项目稳定Framework的公开knowledge checker接口与项目pin采用路径，但保持兼容、无新模块和无新持久状态
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前actor / writer：`NONE / NONE / RELEASED(/root/fw_161_live_root_writer)`
- Stable candidate: `FRAMEWORK_1.6.1_LIVE_ROOT_EXACT6`
- Range summary: profile=CRITICAL; lifecycle=REVIEW; current_exact=FRAMEWORK_1.6.1_LIVE_ROOT_EXACT6; expected_paths=[framework/drafts/1.6.1/FRAMEWORK_TASK.md|framework/drafts/1.6.1/IMPLEMENTATION_ENTRY_ID.md|README.md|INITIALIZATION.md|scripts/register-project.ps1|scripts/upgrade-project.ps1]; actual_paths=[framework/drafts/1.6.1/FRAMEWORK_TASK.md|framework/drafts/1.6.1/IMPLEMENTATION_ENTRY_ID.md|README.md|INITIALIZATION.md|scripts/register-project.ps1|scripts/upgrade-project.ps1]
- Phase gate: FALSE
- release class：`PATCH_HOTFIX`；baseline=`framework/versions/1.6.0`；稳定1.6.0不可原位修改
- 用户门：Pocket用户已要求完善项目知识内容，并接受最小显式Entry ID检索方案；禁止模糊搜索、自动索引、后台服务、结果缓存或项目私有第二checker
- Git / CURRENT / tag / push / project adoption：`CLOSED / CLOSED / CLOSED / CLOSED / SEPARATE_GATE`
- Independent Reviewer：`NONE`；focused live-root Reviewer `/root/fw_161_live_root_review` 已 `APPROVED / 0 finding / RELEASED`
- Current authorization：`NONE`；live-root Review包已消费删除；Framework本任务不再开放写入，CURRENT、Pocket采用与Git继续另门

## 目标

在不改变索引schema、loader拓扑、默认关闭能力与全索引复证语义的前提下，为现有`check-knowledge-entry.ps1`增加可选的显式Entry ID选择：

- 调用者可传入`EntryId` 1～3个；ID必须是合法字符串、区分大小写、无重复；
- checker仍先验证project config、index结构和全部CURRENT reference/authority identity；选择参数不能缩小验证面；
- 只有验证全部完成后才从CURRENT集合按请求ID选择，并按ID稳定排序返回；unknown、non-current、duplicate或超过3个均`REFERENCE_UNAVAILABLE`；
- 未提供`EntryId`时保留1.6.0的兼容行为：按ID返回前三条；
- 不做自然语言搜索、相关度、自动路由、自动索引、后台维护、结果缓存、common聚合或第二查询服务。

## 范围

### 内容候选

- 从`framework/versions/1.6.0`逐字复制完整稳定payload到`framework/drafts/1.6.1/candidate/`，未列为functional delta的文件只允许机械版本投影或保持逐字相同。
- functional delta限定在既有knowledge checker、既有test runner和既有知识/宿主/发行说明；不得新增模块、schema、checker、service或ledger。
- 版本投影必须诚实把candidate runtime、authorization、safe-Git、loader和starter绑定到`1.6.1`，并把baseline标为`1.6.0`。这是新pin的机械完整性，不是新增常态流程。

### 根采用入口

- 复用现有`INITIALIZATION.md`、`scripts/register-project.ps1`与`scripts/upgrade-project.ps1`；只增加1.6.1 schema3注册与1.6.0→1.6.1同拓扑两对象串行升级。
- 继续使用唯一`.framework-upgrade-transaction`及现有read/recover/commit骨架；controller对象只做current健康/ID核验，不被重写；PROJECT-CUSTOM逐字保留。
- 不增加第二事务引擎、并发升级、自动清理、capture/quarantine、撤销账本或自动恢复服务。

## 直接验证

1. Entry ID单选/三选、稳定排序和未传参数兼容前三条；
2. duplicate、unknown、non-current、空/非法ID、超过3个均fail closed；
3. 选择A时，未选择的其他CURRENT reference或authority漂移仍使整次查询不可用；
4. 1.6.0 stable payload与live root在candidate实现期间零漂移；
5. register 1.6.1 schema3/controller健康门；upgrade 1.6.0→1.6.1预览、apply、repeat与中断恢复，controller/custom block保持；旧1.4.1/1.5.x→1.6.0路径无回归；
6. candidate完整inventory、strict UTF-8/LF、JSON、PowerShell syntax、load成本与manifest canonical；
7. frozen candidate经fresh独立CRITICAL Review后，才允许生成`framework/versions/1.6.1`；稳定发布、root替换、CURRENT、Pocket pin与Git分别另门。

## 停止线

- 需要改变knowledge schema、loader模块拓扑、project capability形状或索引owner；
- 需要自然语言搜索/排名、缓存、服务、自动维护或项目私有入口；
- 不能复用现有单一升级事务，或旧项目兼容影响面无法证明；
- 同一finding复发、candidate范围出现第N+1职责路径或需要修改稳定1.6.0。

命中停止线即回owner做`SIMPLIFY / REMOVE / DEFER / REDESIGN`，不得继续补条件链。

## Current frozen result

- implementation card=`framework/drafts/1.6.1/IMPLEMENTATION_ENTRY_ID.md`；candidate=`FRAMEWORK_1.6.1_ENTRY_ID_CANDIDATE_001`。
- frozen manifest=`framework/drafts/1.6.1/candidate/RELEASE_MANIFEST.json|641|271DF8A8D8DD4DC0A247549EDA3007A4082194F147C9325F038FFEC24F39E664`；payload=`37 files / 210525 bytes / 0D5DFDFA2EBF0C3ECBDFF82132C05A23778548F1F1A2BD3FEF5A5485516D241B`。
- candidate inventory=`exact38`：相对stable 1.6.0，exact18逐字相同、exact20为限定功能/版本/说明/测试delta；root副本exact3只在draft内，live root未改。
- RECOVERY_SIMPLIFY_V2 target functional=`127/127 PASS`；quick=`84/84 PASS`，含manifest quick=`85/85 PASS`；manifest重算后final full=`128/128 PASS`。唯一顶层active transaction发现先于普通`ToVersion`分派；显式恢复与commit-catch都进入同一Recover签名并传显式ControllerId/requested target。CREATE与NONE的OLD/MIXED/NEW、target match/mismatch、preview、prep-only、active+prep、显式恢复、commit-catch及旧generic NONE均有确定性覆盖；precondition failure按冻结边界保留材料且零新增mutation。
- stable1.6.0与live `INITIALIZATION/register/upgrade` identity零漂移；candidate保持`DRAFT / NOT_CONSUMABLE / NOT_PIN_ELIGIBLE`。
- V2 root upgrade=`framework/drafts/1.6.1/root-scripts/scripts/upgrade-project.ps1|53289|6FE409A562A8D773C5A96D2B42E9E206DF8B6547326FA873D1A8C2349747DBC9`；strict UTF-8/LF、JSON、PowerShell syntax exact8、inventory exact38、manifest canonical、stable1.6.0/live root/CURRENT zero-drift均PASS。writer已释放；implementation包因exact5写入消费失效并删除。evidence ceiling=`isolated transaction fixtures + draft scripts + static identity`，不是fresh Review、stable release、live-root替换、CURRENT、Pocket采用、自然查询或Git证据。

## Review-1 verdict

- verdict=`CHANGES_REQUESTED / exact43 / reviewer RELEASED`；不改变Entry ID最小方案，也未触发schema、loader、service、cache、search、第二checker或第二事务停止线。
- bounded finding exact3：
  1. 区分真正未提供`EntryId`与显式空/null，并在PowerShell参数绑定转换前拒绝非字符串成员；
  2. `PROJECT_CONTROL.md`纠正为schema2先升级1.6.0、再由1.6.0以exact2升级1.6.1，并明确controller不重写、capabilities/custom保持；
  3. candidate测试必须实际消费candidate root scripts复证旧1.4.1/1.5.x→1.6.0路径，不得用`-SkipRootMigration`冒充该发行门。
- Review-1只读确认candidate/inventory/manifest、完整索引先验证、无新机制、stable1.6.0/live root/CURRENT零漂移；未运行candidate tests。

## Owner SIMPLIFY design freeze

- active transaction发现必须发生在任何`ToVersion`普通分派之前；同一`.framework-upgrade-transaction`只能由一个顶层恢复入口消费，`Invoke-Framework16Upgrade`与generic target分支不再各自拥有恢复路径。
- controller/recovery precondition进入唯一`Recover-UpgradeTransaction`本体，所有调用者（显式恢复及commit失败后的rollback）都传入`ControllerId`与requested target；本体重读冻结state后按以下兼容矩阵复证，不得在caller外围各补一份条件。
- 冻结兼容矩阵：`1.4.1/1.5.x→1.6.0 + CREATE`严格复证冻结`new/controller.json`与显式ControllerId/projectId；`1.6.0→1.6.1 + NONE`严格复证current controller regular leaf/non-reparse/strict JSON、projectId、显式ControllerId、epoch>=1、CURRENT；既有其他generic `NONE`保持1.6.0稳定恢复合同，不强加controller；矩阵外组合fail closed。
- requested target必须与冻结`toVersion`逐字相同；不相同则保留transaction且零mutation。`prep-only`与`active+prep`都保留全部材料并在恢复前fail closed；active preview必须读取/验证冻结state、target与适用controller gate后只报告RECOVERY_REQUIRED。
- 显式恢复的任一precondition失败保证调用前后`project.json / BOOTSTRAP.md / controller.json` identity不变且transaction保留。commit-catch可能已由commit写成MIXED；其precondition失败只保证从进入Recover起零新增mutation并保留mixed transaction，不虚称整次commit零mutation。
- runner状态表必须直接覆盖CREATE/NONE的OLD/MIXED/NEW、requested target match/mismatch、prep-only、active+prep、preview、显式恢复、commit-catch、旧generic NONE positive及failure-preserve边界。
- 实现范围保持existing exact5：parent、child、root upgrade、existing runner、manifest；不新增schema、事务、服务、锁、ledger、恢复目录或第二truth。

## Final independent Review verdict

- verdict=`APPROVED / 0 finding / exact43 / reviewer RELEASED`；owner已接受。
- 独立复证确认active transaction在所有普通`ToVersion`分派前唯一发现，且仅顶层显式恢复与commit-catch两个caller进入同一state/target/controller gate；alternate target或入口不能绕过。
- `CREATE→1.6.0`、`1.6.0→1.6.1/NONE`与旧generic NONE兼容矩阵、target mismatch、prep-only、active+prep、preview、显式恢复与commit-catch mutation ceiling均闭合；EntryId与旧迁移合同无回归，未引入第二transaction/helper truth/service/lock/ledger。
- Review证据上限为独立静态穿透及identity/manifest/syntax复证；未运行candidate tests。producer的`128/128 PASS`仍只代表isolated fixtures，不是stable release、live-root、CURRENT、Pocket、Git或自然查询证据。

## Stable projection result

- stable object=`framework/versions/1.6.1/RELEASE_MANIFEST.json|653|4E5DDDD30AD7EF00B934D63FDC1E0019AF4D5AE92DFBB7D0B0029113E7A49901`；payload=`37 files / 211032 bytes / 67F33F95DC650F9FF5E8CBF55E53F7B19F9A5D6F906DB7DA31D727A73B42FFBD`；状态=`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE / RELEASE_REVIEW_APPROVED / OWNER_ACCEPTED`。
- projection range=`parent + child + stable exact38 = exact40`。相对approved candidate，actual exact8稳定投影delta=`README.md / CHANGELOG.md / STATIC_COMPARISON.md / LOAD_MANIFEST.json / VERSION.json / RELEASE_MANIFEST.json / scripts/resolve-load-plan.ps1 / tests/run-framework-tests.ps1`；其余exact30逐字一致。
- stable manifest保持`sourceCandidate=FRAMEWORK_1.6.1_ENTRY_ID_CANDIDATE_001 / sourceReview=APPROVED / current=1.4.1 / projectPinsChanged=false`；VERSION为`STABLE / consumable=true / currentEligible=false / projectPinEligible=true`。
- stable quick=`84/84 PASS`；stable full applicable=`86/86 PASS`，其中live root仍为approved 1.6.0 exact3，因此1.6.1 root adoption由self-test明确保持`SEPARATE_GATE`，未伪造为stable payload evidence；candidate full=`128/128 PASS`继续作为隔离root transaction fixture证据。
- strict UTF-8/LF exact38、rendered JSON exact8、PowerShell syntax stable exact6 + candidate-root exact2 + live-root exact2、inventory exact38、manifest canonical与candidate→stable exact8/identical exact30均PASS；approved candidate、stable 1.6.0、live root与`CURRENT=1.4.1`零漂移。
- evidence ceiling=`immutable stable payload + isolated stable checker fixtures + approved candidate isolated root-transaction fixtures + static identities`；不是fresh formal release Review、live-root替换、CURRENT、Pocket采用、自然查询或Git证据。writer已释放且未自Review。

## Focused formal release Review

- verdict=`APPROVED / 0 finding / reviewer RELEASED`；owner接受stable exact38。
- candidate→stable实际仅预定exact8变化，exact30逐字一致；stable manifest由Reviewer独立复算一致，`sourceReview=APPROVED / current=1.4.1 / projectPinsChanged=false`与现场及分门合同一致。
- formal Review未运行candidate/stable tests；producer stable `84/84 quick / 86/86 full`与candidate `128/128`只代表isolated fixtures，不构成live-root、CURRENT、Pocket、自然查询或Git证据。

## Live root adoption result

- approved draft root exact3已逐字投影到live root：`INITIALIZATION.md|9392|B13A307DEF4FC47B32FD1DC1FFF051A5F2063C043131EFC162C7E4BA5539E88F`；`scripts/register-project.ps1|26819|A4463AC6B95BA79BF218B28C7B85C9F94154B96F9B15531B60E458B7EEF4DA0C`；`scripts/upgrade-project.ps1|53289|6FE409A562A8D773C5A96D2B42E9E206DF8B6547326FA873D1A8C2349747DBC9`。
- 根`README.md|8098|EC75296F440647F7948FDC40FC7C3176F273ACF6CEEC58F4E2540961BCE0F7F7`仅同步1.6.1=`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE`、显式Entry ID兼容补丁与采用分门；`framework/CURRENT`保持`1.4.1`。
- Windows PowerShell live-root适用quick=`127/127 PASS`、full=`128/128 PASS`；独立重跑稳定1.6.0 payload回归=`129/129 PASS`。root PowerShell syntax、exact6 strict UTF-8/LF、stable1.6.1 manifest canonical、1.6.1 register schema3/repeat、1.6.0→1.6.1 preview/apply/repeat/recovery、旧1.4.1/1.5.x→1.6.0与stable1.6.0/candidate/CURRENT零漂移均闭合。
- evidence ceiling=`live exact3 byte identity + narrow README + isolated transaction fixtures + static manifests`；不是fresh focused live-root Review、CURRENT切换、Pocket采用、自然查询或Git证据。live-root授权包`.tmp/AIW-FW-1.6.1-LIVE-ROOT.authorization.json|1937|90AAE0C21172385DD0A18964A5A507B6C801A97EC61A09D68B1904062E79A90B`已消费删除；writer未自Review并已释放。

## Focused live-root Review

- verdict=`APPROVED / 0 finding / reviewer RELEASED`；owner接受live root exact3与根README同步。
- live `INITIALIZATION/register/upgrade`与approved draft root exact3=`3/3 byte-identical`；README准确声明1.6.1=`STABLE / CONSUMABLE / NOT_CURRENT / PIN_ELIGIBLE`，未夸大Pocket、CURRENT或Git状态。
- `framework/CURRENT`仍为`1.4.1`；stable manifest独立复算一致。Review未运行tests，producer的live quick/full与1.6.0回归仅作声明。

## 唯一下一动作

Framework 1.6.1发行与live root闭合，不再从本任务启动实现或Review。Pocket如采用1.6.1，必须由Pocket current controller在项目任务卡下独立预览、升级pin/control exact2并fresh复证；Git/tag/push继续另门。
