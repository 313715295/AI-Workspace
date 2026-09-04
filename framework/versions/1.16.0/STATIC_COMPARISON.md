# Framework 1.15.1 与 1.16.0

| Concern | 1.15.1 | 1.16.0 candidate |
|---|---|---|
| adoption facts | root tool 中的 target-specific branch | 一个 `ADOPTION_PROFILE.json` |
| direct sources | bounded 1.14.x bridge | profile 声明 1.14.1、1.15.0、1.15.1 |
| selected pack | current-pin ceiling 与 bridge exception | project policy 选择 ceiling；absolute cap `98304` |
| upgrade preflight | current-pin resolver 先运行 | migrated task/policy/budget 的 target projection 先运行 |
| task/Reviewer | actor route 与 package grantee 易混同 | Owner、`taskActor`、action `actor` 分离 |
| DISCOVER | complete selected blocks 作为 boundary receipt | complete blocks 一次加载，另用 compact receipt |
| temporary input | caller-owned lifecycle | project runtime 优先，system temp fallback，显式 cleanup |
| Router source | version copy 与 root projection | root 唯一 canonical Skill，version 仅 contract/history |
| machinery | 一个 resolver/composer | 不增加 service、registry、ledger、cache、poller 或第二 authority |
