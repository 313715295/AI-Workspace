# Framework 1.5.1

## 状态

- lifecycle: `STABLE / CONSUMABLE / OPT_IN / NOT_CURRENT`
- source baseline: `Framework 1.5.0 STABLE`
- owner role: `FRAMEWORK_MAINTAINER`
- release class: `PATCH_HOTFIX`
- release status: `HOTFIX_TESTS_PASS / FRAMEWORK_TESTS_PASS / FOCUSED_REVIEW_2_APPROVED / RELEASE_INTEGRATION_VERIFIED`
- project pin authority: `PROJECT_SPECIFIC_UPGRADE_ONLY`

1.5.1是从1.5.0派生的兼容稳定patch。它不修改`framework/versions/1.5.0/`，已进入register/upgrade可显式选择的稳定版本库存，但不改变`framework/CURRENT=1.4.1`或任何项目pin。

## 本patch修复的问题

1.5.0已经把项目主控、领域owner、执行者和Reviewer职责分开，但CRITICAL模板与task checker没有机械区分“技术证据已完成”和“项目阶段已验收”。阶段父卡可能在缺少领域产品合同核对、runtime/platform适用性或项目主控签署时，直接把技术审计结果送到用户最终门。

1.5.1增加条件式阶段验收门：

- 只有推进项目或多领域里程碑的CRITICAL父卡使用`Phase gate: TRUE`；
- 技术证据、领域合同、runtime/platform、项目签署、用户最终门按固定顺序闭合；
- runtime/platform或领域项确实不适用时允许带原因的`NOT_APPLICABLE`；
- 技术证据无争议时不机械增加第二名fresh Reviewer；
- 技术Review与用户试玩按风险和总成本选择顺序；同一stable candidate上的结论在项目签署后直接绑定且机械比对`current_exact`，不重复询问；
- schema1.5既有任务继续兼容，不批量迁移current/history。

## 成本边界

- MICRO/STANDARD：零新增字段。
- 普通CRITICAL：只增加`Phase gate: FALSE`一行。
- 阶段CRITICAL父卡：增加一行开关和六行紧凑矩阵。
- loader没有新增模块；core-only相对1.5.0增加264B/约66保守token，典型领域owner计划增加3,224B/约806保守token。
- 不新增项目文件、数据库、服务、第二状态、逐任务报表或额外常驻角色。

## 兼容与采用

- checker接受task schema `1.5`和`1.5.1`；新模板使用`1.5.1`。
- 授权包继续绑定task/owner/issuer/grantee/action/path/identity/用户门/失效条件；阶段验收矩阵不授予source、Review、Git或external权限。
- Pocket Legion只在W1整阶段闭环后、W2开始前进行真实升级对比；若1.5.1稳定通过，则从1.4.0直接升级到1.5.1，不临时pin 1.5.0。

## PATCH_HOTFIX完成定义

- task checker的兼容、正向、缺项、顺序、owner、N/A理由和关闭反例通过；
- strict文本、模块/starter拓扑、受影响loader计划、授权版本和1.5.0→1.5.1 smoke通过；未受影响的全角色矩阵与根事务复用1.5.0发行证据；
- 本patch触及机械hard gate，因此由一名fresh聚焦Framework Reviewer确认没有新的误拒、漏放或普通任务成本外溢；
- 发行owner完成STABLE元数据、manifest、正式version目录和全量发行复验；
- commit、push、CURRENT和Pocket pin仍分别授权。
