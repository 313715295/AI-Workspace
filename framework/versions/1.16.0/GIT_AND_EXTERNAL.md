# Git 与 external action

<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:BEGIN -->
Git 证据只对对应 repository 有效。普通repo-local项目使用当前version的protected safe-Git helper；多repository维护布局必须先由相应root adapter解析目标，再调用其root safe-Git入口。使用精确`safe.directory`配置与显式Git top，不得把不同repository状态合成一个status结论。

`GIT_STAGE`、`GIT_COMMIT`、`PUSH` 与 `EXTERNAL` 是独立 action。必须使用 exact paths，不得用 `git add .`。source 或 Review package 不授予这些权限。

stage 前重新证明 candidate identities、index state、unrelated dirty paths 与 Review disposition。commit 后报告 commit/parent identities，以及 protected-safe status/index。Push 需要 remote、branch authority 与最新 remote evidence。

成果 Owner 在当前任务明确授予的 Git 责任内直接协调共享文件、精确暂存和提交；共享 index 有他人成果、并发漂移或中断恢复不明时停止受影响动作。DOMAIN_OWNER 可对已授权的普通 PUSH 自行签发纯 PUSH 包：任务卡当前决定精确覆盖 repositoryId、remote、branch，包的 gitPushBinding 绑定 push URL 身份、最新远端提交、当前单一待推送提交与审核/接受证据。该证据须有唯一 `AcceptedCommit=<完整提交ID>` 行，精确指向待推送提交；仅有一般 Review/Owner 状态不能复用为另一提交的接受。checker 复证当前分支、提交父节点、提交路径集、空 index、远端 URL 与最新远端 ref；正式 Review/Owner 接受及过程门仍各自成立。远端或本地任一事实变化须重绑，不盲推。该路线不推导强推、删远端分支、新分支或改写共享历史权限。

Framework release 与项目的显式 upgrade 彼此独立。Framework Git publication 不发现也不修改 consumers。

本地 PASS 不暗示后台 publication、retry/compensation、account action 或 external claim。
<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:BEGIN -->
browser、device 与其他 external side effect 必须各自绑定当前 action、target、credential/publication boundary、user decision 与 evidence ceiling。process resolution 不是 host enforcement，不能授予 external capability。
<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL:BEGIN -->
## 受限 DOMAIN_OWNER external route

当前 DOMAIN_OWNER 可以为一次用户批准、免费、domain-local 的 atomic batch 直接签发一个纯 `EXTERNAL` package。package 必须绑定 provider、ordered operations、exact payload identities 与 canonicalization、quantity/retry ceilings、output use、stop conditions，以及不可重发的 ambiguous-consumption stop。`ZERO_PROJECT_DATA` 是封闭类别，只包含 provider public-metadata read、public-status read 与 capability discovery；其他 operation 必须绑定 exact payload。

出现 payment/subscription、commercial licensing、account 或 credential change、public publication、installation、protected/secret upload、cross-domain impact、formal asset activation、project-phase change、Git/PUSH、shared quota/resource 或 unknown scope 时，不得使用本 EXTERNAL 直接路线；普通 Git/PUSH 走上文单独合同，其余按现行责任交 PROJECT_CONTROLLER。改变 result kind 不能绕过本规则。action checker、process resolver 与实际 host capability 始终是独立 gate。
<!-- AIW-REQUIREMENT:PR_DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL:END -->

<!-- AIW-REQUIREMENT:PR_GIT_PLANNING_BOUNDARY:BEGIN -->
规划或交付Git去向时，区分READY/DEFERRED/EXCLUDED与实际Git动作。Git证据按仓库分别绑定；stage、commit、push须各自精确授权，不因讨论、Review或Owner接受而获得执行权。实际操作再加载PR_GIT_PUSH_SEPARATE，纯规划不提前运行Git。
<!-- AIW-REQUIREMENT:PR_GIT_PLANNING_BOUNDARY:END -->
