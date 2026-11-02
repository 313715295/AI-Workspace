# 任务热索引

本文件只保存active任务路由，不复制任务正文或历史。每条current入口至少列出task ID、路径、owner、profile、role、lifecycle/phase和唯一下一actor，帮助Bootstrap定位任务。`Work route`的权威仍是任务卡；索引冲突时按过期投影处理，不能覆盖任务卡。

## Active

| Task | Path | Owner | Profile | Role | Phase | Next actor |
|---|---|---|---|---|---|---|

## Archive

历史inventory只记录数量或稳定locator；逐任务历史从Git或`tasks/archive/`读取，不进入首次恢复热上下文。

没有 active task 时保持空表。首次候选接入依据真实采用目标准备有限首卡，由 REGISTER 事务写入并定位；不能创建无目标或无限期 Root 占位任务。之后任务和索引按正常当前授权维护。
