# AI Workspace Framework

让长期 AI 辅助项目在跨会话、跨任务和多角色协作后，仍能从仓库恢复事实、按范围执行、独立审查并安全交接。

AI Workspace Framework 是一套可版本化、可复制采用的 AI 协作流程契约。它把容易散落在聊天记录和临时提示词里的项目事实、任务责任、授权边界与验收要求放回项目仓库。本仓库只保存通用规则、不可变发行版本、起始模板、校验器及发行工具，不保存消费者项目的动态状态。

## 它解决什么问题

AI Workspace Framework 为用户与 AI 共同推进的长期软件项目提供一套可复制、可恢复、可审查的协作机制，重点解决以下问题：

- 使用仓库内的项目事实、Controller、任务卡和 Bootstrap 恢复工作，使新任务不必依赖旧聊天记录才能继续。
- 明确 Controller、DOMAIN_OWNER、临时执行者、Reviewer 等角色的责任，并约束长期 DOMAIN_OWNER 与 Controller 的轮换和交接。
- 将规划、实施、验证、独立 Review、Git、发布及外部操作拆分为独立门禁，避免一次授权被扩展成全部权限。
- 通过受保护路径、完整对象身份、单一 writer 和范围明确的授权包，阻止越权修改、并发覆盖及工作区漂移。
- 规范任务复用与新建、跨任务终态报告、范围门禁和安全异常路由，减少重复汇报、ACK 链和轮询。
- 通过版本化的 `project-starter` 与受控的接入、升级流程，让项目复制同一套流程，同时继续拥有自己的事实、任务、Controller 和 Framework pin。

本文所说的“项目事实”，指能够从项目真实仓库复证的信息：`PROJECT.md` 中的稳定身份、边界和权威入口，`STATUS.md` 与任务卡中的当前状态和决定，`project.json`、`controller.json`、`corrections.json` 中的控制对象，以及实际产品源码、测试、Git 和运行结果。`.ai-workspace` 管理流程权威，但不替代产品源码或运行证据；聊天记录和模型总结只作定位。

它不是产品运行时、业务代码框架或中心化项目管理平台，而是约束用户与 AI 如何安全、连续地协作完成项目工作的流程基础设施。

## 角色术语

- `PROJECT_CONTROLLER`（下文简称 Controller）：维护项目级控制面，并处理跨域、保护边界、项目阶段、Git、设备和外部操作等需要上升的事项。
- `DOMAIN_OWNER`：长期负责某一领域，默认直接安排该领域任务的执行、Review 和结果接收。
- 任务 Owner：任务卡中记录的当前责任方；它不因临时执行者或 Reviewer 的变化而自动改变。
- 临时执行者、Reviewer 和资源档位：按任务或阶段临时承担的角色，不因被分配而获得额外权限。

## 适合谁

它适合这些项目：

- 持续数周或数月使用 Codex、AI Agent 或多个 AI 会话协作开发；
- 同时存在 Controller、DOMAIN_OWNER、临时执行者和独立 Reviewer；
- 需要在切换会话、模型或责任角色后继续恢复同一项目事实；
- 对受保护文件、并发写入、Git、发布或外部操作有明确边界；
- 希望项目自行选择 Framework 版本，而不是被中心系统自动升级。

如果只是一次性脚本、短对话或没有交接与审查需求的小任务，直接使用普通提示词通常更简单。

## 一次任务如何流转

```text
从 BOOTSTRAP 恢复项目事实
        ↓
确认 Controller、任务 Owner、任务和工作区
        ↓
复用现有任务或创建用户明确要求的新任务
        ↓
按动作、路径和对象身份取得范围授权
        ↓
实施与验证
        ↓
必要时进行独立 Review
        ↓
单独授权 Git、发布或其他外部操作
```

同一领域任务默认由 DOMAIN_OWNER 直接选择临时执行者或 Reviewer，并接收结果。只有遇到公共决定、跨域冲突、受保护边界、项目阶段、Git、设备或外部操作时才需要上升到 Controller。普通进度不建立 ACK、heartbeat 或轮询链。

## 它和普通提示词有什么不同

| 普通提示词或说明文件 | AI Workspace Framework |
| --- | --- |
| 依赖当前聊天上下文 | 从仓库内 Bootstrap 和项目事实恢复 |
| 用自然语言约定职责 | Controller、DOMAIN_OWNER、临时角色和交接边界版本化 |
| 一次授权容易被扩大理解 | 写入、测试、Review、Git、发布和外部操作分别授权 |
| 文件变动主要靠人工发现 | 通过路径、完整对象身份和校验器机械检查漂移 |
| 流程变化直接覆盖旧规则 | 每个项目持有明确版本 pin，并自行决定升级 |

