# Prompt patterns

## Cold recovery

证明 cwd 与 Git top。读取 repo-local project/controller/Bootstrap、current task locator 与绑定 profile、task owner、task actor、action actor、role、phase、action/result、paths、capabilities 和 authority sources 所需的最小 facts。解析 pinned Framework，对完整 catalog 执行 `PROCESS_REQUIREMENTS_RESOLVE / DISCOVER`，一次加载全部 returned exact Markdown blocks 与 selected corrections/project-policy rules，再加载必要 supporting artifacts。Recovery 只读；报告 boundary、evidence ceiling 与 unique next action。compatible root Router 未证明运行时，直接走 Bootstrap 并如实说明。

## Implementation launch

用 signed package 绑定 task、owner、actor、Controller epoch、actions、exact paths/identities、repository/config 与 user decision。执行 `PROCESS_REQUIREMENTS_RESOLVE / ADMIT_ACTION`，再通过 `<FW>/TOOLCHAIN.json` 完成 authorization 与 workflow-route checks。全部 gate PASS 后无需第二次 START 即可开始；否则返回最窄 drift 或 missing preparation。

## Task routing

评估 project、cwd/Git top、outcome、task-owner continuity、actor eligibility、lineage、resource、independent-context need、protection、Git/device/external boundary 与 public decision。把 strict ephemeral input 写入 `.ai-workspace/runtime/<task>/<actor>/`，通过 Tool Contract 运行 `WORKFLOW_ROUTE_RESOLVE`，随后删除 input。mandatory facts 任一缺失或冲突都 `fail closed`；只返回 `REUSE`、`MUST_NEW` 或 `BLOCKED`。

`TERMINAL`、`MESSAGE`、`HANDOFF` 与 `HOT_STATE` 必须在声称 transition 前调用相应 operation。最终输出前，用实际 result/delivery 执行 `FINALIZE_OUTPUT`。Codex independent task 只做一次 compact terminal delivery；只有 exact result 阻塞 unique next action 且无其他安全工作时才用 `wait_threads`。

## Review

消费纯 Review package，独立校验 frozen candidate，返回 findings、evidence ceiling 与 Git disposition；不得写入或 repair。Reviewer 是临时 action grantee，不改写 task Work route。Review approval 与 `OWNER_ACCEPT` 分离。

## Framework maintenance

从 Maintenance control repo 开始，只修改授权的新 final-version candidate 与 root integration paths。不得改 stable release、discover consumer 或改 project pin。实现期只跑 affected checks；freeze 时只跑一次完整 current-version suite，然后依次独立完成 Source Review、`OWNER_ACCEPT`、seal 与 deterministic post-seal verification。Git/push 是后续独立 gate。
