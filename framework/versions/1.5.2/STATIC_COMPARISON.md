# Framework 1.5.1 vs 1.5.2静态对比

日期：2026-08-12。本文件是发行证据，不进入普通项目loader。

## 运行时与成本

- loader模块集合、项目starter、任务卡schema和根事务拓扑不变。
- 普通恢复不加载本文件、CHANGELOG、MIGRATION_MATRIX或版本README。
- 合法授权包零新增字段，正常执行不增加额外checker调用。

## 行为差异

| 输入 | 1.5.1 | 1.5.2 |
|---|---|---|
| `delegatedGitCloser: false` | 正确处理 | 保持 |
| `delegatedGitCloser: "false"` | 错误PASS | FAIL |
| `actions: "SOURCE_WRITE"` | 可能被标量强制消费 | FAIL |
| `schemaVersion: "1"` | 可能被数值强制消费 | FAIL |
| 纯`REVIEW_EXECUTE`独立包 | PASS | PASS |
| `SOURCE_WRITE + REVIEW_EXECUTE`混合包 | 错误PASS | FAIL |

结论：1.5.2只消除异常授权漏放，不改变合法包成本或项目工作流。

## Current loader cost

The loader reports the current repo-local cost directly; commas are omitted so the release test can compare the values mechanically.

| Role plan | Modules | Bytes | Estimated tokens |
|---|---:|---:|---:|
| DOMAIN_OWNER / STANDARD / PLAN+IMPLEMENT+VERIFY | 5 | 39792 | 9948 |
| CONTROLLER / CRITICAL / RECOVER+PLAN | 6 | 44514 | 11129 |
| FRAMEWORK_MAINTAINER / CRITICAL / full lifecycle | 8 | 52479 | 13120 |
