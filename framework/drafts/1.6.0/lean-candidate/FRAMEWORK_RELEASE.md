# Framework 1.6.0发行门

本模块只供Framework维护者在完整候选冻结后加载。当前目录是`DRAFT / NOT_CONSUMABLE`，以下规则不是发行授权。

## 1. 输入与不可变边界

- baseline必须是稳定1.5.2 inventory与当时live root scripts的冻结identity；稳定目录永久只读。
- clean candidate不得import或加载旧`framework/drafts/1.6.0/candidate/**`与`root-scripts/**`。
- D/E/F/H未完成前，A-C+G候选不能冒充完整1.6.0 release。

## 2. A-C+G审核门

- RemoteBatch逐remote授权/head/refspec/fingerprint、一次尝试、PARTIAL与fresh retry新包闭合；旧RemoteTransaction、PreviousLedger与COMPENSATION只有拒绝负键，零有效语义。
- protected sentinel不进入允许pathset、输出或evidence；project config缺失/损坏/漂移与安全Git失败均为`UNVERIFIED`且无宽扫描fallback。
- DEFAULT资源快路径和特殊工具/fresh约束都闭合；低于minimum、缺工具或任一binding输入漂移均拒绝。
- controller轮换、旧epoch route/auth/ACK、queued routine suppression、exception一次重路由、state dedup与DOMAIN_OWNER兼容闭合。
- register/upgrade对支持来源、冻结preimage、失败恢复和不自动改真实项目闭合。

## 3. 独立阶段

1. feature writer释放并冻结candidate manifest；
2. fresh独立实现Review；
3. D/E、F和全局integration分别实现与Review；
4. release candidate重新计算完整manifest、strict文本、load plan与迁移矩阵；
5. 内容批准、正式version生成、Git、tag/push、CURRENT和项目pin分别授权。

任何direct PASS都不授权真实Git、remote、external、CURRENT或项目采用。项目级知识内容与自然样本不是本A-C+G分片的发行证据。
