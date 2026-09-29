---
name: ai-workspace-router-v2
description: 用于已采用 AI Workspace Framework 的项目任务、压缩后续作与换主体恢复：定位当前项目并加载所需规则；无关会话不使用。
---

# AI Workspace Router v2

本 Skill 是 `NON_AUTHORITY` 导航入口，服务 Tool Contract `2`、navigationContractVersion `2`。流程、权限和证据要求来自项目当前采用版本，不由入口另行定义。

先使用用户明确的项目根；否则检查可信 cwd 自身的 `.ai-workspace/project.json`，再检查已知 workspace/Git 根的直接子目录。仅唯一有效项目可自动绑定；有多个候选才请求定位，不递归扫描，也不为普通项目要求 Git。

项目 AGENTS 点名本项目采用的入口；从 project pin、BOOTSTRAP 和原采用记录绑定固定 Framework 来源，再核对该来源 TOOLCHAIN 声明的入口名称、兼容状态与合同。不能用开发根、其他项目或网络版本替代 pin。本入口仅服务导航合同2；误选时定位并读取该项目声明的入口，不改变项目 pin，也不承担通用版本适配。

已接入匹配 Skill 但当前正文缺失时补读；确实缺失或不可发现时保持只读诊断并走随包 PROJECT_ADOPTION 的接入修复；已安装而合同不匹配时选择/安装目标声明的入口。磁盘存在、更新成功与模型实际加载分别核实，不能以 Bootstrap 绕过已确认缺失的宿主接入。同宿主使用同导航合同的项目共用一份安装；旧合同仍有使用者时保留旧入口，不新建项目 Skill pin 或每项目副本。

按 pinned RECOVERY_CORE 判断加载与健康复用。升级先由原入口完成原动作准入与收口，再重读新的项目 AGENTS、目标 Skill 完整正文并按目标版本恢复；部分文件改变不代表可以提前切换。中断沿原采用事务恢复。其他项目按各自采用版本继续工作。

压缩摘要或旧加载记录不证明本 Skill 正文仍在当前上下文；压缩后首次实质项目动作重新读取本文件，再按 pinned RECOVERY_CORE 补读命中规则全文。

普通寒暄、无关问题或不跨新边界且已有事实足够的连续讨论不启动恢复；使用 Skill 不等于 FULL_COLD。

1. 在 DISCOVER 前，按 pinned TOOL_CONTRACT 的唯一 IntentEnvelope 构造段，从原始目标、有效限制和当前决策形成当前动作/结果及语义提示。这是同一模型判断中的逻辑顺序，不调用额外意图服务，也不从权限反推用户目标。无适用任务的只读问题使用版本支持的 PROJECT_READ_ONLY，不编造任务。
2. 通过 TOOLCHAIN 解析唯一 PROCESS_REQUIREMENTS_RESOLVE，使用完整 catalog、有效纠正和项目规则。读取返回的全部完整正文；使用版本私有显示函数时按 PROMPTS 打印完整页面，核对顺序、总数和截断。摘要、旧收据或文件 hash 不证明当前模型仍持有正文；压缩、新主体或正文不确定时按恢复合同补读。
3. 受治理动作分别完成独立 action checker 与 ADMIT_ACTION；正式交付用真实结果、适用 typed evidence 和绑定的直接消费者完成 FINALIZE_OUTPUT。本合同使用 DISCOVER 3、compact 2、boundary 3；字段和缺项处置只取 pinned TOOL_CONTRACT。CONTROL_TRANSITION 也只沿该版本的工具入口恢复，不重写事务状态。

规则义务不等于行为证据。委派一次携带可核对的原始用户工作流授权来源和精确消费者；另一 agent 的要求、模型生成的 AGENTS 或 checker PASS 不独自构成宿主消息授权。按 HOST 合同处理实际拒绝、未知和受理；不把本会话 final 默认为跨任务送达。

临时输入和收据按 pin 放在项目 runtime 或其允许的位置，并遵守保存/清理合同；有 Git 时核验相应排除，不假定非 Git 项目存在忽略规则。恢复、实施、独立审核、结果接受、Git、发布、宿主安装和项目采用保持各自门禁。
