# AI Workspace {{FRAMEWORK_VERSION}} 用户发行包

这个目录是单版本、可直接解压使用的 Framework 发行包，不是 Framework 开发仓。发行包目录本身不要求是 Git 仓库；准备接入的用户项目必须已经是 Git 仓库，并使用 Windows PowerShell 7。

## 给用户与项目 AI

- 已有 `.ai-workspace/BOOTSTRAP.md` 的治理项目先从该入口恢复当前 pin、任务和权限；需要升级时，再按 [`scripts/upgrade-project.ps1`](scripts/upgrade-project.ps1) 的预览结果以及当前版本的 [迁移矩阵](framework/versions/{{FRAMEWORK_VERSION}}/MIGRATION_MATRIX.md) 处理。
- 首次注册的 Git 项目还没有 Bootstrap。先阅读本页和下列版本元数据，再用 [`scripts/register-project.ps1`](scripts/register-project.ps1) 做不带 `-Apply` 的预览；在用户已有授权范围内确认并应用注册。入口生成后，后续工作再从项目自己的 `.ai-workspace/BOOTSTRAP.md` 恢复。缺少尚未生成的 Bootstrap 本身不阻塞首次注册。
- 版本生命周期、普通采用资格和升级支持范围以 [`VERSION.json`](framework/versions/{{FRAMEWORK_VERSION}}/VERSION.json)、[`RELEASE_MANIFEST.json`](framework/versions/{{FRAMEWORK_VERSION}}/RELEASE_MANIFEST.json) 与 [版本说明](framework/versions/{{FRAMEWORK_VERSION}}/README.md) 为准。候选版本若声明不可消费，就不能作为普通项目采用包；迁移矩阵未声明的跨 pin 路径也不能假定受支持。
- 用户标准可以由项目规则显式引用项目内文件或受支持宿主上的本机绝对文件；多个项目可以指向同一份外部标准。复用既有文档、整理历史资料或改造旧文档结构都是可选工作，不要求把这些内容复制进初始化文件。

可以把下面这段交给项目 AI，并替换占位符：

```text
发行包绝对路径：<解压后的发行包绝对路径>
项目绝对路径：<用户项目绝对路径>
项目 ID：<项目ID>
若项目已有 .ai-workspace/BOOTSTRAP.md，先从它恢复；否则按发行包 README 和当前版本元数据检查资格，先运行 register-project.ps1 预览，只在我的既有授权范围内应用注册，生成后再读取项目 Bootstrap。
```

解压目录只提供发行内容和接入工具，不授予项目写入或其他权限。已有治理项目继续遵循其 Bootstrap、当前任务和独立授权；首次注册则以用户本次明确授权为边界。
