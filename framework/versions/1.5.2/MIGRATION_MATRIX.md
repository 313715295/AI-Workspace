# Framework 1.5.1 → 1.5.2 patch迁移矩阵

本文件只用于Framework开发、Review和发行证据，不进入项目运行时加载计划。1.5.2不重写1.5.1稳定目录。

| 1.5.1对象 | 处置 | 1.5.2落点 | 状态与说明 |
|---|---|---|---|
| `scripts/check-authorization.ps1`字段解析 | FIX | 严格JSON类型门 | 字符串布尔、字符串整数、标量数组和错误成员类型必须拒绝 |
| `REVIEW_EXECUTE`独立性 | FIX | action互斥门 | 候选写入、Git、push/external变更动作不得与最终审核同包 |
| authorization direct tests | ADD | hotfix + framework tests | 覆盖两项已复现漏放及合法包回归 |
| `AUTHORIZATION_MODEL.md` | CLARIFY | checker证明边界 | 明确类型、分包及writer lineage责任 |
| task checker/schema | KEEP | 原文件版本自指向 | 1.5.1阶段验收规则不变 |
| recovery/loader/starter | KEEP | 原拓扑 | 模块、角色、阶段、宿主和项目文件inventory不变 |
| 根register/upgrade | KEEP | 根脚本 | 只做1.5.1→1.5.2 smoke |
| 1.5.1稳定目录 | KEEP_IMMUTABLE | `framework/versions/1.5.1/**` | 零原位修改 |
| 多远程仓库支持 | DEFER | 1.5.3 | 不扩大本安全热修 |

## 兼容与完成门

- 合法1.5.1授权包无需新增字段；项目只改pin与Bootstrap受管区。
- 异常JSON和写审混合包从错误`PASS`改为`FAIL`，属于安全收紧而非产品schema迁移。
- hotfix direct、完整Framework回归、strict文本、拓扑、1.5.1→1.5.2升级smoke和fresh聚焦Review全部通过后才可进入STABLE。

## Machine-readable release gate

- Test harness: `tests/run-framework-tests.ps1`
- `current_status=STABLE_RELEASED`
