# Review 与 evidence

<!-- AIW-REQUIREMENT:PR_CRITICAL_REVIEW_INDEPENDENCE:BEGIN -->
## 风险跟随 action

public contract change、candidate payload、Controller/long-lived owner switch、material scope 的 Git integration，以及 profile 要求的 external action，都需要 independent Review。

mechanical formatting、canonical projection 与 release-field sealing 在不改变已 Review 的 public contract 或 candidate payload 时，可以使用直接 checker evidence。

Review 不授予 write、Git、push 或 external capability。

对未变化的 domain task，DOMAIN_OWNER 可以直接选择 independent Reviewer，并签发纯 `REVIEW_EXECUTE` package；PROJECT_CONTROLLER 不是强制签名或 delivery hop。临时 Reviewer 只成为 action grantee，不改写 task Owner、Work route actor、task identity 或 candidate bytes。CRITICAL scope 下，task owner、issuer、candidate writer 与 material solution contributor 必须被机械排除；合格 cross-domain writer 仍是 writer/contributor，不改变 task ownership。`OWNER_ACCEPT` 是之后的 domain/product gate，不是 Review。

## Candidate freeze

stable candidate 标识 repository、parent/baseline、exact files、byte identities、canonical payload、known dirty/index state、writer release 与 evidence ceiling。canonical immutable evidence 只存一次并由其他对象引用；不要在 mutable card 之间复制，也不要增加 field-level manifest。

finding 不授权 repair。same-scope repair 使用新 writer package，更新 affected freeze，并由同一个仍保持独立的 Reviewer 做 focused rereview。contract、path 或 impact set 扩大时，需要新的 full Review。

release 声明已吸收某条 project correction 时，Review 必须把原始 correction reason、effective rule 与 applicability boundary 对照实际 normative modules 与 behavior tests。coverage ID、changelog 声明或近似措辞本身不是 acceptance evidence。
<!-- AIW-REQUIREMENT:PR_CRITICAL_REVIEW_INDEPENDENCE:END -->

<!-- AIW-REQUIREMENT:PR_EVIDENCE_CEILING_DISCIPLINE:BEGIN -->
## Evidence ceiling

direct fixture 可以证明 generic contract、failure case、canonical manifest 与 anonymous project preservation。可选 post-release project observation 可以提供来源项目中的实际 invocation、false-block/leak 与 cost evidence，但不阻塞 release，也不证明 universal semantic correctness、model attention、browser/device state、remote publication 或 external claim。

official PowerShell 7 backend 必须在每个声称支持的平台保持 timestamp string 与 normalized result。`1.16.0` 只声称 Windows。以后若声称 Linux 或 macOS，必须有对应实际 conformance result；missing platform/runtime 是显式 evidence ceiling，不得伪造 PASS。
<!-- AIW-REQUIREMENT:PR_EVIDENCE_CEILING_DISCIPLINE:END -->

<!-- AIW-REQUIREMENT:PR_OWNER_ACCEPT_SEPARATE:BEGIN -->
`OWNER_ACCEPT` 是 current task owner 对 exact reviewed result 的独立 product/domain acceptance。Reviewer approval 不等于 `OWNER_ACCEPT`；owner acceptance 也不会追溯改变 Reviewer independence，或授予 implementation、Git、push、external authority。

该规则由接受动作触发，不因 Work phase、角色标签或 Profile 不同而漏加载。动作前绑定范围内所需的 Review 或允许的直接证据；输出前确认实际接受记录。`OWNER_ACCEPTANCE` 结果必须使用 `OWNER_ACCEPT` 动作，不能改成 `NONE` 或记录写入动作来代替准入。机械检查验证当前 Owner、授权、对象身份与所需回执，不声称已经证明 Review 内容或接受判断的语义正确性。
<!-- AIW-REQUIREMENT:PR_OWNER_ACCEPT_SEPARATE:END -->
