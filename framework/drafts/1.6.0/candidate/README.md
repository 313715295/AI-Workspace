# Framework 1.6.0 A-C+G candidate

## 状态

- lifecycle: `DRAFT / NOT_CONSUMABLE`
- source baseline: `Framework 1.5.2 STABLE`
- release class: `FULL_RELEASE`
- implemented slices: `A / B / C / G`
- unimplemented gates: `D / E / F / H / INTEGRATION / REVIEW / RELEASE`
- `framework/CURRENT`、live root scripts、正式version和项目pin：未改变

本目录是隔离实现候选。`resolve-load-plan.ps1`默认拒绝加载；只有candidate direct tests可显式传入`-AllowDraftCandidate`。register/upgrade的实现副本只位于draft `root-scripts/`，不能被项目消费。

## 当前能力

- A：逐remote稳定身份、独立ledger、部分成功、幂等重试、head/config漂移、受保护路径排除和另授权补偿。
- B：公共层只保存host-neutral最低质量、工具、上下文、延迟、成本和并发约束；host adapter fresh rebind失败时fail closed，不静默降级。
- C：长周期独立任务主动回传；wait只在当前消费者依赖结果时一次有界；terminal才归档；复用前重新绑定来源、owner、资源、候选和路径。
- G：`.ai-workspace/controller.json`是current controller唯一真相；PROJECT_CONTROLLER包绑定controller identity/epoch，DOMAIN_OWNER包不消费这些字段；route先验epoch再去重，旧routine queue抑制，旧exception仅复证后单次重路由。

## 证据上限

本候选的direct tests只证明A-C+G对象的局部合同与根脚本副本行为。它不证明完整迁移矩阵、知识自然样本、全版本集成、独立Review、发行、CURRENT更新或任何项目采用。
