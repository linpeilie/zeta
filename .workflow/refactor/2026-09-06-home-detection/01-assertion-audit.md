# WP-5 原测试与断言审计

基线 `479839d6`；按 analyzer AST 比较本次修改的既有测试文件，原文件保存在 `/tmp/zeta-wp5-baseline/test/`。测试文件中的 `test/testWidgets` 声明名全部保留：89 → 91；循环参数化的实际运行次数以最终门禁为准。

原断言 661 条，其中 649 条 AST 文本不变，12 条入口或语义调整。新文件与现有文件中新场景另计。原始逐表达式差异见 [JSON](01-assertion-audit.json)。

| 调整 | 原业务不变量与理由 |
|---|---|
| logPaths → availableLogFileCount | 不再让 application 获取原路径；仍确认日志读取来源数量为 1，原日志内容断言保留 |
| 探测关闭 StateError → typed closed | WP-5 规定的新终态；另一个多 waiter 用例把探测从原异常列表分离，仍检查立即结算与真实 drain |
| Home loader → 统一 detection port | 无真实 I/O 的测试不变量保留，检测端口明确为 fixture 实现，且实际首页安装列表为空 |
| HomeProviderSummary.fromManagedAgent → fromAgentView | 五种原状态及升级不改变可用性的预期完全保留，仅切换安全 DTO 输入 |
| 语言断言限定 agent-detect-button | 统一空安装结果使空态重试和工具栏均显示自动检测文案；断言仍验证原按钮在当前语言下的文字，不依赖出现次数 |
| 第四插件测试显式使用默认探测适配器 | 仓储已全部替换为测试工厂，必须通过真实 app 适配器检测，避免通用无安装测试 port 遮蔽贡献链；原检测次数与安装断言均保留 |

新失败行为用 [跨版本回归](02-regression-before-after.md) 证明原实现不满足。新增测试同时覆盖取消后不可并发新轮、关闭与旧 owner、observer 异常/重入、目录代次、缓存写失败、详情资源分槽/回执/关闭、连接模型覆盖及配置失效、真实首页与管理页切换和路径复制点击。
