# 任务模板

任务卡是current状态，不是历史日志。`<...>`必须替换；路径使用workspace相对`/`。授权包嵌在同一热卡，避免第二状态文件。只有当前阶段存在状态变更授权时保留一个`authorization-package`块；writer释放后将其lifecycle改为非ACTIVE或移入history，不能让旧包继续有效。

## 1. MICRO（可选持久卡）

健康owner能同turn闭合时不建卡；当轮仍要明确目标、exact/forbidden、验证、Git/external和结果。MICRO跨turn、阻断或扩面立即升级STANDARD。

```markdown
# <TASK-ID> — <标题>

- 状态：IN_PROGRESS
- Task schema: 1.5.2
- 档位：MICRO；理由=<四维均低的事实>
- Owner: <唯一owner>
- Range summary: profile=MICRO; lifecycle=ACTIVE_WRITE; expected_paths=[<path>]; actual_paths=[]
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 目标：<...>
- exact / forbidden：<...>
- 验收与直接验证：<...>
- 最直接失败方式：<...> → <检查>
- 唯一下一动作：<...>
```

若owner直接实施，在同卡加入最小阶段包，`issuer=owner=grantee`合法；这不是独立Review。

## 2. STANDARD紧凑热卡

~~~~markdown
# <TASK-ID> — <标题>

- 状态：READY / IN_PROGRESS / REVIEW / APPROVED / BLOCKED
- Task schema: 1.5.2
- 档位：STANDARD；理由=<影响/复杂度/依赖/可观察性>
- Owner: <唯一长期owner>
- 当前actor / writer：<OWNER|EXECUTOR|REVIEWER|USER|NONE> / <id|NONE>
- Range summary: profile=STANDARD; lifecycle=<ACTIVE_WRITE|ACTIVE|REVIEW|CLOSED>; expected_paths=[<a>|<b>]; actual_paths=[<已知actual>]
- Stable candidate: <NONE或section/manifest identity>
- Git / push / external：<状态分别列出>

## Current

- 目标：<问题、根因、目标行为、可达性>
- 非目标：<不改变的产品/合同/相邻行为>
- exact / contingency / forbidden：<...>
- 权威与影响：<producer、direct consumers、tests、runner、必要docs>
- Terminology impact：<仅新增/改变稳定概念时写BIND或CHANGE，并给canonical term、authority locator、映射、旧alias owner/退出条件；否则省略>
- 验收与验证：<direct、相邻回归、运行/玩家门与UNVERIFIED>
- pre-mortem：<1–3项，每项→实际检查>
- 当前结果/阻断：<只留current>
- 唯一下一动作：<一个actor可执行动作或明确trigger>

## Current authorization

```authorization-package
{
  "schemaVersion": 1,
  "frameworkVersion": "1.6.0",
  "taskId": "<TASK-ID>",
  "profile": "STANDARD",
  "lifecycle": "ACTIVE",
  "owner": "<owner-id>",
  "issuer": "<owner-id>",
  "issuerRole": "DOMAIN_OWNER",
  "grantee": "<executor-id>",
  "bundle": "IMPLEMENT_LOCAL",
  "decisionClass": "ROUTINE_LOCAL",
  "userConfirmation": "NOT_REQUIRED",
  "reviewIndependence": "NOT_APPLICABLE",
  "delegatedGitCloser": false,
  "actions": ["SOURCE_WRITE", "TEST_WRITE", "TEST_RUN"],
  "exactPaths": ["<a>", "<b>"],
  "objectIdentities": [
    {"path": "<a>", "identity": "<bytes|UPPER_SHA256>"},
    {"path": "<b>", "identity": "NEW"}
  ],
  "invalidatesOn": ["TASK_CHANGE", "OWNER_CHANGE", "GRANTEE_CHANGE", "ACTION_CHANGE", "PATHSET_CHANGE", "OBJECT_DRIFT", "USER_DECISION_CHANGE"]
}
```

当且仅当`issuerRole=PROJECT_CONTROLLER`时，在包中增加`issuerControllerId`、整数`issuerControllerEpoch`与`controllerControlIdentity`，并在`invalidatesOn`增加`CONTROLLER_EPOCH_CHANGE`；`DOMAIN_OWNER`示例保持不带这些字段。

## History locator

- `<NONE，或NON_CURRENT carrier/commit与覆盖边界>`
~~~~

## 3. CRITICAL完整热卡

在STANDARD字段基础上增加：

