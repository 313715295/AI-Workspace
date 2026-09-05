# 授权模型

<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:BEGIN -->
授权必须显式、限域，并且只对当前 phase 有效。不得从 recovery、Review、任务分配或聊天意图中推断授权。

## Actions

`CONTROL_WRITE`、`SOURCE_WRITE`、`TEST_WRITE`、`TEST_RUN`、`BROWSER_RUN`、`DEVICE_RUN`、`REVIEW_ROUTE`、`REVIEW_EXECUTE`、`OWNER_ACCEPT`、`GIT_STAGE`、`GIT_COMMIT`、`PUSH`、`EXTERNAL`。

范围内的安全读取不需要 implementation package。以上每个会修改状态或产生副作用的 action 都保持独立。

## Package binding

package 绑定 framework version、task ID 与当前整张任务卡 identity、profile、lifecycle、owner、issuer、grantee、action set、exact paths、whole-object identities、decision class、user confirmation 与 project-config identity。checker 同时比较 package grantee、任务卡中的当前 actor 与 host 实际 actor；Controller 和 repository 字段是否必需，由 topology 与 issuer role 决定。

package JSON 按严格安全输入解析。转义解码后出现的递归重复 member 也必须拒绝；不得用 last-member-wins 行为解释权限。

必需 invalidator 包括 task、owner、grantee、action set、path set、object、user decision、Controller epoch、repository 与 project-config drift。未知 drift 一律 fail closed。

tool backend 由 project config 选择，因此 repo-local package 与由 root adapter 预先验证的 repository-bound package 都通过 `projectConfigIdentity` 绑定它。package 不重复 `frameworkToolBackend`；backend/config 字节变化会使 package 失效，不创建第二个选择真相。repository-bound package 不能直接调用 version checker，必须先经过拥有 topology authority 的 root adapter；version checker只复用通用 action、task、object 与Controller绑定语义。

Framework `1.16.0` 接受 `ObservedAction` array。同一个未变化 lease 可以一次预检多个已授予 action，checker 对每个 action 返回独立结果。重复、未知或未授予 action 必须失败；原有单 action 调用仍有效。

schema3 project-upgrade package 可包含 `targetFrameworkSnapshot={canonical,manifestIdentity}`。stable adoption 保持向后兼容；local candidate pilot 则必须由 root upgrader 要求该字段，并与当次重算 payload 及最终 manifest identity 精确一致。它只是逐次使用的候选绑定，不创建发布 ledger 或第二份 release truth。

批量预检不会合并能力：`SOURCE_WRITE` PASS 不等于 `TEST_RUN`、Review 或 Git 权限。任何绑定 identity、repository 或 decision 漂移后，后续 phase 必须使用新 package。

`PROCESS_REQUIREMENTS_RESOLVE/ADMIT_ACTION` 消费当前 task/source decision 并校验 preparation，但始终返回 `authorityGranted=false`。process decision 与独立 action checker 必须分别 PASS，彼此不能替代。

仓库内不设置 authorization-consumption ledger。有效期由绑定的 invalidators 和显式 phase release 结束；host 无法证明 single consumption 时，不得声称已单次消费。
<!-- AIW-REQUIREMENT:PR_ACTION_AUTHORIZATION_INDEPENDENT:END -->

<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:BEGIN -->
protected 或 excluded 的 read/hash/diff/index/write 边界必须精确且 fail closed。scope 为 UNKNOWN 或 bounded helper 不可用时，只返回最窄 blocker；不得扩大搜索、使用绕行读取或放宽 path set。
<!-- AIW-REQUIREMENT:PR_PROTECTED_PATH_FAIL_CLOSED:END -->

<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:BEGIN -->
authority context 只能来自当前机械观察到的 project、Controller、task、package、scope、identity、capability、recovery 与 host facts。requested objective/action/result 和 semantic hints 只构成 intent envelope。authority facts 始终优先；UNKNOWN、未授权 action 或 hint/fact mismatch 会阻止受治理 action，或保守选择受影响的完整规则块。
<!-- AIW-REQUIREMENT:PR_AUTHORITY_CONTEXT_INTENT_RECONCILIATION:END -->

<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:BEGIN -->
## Controller、Owner 与临时角色

`controller.json` 是当前 Controller ID/epoch 的唯一字面真相。PROJECT_CONTROLLER issuer 必须与其精确一致；DOMAIN_OWNER 不得伪装 Controller 字段。

PROJECT_CONTROLLER 与 DOMAIN_OWNER 是长期责任。Executor、writer、Reviewer、Git、browser、device 与 resource route 都是临时 task/phase 角色。action、grantee、path/object set 或 user decision 改变时需要新 package；旧 package 因此失效，但健康 recovery baseline 不会自动失效，也不因此强制由 PROJECT_CONTROLLER 签发。

任务卡的 Owner 表示责任归属，`Work route` 表示当前连续生产 actor；一次临时 action 的 grantee 不取得任务归属。Owner 可为单次写入、测试、Review、Git、browser/device 或 external action 选择临时 actor，resolver 根据唯一 package action 形成相应临时 role/phase，并保留 `taskActor` 作为任务生产路线证据。`REVIEW_ROUTE` 与 `OWNER_ACCEPT` 仍由有责任的 Owner/route actor 执行；只有真实责任转移才可改写任务路线。

在未变化的 domain task 内，DOMAIN_OWNER 是默认直接 issuer 与 phase consumer。Owner 可自己完成连续工作，也可因并行、上下文隔离、独立性或资源成本选择临时 actor；fresh package 只绑定该 action，不等于新任务、责任转移或 FULL_COLD。Owner 可直接向独立 Reviewer 签发纯 `REVIEW_EXECUTE` package、接收 verdict 并执行 `OWNER_ACCEPT`。接受动作复用现有 scoped package，绑定当前 task 和 exact result；`OWNER_ACCEPT` 的 grantee 必须是经当前任务卡复证的 Owner，并继续满足既有 actor 绑定。它不要求新增授权格式，也不因获准接受而获得任何写入、安装、Git 或 external 权限。合格的跨域 actor 可以写入，任务 Owner 仍保持不变。CRITICAL Review 中，task owner、package issuer、candidate writer 与所有 material contributor 都不能成为最终独立 Reviewer；`candidateWriter` 不得在 `materialContributors` 中重复。

只有 PROJECT_CONTROLLER 拥有唯一 next action，或必须解决 owner/public-decision、cross-domain contract、protected-path、project-phase、Git/device/external 或 resource-conflict 边界时，才路由至 PROJECT_CONTROLLER。resource selection 本身不授予权限。

Controller handoff 是单向过程，并在 `TAKEOVER_COMPLETE` 结束。predecessor 的只读宽限不是 routing authority，也不是 retirement permission。
<!-- AIW-REQUIREMENT:PR_DYNAMIC_ROLE_DIRECT_ISSUANCE:END -->

<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:BEGIN -->
## User decision

只要冻结的 decision、scope、risk 与 boundary 未变化，user confirmation 就继续有效。material 或 UNKNOWN drift 需要新 decision；无关 metadata 或 deterministic projection 不需要。

drift class 为 `MATERIAL / UNRELATED_METADATA / PROJECTION / UNKNOWN`。immutable candidate、protected object 与 canonical evidence 仍执行严格 whole-object stop。
<!-- AIW-REQUIREMENT:PR_USER_DECISION_DRIFT:END -->
