# AI Workspace Framework 路线图

本文件只记录当前候选的目标范围和未来准入条件，不保存逐轮实施状态、Review 叙事或完整发行历史。

- 当前任务状态由 Framework Maintenance 项目的任务卡持有。
- 候选或发行生命周期由对应版本的 `VERSION.json` 与 `RELEASE_MANIFEST.json` 持有。
- 版本变化由对应版本的 `CHANGELOG.md` 说明。
- 旧发行内容和历史决定由 Git 历史保留。

## 1.16.0 候选目标

1.16.0 是当前整理基线。它不把旧版本目录、旧 Maintenance 布局或无消费者的专用升级分支继续带入日常载荷。

### 渐进规则加载

- 在自然任务、上下文、authority 或来源变化边界执行 `DISCOVER`。
- 先根据真实任务、角色、阶段、动作、路径和能力选择规则，再加载命中的完整规则区块。
- 同一绑定上下文连续工作时复用完整规则；受治理动作和正式输出前只前置紧凑义务。
- 上下文不确定、selector 扩大或来源漂移时重新读取；不能用旧 selector 排除新要求。
- 组合 Framework 通用规则、仍有效项目纠正和项目永久流程规则，但不复制第二份正文或建立第二 composer。
- 项目标准可以选择来源绑定区块或全文回退；不要求所有项目文档先改造成规则目录。
- 没有任务卡时只允许显式 `PROJECT_READ_ONLY` 分析入口；执行、正式 Review、接受、Git 和外部操作仍需任务及授权。

### 任务、角色与 Review

- 区分任务 Owner、当前 `taskActor` 和一次授权的 `grantee`。
- Owner 可以自己执行，也可以安排临时 actor；资源档位和动作角色不产生长期所有权。
- 同任务、同结果、同边界的健康上下文优先复用及 NONE/WARM rebind；新授权不等于完整冷恢复。
- 同领域默认 Owner 直接安排执行和 Review，不强制 Controller 转述。
- CRITICAL 独立 Review 继续排除任务 Owner/issuer、候选 writer 和实质方案贡献者。
- 正常 Review 只需一次完整委派与一次可用终态返回。Reviewer 不写主任务卡、STATUS 或任务索引，不反向申请“释放”授权；Owner 在唯一任务卡收口并单独决定 `OWNER_ACCEPT`。
- STATUS 只保留项目阶段、真实阻塞和唯一下一行动；任务索引只负责定位，不复制完整审查结论。

### 授权与过程产物

- 写任务卡前严格绑定 preimage；写后只接受授权范围内的 exact postimage。自身受权写入不冒充外部漂移，并发或越界变化仍停止。
- 写入、测试、Review、`OWNER_ACCEPT`、Git、推送、浏览器、设备和外部操作保持独立类别门。
- 临时 process/authorization/diagnostic/transaction JSON 默认位于 `.ai-workspace/runtime/<task-or-request>/<actor>/`，由项目根 `.gitignore` 排除。
- 同一收据不重复顶层与嵌套 authority/intent/source 事实；能在同进程传递时不强制物化文件。
- 临时授权在本轮终态后不得启动新动作；垃圾清理与授权终点分开，不为此新增 ledger 或释放 ACK。
- 项目可在 `process-policy.json` 选择规则包预算；Framework 只提供默认值与绝对安全上限。预算不足时保留窄只读诊断和 exact policy repair，不让项目失去恢复能力。

### 项目接入与升级

- 新注册、跨 pin 采用、同 pin 受管修复和明确批准的永久规则迁移，共用状态读取、目标投影、Diff、Preflight、Apply、Postcheck/Recover。
- Project Format 根据真实控制载体 schema 与结构能力判断，不按 Framework 版本白名单放行。
- 采用结果绑定 `Framework Pin + Project Format + Root Tool Revision`；Root Tool Revision 来自真实入口及其行为依赖的组合 identity。
- 无差异返回 no-op，不创建持久事务、不改任务卡、不刷新历史快照。
- Preflight 前不写受管状态；Apply 或 Postcheck 失败时恢复旧 pin、旧受管对象和旧三源有效行为。
- 进程中断保留有界恢复材料；恢复完成前不把混合状态开放给普通工作，也不覆盖第三方新字节。
- 永久规则从 legacy PROJECT-CUSTOM 迁入 process-policy 时执行成对迁移，保证正常消费只看到完整旧集合或完整新集合。
- Maintenance sibling 拓扑、overlay、目标解析和旧布局迁移只属于根级 `framework/maintenance-overlay/` 与根工具，不进入版本通用载荷。

