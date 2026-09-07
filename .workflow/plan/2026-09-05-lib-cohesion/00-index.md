# 应用状态与命令改造记录

任务日期：2026-09-05—2026-09-06。代码阶段已完成；最终集成和实机验收尚未完成。旧目标设计和伪代码已由现行源码及工程规范替代。

## 阶段证据

以下提交号和测试数来自原阶段登记，不是本次文档清理重新运行的结果。

| 阶段 | 原登记提交 | 验证记录 |
| --- | --- | --- |
| WP-6 会话配置结果 | `8778a8ae` | [定向 54、受影响 925](../../fix/2026-09-05-session-config/00-validation.md) |
| WP-1 管理运行状态 | `ea56f5c9` | [Shell 34、受影响 681](../../fix/2026-09-06-management-runtime/00-validation.md) |
| WP-4 Project Threads 规则 | `11c6d9c8` | [full 根 2007、内部包 1076](../../refactor/2026-09-06-project-threads/00-validation.md) |
| WP-3M 管理状态所有权 | `62a16ed6` | [full 根 2024、内部包 1076](../../refactor/2026-09-06-management-owner/00-validation.md) |
| WP-3P Project Threads 所有权 | `c2a5219d` | [full 根 2047、内部包 1076](../../refactor/2026-09-06-project-threads-owner/00-validation.md) |
| WP-3C Workspace / Conversation | `c2197f76` | [full 根 2060、内部包 1076](../../refactor/2026-09-06-conversation-owner/00-validation.md) |
| WP-2 会话命令 | `16cba246` | [full 根 2087、内部包 1076](../../refactor/2026-09-06-conversation-actions/00-validation.md) |
| WP-5 首页检测 | `d2461d25` | [full 根 2118、内部包 1076](../../refactor/2026-09-06-home-detection/00-validation.md) |

## 现行规则

状态、命令入口与关闭次序见[工程规范 §3](../../../docs/zh/architecture/engineering_standards.md#3-状态与异步编排)。接入和回归清单见[开发者指南](../../../docs/zh/development/developer_guide.md)。阶段记录继续保留断言审计和失败修正，不把旧测试结果改写为当前通过。

## 待完成的集成验收

- [ ] 从生产入口复核六项改造的组合：多 Provider、多会话、后台任务、草稿晋升、关闭重开和迟到结果。
- [ ] 在最终代码基线上执行完整门禁，记录实际命令、提交和结果。
- [ ] 真实 CLI 检测、原生文件管理器打开、macOS 手工退出和 Windows/Linux Profile 验证。
- [ ] 将实测差异归入对应缺陷，不以自动化结果替代平台结果。

统一入口见[未完成事项](../../pending-validation.md)。
