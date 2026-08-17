# AIW-FW-1.7.0-MAINTENANCE-TOPOLOGY-001 — 1.7.0候选实现

- 状态：`DRAFT / CANDIDATE_REFROZEN / NOT_CONSUMABLE / WRITER_RELEASE_PENDING_CONTROL_UPDATE / REVIEWER_NONE`
- baseline：`framework/versions/1.6.1`，不可写。
- public contract：`FRAMEWORK_PLAN.md`。
- owner：`01a00a2e-4422-7560-a72f-eddeff3cc56e`。
- candidate：`FRAMEWORK_1.7.0_MAINTENANCE_TOPOLOGY_CANDIDATE_001`。
- implementation exact：parent task所列exact52；candidate payload exact50。
- Git / CURRENT / push / migration：`CLOSED / CLOSED / CLOSED / NOT_STARTED`。

## Objective

实现单一Maintenance控制仓安全管理同父目录唯一Framework目标仓，同时保留普通项目repo-local默认和全部既有职责分门。

## Acceptance

- schema、resolver、Bootstrap、loader、authorization、safe-Git、starter和文档形成定义—producer—consumer—test闭环；
- isolated双Git正反例与repo-local回归通过；
- candidate manifest冻结后writer释放，由未参与候选写入的fresh Reviewer执行完整CRITICAL Review；
- stable投影、live root、物理迁移及两个仓Git另门。

## Current

- PLAN已由用户批准并由Framework Controller选择`1.7.0 / MINOR`。
- 首次baseline复制因隐藏`.gitattributes`触发scope rebind；actual未覆盖既有文件，current exact已修正为52。
- Review-1旧对象=`669|9D7932DD8CCE32982724EF7EA0324BEF83658E38B33EE223BA9072DF4A190B5B / CHANGES_REQUESTED / 3_FINDING`；旧137/137只证明当时有限断言。
- 第一次同范围返工曾实现PREPARED/cutover状态与完整candidate迁移fixture；旧manifest=`707|8CE0BA40E7A4A71AAF8B5F56E7870D36A1C67FD6790E2B7CD170CE9FA04AA4FD`，direct suite=`163/163 PASS`。
- Review-2=`CHANGES_REQUESTED / 2_FINDING`：PREPARED与零CURRENT窗口没有可安全签发/消费promotion或rollback的canonical authority；resolver也未冻结旧controller/control-plane及恢复目录identity。
- 用户批准减法返工：Framework仅定义最终稳定sibling布局，删除PREPARED、migration switch、cutover状态与通用迁移授权；物理迁移改为AI-Workspace项目特定离线任务，另行冻结和授权。
- 减法返工已完成：candidate不含PREPARED、migration switch或通用cutover状态；controller/current recovery、authorization与safe Git只接受最终稳态，目标仓任何`.ai-workspace`均fail closed。
- 新manifest=`718|15B5332403AFFCFF0FF93D2ACAAC104A0019C05EC6C3257D8E730737151C7B99`；payload=`49 files / 262832 bytes / canonical 8CB9A3DA012485B09FE6F3B5E877284305A9AF4D1CE33B603A4136DD907C6ABC`。
- final direct verification=`165/165 PASS`，包含canonical manifest断言与冻结stable 1.6.1完整回归；manifest事实更新后的短复证=`164/164 PASS`。
- Review-3=`CHANGES_REQUESTED / 1_FINDING / HIGH`：schema2 checker没有消费steady-state resolver，在目标出现`.ai-workspace`时仍可能放行CONTROL或target包。
- Same-route rework已完成：schema2 checker直接调用同版本resolver并绑定返回的project/config/controller/repository结果；complete/partial/foreign/reparse/dangling目标控制面下两类包均拒绝。
- 新manifest=`723|E5B2AA9F924513B300CC151372B92F9B938BC85C538FEC68A63BB1D93718C723`；payload=`49 files / 271843 bytes / canonical 6775254C04E8900188C0BFC5D48ED5E12E9FC087D0B67802186D2B1DA504F521`。
- final direct verification=`171/171 PASS`，包含canonical manifest与stable 1.6.1完整回归；manifest事实更新后的短复证=`170/170 PASS`。
- Review-4=`CHANGES_REQUESTED / 1_FINDING / HIGH`：schema1仍可在Maintenance/schema4绕过project config/controller/resolver，旧测试错误断言该路径PASS。
- 用户批准的最窄返工已完成：checker从实际Git top严格读取canonical project config；只有schema3/repo-local接受schema1，schema4拒绝schema1。Maintenance稳态/非稳态负例与独立repo-local正例均PASS。
- 新manifest=`716|EA7DD45CD66E99C3FDB30ABC2C9228ECFD757D3B45B47E87C8A0150BDF106222`；payload=`49 files / 277387 bytes / canonical 2ED38A123126C780009B6107B952BFE8699B97624B50A620F6823DD337F5421B`。
- final direct verification=`174/174 PASS`，包含canonical manifest与stable 1.6.1完整回归；manifest事实更新后的短复证=`173/173 PASS`。
- Review-5=`CHANGES_REQUESTED / 2_FINDING / HIGH+HIGH`：schema1 Git top发现继承`GIT_DIR/GIT_WORK_TREE/GIT_COMMON_DIR`且未证明cwd/top归属；nested schema3 exclusions/capabilities仅浅验。
- 用户批准的最窄Rework-5已实现：拒绝三个Git身份覆盖变量，逐组件证明cwd属于无reparse top，并对schema3 exclusions和`KNOWLEDGE_REFERENCE`执行与safe-Git等价的严格验证；没有新增状态、流程、helper文件或迁移机制。
- direct pre-manifest verification=`183/183 PASS`；覆盖三个Git环境覆盖、wrong-version/missing/reparse config、非法/重复exclusion及未知/畸形capability，schema1独立repo-local正例和schema2 resolver门均保持。
- frozen manifest payload=`49 files / 287651 bytes / canonical 843200567BB1B3853A389EE1400AC8E8EE95070D9FCAE57AFC6A3D9F1DE9E58C`；包含stable 1.6.1 baseline与canonical manifest的完整direct verification=`185/185 PASS`。
- manifest事实更新后的短复证=`184/184 PASS`。
- 唯一下一动作：重新冻结身份，释放writer并路由fresh Review-6；候选冻结后不得再写。
