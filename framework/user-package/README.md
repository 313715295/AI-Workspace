# AI Workspace {{DISTRIBUTION_ID}} 用户发行包

这个目录是单版本、可直接解压使用的 Framework 发行包，不是 Framework 开发仓。发行包目录本身不要求是 Git 仓库；准备接入的用户项目必须已经是 Git 仓库，并使用 Windows PowerShell 7。

{{DISTRIBUTION_NOTICE}}

内部 Framework version 和项目 pin 仍为 `{{FRAMEWORK_VERSION}}`。分发标识以包内 [PACKAGE_MANIFEST.json](PACKAGE_MANIFEST.json) 为准，版本资格以版本元数据为准；改 ZIP 名称不会改变它们。snapshot 序号不表示累计增量验证，当前包仍须通过既有完整证据校验。

## 使用与接入

按用户需求或已授权任务注册、升级项目，操作步骤和 Router 安装、宿主发现、兼容性收尾统一见 [项目接入与升级](framework/PROJECT_ADOPTION.md)。目标项目必须是 Git 仓库；发行包目录无需 Git。

版本资格以 [VERSION.json](framework/versions/{{FRAMEWORK_VERSION}}/VERSION.json)、[RELEASE_MANIFEST.json](framework/versions/{{FRAMEWORK_VERSION}}/RELEASE_MANIFEST.json) 和 [版本说明](framework/versions/{{FRAMEWORK_VERSION}}/README.md) 为准。
项目标准由用户选择保存位置，可直接复用已有文档；项目规则支持引用项目内文件或本机绝对文件，多个项目可指向同一份外部标准。提取规则、精炼或改造文档均为可选，不是接入前置条件，也不要求把标准正文抄回 Framework 或初始化入口。
