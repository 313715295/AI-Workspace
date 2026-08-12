# Framework 1.5.2

## 状态

- lifecycle: `STABLE / CONSUMABLE / OPT_IN / NOT_CURRENT`
- source baseline: `Framework 1.5.1 STABLE`
- owner role: `FRAMEWORK_MAINTAINER`
- release class: `PATCH_HOTFIX`
- release status: `DIRECT_TESTS_PASS_37 / FRAMEWORK_TESTS_PASS / FOCUSED_REVIEW_APPROVED / RELEASE_INTEGRATION_PASS`
- project pin authority: `PROJECT_SPECIFIC_UPGRADE_ONLY`

1.5.2是从1.5.1派生的兼容安全patch。它不修改`framework/versions/1.5.1/`，进入稳定库存后可由项目显式升级，但不改变`framework/CURRENT=1.4.1`或任何项目pin。

## 本patch修复的问题

1.5.1授权规则已经要求真实Git委派与独立Reviewer，但checker存在两个实现漏放：PowerShell把非空字符串`"false"`转换为布尔真；同一包可同时携带候选写入和`REVIEW_EXECUTE`。

1.5.2把规则落实为机械拒绝：

- 授权包关键字段和数组使用严格JSON类型，不再先强制转换后判断；
- 字符串`"false"`不能取得Git closer委派；
- `REVIEW_EXECUTE`与候选写入、Git、push/external变更动作互斥；
- 写入候选与独立审核使用不同阶段包，冻结候选后由未参与写入的Reviewer审核。

## 成本与兼容边界

- 授权包零新增必填字段；合法1.5.1包保持兼容。
- loader、任务卡、项目starter和普通恢复上下文不增加模块或字段。
- 仅异常类型和写审混合包从误放改为拒绝。
- 多远程仓库支持顺延到1.5.3，不混入本安全热修。

## PATCH_HOTFIX完成定义

- authorization checker的合法正例、严格类型负例及写审互斥负例通过；
- strict文本、模块/starter拓扑、受影响loader计划、授权版本和1.5.1→1.5.2 smoke通过；
- 完整Framework回归通过，确认未误拒合法实现、Git委派或纯独立Review包；
- 一名未参与候选写入的fresh聚焦Framework Reviewer确认没有新的误拒、漏放或流程成本外溢；
- 发行owner完成STABLE元数据、manifest、正式version目录和全量发行复验；
- commit、push、CURRENT和项目pin仍分别授权。
