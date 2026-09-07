# AI Workspace Framework

AI Workspace Framework 面向用户与 AI 共同参与的长期软件项目，围绕交付质量、多会话协作和总交付成本，提供可恢复、可审查、可持续演进的工作机制。

它把项目事实、任务责任、规则来源和交付证据保存在项目中，让后续会话有据接续工作，也让用户能核对当前进度、结果和剩余事项。

## 它解决什么问题

- 跨会话继续工作：从项目入口、当前任务和真实仓库恢复事实与下一动作，减少反复说明背景和重新摸索。
- 组织多会话协作：明确项目 Controller、领域 Owner 和每项任务的结果责任，按需要安排执行者与独立 Reviewer，保持清晰的交接与结果归属。
- 支持交付质量把关：围绕任务目标与验收要求组织验证、必要的独立审查和结果接受，区分已验证结果、未完成事项及证据限制。
- 控制执行边界：校验项目根、路径、对象身份和保护范围，分别管理写入、测试、Git、推送及外部操作的授权。
- 降低沟通与协作开销：健康会话连续规划、实施和测试，按需加载规则并复用有效上下文；结果直接返回负责的 Owner，减少重复状态、恢复和非必要交接。
- 按任务动态分配资源：满足质量与独立性要求，先选足够的模型，再选其支持且足够的推理强度；按需要复核调整，兼顾完整交付成本，并提供可选评估工具支持针对性比较。
- 复用已有资料与标准：保留项目原有文档，通过明确入口引用项目内外标准；多个项目可以共享使用者维护的标准来源，按需使用可选知识管理能力。
- 支持项目持续演进：各项目独立选择 Framework 版本，保留项目纠正和永久规则，并在升级时核对哪些继续生效。

Framework 不是产品运行时、业务代码框架或中心化项目管理平台。它管理的是“用户与 AI 如何协作完成项目工作”，不替代产品源码、测试结果、设备证据或用户决定。

## 实际工作方式

```text
进入项目
  ↓
从 .ai-workspace/BOOTSTRAP.md 恢复项目、任务和权限边界
  ↓
根据当前任务、角色、阶段、动作和范围选择适用规则
  ↓
加载命中的完整规则区块，连续工作期间复用
  ↓
受治理动作前检查授权和准备，正式交付前检查结果
  ↓
必要时独立 Review；Git、推送和外部操作继续单独授权
```

运行时组合三类彼此独立的规则来源：

1. 项目所选 Framework 版本中的通用规则；
2. 该版本尚未吸收的项目纠正；
3. 项目自己的永久流程规则。

规则正文仍由原始 Markdown 或项目真实来源持有。选择器只负责找到当前需要的规则，不复制第二份正文。自然任务、上下文或 authority 边界发生变化时重新选择；连续工作复用既有完整规则；动作和交付边界只前置紧凑义务；绑定不确定或来源漂移时重新读取。

## 接入已有项目资料和标准

初始化不会要求用户重写一套项目文档，也不会把所有说明都变成流程规则。`PROJECT.md` 和 `REVIEW_PROFILE.md` 只保存必要事实与已有资料入口；`RELATIONSHIPS.md` 仅在项目确有稳定关系图时按需建立。产品说明、架构文档、质量手册和历史资料继续由使用者在自己选择的位置维护。

标准来源有两种定位方式：

- 项目内文件：相对项目 Git 根绑定，旧 `locator` 记录继续按这种方式解释；
- 项目外文件：使用 `locatorKind=ABSOLUTE_FILE` 绑定当前受支持宿主上的显式本机绝对路径，例如另一个标准仓库的 checkout。

Framework 不规定标准目录或仓库结构。多个项目分别引用同一来源文件，就自然共享同一标准；不需要把正文迁入 Framework、复制到每个项目、建立全局注册表或运行同步服务。每个项目仍可用自己的依赖文档补充项目特例。

用户不需要编辑机器 JSON。告诉初始化 AI 文档路径、用途、读取全文还是标记章节，以及直接依赖即可。例如：

```text
请把 C:\standards\team-quality.md 中
<!-- QUALITY:BEGIN --> 到 <!-- QUALITY:END -->
作为本项目质量规则，并把项目内 docs/exceptions.md 作为直接依赖。
先只读核对路径、章节和文件 identity，再按当前项目授权更新现有
.ai-workspace/process-policy.json；不要复制或修改来源文件。
```

AI 应先区分普通资料与规范性要求：普通资料只登记为导航入口，普通 Markdown 链接不会自动递归加载；规范性要求才进入 process-policy 的显式 source binding。来源读取权限不包含来源写权限，来源的路径、whole-file identity、章节或依赖变化会让旧 receipt 失效。

项目可以独立选择三种处理方式：

1. 直接引用原文：默认且完整可用，不要求先整理资料。
2. 可选精炼：提取规则、条件、例外和来源，但摘要默认只作导航或参考。
3. 可选文档改造：按项目需要拆分章节、分离规范与说明或消除重复，再重新绑定。

