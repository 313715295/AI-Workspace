# AIW-FW-1.6.0-F-KNOWLEDGE-001 — 默认关闭的项目级知识能力

- 状态：IMPLEMENT_COMPLETE / F_KNOWLEDGE_CANDIDATE_003 / INTEGRATION_REVIEW_PENDING / WRITER_NONE / REVIEWER_NONE
- Task schema: 1.5.2
- 档位：CRITICAL；理由：新增Framework公共knowledge合同、schema、loader selector、starter opt-in与迁移边界，影响所有采用项目
- Owner: 019ffe25-9941-7490-808a-a5fbd8bbe23a
- 当前 actor / writer：NONE / NONE
- Reviewer：NONE
- Resource requirement: minimum=FOCUSED_HIGH; requiredTools=[filesystem|shell]; continuity=SAME_CONTEXT_IMPLEMENT; finalReview=FRESH
- Range summary: profile=CRITICAL; lifecycle=REVIEW; current_exact=F_KNOWLEDGE_CANDIDATE_003; expected_paths=[framework/drafts/1.6.0/minimal-candidate/KNOWLEDGE_AND_REFERENCE.md|framework/drafts/1.6.0/minimal-candidate/KNOWLEDGE_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/minimal-candidate/HOST_CODEX.md|framework/drafts/1.6.0/minimal-candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/scripts/invoke-protected-safe-git.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONFIG_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/project-starter/project.json|framework/drafts/1.6.0/minimal-candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/minimal-candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/minimal-candidate/scripts/check-knowledge-entry.ps1|framework/drafts/1.6.0/minimal-candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/minimal-root/INITIALIZATION.md|framework/drafts/1.6.0/minimal-root/scripts/register-project.ps1|framework/drafts/1.6.0/minimal-root/scripts/upgrade-project.ps1]; actual_paths=[framework/drafts/1.6.0/minimal-candidate/KNOWLEDGE_AND_REFERENCE.md|framework/drafts/1.6.0/minimal-candidate/KNOWLEDGE_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/RECOVERY_CORE.md|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONTROL.md|framework/drafts/1.6.0/minimal-candidate/HOST_CODEX.md|framework/drafts/1.6.0/minimal-candidate/LOAD_MANIFEST.json|framework/drafts/1.6.0/minimal-candidate/scripts/invoke-protected-safe-git.ps1|framework/drafts/1.6.0/minimal-candidate/scripts/resolve-load-plan.ps1|framework/drafts/1.6.0/minimal-candidate/PROJECT_CONFIG_SCHEMA.json|framework/drafts/1.6.0/minimal-candidate/project-starter/project.json|framework/drafts/1.6.0/minimal-candidate/project-starter/BOOTSTRAP.md|framework/drafts/1.6.0/minimal-candidate/TASK_TEMPLATE.md|framework/drafts/1.6.0/minimal-candidate/scripts/check-knowledge-entry.ps1|framework/drafts/1.6.0/minimal-candidate/tests/run-framework-tests.ps1|framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|framework/drafts/1.6.0/minimal-root/INITIALIZATION.md|framework/drafts/1.6.0/minimal-root/scripts/register-project.ps1|framework/drafts/1.6.0/minimal-root/scripts/upgrade-project.ps1]
- Stable candidate: `framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|624|0839F20DBB15E999BA277F58B868C4729B2978652D2446493A2692321554CDB7`；payload=`37 files / 219676 bytes / EEED2502DFBD41655D9D1CC699053CCC9BFAE4A50E192C19EA43D6327961E240`；source baseline=`A_C_G_MINIMAL_CANDIDATE_006 / APPROVED / OWNER_ACCEPTED`
- Phase gate: FALSE
- Git / push / external：CLOSED / CLOSED / CLOSED

## Current

