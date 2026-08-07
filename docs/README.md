# Zeta 项目文档

不知道从哪读起？按你的身份选：

| 你是… | 从这里开始 |
| --- | --- |
| **用户**，想装上用起来 | [README](../README.md) → [故障排查与数据说明](./product/troubleshooting.md) |
| **贡献者**，第一次读代码 | [架构总览](./architecture/overview.md) → [术语表](./guides/glossary.md) → [贡献指南](../CONTRIBUTING.md) |
| **贡献者**，已经上手 | [开发者文档](./guides/developer_guide.md) → [工程规范](./architecture/engineering_standards.md) |
| **贡献者**，用 AI 辅助开发 | [提示词库](./prompts/README.md) → [日常任务模板](./prompts/daily.md) |
| **评估者**，想了解设计取舍 | [产品需求文档](./product/product_requirements.md) → [设计文档](./architecture/design_document.md) |
| **维护者**，要发版 | [发版指南](./release/release_guide.md) → [更新日志](../CHANGELOG.md) |

## 目录结构

```
docs/
├── architecture/   架构总览、设计文档、工程规范、详细设计
├── guides/         开发者文档、术语表
├── prompts/        AI 辅助开发的提示词模板与开发流程
├── product/        产品需求、故障排查与数据说明（中英）
├── protocols/      Provider 协议锁定与适配方案
├── release/        发版流程
├── history/        已退役能力与开发流水，仅存档
├── reference/      与 Zeta 实现无关的外部资料
└── images/         截图与拍摄清单
```

## architecture — 架构

- [**架构总览**](./architecture/overview.md)（[English](./architecture/overview.en.md)）⭐ — 分层、事件管线、能力协商、三种审批的区别。新贡献者从这里开始
- [设计文档](./architecture/design_document.md) — 完整的分层结构、运行时组合、UI 骨架与流式适配职责矩阵
- [工程规范](./architecture/engineering_standards.md) — 架构评审规范与门禁
- [Agent 桌面通知与任务栏未读提醒详细设计](./architecture/desktop_agent_notification_design.md)

## guides — 开发

- [开发者文档](./guides/developer_guide.md) — 环境、命令、目录结构、Provider 接入指南、UI 与测试细则、常见问题
- [**术语表**](./guides/glossary.md)（[English](./guides/glossary.en.md)）⭐ — thread / turn / entryId / bundle / capability / coalescing / lease 等高频术语
- [贡献指南](../CONTRIBUTING.md)（[English](../CONTRIBUTING.en.md)）— 环境、提交格式、架构红线摘要

## prompts — AI 辅助开发

- [**提示词库**](./prompts/README.md) ⭐ — 三档复杂度判定、三套流程怎么选
- [日常任务提示词](./prompts/daily.md) — 新增功能 / 需求变更 / Bug 修复 / 重构各 3 档，外加平台适配、提交前自审、CI 排查、紧急修复、技术调研
- [功能开发流程](./prompts/workflow.md) — 需求分析 → 方案设计 → 任务拆解 → 实现 → 验收；专项：Provider 接入、AgentEvent 接入、协议升级、持久化格式演进
- [重构流程](./prompts/refactoring.md) — 动机 → 测绘 → 安全网 → 目标态 → 执行 → 等价性验收，含重构分型与 Zeta 陷阱表
- [性能优化流程](./prompts/performance.md) — 基线 → 归因 → 改动 → 同基线复测 → 固化，含项目性能指标与回归排查
- [可拼接片段](./prompts/snippets.md) — 约束尾缀、测试尾缀、输出格式约定、反模式禁令

## product — 产品

- [产品需求文档](./product/product_requirements.md) — 目标用户、能力范围、用户流程、明确不做的部分
- [故障排查与数据说明](./product/troubleshooting.md)（[English](./product/troubleshooting.en.md)）— 常见问题、`~/.zeta` 存了什么、清理与重置

## protocols — 协议

- [Codex app-server 协议版本锁定](./protocols/codex_app_server_protocol.md) — 协议 pin 与升级流程
- [Claude Code Provider 适配方案](./protocols/claude_code_provider_adapter.md) — ⚠️ **提案，尚未实现**，当前版本不支持 Claude Code

## release — 发布

- [发版指南](./release/release_guide.md) — Tag 规则、质量门禁、产物与平台说明

## history — 历史归档

只作为历史证据保留，**不代表当前支持的能力**：

- [Cursor Agent 退役历史说明](./history/cursor_agent_guide.md) — Cursor 已退役，运行时不参与
- [Cursor ACP 历史发布门禁](./history/cursor_acp_release_validation.md)
- [开发记录](./history/development_log.md) — 按时间倒序的开发流水
- [项目记忆](./history/project_memory.md) — 跨任务保留的项目事实与决策

## reference — 外部参考

与 Zeta 实现无直接关系，仅作 Flutter 开发参考：

- [Flutter Create with AI 中文整理](./reference/flutter_ai_create_with_ai_zh.md)
- [Flutter AI 开发体验实践指南](./reference/flutter_ai_developer_experience_zh.md)

## 仓库根目录的相关文件

- [更新日志](../CHANGELOG.md) — 用户可感知的版本变化
- [贡献指南](../CONTRIBUTING.md)（[English](../CONTRIBUTING.en.md)）
- [安全策略](../SECURITY.md) — 威胁模型与漏洞上报方式（中英同页）
- [行为准则](../CODE_OF_CONDUCT.md)（中英同页）
- [AGENTS.md](../AGENTS.md) — AI 协作规则的唯一权威源
- [.workflow/](../.workflow/README.md) — 开发过程产物（各流程的阶段输出，随代码提交）

---

> 文档以中文为主。README、贡献指南、故障排查、架构总览与术语表提供英文版本。
> 部分历史文档引用的 `plan/` 目录已被移除，相关内容只存于 Git 历史。
