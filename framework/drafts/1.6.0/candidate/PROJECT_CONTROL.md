# repo-local项目控制

本模块只由项目主控、Framework维护者或明确的控制面任务加载。普通业务执行者不需要理解register/upgrade事务细节。

## 1. 发现顺序

1. 把输入解析为真实Git顶层；非Git或身份不明时停止。
2. 若项目根`.ai-workspace`存在，严格验证`project.json`、Bootstrap受管区、repositoryRoot、project ID、controlPlane layout和Framework pin。
   同时严格读取canonical `controller.json` schema 1；它是current controller identity/epoch唯一真相，STATUS和tasks index只作locator。
3. 完整repo-local优先。partial、reparse、不可读、未知live bytes或ID/repository/pin冲突fail closed，不回退legacy。
4. 只有repo-local完全不存在时才允许项目定义的中央legacy fallback；repository identity必须匹配。
5. 从已挂载workspace唯一定位`framework/versions/<pin>`稳定目录；不得从`CURRENT`、tag、HEAD、网络或`framework/drafts/`猜测。

repo-local与legacy并存且身份一致时repo-local是唯一入口，legacy只读冻结；冲突时保持只读并回owner。

## 2. 控制面文本与路径

控制面文本使用严格UTF-8无BOM、无NUL/U+FFFD、LF并以LF结尾。受管Bootstrap和项目自定义区边界唯一且配对。

路径拒绝绝对、`..`、ADS、保留名、尾随点/空格、大小写或Unicode规范化碰撞和reparse。工具清理临时对象前必须证明对象由本次流程创建，且identity/schema/inventory/hash闭合；未知临时材料保留并停止。

## 3. 新项目register

register只服务repo-local和同ID legacy都不存在的全新Git项目：

- 默认WhatIf；Apply需明确授权；
- 要求正确Git顶层和项目定义的dirty边界；
- 从固定稳定版本starter在项目仓内同级隐藏staging生成完整inventory；
- 完整验证后同仓rename为`.ai-workspace`；失败只清理可证明属于本次流程的staging；
- 不stage/commit/push；
- 只有固定inventory和受管identity全部相同才返回`ALREADY_REGISTERED`，缺失、额外或未知live bytes返回`CONFLICT`并保留。

1.6.0首次register还要求显式`ControllerId`，以canonical JSON生成`controller.json` epoch 1，并把它纳入固定inventory和`ALREADY_REGISTERED`身份检查。对已注册1.6项目的重复调用必须从canonical controller对象读取current controller与任意合法epoch；调用者未重复提供ControllerId时不得把健康轮换误报冲突，显式提供时则必须与current一致。starter `project.json`升级为schema 3；本阶段`frameworkCapabilities={}`，不得顺手实现或启用知识selector。

初始化后由项目owner把稳定项目身份写入PROJECT、项目特有审核重点写入REVIEW_PROFILE、current/未验证写入STATUS、已批准关系写入RELATIONSHIPS。不得复制通用Framework正文。

## 4. 同拓扑upgrade

upgrade只从项目当前固定版本到明确目标稳定版本，且保持控制面拓扑：

- 直接读取旧固定版本目录，缺失时拒绝，不用CURRENT/tag/HEAD补洞；
- repo-local只替换Bootstrap唯一FRAMEWORK-MANAGED区并逐字保留PROJECT-CUSTOM区；
- 受管区被项目改写、marker缺失、目标starter拓扑不同或事务前提不成立时拒绝；
- 中央legacy只按发布时明确列出的目标在原拓扑升级；1.6.0新增repo-local controller对象，因此本通用1.6脚本不把中央→repo-local伪装成同拓扑升级；
- 升级不stage/commit、不改变产品source/test、不自动迁移任务卡。

