# Framework 1.5.2变更说明

## 版本性质

1.5.2从不可变的1.5.1稳定版派生，发行类别为`PATCH_HOTFIX`。本次只修复授权checker的两个机械漏放，不改变模块、starter、任务卡schema、根register/upgrade、CURRENT或普通任务流程。

## 修复

- 严格验证授权包JSON类型：schemaVersion必须是整数，delegatedGitCloser必须是真布尔值，actions/exactPaths/objectIdentities/invalidatesOn必须是真数组，字符串字段及数组成员不得靠强制转换通过。
- 禁止同一授权包同时携带`REVIEW_EXECUTE`与候选写入、Git或外部变更动作；候选写入与独立审核必须分包、分writer lineage。
- 增加字符串`"false"`、标量actions、字符串schemaVersion及`SOURCE_WRITE + REVIEW_EXECUTE`混合包负向测试。

## 保持不变

- 1.5.1阶段验收、用户反馈重绑、peer任务路由与全部项目运行语义。
- loader模块集合、project-starter inventory、根register/upgrade脚本和`framework/CURRENT=1.4.1`。
- 已有项目仅显式改pin后采用；不批量迁移任务卡或授权历史。
- 多远程仓库角色、逐远程结果和部分成功恢复顺延到1.5.3，不混入本安全热修。

## 热修验证

- 运行授权direct正反例、1.5.1→1.5.2升级smoke、strict/拓扑/load检查、完整Framework回归和一次fresh hard-gate聚焦Review。
- 任一异常授权包必须`FAIL`；既有合法本地实现、Git委派与纯独立Review包必须继续`PASS`。