## 项目如何持续演进

Framework 不只帮助项目“继续做完当前任务”，也让项目在长期迭代中保留自己的事实、责任、经验和未被通用流程吸收的规则：

```text
项目实践
   ↓
发现重复偏差或 Framework 缺口
   ↓
在项目中记录纠正及其原因
   ↓
Framework 后续版本吸收可通用的要求
   ↓
项目自主选择是否升级
   ↓
已吸收的纠正不再重复执行，未吸收的继续生效
```

任务和产品事实始终由项目自己维护；项目纠正保留“为什么需要这条规则”；Framework 版本提供可验证的通用流程改进。升级、降级或继续停留在原版本都由用户和相应 DOMAIN_OWNER 决定。Framework 不自动修改项目、不自动升级版本，也不会静默删除项目规则。

## 版本权威

Framework 不存在全局默认版本，也不存在全局 `CURRENT` 版本。

- 每个现有项目都通过自己的 `.ai-workspace/project.json.frameworkVersion` 选择并持有 Framework 版本。
- 每次新项目注册都必须明确指定一个准确的稳定 Framework 版本。
- Framework 发行不会自动升级项目、发现消费者或记录消费者身份。
- 项目升级是由该项目自行拥有的独立任务，必须在项目自己的真实控制面和 Git 边界内执行。

只有同时满足以下条件的版本才可供项目采用：其 `VERSION.json` 声明 `STABLE`、`consumable=true`、`projectPinEligible=true`，并且 `RELEASE_MANIFEST.json` 完整、通过规范化校验且已获得独立 Review 批准。

Framework 1.16.0 只有在上述稳定字段、独立 Review 和规范化发行清单全部通过时才可采用；任一条件仍为候选或待处理时，注册和升级都必须停止。满足条件也不会自动授权 Git 发布，或自动升级、发现、记录任何消费者。下方快速开始以 1.16.0 为明确目标，并把这项机械验证作为写入前置条件。

## 仓库结构

```text
README.md
LICENSE
framework/
  ROADMAP.md
  versions/
    <version>/
      VERSION.json
      RELEASE_MANIFEST.json
      CHANGELOG.md
      TOOL_CONTRACT.md
      TOOLCHAIN.json
      requirements/
      project-starter/
      framework-maintenance-starter/
      scripts/
      tests/
scripts/
  register-project.ps1
  upgrade-project.ps1
```

每个发行版本还包含一组通用规则文件，用来规定项目控制面的行为，而不是保存某个项目的当前状态：

- `RECOVERY_CORE.md`：规定如何从仓内事实恢复项目上下文。
- `PROJECT_CONTROL.md`：规定 Controller、DOMAIN_OWNER、项目纠正和控制面对象的关系。
- `TASK_AND_SCOPE.md`：规定任务范围、复用、新建和临时角色路由。
- `AUTHORIZATION_MODEL.md`：规定写入、测试、Review、Git 和外部操作的独立授权边界。
- `REVIEW_AND_EVIDENCE.md`：规定独立审查、证据范围和验收要求。

这些文件只定义规则。项目的真实动态状态始终保存在该项目自己的 `.ai-workspace/**` 中，包括 `project.json`、`controller.json`、任务卡、`STATUS.md` 和 `corrections.json`。

`framework/versions/<version>/` 下已经发行的目录不可修改。新版本直接在其最终版本目录中开发，但在候选内容冻结、完成独立 Review 并正式封存前，不可供项目采用。无需另外维护一份平行的 draft 副本。

## 版本化能力

项目采用某个发行版本后，Framework 从仓内事实恢复身份、任务、角色、阶段、范围和权限边界；在任务或上下文发生实质变化时，从 Framework 规则、仍然有效的项目纠正和项目永久流程规则中选择本次需要的完整内容。支持紧凑边界回执的版本会在自然 DISCOVER 边界展示一次命中的完整规则区块，再让动作前与输出前门禁复用只含绑定和义务的紧凑回执；绑定不确定或漂移时必须重新 DISCOVER，不能凭旧回执继续。

规范 Markdown 中带稳定 ID 的精确区块是 Framework 规则正文的唯一权威。`requirements/fragments/*.json` 只保存选择条件、动作前/输出前要求和正文区块定位；发行时由它们确定性生成并封存元数据目录 `PROCESS_REQUIREMENTS.json`，不复制规则正文。正常流程先绑定最小项目与任务事实，再让 `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER` 对完整元数据目录做选择，最后只加载命中的完整 Markdown 区块和必要支持材料；`LOAD_PLAN` 仅用于兼容、支持材料和有界回退，不在正常路径中预先排除规则。这样既避免先全文加载所有模块，也不建立第二份规则权威。

