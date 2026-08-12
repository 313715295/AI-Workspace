# Framework 1.5.1变更说明

## 版本性质

1.5.1从1.5.0稳定版派生，发行类别为`PATCH_HOTFIX`。目标是在不增加普通任务治理成本的前提下，补齐项目阶段验收的机械链。1.5.0稳定目录保持不可变。

## 新增

- schema1.5.1 CRITICAL卡必须声明`Phase gate: TRUE|FALSE`。
- TRUE阶段父卡记录技术证据、领域合同核对、runtime/platform适用性、项目主控签署和用户最终门。
- checker机械验证矩阵字段、顺序、N/A理由、项目签署owner、前置依赖和关闭完整性。
- 阶段矩阵顺序只约束最终闭合；`User final gate: CONFIRMED`机械绑定任务`current_exact`，同一stable candidate上的既有用户试玩/确认可在项目签署后复用，不重复询问，candidate或用户决定漂移才重开用户门。
- 用户反馈或反例只使旧READY与旧授权包失效，不授予writer；唯一owner必须重新冻结current范围与用户决定并重新签发。
- Codex长期peer任务使用应用级任务路由；agent协作表只代表同一live agent tree，不能据其误判主控离线或重跑工作。
- 测试覆盖schema1.5兼容、普通任务零矩阵成本及阶段链正反例。

## 保持不变

- MICRO/STANDARD模板成本、授权分层、用户只确认产品结果/重大方案/external、Review独立性、Git/push分离、默认无worktree、默认无wait轮询。
- loader模块集合、project-starter inventory、根register/upgrade脚本和`framework/CURRENT=1.4.1`。
- 既有schema1.5任务与history不批量重写。

## 热修验证与采用门

- 只运行受影响机制direct正反例、strict/拓扑/load smoke和一次hard-gate聚焦Review；不重复1.5.0的完整迁移、全角色组合、自然样本或无关集成。
- 受影响范围任一不明或出现不兼容证据时自动升级`FULL_RELEASE`，否则完成manifest即可发行1.5.1 STABLE。
- Pocket W1整阶段验收完成后、W2前做1.4.0→1.5.1真实升级对比；发现重复验收、普通任务成本反弹、误拒或漏放则先ADJUST，不改项目pin。
