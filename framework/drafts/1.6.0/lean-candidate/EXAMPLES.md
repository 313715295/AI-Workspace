# Framework 1.6.0 A-C+G示例

## 1. 默认任务

```markdown
# TASK-001 — local implementation

- Task schema: 1.6.0
- Owner: domain-owner
- Resource requirement: DEFAULT
- Range summary: profile=STANDARD; lifecycle=ACTIVE; expected_paths=[src/a.js]; actual_paths=[src/a.js]
```

默认协调由Framework合成为`INLINE / DIRECT_OWNER_DEFAULT / NO_POLL / TERMINAL_ONLY / userDecisionHandoff=NONE`，任务卡不展开这些字段。

## 2. 非默认资源需求

```markdown
- Resource requirement: {"minimumQuality":"FOCUSED_HIGH","requiredTools":["browser"],"continuity":"FRESH"}
```

host读取任务卡、adapter policy与现场capability，由`resolve-resource-binding.ps1`生成临时binding。authorization只绑定binding locator、identity和digest，不复制能力矩阵。

## 3. Controller授权条件字段

```json
{
  "issuerRole": "PROJECT_CONTROLLER",
  "issuerControllerId": "controller-session-id",
  "issuerControllerEpoch": 4,
  "controllerControlIdentity": "128|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}
```

checker实际读取唯一controller.json并复算identity。DOMAIN_OWNER包不需要、也不从controller对象推导这些字段。

## 4. RemoteBatch

批次顶层绑定project/task/candidate、唯一Git closer、authorization和整个project.json identity；每个remote只保存脱敏endpoint fingerprint、普通push refspec、expected heads与一次结果。整体结果不写入JSON，由checker现场派生。

- remote A成功、remote B失败 → `PARTIAL`；不能宣称整包成功。
- 重试B → 新batch、新authorization、重新读取head；旧A receipt不改。
- force、删除ref或撤销远端效果 → 新的高风险external包，不进入普通RemoteBatch。

## 5. 路由与轮换

- current epoch routine summary → `SUPPRESSED_ROUTINE`。
- 切换前排队routine → `STALE_QUEUED_AUDIT_ONLY`。
- stale decision/authorization/ACK → 拒绝。
- stale exception → 只有读取current task、保持原始message class、声明零旧授权复用并首次重路由时允许。
- 同epoch同task/candidate-state/responsible reporter → 同一state key，后续副本去重。
