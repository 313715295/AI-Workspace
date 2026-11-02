# Git 与 external action

<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:BEGIN -->
Git证据仅对对应仓库有效。普通项目用当前版本protected safe-Git入口，多仓Maintenance先由root adapter分别解析；可选GIT_WORKTREE验证实际目标Git关系及授权状态，controlRoot任务/pin/恢复不随之搬迁。不得把多仓或不同工作树状态合成一个结论。

STAGE、COMMIT、PUSH及EXTERNAL分别授权，使用精确路径，不用git add .；source或Review包不授这些权限。stage前核候选字节、index、无关dirty及Review去向，commit后报告真实commit/parent和保护安全状态。共享index有他人成果、并发漂移或恢复不明时仅停止受影响动作。

Owner可在当前任务明确仓库/remote/branch决定下直接签纯普通PUSH包，仍须适用Review/接受、最新remote事实及checker。typed RESULT_ACCEPTANCE的唯一acceptedCommit须等于本次待推提交，不能把一般通过状态或另一commit接受拿来推送；精确gitPushBinding、分支/父节点/路径集/index/URL/ref及F13 postTargetState字段取TOOL_CONTRACT。事实变化重绑，不盲推；强推、删远端分支、新分支和共享历史改写仍需相应明确权限。

远端名称和有序发布序列由发布项目自己的决定绑定。Framework发行与项目显式采用互不替代，不发现或修改消费者；本地PASS不暗示后台发布、补偿重试、账户操作或外部完成。
普通C的Review去向取当前同一选择及原接受的严格历史成功解释，不能在递归时仅因CRITICAL重新添加普通Review。PUSH通道始终另需真实typed RESULT_ACCEPTANCE和exact acceptedCommit；本地未选接受也须在进入此通道前完成实际接受。今日新增通道要求不足时补新证据/接受，不回写旧成功；专门发行/source publication等明确独审继续叠加，stage/commit/index/仓库和保护不变。

<!-- AIW-REQUIREMENT:PR_GIT_PUSH_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:BEGIN -->
browser、device 与其他 external side effect 必须各自绑定当前 action、target、credential/publication boundary、user decision 与 evidence ceiling。process resolution 不是 host enforcement，不能授予 external capability。
<!-- AIW-REQUIREMENT:PR_EXTERNAL_DEVICE_BROWSER_SEPARATE:END -->

<!-- AIW-REQUIREMENT:PR_TASK_OWNER_DIRECT_DOMAIN_EXTERNAL:BEGIN -->
TASK_OWNER可在当前领域责任和真实既有用户/项目资源许可内，为有限、有序且可验收的EXTERNAL批次签纯动作包。旧FREE/0分支保持；externalBinding2可引用已批准付费或共享资源的grantRefs，前提是本次用途、provider、操作、payload及原许可实际约束完整可核对。未规定金额、币种或到期日不自动算UNKNOWN，也不推导无限额度；只校验原许可实际规定且本次依赖的条件。

同一成果的既有资源许可仍有效且明确允许Owner委派时，Owner可直接签给具名原专业执行者，复用grantee及原grantRefs；externalBinding2的grantAssessment须明确delegationPermitted=true。省略或false不授委派，旧binding1仍仅Owner自用。执行者按临时EXECUTOR/EXTERNAL路线消费同一纯包，不改变Owner、Work route或父任务。Owner及接收者须核原许可的委派范围、实际账号、费用、共享条件与当前撤回/冲突事实；该声明仅为INSTRUCTION_BOUND判断，不是机械语义证明、用户认证或新许可。许可禁转授、未知或项目保留决定交实际有权者，不靠主控纯转签或提升执行者为Owner绕过。

批次绑定精确payload/输出用途、必要数量与重试上限、停止及恢复条件；没有项目数据的操作仅按TOOL_CONTRACT封闭ZERO_PROJECT_DATA类别处理。批准资料读取不自动批准上传或正式资产激活。UNKNOWN消费状态停止不可安全重发的操作，沿供应商/项目原有界恢复，不盲重试。

已有grant完整覆盖的付费/共享使用不因类别再次索批或强制Controller中转。新购买/订阅、商业许可改变、账户/凭据变化、公开发布、安装、受保护/秘密上传、跨域/阶段变化或资源冲突，若不在原明确许可内仍走相应责任与独立门；真实撤回、越scope或必要事实未知只停受影响动作。改变result kind不绕检查，Git/PUSH另走专门合同。Framework不管理项目预算或计费账本，checker、过程与真实host能力分别成立。
<!-- AIW-REQUIREMENT:PR_TASK_OWNER_DIRECT_DOMAIN_EXTERNAL:END -->

<!-- AIW-REQUIREMENT:PR_GIT_PLANNING_BOUNDARY:BEGIN -->
规划或交付Git去向时，区分READY/DEFERRED/EXCLUDED与实际Git动作。Git证据按仓库分别绑定；stage、commit、push须各自精确授权，不因讨论、Review或Owner接受而获得执行权。实际操作再加载PR_GIT_PUSH_SEPARATE，纯规划不提前运行Git。
<!-- AIW-REQUIREMENT:PR_GIT_PLANNING_BOUNDARY:END -->
