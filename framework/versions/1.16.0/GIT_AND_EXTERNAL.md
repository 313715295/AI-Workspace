# Git 与 external action

<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:BEGIN -->
Git 证据只对对应 repository 有效。普通repo-local项目使用当前version的protected safe-Git helper；多repository维护布局必须先由相应root adapter解析目标，再调用其root safe-Git入口。使用精确`safe.directory`配置与显式Git top，不得把不同repository状态合成一个status结论。

`GIT_STAGE`、`GIT_COMMIT`、`PUSH` 与 `EXTERNAL` 是独立 action。必须使用 exact paths，不得用 `git add .`。source 或 Review package 不授予这些权限。

stage 前重新证明 candidate identities、index state、unrelated dirty paths 与 Review disposition。commit 后报告 commit/parent identities，以及 protected-safe status/index。Push 需要 remote、branch authority 与最新 remote evidence。

Framework release 与项目的显式 upgrade 彼此独立。Framework Git publication 不发现也不修改 consumers。

本地 PASS 不暗示后台 publication、retry/compensation、account action 或 external claim。
<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:BEGIN -->
browser、device 与其他 external side effect 必须各自绑定当前 action、target、credential/publication boundary、user decision 与 evidence ceiling。process resolution 不是 host enforcement，不能授予 external capability。
<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL:BEGIN -->
## 受限 DOMAIN_OWNER external route

当前 DOMAIN_OWNER 可以为一次用户批准、免费、domain-local 的 atomic batch 直接签发一个纯 `EXTERNAL` package。package 必须绑定 provider、ordered operations、exact payload identities 与 canonicalization、quantity/retry ceilings、output use、stop conditions，以及不可重发的 ambiguous-consumption stop。`ZERO_PROJECT_DATA` 是封闭类别，只包含 provider public-metadata read、public-status read 与 capability discovery；其他 operation 必须绑定 exact payload。

出现 payment/subscription、commercial licensing、account 或 credential change、public publication、installation、protected/secret upload、cross-domain impact、formal asset activation、project-phase change、Git/PUSH、shared quota/resource 或 unknown scope 时，不得使用直接路线，必须转交 PROJECT_CONTROLLER。改变 result kind 不能绕过本规则。action checker、process resolver 与实际 host capability 始终是独立 gate。
<!-- AIW-REQUIREMENT:PR_DOMAIN_OWNER_DIRECT_DOMAIN_EXTERNAL:END -->
