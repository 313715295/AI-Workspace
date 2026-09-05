# Framework 1.16.0 静态合同摘要

| 关注点 | 1.16.0 合同 |
|---|---|
| 项目采用事实 | `ADOPTION_PROFILE.json` 声明版本侧格式与能力要求；根级工具负责实际投影 |
| 兼容判断 | 不维护旧发行号白名单；未来跨 pin 只按 Project Format/capability 明确声明 |
| 规则包预算 | 项目 policy 选择预算，Framework absolute cap 为 `98304` |
| 升级预检 | target projection 中先验证任务路线、policy、corrections 和预算，PASS 后才允许写入 |
| 角色 | 任务 Owner、`taskActor` 和一次授权的 `grantee` 分离 |
| 规则加载 | DISCOVER 一次返回完整命中区块；连续工作复用，动作与输出边界使用紧凑 receipt |
| 临时输入 | 项目 `.ai-workspace/runtime/<task-or-request>/<actor>/` 优先；成功后按绑定清理 |
| Router 来源 | 根级唯一 canonical Skill；版本只声明兼容合同，不维护第二份正文 |
| Maintenance | sibling 拓扑、overlay 和旧布局迁移只属于根级工具 |
| 流程机器 | 不新增 service、registry、ledger、poller、actor pool 或第二 authority |

本摘要帮助静态审阅，不替代规范 Markdown、schema、Tool Contract、测试或发行 manifest。
