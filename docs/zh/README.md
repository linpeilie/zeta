# Zeta 中文文档

中文 ｜ [English](../en/README.md)

Zeta 是一个桌面应用，把命令行 AI 编码助手接进一个能看清、能管住的工作台。

## 按身份选起点

| 你是… | 从这里开始 |
| --- | --- |
| **用户**，想装上用起来 | [安装与上手](guide/getting-started.md) → [界面导览](guide/workbench.md) → [审批、提问与计划](guide/approvals.md) |
| **贡献者**，第一次读代码 | [架构总览](architecture/overview.md) → [术语表](development/glossary.md) → [贡献指南](../../CONTRIBUTING.md) |
| **贡献者**，已经上手 | [开发者文档](development/developer_guide.md) → [工程规范](architecture/engineering_standards.md) |
| **评估者**，想了解设计取舍 | [产品需求](product/product_requirements.md) → [设计文档](architecture/design_document.md) |
| **维护者**，要发版 | [发版指南](release/release_guide.md) → [更新日志](../../CHANGELOG.md) |

## guide — 使用指南

面向使用者，不含实现细节。

| 文档 | 内容 |
| --- | --- |
| [安装与上手](guide/getting-started.md) | 系统要求、下载安装、第一次启动、打开项目、第一条消息 |
| [界面导览](guide/workbench.md) | 标题栏、项目与会话列表、对话区、文件树、窄窗口 |
| [对话与时间线](guide/conversations.md) | 时间线读法、输入框、选模型、取消回合、编辑消息与分叉、压缩上下文 |
| [审批、提问与计划](guide/approvals.md) | 权限卡片、权限模式、AI 提问、计划模式与执行确认 |
| [连接 AI 助手](guide/agents.md) | 支持哪些助手、各自支持到什么程度、Agent 管理页、检测与连接测试 |
| [通知与提醒](guide/notifications.md) | 什么时候通知、通知里有什么、开关在哪 |
| [使用统计](guide/usage-statistics.md) | 数据来源、统计口径、筛选与详情、套餐额度 |
| [设置](guide/settings.md) | 常规与外观的每一项设置 |
| [数据与隐私](guide/data-and-privacy.md) | Zeta 存了什么、读了什么、怎么清理 |
| [故障排查](guide/troubleshooting.md) | 按现象查问题 |

## architecture — 架构

- [架构总览](architecture/overview.md) — 分层、事件管线、能力协商、三种审批的区别。新贡献者从这里开始
- [设计文档](architecture/design_document.md) — 完整分层结构、运行时组合、UI 骨架与流式适配职责矩阵
- [工程规范](architecture/engineering_standards.md) — 架构评审规范与门禁
- [Agent 桌面通知与任务栏未读提醒详细设计](architecture/desktop_agent_notification_design.md)

## development — 开发

- [开发者文档](development/developer_guide.md) — 环境、命令、目录结构、Provider 接入、UI 与测试细则
- [术语表](development/glossary.md) — thread / turn / entryId / bundle / capability / coalescing / lease 等高频术语

## product — 产品

- [产品需求文档](product/product_requirements.md) — 目标用户、能力范围、用户流程、明确不做的部分

## protocols — 协议

- [Codex app-server 协议版本锁定](protocols/codex_app_server_protocol.md) — 协议 pin 与升级流程
- [Claude Code stream-json 协议基线](protocols/claude_code_stream_json_protocol.md) — 当前实现、取样版本、wire 边界与升级门禁
- [Claude Code Token 计量](protocols/claude_code_token_metering.md) — 用量口径与数据来源
- [Claude Code Provider 适配方案](protocols/claude_code_provider_adapter.md) — 历史设计提案；其中已否决的模型 REST / 静态目录方案不代表当前实现

## release — 发布

- [发版指南](release/release_guide.md) — Tag 规则、质量门禁、产物与平台说明

## history — 历史归档

只作为历史证据保留，**不代表当前支持的能力**：

- [Cursor Agent 退役历史说明](history/cursor_agent_guide.md)
- [Cursor ACP 历史发布门禁](history/cursor_acp_release_validation.md)
- [开发记录](history/development_log.md) — 按时间倒序的开发流水
- [项目记忆](history/project_memory.md) — 跨任务保留的项目事实与决策

## 仓库根目录

- [更新日志](../../CHANGELOG.md) — 每个版本用户能感知到的变化
- [贡献指南](../../CONTRIBUTING.md) — 环境、提交格式与架构红线
- [安全策略](../../SECURITY.md) — 威胁模型与漏洞上报方式
- [行为准则](../../CODE_OF_CONDUCT.md)
- [AGENTS.md](../../AGENTS.md) — AI 协作规则的唯一权威源

## 英文版进度

`docs/en/` 与本目录结构一一对应。已完成英文版：

- `guide/` 全部 10 篇
- `architecture/overview.md`
- `development/glossary.md`
- `product/product_requirements.md`
- `release/release_guide.md`
- `history/` 全部 4 篇
- `protocols/codex_app_server_protocol.md`

尚未翻译（英文树中暂缺，请阅读中文版）：

| 文档 | 中文篇幅 |
| --- | --- |
| `development/developer_guide.md` | 约 67 KB |
| `architecture/design_document.md` | 约 60 KB |
| `architecture/engineering_standards.md` | 约 52 KB |
| `protocols/claude_code_provider_adapter.md` | 约 66 KB |
| `protocols/claude_code_stream_json_protocol.md` | 约 19 KB |
| `protocols/claude_code_token_metering.md` | 约 15 KB |
| `architecture/desktop_agent_notification_design.md` | 约 13 KB |
