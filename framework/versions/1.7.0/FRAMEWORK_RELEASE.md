# Framework 1.7.0 release governance

## Class

1.7.0 is a `MINOR` candidate from immutable stable 1.6.1. It adds a compatible, opt-in Framework-maintenance control topology; ordinary repo-local projects do not migrate automatically.

## Candidate gates

1. exact50 payload and exact52 implementation inventory;
2. strict UTF-8/LF, JSON and PowerShell syntax;
3. immutable stable 1.6.1 and current live-root identities;
4. schema4 config、CURRENT-only controller与逐组件无reparse sibling resolver正反例；
5. actual-layout authorization schema选择、schema1 repo-local兼容、Git环境覆盖与invalid nested config拒绝、Maintenance降级拒绝、schema2 repository-bound/resolver-bound steady-state gate、目标完整/partial/foreign/reparse控制面双repository拒绝与两仓STATUS/DIFF/INDEX safe-Git fixtures；
6. loader topology selection plus unchanged repo-local load plan;
7. 完整candidate安装到临时target version后，由渲染Maintenance Bootstrap验证最终稳态、topology loader与normal FULL_COLD route；
8. stable 1.6.1 regression;
9. canonical candidate manifest;
10. fresh independent CRITICAL Review of the frozen candidate and direct consumers.

Tests证明隔离临时目录内最终稳态的恢复路线、fail-closed边界和临时Git读证据，不实现或证明真实目录迁移、旧权威交接、真实迁移授权、stable release、live-root adoption、当前仓Git publication、consumer adoption或external state。

## Publication and migration order

Freeze candidate and manifest, obtain independent Review, project the approved payload to a new immutable stable version, then separately decide live roots and CURRENT. Only after the stable capability exists may the AI-Workspace project perform a separately authorized physical migration and FULL_COLD acceptance. Each repository's Git stage/commit/push remains separately authorized.
