# Framework 1.16.0 post-release project observation

本文是 `NON_AUTHORITY / OPTIONAL / PROJECT_LOCAL` 指南，不是 release gate、runtime ledger、project authority、permission source，也不要求创建 evaluation work。

- 只有项目通过正常 pin-adoption boundary 显式采用 stable `1.16.0` 后才开始 observation。
- 使用正常 project task；不得为取样创建 synthetic task、child task 或 artificial action，也不规定固定 sample count/time window。
- observation 有实际价值时，在来源 task 保留一条 compact record：bound task/boundary、source-composition/selection/decision identities、actual result，以及 false block、missed requirement 或 unnecessary load。负面结果同样有效。
- evidence 属于来源项目。Framework 不保存 consumer identity、task copy、measurement ledger 或 standing report，也不要求 delivery/ACK。
- 项目以后可以通过普通 Framework-gap intake 提供 anonymized conclusion；它可支持未来版本，但不追溯改变 `1.16.0` 或其他 project pin。

Framework conformance fixture 与 project observation 分离。机械 PASS 不证明 semantic correctness、attention、host invocation 或 cost/quality improvement；observation 也不替代 conformance、independent Review、`OWNER_ACCEPT` 或 release sealing。
