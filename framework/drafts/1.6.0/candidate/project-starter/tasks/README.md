# 任务热索引

本文件只保存active任务路由，不复制任务正文、controller identity/epoch或历史。current controller唯一locator=`../controller.json`。每条current入口至少列出task ID、路径、owner、profile、lifecycle/phase、report target和唯一下一actor，使Bootstrap能在完整加载模块前确定loader输入并供主控按需pull。

## Active

| Task | Path | Owner | Profile | Phase | Report to | Next actor |
|---|---|---|---|---|---|---|

## Archive

仅terminal任务进入`tasks/archive/`。历史inventory只记录数量或稳定locator；逐任务历史从Git或archive读取，不进入首次恢复热上下文。已完成独立任务复用前重新核对project/domain/role/candidate lineage/owner/lifecycle/resource/path conflicts。
