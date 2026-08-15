# Framework 1.6.0迁移矩阵（A-C+G候选）

| 来源 | 目标 | 支持状态 | 必需输入 | 结果 |
|---|---|---|---|---|
| repo-local 1.4.1 | 1.6.0 | DIRECT_FIXTURE_REQUIRED | controllerId、protectedPathsMigration、legacy controller authorization inventory及各自identity | schema 3 project、managed Bootstrap、epoch 1 controller、revocation ledger |
| repo-local 1.5.0 | 1.6.0 | DIRECT_FIXTURE_REQUIRED | 同上 | 同上 |
| repo-local 1.5.1 | 1.6.0 | DIRECT_FIXTURE_REQUIRED | 同上 | 同上 |
| repo-local 1.5.2 | 1.6.0 | DIRECT_FIXTURE_REQUIRED | 同上 | 同上 |
| central-legacy | 1.6.0 repo-local | NOT_GENERIC_UPGRADE | 项目专属迁移任务 | 根upgrade不改变拓扑 |
| 1.6.0新项目 | 1.6.0 | REGISTER | 明确ControllerId | schema 3 project、空protectedPaths、空frameworkCapabilities、epoch 1 controller |

## 硬边界

- schema 2→3不猜测保护路径。缺失、损坏或identity漂移的migration对象必须停止；materialize前source Git事实保持`UNVERIFIED`。
- legacy PROJECT_CONTROLLER包inventory逐locator复算identity后写入撤销账本；无法证明lineage的包fail closed。DOMAIN_OWNER包不因controller轮换批量撤销。
- target从冻结old material派生；事务准备前、每次replace前都复证preimage。未知live bytes保留并停止。
- 重复调用必须严格验证schema 3 project、controller和存在时的revocation ledger；不得用“已升级”掩盖损坏控制对象。
- upgrade不stage/commit/push，不运行项目瘦身，不自动启用knowledge，不自动重签旧授权。