后两项不是采用 Framework 的前置条件。只有项目明确决定让精炼稿替换规范正文时，才按现有项目规则修改与验证边界切换，并保持单一有效正文；Framework 不提供自动提炼器、全量文档改写、自动搬迁或额外强制审核链。

## 角色和交接

- `PROJECT_CONTROLLER`：维护项目级控制面，处理跨域、保护边界、项目阶段、Git、设备和外部操作等上升事项。
- `DOMAIN_OWNER`：长期负责一个领域，默认直接安排本领域任务、执行者和 Reviewer，并接收结果。
- 任务 Owner：承担单项任务的结果责任，可由项目 Controller 或领域 Owner 担任，不是额外管理层；临时执行者变化不会自动转移这份责任。
- `taskActor`：当前实际推进任务的会话或主体。
- `grantee`：一次授权包中获得某个明确动作权限的主体。
- 临时执行者和 Reviewer：按任务需要参与执行或独立审查，不成为新的长期管理角色，也不会自动获得其他权限。模型与推理强度是资源配置，不属于角色层级。

Owner 可以在健康会话中连续规划、实施和测试，也可以在质量、独立性、并行、隔离与总交付成本需要时安排临时执行者；执行者直接向负责的 Owner 返回可用终态。CRITICAL 独立 Review 仍必须与候选 writer、任务 Owner/issuer 和实质方案贡献者保持必要独立性。

正常 Review 是一次完整委派和一次可用终态返回。Reviewer 不负责反向申请任务卡写权限、维护三份重复状态或在结果送达后再确认“释放”；Owner 在唯一任务卡中收口任务事实，并单独决定是否 `OWNER_ACCEPT`。

资源按当前任务选择：满足质量、风险、独立性和隔离要求，比较执行、工具、等待、交接、验证、审查与返工的总交付成本；先选足够的模型，再选该模型支持且足够的推理强度。任务风险/profile、抽象 route、model 和 effort 不固定一一对应，CRITICAL 不自动要求更高档位。健康配置可复用，必要调整在自然工作边界进行并核实宿主实际接受结果；这是选择与复核规则，不是自动算出唯一参数的调度器，也不承诺固定节省比例。

## 项目事实和版本归属

“项目事实”是能够从项目真实仓库复证的信息，例如项目身份与边界、当前任务和决定、Controller、Framework pin、产品源码、测试、Git 和运行结果。聊天记录与模型总结只作定位，不是执行 authority。

Framework 不存在全局默认版本，也不存在全局 `CURRENT`：

- 每个项目通过自己的 `.ai-workspace/project.json.frameworkVersion` 选择版本；
- Framework 发布不会自动升级、发现或记录消费者项目；
- 项目升级是该项目自己的受治理动作；
- 项目可以继续停留在原版本；
- 已封存版本不可原地修改，根级接入和发布工具可以在不改变项目 pin 的情况下独立修复。

版本只有在 `VERSION.json` 和 `RELEASE_MANIFEST.json` 同时证明 `STABLE`、可采用、完整测试和独立 Source Review 后，才能用于普通注册或升级。

仓库说明的是流程能力，不替代当前 checkout 的发行事实。每次使用前都以目标版本的 `VERSION.json`、`LOAD_MANIFEST.json`、`RELEASE_MANIFEST.json` 与 `ADOPTION_PROFILE.json` 为准；若它们仍声明 `CANDIDATE`，下面的“稳定 1.16.0”提示词只是发布后的使用示例，不能据此把当前字节当作已发布版本。`sourceCompatibility` 未声明当前项目的 Project Format/capability 时，不支持跨 pin direct upgrade；不得仅因版本目录存在或示例写了版本号就推断兼容。

## 用 AI 会话开始使用

新用户下载并解压单版本用户包后，从包内 README/AGENTS 开始；包内 README 链接注册工具与版本元数据，生成项目入口后转到项目自己的 `.ai-workspace/BOOTSTRAP.md`。开发仓的注册/升级说明统一见 [项目接入与升级](framework/PROJECT_ADOPTION.md)。

