# v1.3.0 变更说明

## 2026-08-09 剩余协作成本与发布准备增量

- 新增只供AI内部使用的轻量任务卡一致性检查器：新建/实质修改卡用一行生命周期摘要核对actor、唯一下一动作、具体expected/actual pathset、active/archive和Review通知方；`ACTIVE_WRITE`允许actual身份子集，`REVIEW/ACTIVE/CLOSED`要求集合相等，legacy无摘要不强制迁移。
- 跨域目标默认单owner、单父卡；独立领域包只在有独立生命周期/owner字节/外部状态/可关闭交付物/必须保留审核结论时建立，并在父卡消费后及时归档，不削弱领域owner和必要独审。
- Review改为绑定稳定内容对象/section identity、依赖manifest与验证上限；候选变化先分类内容/依赖/范围/权限和纯机械known-exact delta，只重审受影响层，影响面不明时fail closed。
- 直接审核的接收ACK改为条件式：默认由第一条实质回复兼作ACK，仅在无法立即开始、需显式异步交接或候选identity/manifest、范围、独立性、权限异常时向执行者单发；固定对象发送后执行者立即停写，不等待ACK，也不增加owner阶段通知。
- 任务卡pathset guard从计数改为规范化具体身份集合，并允许AI逐卡传入从git status/diff或manifest取得的`ObservedActualPath`；ACTIVE_WRITE检查子集，REVIEW/ACTIVE/CLOSED检查相等，稳定报告missing/extra且不扫描全仓归属。
- current exact只由唯一机械摘要的`current_exact`声明并与expected集合数量核对；检查器不再扫描历史正文中的candidate/executor/content/closure exact数字，保留完整审计记录也不会污染current范围判断。
- Review开始notifier明确为“向owner发送阶段通知的角色”：正常直接闭环为`EXECUTOR`，无执行者且审核者直审稳定对象时为`REVIEWER`，停止线/range gate后current/next均为owner且由owner自己冻结并委派或续审时为`NONE`；不新增owner自我通知值。
- 含外部发布的任务采用同一卡active生命周期：独立批准后先提交稳定内容，外部发布成功并记录branch/commit/tag/push后再以closure提交归档；阻断时保持active，不把内容提交伪装为关闭。
- README、任务模板、提示词、审核清单、两个Bootstrap与Pocket Legion项目绑定只消费上述唯一规则；未新增第二流程、审批层、恢复状态或legacy迁移项目。

## 2026-08-08 通信与恢复降本增量

- 用户授权在冻结的1.3.0上原位补充owner预授权的直接审核闭环与两级恢复；不新增第二流程、不降低独立审核/范围/权限/Git/阶段门，也不发布1.3.1。
- `FULL_COLD_RECOVERY`用于首次进入或基线不可证明，`WARM_TASK_REBIND`用于同一健康会话的新任务、Review/返工、idle唤醒和已知exact刷新；温重绑重新授权新任务且冲突时升级完整恢复。
- owner可在任务卡冻结审核者、direct loop边界、轮次和停止线后，允许执行者与独立审核者直接处理范围内返工；Review开始、升级冲突和最终结论仍回唯一owner，Git/push/阶段/外部权限不转移。
- Bootstrap、任务模板、提示词、审核清单、根README与项目绑定只消费上述唯一规则，并记录温重绑的实际增量读取集、未重复对象和基线成立理由。

## 2026-08-08 统一使用与项目初始化增量

- 用户授权在冻结的1.3.0上原位增加分发前的项目初始化能力；本增量不修改治理、流程、审核、资源、Git、会话或试点语义，也不发布1.3.1。
- `AI-Workspace/README.md`成为唯一用户入口和完整初始化权威；建立新项目、换电脑或分享给别人都使用同一流程，用户只需把工作区与源码仓加入AI工作区，并提供项目名称、源码位置和产品目标文字或本地文档。
- 新增中立`project-starter`骨架；初始化会话从根README直接读取完整执行合同，自动推导协作根与project ID，只批量询问无法可靠判断的产品、保护、长期owner/资源、Git/push及外部权限，不再跳转或复制第二份初始化合同。
- 复用并校正`scripts/register-project.ps1`：由AI会话内部调用，使用固定版本模板、fail-closed目标目录和严格UTF-8无BOM写入；用户不接触脚本参数、模板替换或故障命令。

相对v1.2.0：

- 长期责任结构收敛为“主控—领域分管”两层；用户/业务负责人持有最终取舍，执行者与独立审核者改为主控或分管按任务挂载的临时角色，不再形成第三层管理。
- `WORKFLOW_PLAYBOOK.md`新增唯一端到端操作图，统一接收路由、一次授权、范围建制、执行/复审、条件预授权Git、阶段收口和关闭恢复；项目不再复制第二套完整流程。
- 每任务强制唯一长期owner且owner=唯一调度者；执行者只向owner交接一次，完成/阻断/范围冲突/新授权通过消息主动唤醒，owner不依靠短周期轮询续跑。
- 区分内部子Agent与独立任务会话：前者只用于同turn必须综合、无外部等待的边界工作；后者用于跨turn、返工、用户/阶段/Git等待、worktree和独立审计。
- 新增动态资源原则：框架只定义机械、常规、复杂和战略能力级，项目自行映射具体模型与请求档位；按最低充分能力选择，不机械继承长期角色最高档。
- 中高风险任务在写前核对producer、direct consumer、tests、runner/manifest、docs与contingency closure，并冻结exact/contingency/forbidden范围；已冻结范围内Review返工由owner自治，只有公共/跨域/阶段/owner/产品/质量/权限变化才升级。
- 本地Git可在任务卡条件预授权；审核通过后逐项stage并核对commit tree、parent、index、边界和post-commit smoke，不重复申请机械Git门。push、发布和外部状态仍独立授权。
- 新增按需会话健康标准：不定期检查、不自动compact、不由AI猜上下文比例；用户准备轮换时以任务能力和上下文干扰质量自检辅助决定。
- 流程/资源试点纳入普通任务生命周期，必须冻结自然样本和停止线并裁决`KEEP / ADJUST / REJECT`；重型证据按有效键复用，降本不降低独立审核、直接行为、范围保护或必要运行/用户门。
- `TASK_TEMPLATE.md`补充唯一owner、执行载体/资源、回传对象、范围闭包、Git预授权和证据有效键；`PROMPTS.md`同步两层角色与健康自检模板。

兼容性：项目必须显式更新`project.json.frameworkVersion`才启用本版本；1.0.0、1.1.0和1.2.0保持不可变。项目可保留旧章节号作为兼容locator，但通用流程正文应只由1.3.0固定框架持有。
