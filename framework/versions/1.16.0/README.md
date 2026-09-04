# Framework 1.16.0

lifecycle authority：`VERSION.json` 与 `RELEASE_MANIFEST.json`。本文不复制或选择 lifecycle state。

baseline：immutable stable Framework `1.15.1`。release class：`MINOR`。

`1.16.0` 保持单一 progressive-loading composer，并收紧 adoption/runtime contract：

- `ADOPTION_PROFILE.json` 统一声明 registration eligibility、direct source versions、schema4 project control、exact capability binding、runtime artifact root 与 absolute process-pack cap。
- version profile只声明通用repo-local project contract。Framework Maintenance的sibling topology、旧版本allowlist与overlay投影由root维护工具拥有；version payload不复制完整Maintenance starter或专属resolver。
- `.ai-workspace/process-policy.json.selectedRulePackBytes` 由项目选择 runtime ceiling；starter 缺省 `32768`，Framework absolute cap 为 `98304`。
- `DISCOVER` 在自然 context boundary 一次返回完整 canonical Markdown blocks，并给出不含 `fullText` 的 compact receipt；`ADMIT_ACTION` 与 `FINALIZE_OUTPUT` 复用该 receipt。
- task Owner、Work route actor 与临时 action grantee 分离。独立 `REVIEW_EXECUTE` Reviewer 不改写任务卡，receipt 同时记录 `taskActor` 与 action `actor`。
- upgrade 在 pin write 前构建 target projection，先迁移 legacy two-field task route、project policy 与 budget，再运行 target resolver；root Maintenance adapter在这套通用target contract之外独立验证双Git-top与目标control-plane禁止条件。
- ephemeral artifact 默认位于 `.ai-workspace/runtime/<task>/<actor>/`；registration/upgrade 幂等维护 root `.gitignore`。system temp `aiw-*.json` 只是 fallback。
- 唯一 canonical Router Skill 位于 root `skills/ai-workspace-router/SKILL.md`；version 内 host 文件仅保存兼容历史。

resolver 不授予 authority，也不证明 semantic correctness。`SOURCE_WRITE`、TEST、REVIEW、`OWNER_ACCEPT`、Git、push、browser/device、external 与 protection gate 保持独立。project corrections 与 project-specific process rules 仍是独立 project authority。

host-global Skill 不可用、不兼容或无法证明已运行时，先读 `RECOVERY_CORE.md`；通过 `TOOLCHAIN.json` 解析 executable operation。`1.16.0` 唯一 official backend 是 Windows 上的 `powershell7`。
