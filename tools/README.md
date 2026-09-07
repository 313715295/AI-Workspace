# 可选配套工具

这些工具可独立使用、按需维护，不参与 Framework 版本载荷、项目初始化、采用或日常运行。

- [资源评估工具](resource-evaluation/README.md)：离线准备试验材料、保留首交、增量汇总质量证据与受试/统筹成本，辅助选择模型和推理强度。需要 Node 20+，无安装依赖。

从仓库根目录开始：

~~~sh
cd tools/resource-evaluation
node --test test/tool.test.cjs
node cli.cjs help
~~~

完整示例和数据格式见工具自己的说明。模型执行与语义判断由使用者完成；工具不会自动调度任务或修改资源策略。工具按自身 package.json 版本维护，默认不打入 Framework 用户安装包。
