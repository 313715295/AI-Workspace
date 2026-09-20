# Framework 1.16.0

当前开发批：规则选择与职责收敛、纠正日常修订和完整历史、中央映射退出、显式采用处置、actor 存储映射与材料生命周期。仍为 CANDIDATE；当前 manifest 的 PENDING 不表示已完成独立 Review 或完整套件验证，历史快照结果不覆盖新字节。

lifecycle authority：`VERSION.json` 与 `RELEASE_MANIFEST.json`。本文不复制或选择 lifecycle state。

baseline：immutable stable Framework `1.15.1`。release class：`MINOR`。

`1.16.0` 保持单一 progressive-loading composer，并收紧 adoption/runtime contract：

- `ADOPTION_PROFILE.json` 统一声明 registration eligibility、Project Format/capability 兼容范围、schema4 project control、exact capability binding、runtime artifact root；1.16新基线的跨pin兼容范围为空。
- version profile只声明通用repo-local project contract。Framework Maintenance的sibling topology、旧版本allowlist与overlay投影由root维护工具拥有；version payload不复制完整Maintenance starter或专属resolver。
- `.ai-workspace/process-policy.json.selectedRulePackBytes` 是保留的历史兼容字段；规则包大小仅记录真实观测，不限制必要完整正文，也不增加调额或确认门。
- `DISCOVER` 在自然 context boundary 一次返回完整 canonical Markdown blocks，并给出不含 `fullText` 的 compact receipt；`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 复用该 receipt，边界输入只补实际 evidence。
- structured project rule 可绑定项目现有标准文档的全文或唯一 marked section；只加载命中正文及必要依赖，来源漂移保守加载，相关来源不可用时阻止依赖动作。
- task Owner、Work route actor 与临时 action grantee 分离。source、test、Review、Git、browser/device 与 external actor 都是可选临时角色，不改写 task Owner；正常 Review 无反向改卡、删包或释放 ACK。
- 没有任务卡的项目只读讨论使用 `PROJECT_READ_ONLY` context，仍选择并加载三源适用规则，但不伪造 task、Owner 或 action authority。
- upgrade 在 pin write 前构建 target projection，先迁移 legacy two-field task route、project policy 与 budget，再运行 target resolver；root Maintenance adapter在这套通用target contract之外独立验证双Git-top与目标control-plane禁止条件。
- ephemeral artifact 默认位于 `.ai-workspace/runtime/<task>/<actorStorageKey>/`；registration/upgrade 幂等维护 root `.gitignore`。存储键映射见 TOOL_CONTRACT，真实 actor 身份不变；system temp `aiw-*.json` 只是 fallback。
- 唯一 canonical Router Skill 位于 root `skills/ai-workspace-router/SKILL.md`；version 内 host 文件仅保存兼容历史。
- root 接入工具按 Project Format/capability 生成幂等投影，失败恢复旧有效组合；采用结果绑定实际 Framework pin、Project Format 与 Root Tool Revision。普通用户包只携带一个目标版本和必要接入依赖。

resolver 不授予 authority，也不证明 semantic correctness。`SOURCE_WRITE`、TEST、REVIEW、`OWNER_ACCEPT`、Git、push、browser/device、external 与 protection gate 保持独立。project corrections 与 project-specific process rules 仍是独立 project authority。

Router 缺失、不可发现或不兼容时，按[接入说明的宿主接入收尾](../../PROJECT_ADOPTION.md#宿主接入收尾)修复后继续。`1.16.0` 唯一 official backend 是 Windows 上的 `powershell7`。

当前开发候选取消中央项目纠正映射：项目当前显式生命周期决定生效；旧包采用处置由根 PROJECT_ADOPTION 说明，保留完整历史。实现期间 RELEASE_MANIFEST 的验证/审核保持 PENDING，不沿用旧 Snapshot 的通过结果。
