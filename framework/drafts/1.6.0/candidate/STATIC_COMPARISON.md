# Framework 1.5.2 vs 1.6.0 A-C+G静态对比

本文件是draft证据，不进入普通loader。

| 维度 | 1.5.2 | 1.6.0 A-C+G candidate |
|---|---|---|
| remote | 单动作授权，无逐remote ledger | stable fingerprint、逐项结果、幂等重试、另授权补偿 |
| resource | host adapter建议为主 | common最低能力合同 + host fresh rebind + fail closed |
| task coordination | 主动回传与少量wait说明 | source/report/wait/archive可机械检查 |
| controller | owner文本身份 | canonical controller object + monotonic epoch |
| controller authorization | 无epoch绑定 | PROJECT_CONTROLLER条件三字段；DOMAIN_OWNER不消费 |
| route | peer说明 | epoch-first、dedup、queue suppression、exception单次复证重路由 |
| starter | schema2、8文件 | schema3、9文件，新增controller.json |
| release | STABLE | DRAFT / NOT_CONSUMABLE |

loader模块集合尚未新增；A-C+G落在既有模块及两个schema/两个checker中。当前成本和完整candidate manifest只有INTEGRATION冻结后才能成为发行证据。
