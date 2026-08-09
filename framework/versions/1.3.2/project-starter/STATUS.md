# {{DISPLAY_NAME}} — 当前状态

> 初始化日期：{{CREATED_DATE}}。本文件只保存current；接手时仍须核对真实源码仓、协作目录和当前任务卡。

## 1. 初始化状态

- 项目ID：`{{PROJECT_ID}}`
- 源码仓：`{{REPOSITORY_PATH}}`
- 固定Framework：`{{FRAMEWORK_VERSION}}`
- 初始化结论：`NEEDS_INPUT`
- 尚未验证：产品目标、保护路径、长期owner/资源、Git/push与外部权限是否已全部确认。

## 2. 当前阶段与写入线

- 当前阶段：建立项目基线，不自动启动产品实现。
- 当前任务：无；出现真实工作后先按固定Framework选择档位。合格`MICRO`可由健康owner同turn无卡闭合，其他工作按固定`TASK_TEMPLATE.md`建卡。
- 当前写入者与文件owner：无。
- 源码工作树与index：`UNVERIFIED`

## 3. 保护与权限

- 用户/其他owner路径：`UNVERIFIED`
- 本地Git、commit、push、回退与删除：`UNVERIFIED`，默认关闭。
- 下载、安装、登录、上传、发布和其他外部动作：`UNVERIFIED`，默认关闭。

## 4. 唯一下一动作

由初始化会话把确认事实写入项目资料并完成Bootstrap链验证；仍缺少会改变产品、责任或权限的信息时向用户一次性请求决定。验证完成前保持`NEEDS_INPUT`。
