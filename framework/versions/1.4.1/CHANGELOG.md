# v1.4.1 变更说明

## 版本性质

Framework 1.4.1是1.4.0发布后的STABLE patch，完成内容批准、完整测试和发行owner收口后由`framework/CURRENT`启用。1.4.0及更早稳定目录保持字节不变。版本继续按`DRAFT / REVIEW / STABLE / RETIRED`管理；版本进入STABLE即不可原位修改，后续修正继续发布新的patch版本。

`AI-Workspace`仍是唯一Framework开发与发行仓。默认分支的`framework/versions/`保留全部稳定版本；tag只作可选审计或下载标记，不参与注册、恢复或升级解析。

## repo-local项目控制面

- 新项目控制面固定在项目Git根`.ai-workspace/`并随项目Git跟踪；布局为`repo-local`。
- `project.json`升级为schema2，记录`controlPlaneLayout=repo-local`、`repositoryRoot=..`和固定Framework版本。
- starter增加作用域`.gitattributes`，只约束控制面文本LF，不改变产品仓其他文件。
- Bootstrap使用唯一受管区和项目自定义区，从已挂载AI-Workspace唯一定位固定版本；不含本机绝对Framework路径。
- 发现时完整repo-local优先，只有其完全不存在才允许中央legacy fallback；partial、reparse、未知live bytes或身份冲突fail closed。

## root入口职责

- `register-project.ps1`只注册全新Git项目，默认WhatIf。它要求Git顶层、干净工作树、无同ID中央legacy和完全不存在的目标；Apply在同仓staging完整生成/验证后rename，不操作Git。重复同身份返回`ALREADY_REGISTERED`。
- `upgrade-project.ps1`只做同拓扑升级。中央1.3.x可作为升级源进入仍受支持的较新中央版本；repo-local只替换Bootstrap受管区并逐字保留自定义后缀。中央→repo-local、受管区自定义和缺失固定旧版本都拒绝。
- 退役根`scripts/check-task-card.ps1`与空`projects/.gitkeep`包装。1.3.0目录保留历史字节和向上升级源模板，但不再作为运行或升级目标；新克隆无需携带空`projects/`目录。

## 一次性项目搬迁不进入Framework

- Framework 1.4.1不提供中央→repo-local通用搬迁命令、跨仓事务引擎或相应故障矩阵。
- 已有中央项目的搬迁由项目owner另建一次性任务完成；项目仓提交和repo-local冷恢复成功前，中央副本保持唯一权威，中央删除另行授权。

## 兼容性

- 1.3.2中央布局仍可发现并在原拓扑升级。
- 1.3.1任务卡、1.3.0机械摘要和可选宿主actor/notifier字段仍可由较新版本内checker解析；这不恢复已退役的1.3.0根checker。
- `CURRENT_REACHABLE / CONTRACT_REACHABLE / FUTURE_ONLY / UNVERIFIED`、三档任务、两级恢复、范围保护、独立审核和外部权限分离继续有效。
- 本版本发行不等于任何现有项目自动升级或搬迁，也不授权项目Git提交、中央删除、tag、push或其他外部动作；现有项目继续读取自己的固定pin。
