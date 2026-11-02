# AI Workspace {{DISTRIBUTION_ID}} 用户发行包

这个目录是单版本、可直接解压使用的 Framework 发行包，不是 Framework 开发仓。发行包目录本身不要求是 Git 仓库；随包工具当前支持 Windows 上的 PowerShell 7。

{{DISTRIBUTION_NOTICE}}

内部 Framework version 和项目 pin 仍为 `{{FRAMEWORK_VERSION}}`。分发标识以包内 [PACKAGE_MANIFEST.json](PACKAGE_MANIFEST.json) 为准，版本资格以版本元数据为准；改 ZIP 名称不会改变它们。snapshot 序号不表示累计增量验证，当前包仍须通过既有完整证据校验。

## 使用与接入

新项目通常从自己的项目目录启动 AI 会话，提供本运行包目录并明确采用意图。稳定注册保持默认；本包实际支持首次候选注册且资格完整时，AI 按 PROJECT_ADOPTION 的 LocalCandidatePilot 路线处理，并准备首张真实有限接入任务。仅有 snapshot 名称、目录或模板不能证明资格。

按用户需求或已授权任务注册、升级项目，操作步骤、目标 Bootstrap 导航及旧来源入口的切换收尾统一见 [项目接入与升级](framework/PROJECT_ADOPTION.md)。2.0普通项目无需 Git；维护双仓拓扑、真实 Git 动作及旧版本要求按所选版本合同验证。发行包目录无需 Git。

版本资格以 [VERSION.json](framework/versions/{{FRAMEWORK_VERSION}}/VERSION.json)、[RELEASE_MANIFEST.json](framework/versions/{{FRAMEWORK_VERSION}}/RELEASE_MANIFEST.json) 和 [版本说明](framework/versions/{{FRAMEWORK_VERSION}}/README.md) 为准。
项目标准由用户选择保存位置，可直接复用已有文档；项目规则支持引用项目内文件或本机绝对文件，多个项目可指向同一份外部标准。提取规则、精炼或改造文档均为可选，不是接入前置条件，也不要求把标准正文抄回 Framework 或初始化入口。
