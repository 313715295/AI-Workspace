# {{DISPLAY_NAME}} — 项目审核配置

本文件只补充项目特有评估单元、风险和验证重点。通用分级与审核方法由固定Framework的`TASK_AND_SCOPE.md`和`REVIEW_AND_EVIDENCE.md`持有；项目可以加严，不能静默降档。

## 1. 项目评估单元

| 单元 | 上游权威 | 实现/输出 | 直接验证 |
|---|---|---|---|
| 产品与体验 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 核心架构与数据 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 表现与用户界面 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 平台、工具链与发行 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |

初始化按真实依赖闭包改写本表；不适用单元删除，不为填满结构制造领域。

## 2. 项目特有审核重点

- 产品可理解性与不可改变的相邻行为：`UNVERIFIED`
- 分层、依赖方向和唯一状态owner：`UNVERIFIED`
- 生命周期、失败恢复与回滚：`UNVERIFIED`
- runtime、视觉、性能、device或平台证据：`UNVERIFIED`
- 数据、凭据、用户内容与保护路径：`UNVERIFIED`
- 必须直接归入CRITICAL的项目特有对象：`UNVERIFIED`
- 必须由用户试玩先于独立Review的玩家行为：`UNVERIFIED`

## 3. 常见偏差

- 把模板、摘要或`UNVERIFIED`写成已授权事实。
- 只验证生成/构建成功，没有直接行为或运行证据。
- 复制通用流程，形成第二角色、审核、Git或授权真相。
- 超出exact，覆盖用户/其他owner字节，或先写后补范围。
- 把公共合同、持久状态、跨turn或external伪装为无卡MICRO。
- 对普通任务执行发布级manifest、设备矩阵或逐命令审批。

初始化完成前替换占位内容；真实缺失项保留`UNVERIFIED`并进入STATUS下一动作。