### 内部模块与测试

- 对外仍是一个 Framework 版本和一个项目 pin；内部实现按状态、投影、事务等真实职责拆分，不建立动态模块包管理器。
- 发行固定一组完整模块依赖；版本载荷和根级工具分别计算受管组合 identity。
- 测试 fixture 自带前置状态，不依赖“先跑前 N 条”形成共享状态。
- 开发期运行受影响模块及反向依赖；共同底层或候选冻结时运行完整当前版本集成测试。
- 保留真实缺陷行为回归；只在行为测试已经覆盖时删除脆弱源码形状断言和重复案例。
- 机械测试只证明结构、身份、路由和可观察结果，不冒称模型语义理解或产品质量。

### 支持基线、分发与发布

- 交付树只保留 1.16.0 当前基线；旧版本和 draft 只在 Git 历史中保留，不进入普通运行、测试或用户包。
- 保留 1.16 新项目接入、同 pin 幂等修复和未来按 Project Format/capability 判定的兼容路径。
- 普通使用者只获得一个 ZIP：当前版本载荷、必要根级工具及依赖、canonical Router、中文 AI 入口、许可证和完整性清单。
- ZIP 排除真实项目状态、`.git`、runtime 临时产物、旧版本集合和 Maintenance 控制数据。
- 先做 provisional ZIP 隔离 smoke，再清理旧依赖，最终候选冻结后做正式 ZIP 验证。
- 候选遵循四个阶段：`CANDIDATE_IMPLEMENTATION` → `PRE_PILOT_VERIFICATION` → `LOCAL_PILOT` → `RELEASE_CLOSURE`。
- 本地试点只使用同一份通过完整测试和独立 Source Review 的冻结快照；finding 先报告根因，不自动打补丁。
- 快照未变时复用 identity-bound 证据；发生变化时按实际 delta 补测试和 Review，不重跑与变化无关的整套发布仪式。
- `OWNER_ACCEPT`、seal、Git、双远程发布和项目正式采用仍是独立结果，不互相替代。

## 当前明确不做

- 不新增 actor registry、Reviewer pool、handoff/consumption ledger、服务、队列、heartbeat、轮询器或第二状态真相。
- 不新增 per-tool hook、全局消费者注册表、自动项目升级或动态模块版本求解。
- 不建设完整卸载系统；只提供有界退出和项目数据保留说明。
- 不为了理论上任意并发读取者引入全局锁、读者表或双缓冲目录。
- 不把三平台 CI 作为 1.16 准入条件；1.16 平台声明由实际 Windows PowerShell 7 证据限定。
- 不把项目本地模型成本、耗时或返工数据变成 Framework 强制记录。

## 未来准入条件

以下方向只有出现新的真实证据、完成比例性评估并由用户明确选入后，才进入后续版本：

- 已接受结果的 current-facing 投影：先由项目纠正自然试点；只有重复出现工作会话残留污染正式权威或交付面时，才考虑吸收软规则或最小机械检查。
- Host 真实性强化：只有宿主提供可测试的可信身份/权限信号，并证明现有机械 preflight 不足时才接入。
- Knowledge 上下文预算扩展：先让现有 DISCOVER/QUERY 在真实任务中使用；只有 compact metadata 与当前 ID 上限实测不足时才扩展。
- 更细的物理模块独立发布：只有根级工具或版本载荷的实际变更仍被无关全量验证拖慢，并且依赖边界已通过自然维护证明稳定时才评估；对外仍保持统一版本。
- 更强的并发迁移机制：只有短维护窗口无法维持，或用户明确要求不停机迁移时才评估。

任何未来项都不得仅因“可能有风险”就增加新的长期角色、状态、服务、台账、ACK 或轮询链。
