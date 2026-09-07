# 工作记录

现行开发规则见 [AGENTS.md](../AGENTS.md) 和[工程规范](../docs/zh/architecture/engineering_standards.md)。这里保存任务决定、提交、验证证据和未完成事项。

优先查看[未完成事项](pending-validation.md)。历史记录中的“已完成”只适用于该次明确写出的范围，不代表后续版本或全部平台已通过。

## 改造索引

- [会话 UI 渲染](plan/2026-09-03-agent-conversation-ui-rendering/00-index.md)
- [Provider 插件拆包](plan/2026-09-04-provider-plugin-packages/00-index.md)
- [应用状态与命令](plan/2026-09-05-lib-cohesion/00-index.md)

## 验证与审计

| 日期 | 任务 | 记录 |
| --- | --- | --- |
| 2026-09-05 | Claude 凭据读取 | [验证](feature/2026-09-05-claude-credentials/00-validation.md) |
| 2026-09-05 | Claude 登录续期 | [验证](feature/2026-09-05-claude-token-refresh/00-validation.md)、[写回诊断](feature/2026-09-05-claude-token-refresh/01-persistence-diagnosis.md) |
| 2026-09-05 | 会话配置 | [验证](fix/2026-09-05-session-config/00-validation.md) |
| 2026-09-04—05 | Provider 插件拆包 | [协议迁移](plan/2026-09-04-provider-plugin-packages/06-wpc-validation.md)、[应用贡献](plan/2026-09-04-provider-plugin-packages/07-wpd-validation.md)、[隔离与 CI](plan/2026-09-04-provider-plugin-packages/08-wpe-validation.md) |
| 2026-09-05 | Provider 图标 | [验证](refactor/2026-09-05-provider-package-icons/00-validation.md) |
| 2026-09-06 | 管理运行摘要 | [验证](fix/2026-09-06-management-runtime/00-validation.md) |
| 2026-09-06 | 会话命令 | [验证](refactor/2026-09-06-conversation-actions/00-validation.md)、[断言审计](refactor/2026-09-06-conversation-actions/01-assertion-audit.md) |
| 2026-09-06 | 会话状态所有权 | [验证](refactor/2026-09-06-conversation-owner/00-validation.md) |
| 2026-09-06 | 首页检测 | [验证](refactor/2026-09-06-home-detection/00-validation.md)、[断言审计](refactor/2026-09-06-home-detection/01-assertion-audit.md)、[前后回归](refactor/2026-09-06-home-detection/02-regression-before-after.md) |
| 2026-09-06 | 管理状态所有权 | [验证](refactor/2026-09-06-management-owner/00-validation.md) |
| 2026-09-06 | 项目会话列表 | [同步逻辑](refactor/2026-09-06-project-threads/00-validation.md)、[状态所有权](refactor/2026-09-06-project-threads-owner/00-validation.md) |
| 2026-09-07 | 文档整理 | [清理与自查](maintenance/2026-09-07-documentation/00-validation.md) |

## 维护方式

新任务按 `.workflow/<类型>/<日期>-<任务>/` 记录。只写结论、依据和实际结果，复杂断言审计可单独保留。任务结束后删除被现行文档替代的草稿和重复代码，不删除尚未解决的差异；旧过程可通过 Git 查阅。