- 唯一范围权威：`framework/drafts/1.6.0/FRAMEWORK_PLAN.md`的F与2.1 F矩阵；knowledge范围Review-2=`APPROVED / 0 finding / OWNER_ACCEPTED`，不复活旧Review lineage。
- 用户顺序决定：1.6.0先发行默认关闭的项目级基础能力；Pocket仅在Framework发布并独立升级后指定术语权威、初始化内容并显式启用。初始化内容、自然样本、common内容与跨项目聚合不属于本任务。
- source baseline：candidate006 manifest=`framework/drafts/1.6.0/minimal-candidate/RELEASE_MANIFEST.json|626|E6B2637DE470F81D96FD9E9934AA53BA4716B75202106D8302F4FB1A02188547`；payload=`34 files / 180511 bytes / 057D18A156C444DF4D81649979F4E4E2098945CFE766B646E594C41D44783590`。
- 新对象exact3：`KNOWLEDGE_AND_REFERENCE.md / KNOWLEDGE_SCHEMA.json / scripts/check-knowledge-entry.ps1`；其余exact15只能从candidate006 current preimage派生。
- range reconciliation：只读consumer复证确认safe-Git也严格消费`frameworkCapabilities`，原exact17会使合法knowledge opt-in被误判。它作为既有direct consumer纳入exact18；全树检索未发现第二个遗漏的机器消费者。该纠偏不新增机制或职责。
- 实现结果：default empty与显式disabled均不加载知识内容；enabled selector只追加一次；unknown/duplicate/unsupported host fail closed；无库、空库、index drift和authority conflict均返回`REFERENCE_UNAVAILABLE`。register/1.4.1–1.5.2 upgrade默认不建库、不启用，合法后置启用可通过health门。
- 资源证据：五角色base plumbing相对candidate006增加`1508–2015 bytes`；enabled optional payload固定`3332 bytes`且去重；disabled optional payload=`0`。
- direct evidence：final simplify quick=`129/129 PASS`；完整迁移矩阵=`171/171 PASS`；冻结manifest复跑=`130/130 PASS`；最终完整结果=`172/172 PASS`。fixture不计自然样本，真实项目采用仍N/A。
- Review-1=`CHANGES_REQUESTED / 2 HIGH / 2 MEDIUM`：checker未绑定唯一project-config opt-in/locator；query-result cache失效键不足；RECOVERY/PROJECT_CONTROL漏写capability selector；locator类型与verifiedAt真实日期未和schema闭合。Reviewer已RELEASED，exact18末检零漂移。
- owner裁决：一次exact8 bounded remediation；checker从冻结project config读取唯一enable/locator，禁止query-result cache，补齐两处loader说明及locator/date严格门与direct negatives。不新增service、ledger、cache对象或第二truth。
- remediation结果：唯一project config opt-in/locator已由checker直接绑定；query result cache已禁止；loader capability说明与locator/date schema门已闭合。exact8内完成，无新增service、ledger、cache对象、第二truth或常态步骤。
- Review-2=`CHANGES_REQUESTED / 2 MEDIUM / REPEATED`：RECOVERY_CORE仍有一句“loader只有四项输入”的旧合同；STALE/HISTORICAL空locator可绕过schema minLength。其余Review-1四项核心闭合，Reviewer已RELEASED。
- owner stopline裁决已完成：RECOVERY_CORE只保留base selectors加可选canonical capability的唯一表述；所有状态的locator均先满足schema非空门，STALE/HISTORICAL仍不解析目标文件。未新增机制，且不启动F组件Review-3。
- 唯一下一动作：由父任务进入完整INTEGRATION，最终integration Review必须复核F Review-2两项；release、CURRENT、Git与Pocket采用保持关闭。

## Scope closure

- 公共语义：项目知识永久为`REFERENCE_ONLY / NON_AUTHORITY`；Bootstrap、pin、current task与专业权威优先。默认最多3条CURRENT，STALE/HISTORICAL不进入普通决策。
- opt-in producer：唯一为project.json schema3的`frameworkCapabilities.KNOWLEDGE_REFERENCE={enabled:true,indexLocator:<normalized repo-relative literal>}`；默认`{}`、缺字段或`enabled=false`均等价于未启用。未知/重复capability、无效locator、enabled缺locator必须在loader前fail closed。
- loader：只新增唯一显式`-Capability KNOWLEDGE_REFERENCE` selector；空集合保持candidate006基础load plan逐字等价，未知、重复或host不支持必须失败；knowledge模块最多追加一次，不自动查询或创建索引。
- checker：只验证项目knowledge entry/index的结构、CURRENT状态、authority locator、verifiedAt、invalidatesOn与tokenEstimate；PASS不授予任何authority、写权、Review、Git或外部权限。
- fallback：未启用、无库、空索引、locator失效、authority conflict统一返回`REFERENCE_UNAVAILABLE`并继续使用正式恢复链；不得把fallback隐去或把fixture当自然样本。
- migration：register默认空capability；1.4.1/1.5.0/1.5.1/1.5.2升级只写schema能力结构，不启用、不创建索引、不生成项目知识。项目采用另立任务。
- 成本：基础capability plumbing增量与optional payload分账；未启用时optional knowledge payload必须为0；显式启用payload单独冻结且稳定去重。不得用新增summary模块掩盖超限。

