# {{DISPLAY_NAME}} — 当前状态

> 初始化日期：{{CREATED_DATE}}。本文件只保存current；恢复仍须核对项目Git根、控制面、热任务和真实仓库。

## 1. 初始化状态

- 项目ID：`{{PROJECT_ID}}`
- 项目Git根：相对本控制面`..`
- 控制面布局：`repo-local`
- 固定Framework：`{{FRAMEWORK_VERSION}}`
- Current controller：`controller.json`；`{{CONTROLLER_ID}}` / epoch `1` / `CURRENT`（本行只作locator）
- 初始化结论：`NEEDS_INPUT`
- 尚未验证：产品目标、保护路径、长期owner/资源、Git/push与external权限。

## 2. 当前阶段与路由

- 当前阶段：建立项目基线，不自动启动产品实现。
- 当前任务：无；出现工作后先选profile/phase。合格MICRO可由健康owner同turn无卡闭合，其他任务使用固定`TASK_TEMPLATE.md`。
- 当前主控：见canonical `controller.json`；领域owner：`UNVERIFIED`
- 当前写入者：NONE
- source工作树、HEAD与index：`UNVERIFIED`

## 3. 保护与权限

- 用户/其他owner路径与visibility/read/hash/diff/index/write：`UNVERIFIED`
- 本地Git、commit、push、回退与删除：`UNVERIFIED`，默认关闭。
- 下载、安装、登录、device、上传、发布和其他external：`UNVERIFIED`，默认关闭。

## 4. 唯一下一动作

初始化会话把确认事实写入项目资料、建立tasks热路由并完成Bootstrap/loader链验证；仍缺少会改变产品、责任或权限的信息时向用户一次性请求决定。验证前保持`NEEDS_INPUT`。