```markdown
- 档位：CRITICAL；理由=<至少一个关键维度高/高失败代价>
- Range summary: profile=CRITICAL; lifecycle=<...>; current_exact=<稳定内容对象或NONE>; expected_paths=[...]; actual_paths=[...]
- Phase gate: <TRUE|FALSE；仅推进项目/多领域里程碑的父任务为TRUE>
- 重大方案/公共合同用户门：<确认引用或NOT_APPLICABLE及理由>
- 独立Reviewer：<id|UNASSIGNED>
- Review轮次/返工上限：<...>

## Stable authority and candidate

- 产品/公共合同：<稳定section identity>
- candidate：<内容manifest，不绑定持续变化的整张热卡>
- dependencies / fixture / toolchain / environment：<有效键>
- 验证上限与未验证：<...>

## Scope closure

- producer / direct consumers / tests / runner-manifest / docs：<...>
- conditional contingency：<触发证据与路径>
- forbidden paths/actions / routine exclusions：<...>

## Design and risk

- 根因、单一真相、数据流、生命周期、失败恢复：<...>
- pre-mortem：<至少3项，每项→检查>
- 适用审核视角：<只选择会改变判断的视角>

## Review and user gates

- 用户试玩/产品结果门：<候选、步骤、结果或PENDING>
- independent Review：<stable object、verdict、findings、delta、残余风险>
- stopline：<范围/产品/owner/权限/质量/复发/轮次>
```

`Phase gate: TRUE`时再增加下面的紧凑矩阵；FALSE时不添加。`PENDING`允许任务自然推进，不要求提前签署。

```markdown
## Phase acceptance

- Technical evidence: <PENDING|READY; producer=<id>; evidence=<stable-reference>>
- Domain contract check: <PENDING|ACCEPTED; owner=<id>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Runtime/platform check: <PENDING|ACCEPTED; owner=<id>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Project phase signoff: <PENDING|READY; controller=<必须等于任务Owner>; evidence=<stable-reference>>
- User final gate: <PENDING|CONFIRMED; candidate=<必须等于Range summary的current_exact>; evidence=<stable-reference>|NOT_APPLICABLE; reason=<原因>>
- Acceptance order: TECHNICAL_EVIDENCE > DOMAIN_CONTRACT > RUNTIME_PLATFORM > PROJECT_SIGNOFF > USER_FINAL_GATE
```

技术证据不能代签领域合同或项目阶段；领域合同检查不重复用户已完成的主观试玩；runtime/platform明显不适用时写明原因即可。项目签署只有在前三项ready/accepted/N/A后才能进入READY。技术Review与用户试玩的实际顺序由owner按风险、准备成本和反例拦截收益选择。矩阵中的`User final gate`只能在项目签署后闭合；`CONFIRMED`必须把`candidate`逐字绑定到Range summary的`current_exact`，并可引用同一stable candidate上更早发生的用户试玩/确认。这只是最终绑定，不要求再次询问用户。candidate或用户决定漂移时回到`PENDING`并重新确认。任务关闭时整条链必须闭合。

CRITICAL授权包的`decisionClass`按事实使用`PRODUCT_RESULT / MAJOR_ARCHITECTURE / EXTERNAL_ACTION / ROUTINE_LOCAL`。重大方案已确认后的本地实施可以是`ROUTINE_LOCAL`，但卡内必须保留其所依据的用户门与失效条件。

## 4. 热卡与history

任务实际查询项目knowledge index时，在Current里增加一行即可：`Knowledge reference: config=<identity>; index=<locator|identity>; query=<natural query|fixture>; result=<最多3条CURRENT ID|REFERENCE_UNAVAILABLE>; authority recheck=<locator>`。未查询时不添加；fixture必须标明`fixture`，不得计入自然样本。该行只记录引用证据，不授予权限，也不替代任务权威。

- current正文建议10–20KB；超过时先识别history/process重复，不能机械删必要权威。
- history carrier标记`NON_CURRENT / AUDIT_ONLY / NO_AUTHORITY / NO_ACTION`，与热卡双向locator并证明迁移字节。
- Review绑定stable content/section和依赖，不绑定整张持续追加热卡SHA。
- legacy卡只在自然写边界迁移，不为Framework升级批量重写。

## 5. 阶段更新

- `ACTIVE_WRITE`：actual可为expected已知子集，不得越界；有效authorization包存在。
- writer release：actual固定，authorization失效，下一actor转OWNER/USER/REVIEWER。
- `REVIEW / ACTIVE / CLOSED`：expected与actual相等；Review前先过task范围和授权释放preflight。
- Git/external分别签发包，不从实现包继承。
- CLOSED卡归档；仍有真实external下一动作时保持active。