## Frozen preimage

- `KNOWLEDGE_AND_REFERENCE.md|NEW`
- `KNOWLEDGE_SCHEMA.json|NEW`
- `RECOVERY_CORE.md|10311|D7880B2635DB9F39F2CA3C8180BBC5B246F66E02FC7290BDAC44F977C2F720C3`
- `PROJECT_CONTROL.md|6508|26B4FB2C140FF363E2D3729D546FC71DACFB8D128FD593DD950F8F98F0D7E9FD`
- `HOST_CODEX.md|3906|4581BA58F021F410399A330D2E3C6EFD74B77E571C0362C73BEC4524904D0966`
- `LOAD_MANIFEST.json|1160|C376CF4D561F6B41D05E86F827ABA2ABD1B1F541318877257094B9E180694E5F`
- `scripts/invoke-protected-safe-git.ps1|7887|ED947819FE3AEEC09E9FAB02EFE83CB230E4A4F104D7F40851A52D7D61AA6CFC`
- `scripts/resolve-load-plan.ps1|3150|6A489A477A0086AF00425E6B1C5C6B32F93749049FC3196225AAAFC38FBABCD1`
- `PROJECT_CONFIG_SCHEMA.json|1146|1E2BB1FB8FCA7C1C520D08B8EF07E56F591FB2212CCB8E94677094C116E7A9DF`
- `project-starter/project.json|269|DBFB20B4F6CEA488E611C262BEE2BD9B1F24F33B5C3E933B6D1BC4E7D6E8D62A`
- `project-starter/BOOTSTRAP.md|3825|CDB099ABCCD6DED8645EB0C609A15F551329B1E0C99DC8016705C3D1B6435209`
- `TASK_TEMPLATE.md|7676|E7A1329A15A3373B9B303B17612D2BF555408E3B2C2E730A080948CE4928D7B4`
- `scripts/check-knowledge-entry.ps1|NEW`
- `tests/run-framework-tests.ps1|37147|FEFA52C6B1AC57E5A81EA228D81A205E4DE9B31AF766AAA02099BF87934FB2BE`
- `RELEASE_MANIFEST.json|626|E6B2637DE470F81D96FD9E9934AA53BA4716B75202106D8302F4FB1A02188547`
- `minimal-root/INITIALIZATION.md|8665|F8CC1FB4F2E7591D6E335CE0B20A15048303B7BE922D531E7EDF9C8A7B84D361`
- `minimal-root/scripts/register-project.ps1|24265|0C6552AF9299C1D9B5B1711E684F2902F53379FFAC6026D49F7B3D77AA7AA988`
- `minimal-root/scripts/upgrade-project.ps1|46405|E55A72A4EC420C182AE3E5956449D67B6E5216DADCC6B79C5E36C47FC3842EB1`

## Verification and stopline

- direct tests至少覆盖default-empty、no-library、empty-index、configured enabled、not-opted-in、unknown/duplicate/unsupported capability、invalid locator、explicit-once、WARM invalidation、authority conflict与fallback；两张starter JSON模板渲染后严格解析。
- 独立冻结基础plumbing增量、未启用optional payload=0、enabled payload cap与dedup；自然查询与两个项目证据明确N/A。
- 任何第二opt-in producer、第二knowledge truth、common内容、跨项目聚合、自动索引创建、自动authority提升、新host service或exact18外职责路径立即RANGE_GATE。
- candidate必须保持DRAFT / NOT_CONSUMABLE；不修改stable 1.5.2、CURRENT、live root、项目pin或Pocket。

## Current authorization

- final simplify package已消费失效；current package=NONE；actor/writer/reviewer=`NONE / NONE / NONE`。Git、external、release、CURRENT与project adoption均CLOSED。
