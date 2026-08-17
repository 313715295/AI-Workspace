# Framework 1.7.0 — 外置维护控制面规划

状态：`DRAFT / NOT_CONSUMABLE / CANDIDATE_REFROZEN / REVIEW_5_PENDING / GIT_CLOSED`

- baseline：immutable Framework 1.6.1。
- release class：`MINOR`；新增兼容控制布局，普通项目repo-local默认不变。
- 用户决定：`USER_2026-08-16_APPROVED_FRAMEWORK_MAINTENANCE_SIBLING_TOPOLOGY_AND_CONTROLLER_ARRANGEMENT`。
- current authority：`.ai-workspace/tasks/active/AIW-FRAMEWORK-MAINTENANCE-TOPOLOGY-001.md`。
- candidate：`framework/drafts/1.7.0/candidate/`；不可被项目pin消费。

## 1. 目标拓扑

```text
<dedicated-workspace-parent>/            # 无 .git、无 .ai-workspace
├─ AI-Workspace-Maintenance/             # control Git root
│  └─ .ai-workspace/                     # 唯一动态authority
└─ AI-Workspace/                         # Framework target Git root
   ├─ framework/
   ├─ scripts/
   ├─ README.md
   └─ AGENTS.md                          # 静态保护入口，不是控制面
```

Codex项目挂载专用父目录，默认cwd在Maintenance仓。父目录只是sandbox/workspace边界；每个状态变更仍绑定一个明确repository ID、一个Git top和仓内相对路径。

## 2. 公共合同

### 2.1 布局分离

- 现有`repo-local / schema3 / repositoryRoot=..`继续是普通项目唯一默认，不因1.7.0升级自动迁移。
- 新增`framework-maintenance-sibling / schema4`，仅允许一个同父目录、单目录名定位的Framework目标仓。
- Maintenance仓持有唯一controller、task、authorization、ROADMAP处理和发行状态；Framework目标仓不得保留`.ai-workspace`。
- 专用父目录不得是Git根或控制面；不支持任意绝对路径、`..`配置、reparse目标、多目标列表或嵌套仓发现。

### 2.2 目标发现与身份

- `.ai-workspace/project.json.repositoryRoot=..`仍只定位control Git root。
- `frameworkTarget.repositoryId`是授权与任务的稳定目标标签；`siblingDirectory`必须是单一安全Windows目录名。
- resolver从control Git root的父目录拼接唯一目标，复证父目录无`.git/.ai-workspace`、control和target均为各自Git top、目标非reparse，并存在当前pin的完整Framework入口。
- 恢复要求controller为`CURRENT`且目标仓`.ai-workspace`不存在；不存在迁移观察开关或临时controller状态。

### 2.3 授权与路径

- actual schema3/repo-local继续消费schema1授权包；checker必须拒绝`GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR`进程覆盖，证明cwd按目录组件真实属于无reparse Git top，并对canonical project config执行完整schema3字段、routine exclusion和capability验证；schema4/Maintenance不得以schema1降级。
- maintenance布局消费schema2授权包，新增`repositoryId`与`projectConfigIdentity`；一个包只绑定一个仓库。
- schema2 checker必须直接消费同版本steady-state resolver；config、controller、两个Git top、目标pin或目标控制面absence任一不成立时，CONTROL与target包都拒绝。
- `CONTROL_WRITE`只允许control repository；Framework source/test/Git动作只允许配置声明的target repository。
- `exactPaths`、`objectIdentities`和observed path始终是所绑定仓内相对路径；禁止使用父目录相对路径、绝对路径或`..`跨仓。
- control卡更新与target源码实现分包，避免一个包混合两套Git根和dirty边界。

### 2.4 Git与宿主

- maintenance safe-Git入口先消费冻结project config identity和resolver结果，再对选定repository ID运行bounded literal pathset。
- control和target分别复证HEAD/index/dirty；同一时刻每仓最多一个Git closer，stage/commit/push仍另门。
- Bootstrap在loader前解析目标；loader新增兼容`Topology`选择器并为maintenance布局加载完整`FRAMEWORK_MAINTENANCE.md`。
- Maintenance Bootstrap显式读取目标仓`AGENTS.md`和Framework入口；不得假设平级仓指令由Codex自动继承。

## 3. 生命周期与项目迁移边界

1. 在当前repo-local自举仓内完成1.7.0 candidate、direct tests与独立Review。
2. stable投影、live root/CURRENT、Git publication仍是独立门；不修改1.6.1。
3. Framework 1.7.0只接受已经形成的最终稳态，不负责创建父目录、移动仓库、复制/退役旧控制面、切换权威或处理中断恢复。
4. 真实物理迁移另立AI-Workspace项目任务，按当时实际源/目标、旧权威、恢复材料和授权设计离线步骤；不得从本公共合同推导写权。
5. 迁移完成后以`CURRENT` Maintenance controller、目标无`.ai-workspace`的最终布局运行fresh FULL_COLD；未接受前旧项目权威不因候选存在而改变。
6. 两个仓的stage/commit/push分别授权；Framework版本发布不自动改变consumer pin。

## 4. Candidate inventory

