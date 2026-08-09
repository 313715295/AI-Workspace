# Framework 1.3.2任务示例

这些示例展示三档的自然形状，不是需要复制的固定组织图。先判断风险，再选择最低充分档位；不要先复制`CRITICAL`卡再删字段。

## 1. MICRO：修正文档中的一个错误链接

事实：稳定owner会话已经恢复；错误和正确目标可直接核实；只改一个文档；无公共合同、持久状态、外部动作、并行owner冲突或跨turn等待。

本例不建任务卡。当轮记录为：

```text
档位：MICRO
目标：把 docs/setup.md 中失效的同仓链接改为已存在的 docs/install.md。
Exact：[docs/setup.md]
Forbidden：[docs/install.md|src/**|assets/**]
验证：打开目标；搜索旧链接只剩历史说明0处；检查新链接存在；git diff --check；阅读实际diff。
Git权限：不暂存、不提交、不push。
外部权限：无。
结果：上述验证通过；只产生exact1；owner当轮闭合。
```

为什么不是`STANDARD`：无需跨turn、没有行为合同或多角色、直接验证足够。若发现旧链接由生成器写入、同一概念散布到多个文件、目标文档归其他owner，或本turn无法闭合，立即停止并升级`STANDARD`。

若项目确需持久locator，可使用最小卡：

```markdown
# DOC-LINK-001 — 修正安装链接

- 状态：ACTIVE_WRITE
- 任务档位：MICRO
- 风险：低；单文档 / 纯文本 / 一个直接消费者 / 直接可见
- 唯一长期owner/调度者：文档owner
- Exact路径：[docs/setup.md]
- Forbidden路径：[docs/install.md|src/config.js]
- Git 权限：关闭
- 外部动作授权：无
- 范围摘要：`profile=MICRO; lifecycle=ACTIVE_WRITE; expected_paths=[docs/setup.md]; actual_paths=[]`
- 创建/更新：2026-01-15

## 目标

把失效的安装链接改到现有权威页面；不改变安装步骤。

## 范围与保护

只写链接所在页；目标页和源码只读。

## 验收与验证

目标存在，旧链接清零，`git diff --check`通过，实际diff只有一行链接变化。

## 交接/下一步

唯一下一动作：文档owner在本turn修改、验证并记录结果；不能闭合时升级STANDARD。
```

## 2. STANDARD：修复配置读取的普通缺陷

事实：问题位于一个模块，但实现和直接测试跨两个文件，可能需要跨turn返工；无公共schema、持久状态、外部动作或高代价失败。owner直接执行并由领域owner聚焦审核，不挂载独立会话。

```markdown
# CONFIG-DEFAULT-001 — 保留显式false配置

- 状态：ACTIVE_WRITE
- 任务档位：STANDARD
- 风险：中；单模块 / 简单行为 / 一个调用族 / 测试可见
- 唯一长期owner/调度者：配置领域owner
- Exact路径：[src/config/read-options.js|test/config/read-options.test.js]
- Forbidden路径：[src/config/schema.js|package-lock.json]
- Git 权限：通过审核后由owner逐项暂存并本地提交；push关闭
- 外部动作授权：无
- 范围摘要：`profile=STANDARD; lifecycle=ACTIVE_WRITE; expected_paths=[src/config/read-options.js|test/config/read-options.test.js]; actual_paths=[]`
- 创建/更新：2026-01-15

## 目标

当前读取器用truthy回退，导致显式`false`被默认值覆盖。目标是只在值缺失时使用默认值，并增加直接回归覆盖。

## 非目标

不改变配置schema、文件格式、默认值或其他选项的转换规则。

## 范围与保护

producer是配置文件解析结果，direct consumer是读取器调用方；测试入口已存在。exact覆盖实现和直接测试；schema与锁文件只读。若修复需要公共schema或第三个实现文件，停止并重新定档。

## 验收与验证

Pre-mortem：`null`与缺失被混同——增加边界用例；其他falsey值回归——覆盖`0`和空字符串；调用方另有回退——搜索同族读取路径。运行定向测试、相关回归、`git diff --check`并阅读实际diff。

## 交接/下一步

唯一下一动作：配置领域owner实现并完成聚焦审核；范围或风险扩大时升级CRITICAL或回owner重冻范围。
```

若宿主实际挂载多个独立任务上下文，才按对应`HOST_ADAPTER_*.md`追加通信字段。没有多会话时不要填占位字段来模拟闭环。

## 3. CRITICAL：迁移公共认证令牌生命周期

