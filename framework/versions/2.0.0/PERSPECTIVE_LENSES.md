# 可选评审视角

<!-- AIW-REQUIREMENT:PR_PERSPECTIVE_LENS_SELECTION:BEGIN -->
视角用于主动寻找盲区，不是固定专家人格，也不替代真实独立Review。只选能改变本任务判断的视角，不规定数量；MICRO通常不加载本文件。

## 视角库

1. 用户成果：目标、实际增量和验收是否一致。
2. 责任与权限：原始决定、实际负责人、消费者及操作边界是否明确。
3. 事实与恢复：当前权威、未完成义务、中断和交接能否正确接续。
4. 证据与限制：实际观察能否支持结论，未知、失败和反例是否保留。
5. 比例与成本：增加的流程是否有真实用途，是否减少总体返工和用户介入。

软件接口、状态、实现、性能及测试方法的可选正文位于 `standards/software/`，采用方式见 `standards/README.md`；其他专业视角按项目已采用来源和真实产物选择。本导航不自动加载或采用这些标准。

## 选择与输出

- 按真实风险选择最可能发现严重遗漏的视角，围绕用户成果、实际增量、失败场景与唯一语义归属；不按profile凑数。
- 不因角色名称模拟人物口吻；每个结论绑定项目对象、调用链、diff、测试或运行证据。
- 若多个视角发现同一根因，合并finding，不制造重复审批。
- 输出：视角、最强反例、证据、影响、结论和完成条件。
<!-- AIW-REQUIREMENT:PR_PERSPECTIVE_LENS_SELECTION:END -->

<!-- AIW-REQUIREMENT:PR_PROPORTIONALITY_WHEN_MACHINERY_ADDED:BEGIN -->
对实际重大架构/Framework/workflow方案，或会新增流程机制的规划，推荐前在既有方案写一行`Proportionality`。CRITICAL标签本身不要求每张卡填写该字段或不适用套话。只判断现有机制、缺口分类、最小充分修正、新增机器数量与升级触发条件；MICRO、普通bug fix及不增加机器的routine work豁免。该结论不是第二决策对象或台账，也不替代用户/Owner/Review门。
<!-- AIW-REQUIREMENT:PR_PROPORTIONALITY_WHEN_MACHINERY_ADDED:END -->