Tool Contract、项目级工具后端和机械校验负责执行一致性；写入、测试、Review、Git、发布及外部操作仍是独立门禁。项目升级时还会明确比较已被新版本吸收的纠正、仍需保留的纠正和需要人工解决的冲突。

顶层 README 不逐版记录能力演进。未来准入条件、当前候选和完整发行历史按这个顺序记录在 [`framework/ROADMAP.md`](framework/ROADMAP.md)；某个版本的精确变化见该版本目录中的 `CHANGELOG.md`。

## 快速开始

下面的示例明确选择目标版本 `1.16.0`；它不是全局默认版本，只有通过前述稳定性验证后才能采用。注册流程复制所选版本中现有的 `project-starter`，不会另外创建第二套流程模型。

### 新项目接入

把下面内容复制给位于目标项目工作区的 AI 会话，并替换路径和项目名称：

```text
请将当前 Git 项目接入 AI Workspace Framework，并明确采用稳定版本 1.16.0。

Framework 仓库：C:\path\to\AI-Workspace
项目 ID：my-project
显示名称：My Project

请先读取 Framework 仓库的入口说明和 1.16.0 对应流程，全程保持只读，并复证当前 cwd、当前项目 Git 根、Framework Git 根、1.16.0 的稳定/可采用状态、所需工具后端与当前平台是否受支持、宿主全局 ai-workspace-router Skill 是否存在且与目标发行兼容，以及本 AI 会话的真实 task/thread ID。使用这个真实 ID 作为初始 Controller；Skill 不可用时按目标版本 Bootstrap 安全回退，不要在项目仓内复制 Skill；如果宿主无法证明任务 ID，或者项目已经存在控制面、路径冲突或不满足接入条件，请停止并说明最窄 blocker。

然后按照 1.16.0 的正式项目接入流程生成一次确定性预览，向我说明将创建或更新的完整受管对象写集、项目 pin、Controller、对项目既有内容的保留边界和全部 blocker。在我明确确认前不要写入项目，不要修改产品源码，不要执行 Git、远程或其他外部操作，也不要创建第二套流程。
```

检查预览结果后，可以直接回复该 AI 会话：

```text
确认按刚才的预览接入项目。只执行预览中已经声明的受管对象写入，不修改产品源码，不执行 Git、远程或其他外部操作；完成后从新建的 .ai-workspace/BOOTSTRAP.md 做一次完整冷恢复，并报告实际项目 pin、Controller、当前边界和任何未完成事项。
```

项目完成首次采用后，后续新 AI 会话通常只需要：

```text
请从当前项目的 .ai-workspace/BOOTSTRAP.md 开始，按其中的 loader 恢复当前项目、Controller、任务和权限边界。在恢复完成前保持只读；不要从聊天历史猜测当前 authority，也不要自行执行 Git 或外部操作。
```

接入后，项目会获得自己的控制面：

```text
AGENTS.md             # 宿主进入项目时的受管导航入口
.ai-workspace/
  .gitattributes      # 控制面文本字节规范
  BOOTSTRAP.md       # AI 任务的恢复入口
  project.json       # 项目身份、布局和 Framework pin
  controller.json    # 当前 Controller 身份与 epoch
  PROJECT.md          # 项目稳定事实
  RELATIONSHIPS.md    # 权威关系与边界
  REVIEW_PROFILE.md   # Review 要求
  STATUS.md          # 当前热点状态
  corrections.json  # 项目纠正记录；运行时只叠加当前版本尚未吸收的要求
  process-policy.json # 项目永久流程规则；与 Framework 规则和项目纠正保持独立权威
  tasks/             # 项目自己的任务权威
    README.md         # 当前任务索引
    active/           # 活跃任务卡
    archive/          # 已归档任务卡
```

1.16.0 只在项目根投影受管的 `AGENTS.md` 导航块，不再向每个项目复制 Skill。Framework 仓库根部的 `skills/ai-workspace-router/SKILL.md` 是宿主全局安装/发现所用的规范副本；它只负责在自然任务边界触发当前项目所选版本的恢复和规则解析，不成为新的规则权威，也不在每次工具调用时重载。Skill 缺失、未被宿主发现或兼容性无法证明时，项目仍可从自己的 `.ai-workspace/BOOTSTRAP.md` 安全工作，并如实保留宿主执行证据上限。

之后让新的 AI 任务从项目的 `.ai-workspace/BOOTSTRAP.md` 开始即可。Bootstrap 会根据项目 pin、任务卡中绑定的 actor/role/phase、风险级别和宿主/拓扑能力装载对应规则，而不是要求用户重新粘贴历史聊天。

