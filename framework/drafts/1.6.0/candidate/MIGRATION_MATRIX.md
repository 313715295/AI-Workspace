# Framework 1.4.1 / 1.5.x → 1.6.0 draft迁移矩阵

本文件是候选证据输入，不进入普通项目loader。当前状态=`A_C_G_DIRECT_ONLY / NOT_RELEASE_READY`。

| 来源（已验证repo-local布局） | controller迁移 | legacy controller包 | DOMAIN_OWNER包 | remote | 状态 |
|---|---|---|---|---|---|
| 1.4.1 | 明确ControllerId，生成canonical epoch 1 | frozen inventory→`STALE_AUDIT_ONLY_NO_ACTION` | 按原invalidators保留 | 旧单remote权限不扩张 | DIRECT_TEST_REQUIRED |
| 1.5.0 | 同上 | 同上 | 同上 | 同上 | DIRECT_TEST_REQUIRED |
| 1.5.1 | 同上 | 同上 | 同上 | 同上 | DIRECT_TEST_REQUIRED |
| 1.5.2 | 同上 | 同上 | 同上 | 同上 | DIRECT_TEST_REQUIRED |

upgrade preview必须先解析并冻结ACTIVE legacy PROJECT_CONTROLLER locator与identity；任何DOMAIN_OWNER locator直接拒绝，不得进入revocation ledger。Apply通过可恢复事务写schema3 project pin、受管Bootstrap、`controller.json`和revocation ledger；project/Bootstrap target必须由首次严格读取的冻结preimage派生，old copy与每次live replace都逐字复证该preimage。全部legacy载体还必须在Apply入口与revocation ledger落盘前分别按冻结locator复算bytes identity；inventory后漂移、事务中漂移、缺失或迁移均fail closed，已进入事务时走recoverable rollback并保留未知载体字节。首次读取后漂移、copy漂移或replace漂移均停止并保留未知字节。旧controller包不转换为successor包；successor基于current task重新签发。remote ledger的成功receipt也不因本地恢复或补偿失败而删除。

中央legacy→repo-local会改变拓扑，不属于本矩阵的通用upgrade；必须另建项目专属迁移任务。已完成1.6.0升级的current controller重复调用只有在canonical current controller与完整canonical revocation ledger都复证后才返回`ALREADY_UPGRADED`；checker还必须从每个ledger locator重新读取legacy载体并复算实际bytes identity，载体缺失、迁移或identity漂移均fail closed。legacy审计载体因此必须保留到另一个明确授权的locator迁移同步更新该证明为止。ledger未知字段、缺字段、类型/枚举/条目identity漂移均fail closed。合法轮换后的current controller epoch大于1可以重复升级检查通过，ledger仍保留迁移时epoch 1来源记录。已注册项目经历合法controller轮换后，register重复检查接受current epoch大于1，但显式ControllerId必须与current一致。

## 尚未闭合

- D/E/F/H与知识双项目门；
- 完整四来源迁移、全角色loader、失败注入矩阵和独立Review；
- 正式release manifest、live scripts、CURRENT、Git与项目pin。

Machine gate: `current_status=DRAFT_A_C_G_NOT_CONSUMABLE`
