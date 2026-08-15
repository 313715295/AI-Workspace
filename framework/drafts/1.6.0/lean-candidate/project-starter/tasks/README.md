# 任务热索引

本文件只保存active任务路由，不复制任务正文或历史。每条current入口至少列出task ID、路径、owner、profile、lifecycle/phase和唯一下一actor，使Bootstrap能在完整加载模块前确定loader输入。

current controller只从`../controller.json`读取。本索引不复制controller ID/epoch；主控按需pull current任务，routine终态不形成ACK链或逐条上报。

## Active

| Task | Path | Owner | Profile | Phase | Next actor |
|---|---|---|---|---|---|

## Archive

历史inventory只记录数量或稳定locator；逐任务历史从Git或`tasks/archive/`读取，不进入首次恢复热上下文。
