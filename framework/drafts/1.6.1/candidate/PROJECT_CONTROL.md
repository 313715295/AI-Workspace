# repo-local项目控制

本模块只由项目主控、Framework维护者或明确的控制面任务加载。普通业务执行者不需要理解register/upgrade事务细节。

## 1. 发现顺序

1. 把输入解析为真实Git顶层；非Git或身份不明时停止。
2. 若项目根`.ai-workspace`存在，严格验证`project.json`、Bootstrap受管区、repositoryRoot、project ID、controlPlane layout和Framework pin。
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

初始化后由项目owner把稳定项目身份写入PROJECT、项目特有审核重点写入REVIEW_PROFILE、current/未验证写入STATUS、已批准关系写入RELATIONSHIPS。不得复制通用Framework正文。

## 4. 同拓扑upgrade

upgrade只从项目当前固定版本到明确目标稳定版本，且保持控制面拓扑：

- 直接读取旧固定版本目录，缺失时拒绝，不用CURRENT/tag/HEAD补洞；
- repo-local只替换Bootstrap唯一FRAMEWORK-MANAGED区并逐字保留PROJECT-CUSTOM区；
- 受管区被项目改写、marker缺失、目标starter拓扑不同或事务前提不成立时拒绝；
- 中央legacy只按发布时支持合同在原拓扑升级；
- 升级不stage/commit、不改变产品source/test、不自动迁移任务卡。

中央→repo-local不是通用upgrade。它只能由项目owner另建一次性专属任务；项目仓提交并完成repo-local冷恢复前，中央副本保持唯一权威，冻结和删除分别授权。

## 5. 1.6.1按需加载与项目控制

1.6.1 starter按以下顺序：

1. 定位并验证项目/稳定Framework；
2. 读取`RECOVERY_CORE.md`；
3. 轻量读取项目`STATUS`、tasks hot index和分配任务顶部current元数据，确定role/profile/phase；这一步只定位，不用摘要替代任务正文；
4. 用确定的role/profile/phase/host和Bootstrap验证后的可选canonical capability集合运行loader，读取其返回的完整模块；空集合保持base plan，已启用项不得省略；没有分配任务时使用实际恢复职责，无法判定风险时向上选择而不是猜低档；
5. 读取项目稳定核心、完整current任务及其列出的业务权威与实现；
6. 复证真实HEAD/index/actual、其他owner边界和阶段授权包。

loader成功默认只返回一行含有有序模块路径与成本的计划摘要；宿主随后完整读取选定模块。它不能选择DRAFT、不按段落拼接、不以摘要替代模块。普通WARM重绑不重跑未变化加载计划。

## 6. 控制面审核门

`project.json` schema3增加`routineExcludedPaths`与`frameworkCapabilities`；前者只控制日常恢复/搜索/Git不展示不操作，后者默认空且当前只允许严格的`KNOWLEDGE_REFERENCE`配置。`controller.json`独立保存current controller ID、epoch和状态。注册1.6.1必须提供ControllerId并生成starter exact9；旧CURRENT或显式1.4/1.5注册仍保持schema2兼容。

主控轮换采用单一原子控制对象：successor完成FULL_COLD并明确接受前，旧主控保持唯一权威；commit一次替换controller ID并递增epoch，随后长期owner只把exception target重绑到successor。切换前排队的旧routine消息按旧epoch/stable identity丢弃，不重新污染新主控；successor确认后旧主控进入read-only grace再archive。旧epoch PROJECT_CONTROLLER授权由预检自然拒绝，不建立撤销账本。

schema2的1.4.1/1.5.x项目只允许先按1.6.0合同升级到1.6.0：接受repo-local直接来源和冻结的routine-exclusion migration输入，现有可恢复事务骨架保存旧/新exact3并串行写入`project.json / BOOTSTRAP.md / controller.json`。1.6.1只接受健康的schema3 1.6.0直接来源，再通过同一事务骨架以exact2串行更新`project.json / BOOTSTRAP.md`；`controller.json`只做current健康、ID与epoch复证，绝不重写，既有`routineExcludedPaths`、`frameworkCapabilities`值和Bootstrap `PROJECT-CUSTOM`区逐字保持。schema2项目直接跳到1.6.1必须拒绝且不写。两步升级前都由current controller进入独占维护窗口，确认其他writer、Review、Git、external与控制写均关闭；已有事务即拒绝第二次启动。中断或未知状态保留恢复材料并停止；不支持维护窗口内并发控制写，不建立第二事务引擎、capture/quarantine双树或脚本内递归自动清理。

项目必须为稳定概念指定现有领域/产品权威或专门术语权威；Framework不强制新建全局词典。canonical term、跨语言/代码映射及alias退出由对应领域owner维护，只有改变玩家可见含义或产品语义时才回用户。

`KNOWLEDGE_REFERENCE`的唯一启用producer是schema3 project config。register与旧项目升级始终生成空能力对象，不创建索引；项目升级后由项目owner另立任务，先指定术语/专业权威，再初始化索引并显式启用。知识索引与条目永久`REFERENCE_ONLY / NON_AUTHORITY`，不得成为第二任务真相或第二术语权威。

相关Review至少验证：

- discovery对partial/reparse/冲突fail closed；
- schema、repositoryRoot、固定Framework与受管Bootstrap闭合；
- register WhatIf、staging/rename、inventory和`ALREADY_REGISTERED`严格性；
- upgrade同拓扑、受管区/自定义区和旧版本缺失拒绝；
- 未产品化中央→repo-local跨仓事务；
- 升级恢复材料在项目FULL_COLD前保持audit-only，后续housekeeping精确处理且不影响升级成功；
- 新加载计划不能漏掉角色/档位/阶段硬依赖；
- 阶段父卡不能把技术audit或Review verdict直接冒充领域合同核对、项目阶段签署或用户最终决定；
- 项目升级前后冷恢复、权限、日常排除、术语权威和current任务可重新证明。

控制面普通字段更新不以whole-file SHA作为唯一有效性；受管Bootstrap、project identity、稳定candidate和版本发布仍使用强identity。
