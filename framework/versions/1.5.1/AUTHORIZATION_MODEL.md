# 分级授权模型

## 1. 目的

授权包不是逐命令审批单，而是一个阶段能力包。它把可执行动作机械限制在已确认的task、owner、唯一执行者、对象、pathset和用户决策内；阶段内的常规读写和验证不重复询问。

## 2. 动作类型

- `CONTROL_WRITE`
- `SOURCE_WRITE`
- `TEST_WRITE`
- `TEST_RUN`
- `BROWSER_RUN`
- `DEVICE_RUN`
- `REVIEW_ROUTE`
- `REVIEW_EXECUTE`
- `GIT_STAGE`
- `GIT_COMMIT`
- `PUSH`
- `EXTERNAL`

只读搜索、读取、hash和非变更诊断默认不需要包，但仍受保护路径visibility/read/hash/diff/index边界约束。

常用bundle只是建议名，真实权限永远由`actions`与`exactPaths`决定：

- `PLAN_LOCAL`：通常只有`CONTROL_WRITE`。
- `IMPLEMENT_LOCAL`：可一次包含`CONTROL_WRITE / SOURCE_WRITE / TEST_WRITE / TEST_RUN / BROWSER_RUN`的必要子集。
- `REVIEW_LOCAL`：`REVIEW_ROUTE / REVIEW_EXECUTE`，默认没有候选写权。
- `CHECKPOINT_LOCAL`：`GIT_STAGE / GIT_COMMIT`。
- `EXTERNAL_RELEASE`：按需包含`PUSH / DEVICE_RUN / EXTERNAL`，必须有用户确认。

## 3. 签发层级

### PROJECT_CONTROLLER

可在项目范围内签发本地阶段包、指定Git closer和路由独立Review。产品结果、重大方案/公共合同及外部动作仍需要用户确认；主控不能用自己的签发替代用户决定。

### DOMAIN_OWNER

可在自己的领域和已批准边界内签发：

- `MICRO / STANDARD`的控制面、本地实现、测试和聚焦审核；
- `CRITICAL`在重大方案/公共合同已由用户或项目主控确认后，冻结范围内的本地实施与验证；
- 已明确委派时的本地Git checkpoint。

不得签发跨领域公共合同取舍、改变项目pin、push/发布或未获用户确认的外部动作。遇到范围、产品、owner、质量底线或公共合同变化回项目主控。

### EXECUTOR / REVIEWER

执行者只能消费包；不能自签、自扩或把测试通过当作新权限。审核者可给finding与verdict，不能据此授予候选写入、Git或外部动作。需要限定返工时，由原授权包预先给出一次范围内返工，或由有权owner签发新包。

## 4. 用户确认边界

`decisionClass`取值：

- `ROUTINE_LOCAL`：已批准边界内的本地实现、测试和聚焦审核；`userConfirmation=NOT_REQUIRED`。
- `PRODUCT_RESULT`：玩家可见结果接受、试玩结论或改变产品行为；必须绑定用户确认引用。
- `MAJOR_ARCHITECTURE`：公共合同、跨域职责、持久状态、核心状态机或高代价方案；必须绑定用户确认引用。
- `EXTERNAL_ACTION`：push、账号/设备、上传、提审、发布、付费或其他外部状态变化；必须绑定用户确认引用。

用户确认一次重大方案后，领域owner可在冻结exact与停止线内签发后续本地实施包，不需要用户逐文件、逐测试或逐轮确认。反例、范围变化或公共合同变化使该确认不再覆盖新方案。

## 5. 机械包字段

最小JSON形状：

```json
{
  "schemaVersion": 1,
  "frameworkVersion": "1.5.1",
  "taskId": "TASK-001",
  "profile": "STANDARD",
  "lifecycle": "ACTIVE",
  "owner": "domain-owner-id",
  "issuer": "domain-owner-id",
  "issuerRole": "DOMAIN_OWNER",
  "grantee": "executor-id",
  "bundle": "IMPLEMENT_LOCAL",
  "decisionClass": "ROUTINE_LOCAL",
  "userConfirmation": "NOT_REQUIRED",
  "reviewIndependence": "NOT_APPLICABLE",
  "delegatedGitCloser": false,
  "actions": ["SOURCE_WRITE", "TEST_WRITE", "TEST_RUN"],
  "exactPaths": ["src/a.js", "test/a.test.js"],
  "objectIdentities": [
    {"path": "src/a.js", "identity": "123|<UPPER_SHA256>"},
    {"path": "test/a.test.js", "identity": "NEW"}
  ],
  "invalidatesOn": [
    "TASK_CHANGE", "OWNER_CHANGE", "GRANTEE_CHANGE", "ACTION_CHANGE",
    "PATHSET_CHANGE", "OBJECT_DRIFT", "USER_DECISION_CHANGE"
  ]
}
```

`NEW`只允许明确新建的exact path，而且preflight必须收到该path的显式observed identity=`NEW`；若现场已有对象或未提供observed identity，授权失败。既有写对象必须使用`bytes|UPPER_SHA256`。授权包不长期复制整个manifest；candidate稳定节点另生成候选manifest。

exact、identity和observed path共用同一Windows安全规范：repo-relative、NFC、无空组件、无`.`/`..`、无尾随点/空格、无Windows保留名；比较使用OrdinalIgnoreCase，大小写或规范化碰撞均失败。checker不静默清洗路径。

## 6. Checker证明边界

`scripts/check-authorization.ps1`验证：字段、角色签发权限、动作、用户门、路径规范化、observed path子集、对象identity、actor和必需失效条件。

它不证明：

- issuer确实拥有组织层面的领域；
-设计或实现正确；
- Git worktree中没有其他owner变化；
- 用户确认引用真实有效；
- 宿主一定在每个变更工具前调用了checker。

这些事实分别由项目权威、Review、真实Git检查、用户记录和宿主pre-tool集成承担。Framework不得把脚本PASS冒充更强结论。
