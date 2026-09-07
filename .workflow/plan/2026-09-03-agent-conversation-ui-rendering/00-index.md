# 会话 UI 渲染改造记录

任务日期：2026-09-03。历史计划已收尾，后续状态所有权调整见[应用状态改造](../2026-09-05-lib-cohesion/00-index.md)。本页保留结果和未实施项，不再提供旧代码草稿。

| 阶段 | 原记录状态 | 当前资料 |
| --- | --- | --- |
| WP-1 切片与 ViewModel | 已完成；后续由状态改造继续调整 | [工程规范 §3](../../../docs/zh/architecture/engineering_standards.md#3-状态与异步编排) |
| WP-2 拆分 part-of | 已完成 | 现行源码与 Git 历史 |
| WP-3 renderer 注册表 | 已完成 | [开发者指南](../../../docs/zh/development/developer_guide.md) |
| WP-4 UI 控件复用 | 已完成 | [工程规范 §6](../../../docs/zh/architecture/engineering_standards.md#6-ui-与交互) |
| WP-5 历史分页 | 跳过，未排期；原表的“未开始”不代表已承诺实施 | [评估记录](05-wp5-history-pagination.md) |
| WP-6 Markdown 包 | 已完成；P2 三项跳过 | [决策记录](06-wp6-markdown-vendor.md) |
| WP-7 清理 | 已完成 | Git 历史 |

## 保留的决定

Markdown 使用本地 `zeta_markdown` 包，以注入点提供语法、高亮、工具栏和菜单定制。该包不依赖内部业务包，宿主负责主题和文案映射。维护清单在 [UPSTREAM.md](../../../packages/zeta_markdown/UPSTREAM.md)。

Provider 差异继续在各插件中处理，渲染注册表只消费中立模型。状态的现行发布路径以工程规范为准，旧 Store 与镜像 Notifier 草稿不得用于新增实现。

## 证据与限制

各任务的原始实施和测试记录保留在 Git 历史。本次文档清理没有重新执行这些代码阶段的测试，也不补记实机通过。未实施项和跨阶段验收见[未完成事项](../../pending-validation.md)。