## 现有项目升级

把下面内容复制给当前项目中的 AI 会话；升级属于这个项目自己的任务，而不是 Framework 维护仓或其他项目的操作：

```text
请先评估当前项目到 AI Workspace Framework 1.16.0 的受支持升级路径；只有目标版本 `MIGRATION_MATRIX.md` 明确列出当前 pin 为直接来源时，才准备升级到 1.16.0。

Framework 仓库：C:\path\to\AI-Workspace

请先从当前项目的 .ai-workspace/BOOTSTRAP.md 做完整冷恢复，复证当前项目 Git 根、当前 Framework pin、Controller、当前活动任务及其真实 actor、仍然有效的项目纠正、永久项目流程规则、受保护边界和真实工作区状态。随后严格读取目标版本 1.16.0 的 `MIGRATION_MATRIX.md` 和正式升级要求，但先保持只读。

请先向我报告：当前版本到 1.16.0 是否存在受支持的直接升级路径；目标发行是否稳定且可采用；完整升级写集及每个对象的当前身份和目标身份；会被目标版本吸收、继续保留或发生冲突的项目纠正；项目事实、Controller、自定义区域、永久流程规则和产品源码如何保持；当前活动任务的 actor 路由、任务最后写入和写后零写入边界；旧项目内导航 Skill 是否满足精确移除条件；以及全部 blocker。如果当前版本跨度不受支持，请停止并给出受支持的最小下一步，不要自行跳过迁移边界。

在我明确确认前不要写入项目。不要修改产品源码，不要执行 Git、push、远程或其他外部操作，也不要升级任何其他项目。
```

检查预览结果后，可以直接回复该 AI 会话：

```text
确认按刚才的预览升级当前项目到 1.16.0。只执行预览中已经声明、绑定完整前后对象身份并获得项目授权的受管对象写入，保留项目事实、Controller、项目纠正、永久流程规则和产品源码；按目标版本要求将当前活动任务卡作为最后一个受管对象更新，并在任务写入后保持零写入。不要执行 Git、push、远程、宿主全局 Skill 安装或其他外部操作。完成后必须在新 pin 下从 .ai-workspace/BOOTSTRAP.md 做一次完整冷恢复，并报告升级后的 pin、纠正比较结果、Controller、任务路由、导航 Skill 状态和任何未完成事项。
```

项目必须在新 pin 下完成一次全新的冷恢复，才能声明已经采用该版本。自然流程验收可以在用户之后选择的任意项目任务中完成；相关证据始终保留在项目本地。

## 维护拓扑

Framework 维护过程中的动态状态属于专用控制仓库。Framework 源仓库只是维护目标，不是第二个控制面权威。维护工作必须从 Maintenance 仓库自身的 `.ai-workspace/BOOTSTRAP.md` 开始；聊天记录、记忆和本仓库都只能作为定位线索。

## 使用环境与兼容性

- 项目需要位于可识别的 Git 仓库中；Framework 不接管项目源码仓库或远程配置。
- 具体运行时由项目所选 Framework 版本的 `TOOLCHAIN.json` 决定。当前快速开始使用的 1.16.0 只接受 `pwsh` / PowerShell 7，正式支持的平台为 Windows；其他已发布版本遵循各自不可变的工具合同。Linux/macOS 尚未被 1.16.0 声明为受支持平台。
- 当前提供明确的 Codex host 合同；其他 AI 宿主可以复用仓内流程，但需要自行提供等价的任务身份、消息真实性和工具权限信号。
- Framework 规则可以约束协作流程，但不能替代产品事实、运行时测试、浏览器/设备证据或人工产品决定。

## 开源许可证

除非文件明确另有声明，本仓库全部内容统一采用 [Apache License 2.0](LICENSE)。该许可证允许个人及商业使用、修改和分发，也允许将 Framework 用于闭源项目；它不会自动改变消费者项目中独立产品源码的许可证。

从 `project-starter` 或 `framework-maintenance-starter` 复制、生成或修改的 Framework 文件仍适用 Apache-2.0。对外分发这些文件时，应随附许可证、保留适用声明，并按照许可证要求标明发生过的重要修改。

## 安全边界

恢复和安全读取不会授予写入权限。源文件写入、测试写入、测试运行、Review、Git、push、设备/浏览器和外部操作仍是相互独立的能力。单一 writer、必要时的独立 Review、受保护路径边界、稳定版本不可变以及独立的 Git/发布门禁仍然是强制要求。

Framework 采用项目本地事实、按需加载和临时授权，不维护消费者注册表、后台监控器、ACK/轮询链或授权消费 ledger。任何未来扩展都不能削弱项目自有版本、单一状态权威和独立动作门禁。
