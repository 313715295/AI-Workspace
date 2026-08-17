# Framework 1.7.0任务示例

示例只说明分级与权限边界，不替代项目任务卡和actual证据。

## 1. MICRO只读定位

目标：确认一个错误文案来自哪条current错误码映射，不修改文件。

- role/profile/phase/host：`EXECUTOR / MICRO / DISCOVER / CODEX`
- loader：公共核心+Codex宿主；若不需要Codex任务工具，可用GENERIC只读核心。
- 无任务卡、无authorization、无worktree、无Reviewer。
- 输出：current producer、consumer、可达性与建议owner。

若用户随后要求修复且能同turn低风险闭合，领域owner可自签MICRO本地包；跨turn或涉及公共错误合同则升级STANDARD。

## 2. STANDARD领域owner签发IMPLEMENT_LOCAL

目标：修复本域一个配置读取缺陷，保持显式`false`。

领域owner冻结`src/config.js`与`test/config.test.js`，签发一次：

```json
{
  "issuerRole": "DOMAIN_OWNER",
  "bundle": "IMPLEMENT_LOCAL",
  "decisionClass": "ROUTINE_LOCAL",
  "userConfirmation": "NOT_REQUIRED",
  "actions": ["SOURCE_WRITE", "TEST_WRITE", "TEST_RUN"],
  "exactPaths": ["src/config.js", "test/config.test.js"]
}
```

执行者取得writer lease时验证一次，连续修改和direct tests复用PASS。没有path/action/identity/owner变化，不为每次编辑重复脚本。完成后释放writer并主动回领域owner；领域owner聚焦验收，不需要项目主控逐轮转述。

## 3. CRITICAL重大方案确认后的本地实施

目标：改变公共持久状态版本合同。

1. 领域owner与主控完成影响闭包和方案；用户确认`MAJOR_ARCHITECTURE`稳定方案。
2. 任务卡保留用户确认引用、stable contract section、exact、依赖和stopline。
3. 后续本地实施包可以是`ROUTINE_LOCAL`，因为产品/方案门已通过；它不要求用户逐文件确认。
4. 任一公共字段、迁移策略、exact或用户决定变化使包失效，回重大方案门。
5. 用户/运行验证完成后再由fresh独立Reviewer审核同一candidate。

这避免“每一步都问用户”，同时不把一次用户确认扩成无限范围授权。

## 4. Fresh聚焦Review

STANDARD高风险或CRITICAL候选由未参与实质设计/写入的Reviewer读取stable candidate、actual diff、direct dependencies和验证上限。

- 任务一次预授权范围内`CHANGES_REQUESTED → 一次限定返工 → 聚焦Review-2`。
- Reviewer主动回传，不使用wait维持进度。
- 同一finding复发、第三路径、产品/公共合同或权限变化立即回owner，不开始Review-3。
- Reviewer若写候选，失去唯一最终批准资格。

资源建议用高质量聚焦档；不能只为便宜下调并把返工转嫁给owner。

## 5. Git与external分离

实现包即使包含tests，也没有Git权。领域owner完成验收后，项目委派Git closer签发`CHECKPOINT_LOCAL`，只stage/commit exact。

commit成功仍不授权push。push、device、上传、提审和发布各自绑定`EXTERNAL_ACTION`用户门和真实执行者。内容已提交但等待平台状态时任务保持active，不归档、不轮询。

## 6. Worktree例外

普通新会话直接使用共享工作树并遵守exact owner边界。只有两个候选必须长期并行且文件范围重叠，主工作树又要保持可发布时，才创建worktree；创建前记录dirty复制成本、依赖缓存、磁盘、集成owner和合并顺序。

独立Review只需要独立上下文与取证，不因“独立”二字默认复制工作树。

## 7. 阶段父卡验收链

技术审计任务只产出稳定evidence，不直接宣布阶段完成。真正推进项目/多领域里程碑的CRITICAL父卡使用：

