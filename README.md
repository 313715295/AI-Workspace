# AI Workspace Framework

AI Workspace Framework 是一套面向 AI 辅助项目、可版本化并可复制采用的流程契约。本仓库保存通用 Framework 源文件、不可变发行版本、起始模板、校验器及发行工具，不保存任何实际消费者项目的动态状态。

## Framework 的作用

AI Workspace Framework 为人员与 AI 共同参与的软件项目提供一套可复制、可恢复、可审查的协作机制，重点解决以下问题：

- 使用仓库内的项目事实、Controller、任务卡和 Bootstrap 恢复工作，使新任务不必依赖旧聊天记录才能继续。
- 明确 Controller、Owner、Executor、Reviewer 等角色的责任，并约束长期 owner 与 Controller 的轮换和交接。
- 将规划、实施、验证、独立 Review、Git、发布及外部操作拆分为独立门禁，避免一次授权被扩展成全部权限。
- 通过受保护路径、完整对象身份、单一 writer 和范围明确的授权包，阻止越权修改、并发覆盖及工作区漂移。
- 规范任务复用与新建、跨任务终态报告、范围门禁和安全异常路由，减少重复汇报、ACK 链和轮询。
- 通过版本化的 `project-starter`、注册工具和升级工具，让项目复制同一套流程，同时继续拥有自己的事实、任务、Controller 和 Framework pin。

它不是产品运行时、业务代码框架或中心化项目管理平台，而是约束人员与 AI 如何安全、连续地协作完成项目工作的流程基础设施。

## 版本权威

Framework 不存在全局默认版本，也不存在全局 `CURRENT` 版本。

- 每个现有项目都通过自己的 `.ai-workspace/project.json.frameworkVersion` 选择并持有 Framework 版本。
- 每次新项目注册都必须明确指定一个准确的稳定 Framework 版本。
- Framework 发行不会自动升级项目、发现消费者或记录消费者身份。
- 项目升级是由该项目自行拥有的独立任务，必须在项目自己的真实控制面和 Git 边界内执行。

只有同时满足以下条件的版本才可供项目采用：其 `VERSION.json` 声明 `STABLE`、`consumable=true`、`projectPinEligible=true`，并且 `RELEASE_MANIFEST.json` 完整、通过规范化校验且已获得独立 Review 批准。

## 仓库结构

```text
framework/
  ROADMAP.md
  versions/
    <version>/
      VERSION.json
      RELEASE_MANIFEST.json
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
- `PROJECT_CONTROL.md`：规定 Controller、Domain Owner、项目纠正和控制面对象的关系。
- `TASK_AND_SCOPE.md`：规定任务范围、复用、新建和临时角色路由。
- `AUTHORIZATION_MODEL.md`：规定写入、测试、Review、Git 和外部操作的独立授权边界。
- `REVIEW_AND_EVIDENCE.md`：规定独立审查、证据范围和验收要求。

这些文件只定义规则。项目的真实动态状态始终保存在该项目自己的 `.ai-workspace/**` 中，包括 `project.json`、`controller.json`、任务卡、`STATUS.md` 和 `corrections.json`。

`framework/versions/<version>/` 下已经发行的目录不可修改。新版本直接在其最终版本目录中开发，但在候选内容冻结、完成独立 Review 并正式封存前，不可供项目采用。无需另外维护一份平行的 draft 副本。

Framework 1.10.0 增加最小的跨版本项目纠正规则闭环：项目用自己的 `.ai-workspace/corrections.json` 保存为什么需要某条修正规则，Framework 1.10.0 的不可变版本 payload 用 `CORRECTION_COVERAGE.json` 声明各已发行版本完整吸收了哪些 correction ID。注册和升级只对调用方明确提供的项目做机械比较，展示已吸收、仍需生效和冲突项；不会删除记录、保存消费者身份或自动升级项目。

## 新项目初始化

注册流程复制所选版本中现有的 `project-starter`，不会另外创建第二套流程模型。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/register-project.ps1 \
  -RepositoryPath <git-root> \
  -ProjectId <id> \
  -DisplayName <name> \
  -FrameworkVersion 1.10.0 \
  -ControllerId <host-task-id>
```

默认只执行预览。只有在取得项目写入授权后才能添加 `-Apply`。未提供 `FrameworkVersion`、版本未知、发行清单不完整或版本并非稳定版时，脚本会在写入项目之前失败。

## 现有项目升级

`scripts/upgrade-project.ps1` 接收调用方明确提供的项目根目录和 `ToVersion`。它会校验源控制面、目标发行版本及可恢复的事务边界，保留项目自有的身份、Controller、常规排除项、能力配置和 Bootstrap 自定义区域，并且只修改声明过的受管对象。它不会搜索消费者，也不会修改其他项目。

项目必须在新 pin 下完成一次全新的冷恢复，才能声明已经采用该版本。自然流程验收可以在用户之后选择的任意项目任务中完成；相关证据始终保留在项目本地。

## 维护拓扑

Framework 维护过程中的动态状态属于专用控制仓库。Framework 源仓库只是维护目标，不是第二个控制面权威。维护工作必须从 Maintenance 仓库自身的 `.ai-workspace/BOOTSTRAP.md` 开始；聊天记录、记忆和本仓库都只能作为定位线索。

## 安全边界

恢复和安全读取不会授予写入权限。源文件写入、测试写入、测试运行、Review、Git、push、设备/浏览器和外部操作仍是相互独立的能力。单一 writer、必要时的独立 Review、受保护路径边界、稳定版本不可变以及独立的 Git/发布门禁仍然是强制要求。

Framework 1.10.0 在增加一个项目 correction 对象和一个通用版本覆盖映射的同时，没有引入可变任务字段 manifest、授权消费 ledger、消费者注册表、后台监控器、重试服务或跨仓库事务。
