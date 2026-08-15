# Framework 1.5.2 vs 1.6.0 A-C+G候选

| 维度 | 1.5.2 | 1.6.0候选 |
|---|---|---|
| 远端动作 | 单动作授权，无批次公共DTO | 同一本地repo的RemoteBatch；逐remote一次、无自动retry/compensation |
| 保护路径 | 项目规则与授权边界 | project.json schema 3唯一机器policy；Framework Git入口fail closed |
| 资源 | 原则性最低充分质量 | DEFAULT/例外需求 + 短期机器binding；不保存完整矩阵 |
| 协调 | owner/执行者/Review基础路由 | 默认直达/no-poll/terminal-only；只持久化例外 |
| controller | 项目控制文档事实 | controller.json唯一current ID/epoch；旧epoch控制消息与授权失效 |
| register/upgrade | schema 2、pin+Bootstrap事务 | schema 3、controller与撤销账本的冻结多对象事务 |

减重没有删除owner、writer、authorization、protected path、controller epoch、preimage或真实remote结果。删除的是默认字段展开、主控routine报告、ACK链、自动remote恢复引擎和重复状态。