```text
Phase gate: TRUE
Technical evidence: READY; producer=audit-executor; evidence=audit-manifest
Domain contract check: ACCEPTED; owner=design-owner; evidence=contract-check
Runtime/platform check: NOT_APPLICABLE; reason=no-runtime-or-platform-boundary
Project phase signoff: READY; controller=project-controller; evidence=phase-ready
User final gate: PENDING
```

此时技术、产品合同和项目整合都已闭合，只等待用户决定是否推进下一阶段。技术证据无争议，不再增加一名Reviewer；普通CRITICAL写`Phase gate: FALSE`且不带矩阵。

Review与试玩顺序不固定。若试玩便宜且容易暴露产品问题，可先试玩并记录`User playtest evidence: PASSED; candidate=<current_exact>; evidence=<user-reference>`，以免把明显错误候选送审；若技术风险或环境准备要求先审，则Review通过后再试玩。前一种情况下矩阵中的`User final gate`仍保持`PENDING`直到项目签署，随后写成`CONFIRMED; candidate=<current_exact>; evidence=<user-reference>`直接复用既有引用，不再请用户重复确认；candidate或用户决定漂移才重新打开用户门。

## 8. Legacy项目升级

现有schema2 repo-local项目升级1.5时：

- 不重建PROJECT/STATUS/RELATIONSHIPS/tasks；
- 不批量迁移legacy任务卡；
- 只更新project pin和Bootstrap受管区；
- 新任务使用1.5.2 template，schema1.5卡由checker继续兼容；
- 第一次1.7.0冷恢复验证loader、schema3日常排除结构、controller ID/epoch、owners、current任务，以及bounded Git consumer对排除配置的使用点验证结果。

## 1.7.0轻量合同例

- routine owner完成本域工作后直接持久化终态；主控按需pull，不要求ACK，只有跨域/公共合同/资源冲突/routine-exclusion冲突/对象漂移才上报。
- 非默认资源需求可在任务中写`minimum=FOCUSED_HIGH; requiredTools=[browser]; continuity=FRESH`；宿主满足或保持未分配，不生成binding文件。
- 两个remote发布任务冻结`origin/main`与`mirror/main`，closer各尝试一次并分别记录结果；失败remote若要重试，另签fresh阶段授权。
- Git检查只允许`docs/release`时，以冻结project config identity调用safe-Git；默认仍启动bounded命令并附加日常排除。只有显式包含排除对象时，allow路径必须与排除项exact一致；广泛override或无法作为literal表达的配置返回`UNVERIFIED`且命令不启动。
- 已知知识条目ID时，调用现有checker并精确传入，例如`-EntryId @('ROUTE_EDITOR','RENDER_SNAPSHOT')`。checker仍验证完整索引和全部CURRENT引用/authority后才返回请求项；未知、非CURRENT、重复或超过3个ID均不可用。未传`EntryId`时保持1.6.0按ID前三条的兼容行为。

Pocket等大型dirty项目必须在自己的采用任务中另做版本对比；即使1.7.0未来正式发行，也不会自动升级项目。

## 9. Framework维护sibling任务

Maintenance控制仓`AI-Workspace-Maintenance`与目标仓`AI-Workspace`位于同一非Git父目录。控制卡更新使用`schemaVersion=2, repositoryId=CONTROL`且只给`CONTROL_WRITE`；候选实现使用另一个schema2包，`repositoryId`等于project config声明的目标ID，只给目标仓`SOURCE_WRITE / TEST_WRITE / TEST_RUN`。两包共享冻结project config identity，但writer不重叠、paths都相对各自Git top。

目标仓Review读取冻结candidate与manifest，不修改Maintenance控制面；之后若要投影stable、移动现有目录、改变CURRENT、提交任一仓或通知consumer，分别进入新的明确阶段。共同父目录出现`.git`、目标出现未声明`.ai-workspace`、target ID漂移或需要第三仓时立即停止，不自动搜索替代位置。