- draft control：`FRAMEWORK_PLAN.md + FRAMEWORK_TASK.md`。
- candidate payload：baseline exact38，加`FRAMEWORK_MAINTENANCE.md`、maintenance config schema、maintenance starter exact9、target resolver，共exact50。
- implementation authorization：exact52；现有stable、live root、CURRENT、consumer仓和Git均在范围外。

## 5. Direct verification

1. 普通repo-local schema3、loader、authorization、safe-Git和starter回归保持。
2. maintenance schema4严格字段、类型、重复字段、单目录名与routine exclusions正反例；controller schema、recovery与所有schema2 issuer只接受CURRENT。
3. resolver覆盖正确双仓、父目录含Git/control、control或target非Git top、缺失target/pin、stale controller，以及config/controller/required pin/legacy control的逐组件junction与dangling拒绝。
4. schema2授权覆盖control/target正确路由、repository/config漂移、跨仓路径、混合动作、非CURRENT controller、stale controller、object drift，并在目标完整/partial/foreign/reparse控制面下对CONTROL与target包同时fail closed；schema1只在独立actual schema3 repo-local fixture中PASS，在Maintenance稳态/非稳态、Git环境覆盖、missing/reparse/wrong-version config、非法exclusion与未知/畸形capability下均拒绝。
5. maintenance safe-Git在临时双Git仓分别覆盖bounded STATUS/DIFF/INDEX、错误repository ID、目标漂移与排除项；不触碰当前仓Git。
6. loader对`REPO_LOCAL`不增加模块，对`FRAMEWORK_MAINTENANCE_SIBLING`稳定加载maintenance模块，未知topology失败。
7. isolated双Git fixture把完整frozen candidate安装到目标`framework/versions/1.7.0`，从渲染后的Maintenance Bootstrap走通最终稳态、topology loader与normal FULL_COLD route；目标完整/部分/foreign/reparse控制面全部失败。真实目录迁移不由Framework实现或测试。
8. strict UTF-8/LF、JSON、PowerShell syntax、inventory、manifest canonical及fresh独立CRITICAL Review闭合。

Review-1对旧manifest返回`CHANGES_REQUESTED / 3_FINDING`。第一次同范围返工补齐迁移状态与逐组件reparse停止线，direct suite为`163/163 PASS`。Review-2仍返回`CHANGES_REQUESTED / 2_FINDING`：通用PREPARED/cutover没有可安全消费的权威，且迁移冻结身份不足。用户据此批准减法返工：删除通用迁移状态机，Framework只保留最终稳态合同。新payload=`49 files / 262832 bytes / 8CB9A3DA012485B09FE6F3B5E877284305A9AF4D1CE33B603A4136DD907C6ABC`；完整direct suite=`165/165 PASS`，最终manifest-only复证=`164/164 PASS`。当前必须fresh Review-3。

Review-3对该对象返回`CHANGES_REQUESTED / 1_FINDING`：resolver/safe-Git已拒绝目标控制面，但schema2 checker未消费resolver，授权仍可能在非稳态PASS。same-route修正只复用现有resolver并补双repository负例，不新增状态、迁移流程或第二套拓扑判断。新payload=`49 files / 271843 bytes / 6775254C04E8900188C0BFC5D48ED5E12E9FC087D0B67802186D2B1DA504F521`；完整direct suite=`171/171 PASS`，manifest事实更新后短复证=`170/170 PASS`。当前必须fresh Review-4。

Review-4返回`CHANGES_REQUESTED / 1_FINDING`：Maintenance仍可用schema1包绕过schema2门，且旧测试把该旁路当兼容PASS。用户批准最窄修正：由actual canonical project config决定授权schema，只有schema3/repo-local接受schema1，schema4只接受schema2；兼容性正例移至独立repo-local fixture。新payload=`49 files / 277387 bytes / 2ED38A123126C780009B6107B952BFE8699B97624B50A620F6823DD337F5421B`；完整direct suite=`174/174 PASS`，manifest事实更新后短复证=`173/173 PASS`。当前必须fresh Review-5。

Review-5返回`CHANGES_REQUESTED / 2_FINDING`：继承Git环境仍可伪装schema1发现的Git top，且schema3 nested config只做浅验。用户批准的Rework-5不增加流程：schema1在调用Git前拒绝三个仓库覆盖变量，证明cwd/top组件链无reparse，并执行与现有schema3 safe-Git等价的exclusion/capability严格验证；新增直接负例后的pre-manifest短套件=`183/183 PASS`，冻结manifest与stable 1.6.1 baseline完整套件=`185/185 PASS`，manifest事实更新后的短复证=`184/184 PASS`。当前必须fresh Review-6。

## 6. Stoplines

- 扩成通用任意跨仓控制、多目标列表、远端服务、中央ledger或consumer写入；
- 需要绝对路径、父目录Git、junction/symlink或隐式仓发现；
- 无法维持一个授权包一个repository、单一CURRENT或最终稳态；
- 普通repo-local项目必须改变现有行为才能采用；
- 需要修改stable 1.6.1、root CURRENT、consumer pin或执行未授权Git/external。
