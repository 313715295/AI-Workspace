# ai-workspace-router-v2 / Framework 2.0.0 导航合同

状态：`REFERENCE_ONLY / VERSION_CONTRACT / NON_INSTALLABLE / NON_AUTHORITY`

Tool Contract `2`，navigationContractVersion `2`。可安装产物位于根 `skills/ai-workspace-router-v2/SKILL.md`，本文件不得安装为Skill。Framework pin与TOOLCHAIN确定当前需要的合同；共享同一导航合同的项目共用入口，不建立每项目副本。旧合同仍有项目需要时保留其独立入口。

入口须导航到当前版本的唯一IntentEnvelope、完整规则正文、ADMIT_ACTION/FINALIZE_OUTPUT及其有类型证据边界；控制转换只走当前版本声明的CONTROL_TRANSITION入口。DISCOVER/compact结构沿用3/2，boundary为3。具体行为以该版本完整规则为准。

当前为开发候选：根入口源码已形成；独立源码审核、封装内容绑定及真实宿主安装/发现/加载仍由发行和接入阶段完成。本文不证明已接入。根Skill只导航、不授予授权，不合并测试、审核、接受、Git、发布或项目采用。
