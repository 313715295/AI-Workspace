# Framework 1.16.0 examples

## New project

`1.16.0` stable 后，显式 registration 复制 exact starter。项目获得自己的 pin、Controller、corrections、空 process-policy 与 root `.gitignore` runtime rule；Framework 不保存 consumer record。

## Existing project

1.14.1/1.15.x project 预览 `ToVersion=1.16.0`。工具在隔离 projection 中先写 target policy/budget 与 migrated task route，运行 target resolver PASS 后才准备可恢复 transaction。non-task object 先写，task 最后写，之后零写入。

## Task actor 与 independent Reviewer

current card 可声明 `Work route: actor=task-123; role=EXECUTOR; phase=VERIFY`。DOMAIN_OWNER 给 `review-task-9` 签发纯 `REVIEW_EXECUTE` package 后，任务卡仍保持 `task-123`；receipt 报告 `taskActor=task-123`、`actor=review-task-9`、`role=REVIEWER`、`phase=REVIEW`。

## Progressive requirements

`DISCOVER` 一次返回完整 selected Framework rules 与 applicable project rules，并生成 compact receipt。`ADMIT_ACTION` 在 preparation receipt 缺失或 exact object 漂移时阻塞；结构 PASS 不授予 `SOURCE_WRITE`。`FINALIZE_OUTPUT` 在 result、`OBJECT_POSTIMAGE|path|identity` 或 delivery evidence 缺失时阻塞，并保持 `semanticCorrectnessProven=false`。

## Runtime artifact

默认 input 位于 `.ai-workspace/runtime/TASK-001/task-123/discover.json`。resolver 在 `-DeleteInputOnExit` 下只删除经过 task/actor binding、非 reparse 且文件名安全的 exact file。项目 runtime 不可用时才使用 system temp `aiw-*.json`。

## Host ceiling

conforming adapter 可以证明调用 resolver；instruction-only host 报告 `INSTRUCTION_BOUND / INVOCATION_UNPROVEN`。两者都不证明 model 已正确理解或语义应用规则。
