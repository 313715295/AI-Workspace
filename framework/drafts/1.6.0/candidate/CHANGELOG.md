# Framework 1.6.0 draft变更说明

## A-C+G第一阶段

- 新增`REMOTE_TRANSACTION_SCHEMA.json`与`check-remote-transaction.ps1`，按remote冻结endpoint fingerprint、refspec、expected heads、幂等键和secret-safe ledger；成功项不可重跑，失败/未知项可重试，远端副作用只可另授权补偿。
- 资源合同改为host-neutral能力约束；具体model/effort只属于host adapter。task checker验证最低质量、工具可用性和no-silent-downgrade。
- task schema 1.6记录独立任务、来源、唯一report target、wait和terminal archive；controller route checker完成epoch-first、state dedup、queue suppression和exception单次重路由。
- 新增canonical `controller.json` schema 1。PROJECT_CONTROLLER授权包条件必填controller三字段并由checker读取current control object复算；DOMAIN_OWNER分支保持独立。
- draft root register/upgrade副本生成controller epoch 1；upgrade生成legacy controller revocation ledger并以可恢复本地事务写pin、Bootstrap、controller和ledger。

## 未完成

D/E/F/H、知识selector、完整集成、迁移矩阵最终证据、fresh独立Review、正式manifest、live root scripts、CURRENT、Git和项目采用均关闭。
