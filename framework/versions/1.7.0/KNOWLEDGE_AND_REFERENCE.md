# 项目知识引用

本模块只在项目显式启用`KNOWLEDGE_REFERENCE`且loader收到同名capability时加载。它提供项目级参考资料的最小读取合同，不创建知识库、不自动查询、不跨项目聚合，也不把参考资料提升为权威。

## 1. 优先级与证据上限

知识条目永久是`REFERENCE_ONLY / NON_AUTHORITY`。系统与当前用户指令、项目Bootstrap和pin、current任务、项目正式权威与实现actual始终优先。知识条目可以帮助定位、减少重复阅读和提出候选答案，但不能授予写入、Review、Git、external或产品决定权。

知识结果与current权威冲突、identity失效、索引缺失或结构不合法时，返回`REFERENCE_UNAVAILABLE`并继续正式恢复链；不得用历史摘要、缓存或猜测补洞。checker的PASS只证明本次引用结构和被冻结对象仍匹配。

## 2. 唯一启用入口

唯一producer是项目`.ai-workspace/project.json` schema3：

```json
{
  "frameworkCapabilities": {
    "KNOWLEDGE_REFERENCE": {
      "enabled": true,
      "indexLocator": ".ai-workspace/knowledge/index.json"
    }
  }
}
```

缺少`KNOWLEDGE_REFERENCE`或显式`enabled=false`都等价于关闭。启用时必须给出规范化、repo-relative、无glob含义的literal `indexLocator`。未知capability、重复loader selector、无效locator或启用但缺locator均fail closed；关闭时不创建目录、索引或内容。

Bootstrap在严格验证project config后才把已启用capability传给loader。loader只追加本模块一次，不读取索引，也不自动触发查询。

## 3. 索引与查询

项目索引遵循`KNOWLEDGE_SCHEMA.json`。每个条目包含稳定ID、状态、短摘要、引用对象locator/identity、正式authority locator/identity、验证时间、失效条件和token估算。

- `CURRENT`可进入普通查询；`STALE / HISTORICAL`只作审计，不进入普通决策。
- `scripts/check-knowledge-entry.ps1`从项目根直接复证索引、引用对象和authority bytes；任何CURRENT条目失效时整次结果为`REFERENCE_UNAVAILABLE`，不返回混合可信度结果。
- 调用者可选传1～3个精确`EntryId`；checker仍先复证完整索引和全部CURRENT引用/authority，随后只返回已请求且仍为CURRENT的条目，并按ID稳定排序。重复、非法、未知或非CURRENT ID统一返回`REFERENCE_UNAVAILABLE`。
- 未传`EntryId`时保持1.6.0兼容行为：按ID稳定排序返回前三条。显式ID不是自然语言搜索、相关度排名或自动路由；调用者仍须按任务风险读取正式权威或actual。
- 索引内容、fixture测试、人工初始化和自然查询样本是四种不同事实。fixture PASS不计为自然查询证据。

## 4. 缓存与失效

宿主可以缓存load plan，但cache key至少绑定canonical capability集合、project config identity与load manifest identity。知识查询结果禁止缓存（`QUERY_RESULT_CACHE_PROHIBITED`）：每次自然查询或任务复用都重新运行checker，使reference与authority actual identity变化立即返回`REFERENCE_UNAVAILABLE`。不得后台轮询、自动改索引或静默沿用旧结果。

## 5. 项目采用与未来common

Framework 1.7.0逐字继承稳定1.6.1的按需知识引用行为；本次MINOR不扩展知识合同。普通repo-local项目仍可按schema3显式启用；Framework Maintenance schema4首版要求`frameworkCapabilities={}`。物理拓扑迁移在Framework runtime之外，也不携带知识库迁移。项目内容、自然查询样本与common聚合仍由各自任务管理，不因本版本自动创建或改变。

通用知识、跨项目聚合和common晋升不在本版本实现范围。未来只有在至少两个独立项目的自然证据足以证明复用价值时，才另立Framework方案；不得把项目条目直接复制成通用权威。
