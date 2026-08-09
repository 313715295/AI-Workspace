# {{DISPLAY_NAME}} — 项目审核配置

本文件只补充项目特有的评估单元、风险与验证重点。通用`MICRO / STANDARD / CRITICAL`准入与审核方法仍由固定Framework `REVIEW_CHECKLIST.md`持有；项目可以加严，不能静默降档。

## 1. 项目评估单元

| 单元 | 上游权威 | 实现/输出 | 直接验证 |
|---|---|---|---|
| 产品与体验 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 核心架构与数据 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 表现与用户界面 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |
| 平台、工具链与发行 | `UNVERIFIED` | `UNVERIFIED` | `UNVERIFIED` |

初始化会话应按真实依赖闭包改写本表；不适用的单元删除，不为填满结构制造领域。

## 2. 项目特有审核重点

- 产品可理解性与不可改变的相邻行为：`UNVERIFIED`
- 分层、依赖方向和唯一状态owner：`UNVERIFIED`
- 生命周期、失败恢复与回滚：`UNVERIFIED`
- runtime、视觉、性能、设备或平台证据：`UNVERIFIED`
- 数据、凭据、用户内容与保护路径：`UNVERIFIED`
- 必须直接归入`CRITICAL`的项目特有对象：`UNVERIFIED`

## 3. 常见偏差

- 把模板建议或`UNVERIFIED`项写成已授权事实。
- 只验证生成/构建成功，没有直接行为或运行证据。
- 复制通用流程，形成第二套角色、审核或Git规则。
- 修改超出任务卡exact范围，或覆盖用户和其他owner字节。
- 把跨turn、公共合同、持久状态或外部动作伪装成无卡`MICRO`。

初始化完成前应把以上占位内容替换为项目证据；真实缺失项保留`UNVERIFIED`并进入`STATUS.md`的下一动作。