对外分发名称为 `1.16.0-snapshot.N` 或 `1.16.0-release`，内部版本与项目 pin 仍为 `1.16.0`。snapshot 仍受 CANDIDATE 试点限制；分发名称不表示已实现累计增量验证或固定安装位置绑定。构建参数、序号和资格以 [分发命名与用户包](framework/FRAMEWORK_RELEASE.md#分发命名与用户包) 为准。

不需要用户手动运行脚本。把下面提示词交给目标项目中的 AI 会话，并替换实际路径和项目名称即可。

### 新项目接入

```text
请将当前 Git 项目接入 AI Workspace Framework，并采用稳定版本 1.16.0。

Framework 发行包或仓库：C:\path\to\AI-Workspace
项目 ID：my-project
显示名称：My Project

请先只读检查当前 cwd、项目 Git 根、Framework 发行内容定位、目标版本是否稳定且可采用、平台与工具后端是否受支持，以及本会话真实 task/thread ID。发行包本身不要求有 Git。随后按 Framework 的项目接入流程生成确定性预览，说明完整受管写集、项目 pin、初始 Controller、对既有项目内容的保留边界和全部 blocker。在我确认预览前不要写入，不要修改产品源码，不要执行 Git、推送或外部操作。
```

确认预览后回复：

```text
确认按刚才的预览接入。只执行预览中已经声明的受管对象写入；完成后从新建的 .ai-workspace/BOOTSTRAP.md 做一次完整冷恢复，并报告实际 pin、Controller、任务入口和未完成事项。不要修改产品源码，不要执行 Git、推送或外部操作。
```

### 现有项目兼容升级

```text
请从当前项目的 .ai-workspace/BOOTSTRAP.md 完整恢复，然后只读评估是否能兼容升级到已发布的稳定 Framework 1.16.0。若目标 ADOPTION_PROFILE 未明确声明当前 Project Format/capability，请停止并报告不支持跨 pin direct upgrade。

Framework 仓库：C:\path\to\AI-Workspace

请先报告目标版本是否可采用、当前 Project Format 与目标能力是否兼容、完整差异写集、项目纠正的吸收/保留/冲突结果、永久规则和用户扩展如何保留、失败如何恢复，以及全部 blocker。在我确认前不要写入，不要修改产品源码，不要执行 Git、推送或外部操作。
```

确认预览后回复：

```text
确认按刚才的预览升级当前项目。只执行已声明并绑定前后对象身份的受管写入；失败时恢复旧 pin、旧受管状态和旧有效规则。完成后必须在新 pin 下重新从 .ai-workspace/BOOTSTRAP.md 冷恢复。不要修改产品源码，不要执行 Git、推送或外部操作。
```

接入或升级完成后，新的 AI 会话通常只需要：

```text
请从当前项目的 .ai-workspace/BOOTSTRAP.md 开始，按入口恢复当前项目、任务、角色和权限边界。在恢复完成前保持只读，不要从聊天历史猜测 authority，也不要自行执行 Git 或外部操作。
```

## 仓库和项目结构

```text
AI-Workspace/
  README.md
  LICENSE
  framework/
    ROADMAP.md
    FRAMEWORK_RELEASE.md
    PROJECT_ADOPTION.md
    maintenance-overlay/
    versions/
      <version>/
  scripts/
  skills/ai-workspace-router/
```

Framework 仓库只保存通用规则、发行载荷、根级接入/发布工具和 Router Skill。消费者项目的动态状态始终保存在消费者自己的 `.ai-workspace/**` 中。

项目接入后通常包含：

```text
AGENTS.md
.ai-workspace/
  BOOTSTRAP.md
  project.json
  controller.json
  PROJECT.md
  RELATIONSHIPS.md     # 可选：仅在项目确有稳定关系图时创建
  REVIEW_PROFILE.md
  STATUS.md
  corrections.json
  process-policy.json
  tasks/
  runtime/            # 临时过程产物；由项目根 .gitignore 排除
```

Framework 根部的 `skills/ai-workspace-router/SKILL.md` 是宿主安装或发现的规范副本。它只负责在自然边界导航当前项目所选版本的恢复和规则解析，不成为新的规则 authority，也不在每次工具调用时重载。Skill 不可用时，项目仍可从自己的 `BOOTSTRAP.md` 安全回退。

## 兼容性和证据边界

- 项目必须位于可识别的 Git 仓库中；Framework 不接管项目源码仓库或远程配置。
- 具体平台与后端由所选版本的 `TOOLCHAIN.json` 声明。1.16.0 的官方实现是 Windows 上的 PowerShell 7；其他平台不能凭推断冒称已支持。
- 当前提供明确的 Codex host 合同；其他 AI 宿主需要提供等价的任务身份、消息真实性和工具权限信号。
- 机械 PASS 只能证明可观察的结构、身份和范围，不证明模型理解、语义正确或产品结果正确。

## 许可证与安全边界

本仓库采用 [Apache License 2.0](LICENSE)。它允许个人和商业使用、修改与分发，也允许把 Framework 用于闭源项目；不会自动改变消费者项目产品源码的许可证。

恢复和安全读取不授予写权限。写入、测试、Review、`OWNER_ACCEPT`、Git、推送、设备、浏览器和外部操作保持独立门禁。Framework 不维护消费者注册表、后台监控器、ACK/轮询链、授权消费 ledger 或第二套状态真相。

当前候选范围和未来准入条件见 [`framework/ROADMAP.md`](framework/ROADMAP.md)；某个版本的准确能力与变化见其 `README.md`、`CHANGELOG.md`、`VERSION.json` 和 `RELEASE_MANIFEST.json`。
