# Zeta 项目文档

中文 ｜ [English](./README.en.md)

本仓库是 Zeta 的 VGV 架构重写版本。迁移进行中，文档随迁移步骤同步更新。

不知道从哪读起？按你的身份选：

| 你是… | 从这里开始 |
| --- | --- |
| **贡献者**，第一次读代码 | [架构总览](./architecture/overview.md) → [术语表](./guides/glossary.md) |
| **贡献者**，参与迁移 | [迁移拓扑分析](./architecture/migration_topology.md) → [迁移任务清单](./architecture/migration_tasks.md) |
| **贡献者**，已经上手 | [开发者文档](./guides/developer_guide.md) → [工程规范](./architecture/engineering_standards.md) |
| **评估者**，想了解设计取舍 | [产品需求文档](./product/product_requirements.md) → [设计文档](./architecture/design_document.md) |
| **维护者**，要发版 | [发版指南](./release/release_guide.md) |

## 目录结构

```
docs/
├── architecture/   架构总览、分层设计、工程规范、迁移文档
├── guides/         开发者文档、术语表、国际化指南
├── product/        产品需求、故障排查与数据说明
├── protocols/      Provider 协议锁定与适配方案
├── release/        发版流程
├── history/        已退役能力与开发流水，仅存档
└── images/         截图与拍摄清单
```

**每个文档都维护中英两版**：`xxx.md`（中文）与 `xxx.en.md`（英文）。约定见[工程规范](./architecture/engineering_standards.md)。

## architecture — 架构

- [**架构总览**](./architecture/overview.md)（[English](./architecture/overview.en.md)）⭐ — VGV 四层分层、包边界、事件管线、能力协商。新贡献者从这里开始
- [**迁移拓扑分析**](./architecture/migration_topology.md)（[English](./architecture/migration_topology.en.md)）⭐ — 旧仓库模块划分、依赖关系图、P0–P7 迁移 Roadmap
- [**迁移任务清单**](./architecture/migration_tasks.md)（[English](./architecture/migration_tasks.en.md)）⭐ — 34 个步骤的四层类名设计与可勾选任务
- [分层设计](./architecture/layering.md)（[English](./architecture/layering.en.md)）— Data / Repository / Bloc / Presentation 四层职责、注入方式、bloc 作用域
- [设计文档](./architecture/design_document.md)（[English](./architecture/design_document.en.md)）— 完整的运行时组合、UI 骨架与流式适配职责矩阵
- [工程规范](./architecture/engineering_standards.md)（[English](./architecture/engineering_standards.en.md)）— 架构评审规范、CI 门禁、文档双语约定

## guides — 开发

- [开发者文档](./guides/developer_guide.md)（[English](./guides/developer_guide.en.md)）— 环境、命令、包结构、Provider 接入指南、测试细则
- [**术语表**](./guides/glossary.md)（[English](./guides/glossary.en.md)）⭐ — thread / turn / entryId / bundle / capability / coalescing 等高频术语
- [国际化指南](./guides/internationalization.md)（[English](./guides/internationalization.en.md)）— 共享组件文案传参、TextCatalog 抽象、Locale 冻结

## product — 产品

- [产品需求文档](./product/product_requirements.md)（[English](./product/product_requirements.en.md)）— 目标用户、能力范围、明确不做的部分
- [故障排查与数据说明](./product/troubleshooting.md)（[English](./product/troubleshooting.en.md)）— 常见问题、`~/.zeta` 存了什么、清理与重置

## protocols — 协议

- [Codex app-server 协议版本锁定](./protocols/codex_app_server_protocol.md)（[English](./protocols/codex_app_server_protocol.en.md)）
- [Claude Code stream-json 协议基线](./protocols/claude_code_stream_json_protocol.md)（[English](./protocols/claude_code_stream_json_protocol.en.md)）
- [Grok ACP 协议基线](./protocols/grok_acp_protocol.md)（[English](./protocols/grok_acp_protocol.en.md)）

## release — 发布

- [发版指南](./release/release_guide.md)（[English](./release/release_guide.en.md)）— Tag 规则、质量门禁、产物与平台说明

## history — 历史归档

只作为历史证据保留，**不代表当前支持的能力**。

## 仓库根目录的相关文件

- [README](../README.md)（[English](../README.en.md)）
- [贡献指南](../CONTRIBUTING.md)（[English](../CONTRIBUTING.en.md)）
- [更新日志](../CHANGELOG.md)

---

> 迁移期间，本索引中标注但尚未创建的文档会随对应迁移步骤补齐。映射关系见[迁移任务清单 §0.6](./architecture/migration_tasks.md#06-文档约定)。
