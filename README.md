# AI Workspace Framework

AI Workspace Framework 为用户与 AI 共同参与的长期软件项目提供一套可复制、可恢复、可审查、可持续演进的协作机制。

它把容易散落在聊天记录里的项目事实、任务责任、授权边界、审查要求和交接关系放回项目仓库。新的 AI 会话可以从仓内入口恢复当前状态，而不是依赖旧聊天或模型记忆猜测项目事实。

## 它解决什么问题

- 跨会话继续工作：从项目自己的 `BOOTSTRAP.md`、任务卡和真实仓库恢复上下文。
- 明确责任：区分项目 Controller、领域 Owner、任务 Owner、临时执行者和独立 Reviewer。
- 控制权限：写入、测试、Review、Git、推送、设备和外部操作分别授权，不能相互推导。
- 防止漂移：用项目根、Git 根、路径、对象身份和受保护边界校验实际工作区。
- 降低协作开销：同一健康会话可以连续规划、实施和测试；只有真实独立性、并行或隔离需要新会话。
- 支持项目进化：项目可以保存尚未被 Framework 吸收的纠正和永久规则，并在升级时确定哪些继续生效。

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

## 角色和交接

- `PROJECT_CONTROLLER`：维护项目级控制面，处理跨域、保护边界、项目阶段、Git、设备和外部操作等上升事项。
- `DOMAIN_OWNER`：长期负责一个领域，默认直接安排本领域任务、执行者和 Reviewer，并接收结果。
- 任务 Owner：对一张任务卡及其结果负责，不因临时执行者变化而自动改变。
- `taskActor`：当前实际推进任务的会话或主体。
- `grantee`：一次授权包中获得某个明确动作权限的主体。
- 临时执行者、Reviewer 和资源档位：按任务或阶段临时承担，不成为新的长期管理角色，也不会自动获得其他权限。

Owner 可以自己规划、实施和测试，也可以为了并行、成本、上下文隔离或继续讨论其他事项而安排临时执行会话。CRITICAL 独立 Review 仍必须与候选 writer、任务 Owner/issuer 和实质方案贡献者保持必要独立性。

正常 Review 是一次完整委派和一次可用终态返回。Reviewer 不负责反向申请任务卡写权限、维护三份重复状态或在结果送达后再确认“释放”；Owner 在唯一任务卡中收口任务事实，并单独决定是否 `OWNER_ACCEPT`。

## 项目事实和版本归属

“项目事实”是能够从项目真实仓库复证的信息，例如项目身份与边界、当前任务和决定、Controller、Framework pin、产品源码、测试、Git 和运行结果。聊天记录与模型总结只作定位，不是执行 authority。

Framework 不存在全局默认版本，也不存在全局 `CURRENT`：

- 每个项目通过自己的 `.ai-workspace/project.json.frameworkVersion` 选择版本；
- Framework 发布不会自动升级、发现或记录消费者项目；
- 项目升级是该项目自己的受治理动作；
- 项目可以继续停留在原版本；
- 已封存版本不可原地修改，根级接入和发布工具可以在不改变项目 pin 的情况下独立修复。

版本只有在 `VERSION.json` 和 `RELEASE_MANIFEST.json` 同时证明 `STABLE`、可采用、完整测试和独立 Source Review 后，才能用于普通注册或升级。

## 用 AI 会话开始使用

不需要用户手动运行脚本。把下面提示词交给目标项目中的 AI 会话，并替换实际路径和项目名称即可。

### 新项目接入

```text
请将当前 Git 项目接入 AI Workspace Framework，并采用稳定版本 1.16.0。

Framework 仓库：C:\path\to\AI-Workspace
项目 ID：my-project
显示名称：My Project

请先只读检查当前 cwd、项目 Git 根、Framework Git 根、目标版本是否稳定且可采用、平台与工具后端是否受支持，以及本会话真实 task/thread ID。随后按 Framework 的项目接入流程生成确定性预览，说明完整受管写集、项目 pin、初始 Controller、对既有项目内容的保留边界和全部 blocker。在我确认预览前不要写入，不要修改产品源码，不要执行 Git、推送或外部操作。
```

确认预览后回复：

```text
确认按刚才的预览接入。只执行预览中已经声明的受管对象写入；完成后从新建的 .ai-workspace/BOOTSTRAP.md 做一次完整冷恢复，并报告实际 pin、Controller、任务入口和未完成事项。不要修改产品源码，不要执行 Git、推送或外部操作。
```

### 现有项目升级

```text
请从当前项目的 .ai-workspace/BOOTSTRAP.md 完整恢复，然后只读评估升级到稳定 Framework 1.16.0。

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
  RELATIONSHIPS.md
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
