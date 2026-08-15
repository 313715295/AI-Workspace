# Framework 1.6.0开发与发行

本模块只由Framework维护/发行owner加载。当前candidate固定为`DRAFT / NOT_CONSUMABLE`。

## 生命周期

- `DRAFT`：可返工；不得项目pin、register/upgrade消费或复制进正式versions。
- `REVIEW`：完整候选inventory与测试冻结后，由fresh独立Reviewer审核。
- `STABLE`：完整批准和发行收口后进入新`framework/versions/1.6.0/`；进入后永久只读。

本次为`FULL_RELEASE`：公共remote/controller/task/resource合同、starter inventory与根迁移事务均变化。A-C+G direct PASS不允许跳过D/E/F/H、INTEGRATION、全来源版本迁移、最终Review或发行门。

## A-C+G writer release门

1. 1.5.2基线32文件和两份live root scripts源identity复证零漂移；
2. candidate actual inventory精确等于授权39路径；
3. `VERSION.json`、本文件、README、LOAD_MANIFEST与RELEASE_MANIFEST明确DRAFT/NOT_CONSUMABLE；
4. remote、resource、task/wait/archive、controller epoch/route与register/upgrade direct正反例通过；
5. strict UTF-8/LF、语法、inventory和draft loader gate通过；
6. writer释放后才可由owner冻结独立实现Review对象。

## 分离动作

内容批准、正式version生成、live root scripts更新、完整tests、Git、tag/push、CURRENT和项目采用分别授权。任何一步不推定下一步。
