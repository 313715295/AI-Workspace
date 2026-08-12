# Framework 1.5.0变更说明

## 版本性质

1.5.0是从1.4.1稳定版派生的major版本，目标是在不降低必要质量门的前提下，减少首次恢复、重复全文读取、发布级防御外溢、多会话等待和逐动作授权成本。

本版本可由项目通过独立升级任务显式pin；`framework/CURRENT`仍为1.4.1。稳定发行不授权Git、tag、push、CURRENT切换或任何具体项目升级。

## 已落地能力

- 公共`RECOVERY_CORE`与role/profile/phase/host确定性loader。
- 完整的任务/范围、审核/证据、Git/external、项目控制和Framework发行按需模块。
- 项目主控/领域owner分级签发阶段能力包；用户只守产品结果、重大方案/公共合同和external。
- 授权checker绑定task、owner、grantee、action、exact、identity、用户门和失效条件。
- task checker验证1.5热卡range/actual/authorization，legacy不强迫批量迁移。
- current/history物理分离、manifest稳定边界、普通控制卡不以whole-file漂移阻断。
- Codex主动回传、禁止默认wait、禁止默认worktree和紧凑脚本输出。
- starter保持schema2和既有inventory，只改变Bootstrap受管区即可升级加载协议。

## 明确不做

- 不建立数据库、服务、长期授权仓库、逐任务指标平台或角色×档位组合文档。
- 不逐工具调用重复授权脚本，不为每个会话创建worktree，不为MICRO/STANDARD机械挂载独立Review。
- 不批量重写legacy卡、history或项目关系资料。
- 不在Pocket W1进行中改pin或混入Framework业务验证。

## 后续采用门

- 独立聚焦Review与稳定发行测试已经通过；根register/upgrade无需语义改写，已通过1.5.0注册和1.4.1→1.5.0事务验证。
- 自然样本继续验证恢复完整性、授权误拒/漏放、质量与返工率；这些结果决定是否调整1.5.x或切换CURRENT。
- Pocket可升级时必须做1.4.0/1.4.1/1.5.0真实对比，按`KEEP / ADJUST / REJECT`修订。