从已验证repo-local布局的`1.4.1 / 1.5.0 / 1.5.1 / 1.5.2`到1.6.0时，owner/controller先冻结legacy ACTIVE PROJECT_CONTROLLER包locator+identity。脚本必须解析每个包并证明`issuerRole=PROJECT_CONTROLLER / lifecycle=ACTIVE`；DOMAIN_OWNER输入直接拒绝，不得仅凭调用者命名分类。preview生成controller epoch 1与revocation ledger；Apply使用同一可恢复local transaction写schema3 project pin、受管Bootstrap、controller和ledger，并在每次替换live对象前复证冻结preimage。legacy PROJECT_CONTROLLER包标为`STALE_AUDIT_ONLY_NO_ACTION`，不得转换给successor；DOMAIN_OWNER包按原invalidators保留。中断只在已知old/new identity间恢复，未知字节保留并停止。已成功升级的同一current controller重复调用必须返回`ALREADY_UPGRADED`，不得被source allowlist误拒绝。

Apply使用首次严格读取形成project/Bootstrap冻结preimage；事务old copy必须逐字匹配该preimage，target也只能由同一冻结读取派生。首次读取后、old copy前或任一replace前发生identity漂移都必须停止并保留未知live bytes。`ALREADY_UPGRADED`不是弱快捷路径：它必须严格复证canonical current controller以及完整canonical revocation ledger字段集、类型、枚举、legacy条目identity与未知字段；合法轮换后的current controller epoch大于1仍可幂等通过，ledger继续保存迁移发生时的epoch 1来源记录。

中央→repo-local不是通用upgrade。它只能由项目owner另建一次性专属任务；项目仓提交并完成repo-local冷恢复前，中央副本保持唯一权威，冻结和删除分别授权。

controller route只接受四个组合：`STATE/ROUTINE_SUMMARY`、`EXCEPTION/EXCEPTION`、`USER_DECISION/USER_DECISION`、`AUTHORIZATION/AUTHORIZATION`。`ACK`及未知class无条件拒绝；stale epoch只允许routine summary丢弃，或由current task复证后的真实exception重路由一次。stale exception重路由必须同时绑定队列侧不可变original envelope locator+observed identity+original class，以及现场读取的current task locator+stable identity+task ID；outer route的自报class或revalidation布尔值不能替代这两项观察。original envelope为user decision、authorization或ACK时，无论outer如何包装为exception都必须拒绝。

## 5. 1.6按需加载starter要求

未来1.5 starter应按以下顺序：

1. 定位并验证项目/稳定Framework；
2. 读取`RECOVERY_CORE.md`与canonical `controller.json`；
3. 轻量读取项目`STATUS`、tasks hot index和分配任务顶部current元数据，确定role/profile/phase；这一步只定位，不用摘要替代任务正文；
4. 用确定的role/profile/phase/host运行loader，读取其返回的完整模块；没有分配任务时使用实际恢复职责，无法判定风险时向上选择而不是猜低档；
5. 读取项目稳定核心、完整current任务及其列出的业务权威与实现；
6. 复证真实HEAD/index/actual、其他owner边界和阶段授权包。

loader成功默认只返回一行含有有序模块路径与成本的计划摘要；宿主随后完整读取选定模块。它不能选择DRAFT、不按段落拼接、不以摘要替代模块。普通WARM重绑不重跑未变化加载计划。

## 6. 控制面审核门

相关Review至少验证：

- discovery对partial/reparse/冲突fail closed；
- schema、repositoryRoot、固定Framework与受管Bootstrap闭合；
- register WhatIf、staging/rename、inventory和`ALREADY_REGISTERED`严格性；
- upgrade同拓扑、受管区/自定义区和旧版本缺失拒绝；
- 未产品化中央→repo-local跨仓事务；
- 临时清理只删除可证明对象；
- 新加载计划不能漏掉角色/档位/阶段硬依赖；
- 阶段父卡不能把技术audit或Review verdict直接冒充领域合同核对、项目阶段签署或用户最终决定；
- 项目升级前后冷恢复、权限、保护路径和current任务可重新证明。
- controller唯一真相、epoch单调轮换、legacy包撤销、DOMAIN_OWNER兼容和revocation ledger可复核。

控制面普通字段更新不以whole-file SHA作为唯一有效性；受管Bootstrap、project identity、稳定candidate和版本发布仍使用强identity。
