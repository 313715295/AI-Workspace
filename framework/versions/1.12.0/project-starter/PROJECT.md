# {{DISPLAY_NAME}} — 稳定项目资料

这里只记录跨阶段稳定的项目身份、边界和权威地图。current进入`STATUS.md`和热任务卡，过程历史进入Git或只读carrier。

## 1. 项目身份

- 项目ID：`{{PROJECT_ID}}`
- 项目Git根：`.ai-workspace/project.json.repositoryRoot = ..`
- 控制面布局：`repo-local`；本目录随项目Git跟踪
- 固定Framework：`{{FRAMEWORK_VERSION}}`
- 产品目标：`UNVERIFIED`
- 目标用户与平台：`UNVERIFIED`

## 2. 稳定产品与架构边界

- 产品原则与明确非目标：`UNVERIFIED`
- 主要运行环境、技术栈与分层：`UNVERIFIED`
- 状态、数据、生命周期与公共接口owner：`UNVERIFIED`
- 日常默认排除路径：read `.ai-workspace/project.json`；用户独占或任务禁止的额外路径：`UNVERIFIED`

## 3. 项目权威入口

- 产品/设计权威：`UNVERIFIED`
- 架构、规则、接口与数据权威：`UNVERIFIED`
- 测试、构建、运行与发布权威：`UNVERIFIED`

机制细节服从对应current权威和已验证实现；聊天、模板、报告和历史摘要只作定位。无法消解的公共或跨域冲突交项目主控。

## 4. 验证入口

- 静态与文档检查：`UNVERIFIED`
- 单元/集成/场景测试：`UNVERIFIED`
- 构建、运行、视觉、性能或设备门：`UNVERIFIED`

## 5. Git、external与资源

- 本地Git、commit与push权限：`UNVERIFIED`
- 下载、安装、登录、上传、发布等external权限：`UNVERIFIED`
- 长期领域、owner与实际资源映射：`UNVERIFIED`
- 质量资源映射：owner/重大判断、聚焦高质量分析/Review、常规实现、纯机械工作的项目对应：`UNVERIFIED`
- `MICRO / STANDARD / CRITICAL`项目特有加严：`UNVERIFIED`；不加严时采用固定Framework

未确认权限不得从建议、工具可用性或前一步动作推定。资源下调必须以自然样本证明质量和返工不恶化。

## 6. Project corrections

- 独立项目权威对象：`.ai-workspace/corrections.json`。
- 任务可以发现或更新correction，但任务生命周期和聊天历史不控制其保留。
- 运行时有效规则由显式Framework pin与released coverage机械求差得到，不在本文件复制第二份状态。