事实：变更公共合同、持久状态、安全边界和外部部署顺序；失败可能导致用户无法登录。必须有完整范围闭包、独立最终审核、稳定候选和外部动作门。

```markdown
# AUTH-TOKEN-MIGRATION-001 — 迁移版本化令牌生命周期

- 状态：ACTIVE_WRITE
- 任务档位：CRITICAL
- 风险：高；跨模块 / 持久生命周期 / 多消费者 / 失败只能经集成观察
- 审核场景：修改后审核
- 唯一长期owner/调度者：认证领域owner
- 执行载体与资源：独立任务上下文；需要跨turn实现、返工与稳定审计对象
- 恢复模式与基线：FULL_COLD_RECOVERY；执行者首次接触认证公共合同
- 当前写入者：指定执行者
- 审核人：未参与方案和写入的认证审核者
- Git 收口者：认证领域owner
- Git 权限：独立APPROVED后允许owner逐项本地提交；push关闭
- 外部动作授权：部署、密钥轮换和发布均未授权
- Exact路径：[docs/auth-contract.md|src/auth/token-store.js|src/auth/token-service.js|test/auth/token-lifecycle.test.js]
- Forbidden路径：[deploy/**|secrets/**|package-lock.json]
- 范围摘要：`profile=CRITICAL; lifecycle=ACTIVE_WRITE; current_exact=4; expected_paths=[docs/auth-contract.md|src/auth/token-store.js|src/auth/token-service.js|test/auth/token-lifecycle.test.js]; actual_paths=[]`
- 创建/更新：2026-01-15

## 目标

把令牌从无版本持久记录迁移为版本化记录，冻结创建、读取、刷新、撤销、过期和失败恢复合同，并保持旧记录只读迁移能力。该问题为`CURRENT_REACHABLE`：current持久记录与登录/刷新producer正在消费该合同。

## 非目标

不部署、不轮换真实密钥、不改变账号产品策略，不修改部署或secret路径。

## 权威输入与前置事实

认证合同、当前数据结构、所有读写方、迁移fixture、真实HEAD/index和其他owner边界均须在写前核实；未知外部状态保持`UNVERIFIED`。

## 范围与保护

### Producer / direct consumer / tests / runner-manifest / docs

store是持久记录owner，service是唯一生命周期写入者；登录和刷新调用方只读公共结果。exact包含合同、两个实现点和直接迁移/生命周期测试；部署与secret消费者只读。

### Conditional contingency

只有fixture证明旧记录无法经现有store读取时，才申请新增fixture路径；未批准前停写。

### Forbidden与保护边界

禁止读取或修改真实secret；禁止部署、push、发布和变更账号状态；不纳入其他owner差异。

## 方案、影响与pre-mortem

先冻结版本字段和单一迁移owner，再实现读取迁移、写回时机、撤销与过期清理。Pre-mortem：部分迁移造成双写——验证唯一写入者；回滚无法读新记录——运行双版本fixture；失败重试重复发令牌——覆盖中断与幂等路径。

## 选用评审视角

程序理论、依赖方向、测试与安全重构、平台与发行生命周期；分别核对合同归属、写入者、迁移安全网和外部动作隔离。

## 验收与验证

行为清单覆盖创建/读取/刷新/撤销/过期/迁移/失败恢复；直接测试与相关集成回归通过；稳定candidate/依赖manifest/工具链与命令形成证据有效键；实际diff和保护路径零纳入。

## 执行、审核与Git记录

执行者记录actual与验证；独立审核者绑定稳定对象给出结论；只有owner可决定Git。外部动作保持未授权。

## 交接/下一步

唯一下一动作：执行者在exact内形成候选和证据并按宿主适配交指定审核者；停止线和最终结论回唯一owner。
```

若上述任务运行在Codex并授权直接审核闭环，再从`HOST_ADAPTER_CODEX.md`追加actor/notifier、消息与轮次字段；这些字段不是认证合同的一部分。

## 4. 向上升级，不向下降级

- `MICRO -> STANDARD`：跨turn、阻断、范围扩大、需要第二写入者/审核上下文、出现并行owner冲突，或直接验证不再足够。
- `MICRO / STANDARD -> CRITICAL`：发现公共合同、复杂状态机、核心循环、持久状态、平台/runtime、账号/发布、不可逆动作或高缺陷代价。
- 任何档位发现owner、范围、权限或风险无法确定：停写并回有权限的owner；checker不能替代该判断。
- `CRITICAL`不能因为文件少或测试易写降级；`MICRO`也不能因为“不建卡”被解释成无owner、无范围、无验证或默认Git权限。
