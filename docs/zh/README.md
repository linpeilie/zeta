# Zeta 项目文档

中文 ｜ [English](../en/README.md)

本仓库是 Zeta 的 VGV 架构重写版本。迁移进行中，文档随迁移步骤同步更新。

不知道从哪读起？按你的身份选：

| 你是… | 从这里开始 |
| --- | --- |
| **贡献者**，第一次读代码 | [架构总览](./architecture/overview.md) → [术语表](./guides/glossary.md) |
| **贡献者**，参与迁移 | [迁移拓扑分析](./architecture/migration_topology.md) → [迁移任务清单](./architecture/migration_tasks.md) → [逐文件清单](./architecture/migration_manifest.md) |
| **贡献者**，要动某个旧类 | [归属映射表](./architecture/ownership_map.md) |
| **贡献者**，要写某个包 | [包 API 契约](./architecture/package_api_contracts.md) |
| **贡献者**，要接 Provider | [协议文档](#protocols--协议) |
| **贡献者**，已经上手 | [开发者文档](./guides/developer_guide.md) → [工程规范](./architecture/engineering_standards.md) |
| **评估者**，想了解设计取舍 | [产品需求文档](./product/product_requirements.md) → [设计文档](./architecture/design_document.md) |
| **维护者**，要发版 | [发版指南](./release/release_guide.md) |

## 目录结构

`docs/` 按语言分为两棵树，**子目录结构与文件名完全一致**，语言由所在目录决定：

```
docs/
├── README.md               语言入口
├── zh/                     ← 你在这里
│   ├── README.md
│   ├── architecture/       架构总览、分层设计、工程规范、迁移文档   ✅
│   ├── protocols/          Provider 协议基线                      ✅
│   ├── history/            已退役能力与开发流水，仅存档              ✅
│   ├── guides/             开发者文档、术语表、国际化指南             ⏳
│   ├── product/            产品需求、故障排查与数据说明              ⏳
│   ├── release/            发版流程                              ⏳
│   └── images/             截图与拍摄清单                          ⏳
└── en/                     English —— 同名子目录、同名文件
```

✅ 已存在　⏳ 随对应迁移步骤创建（Git 不跟踪空目录，因此现在还看不到）。

**文件名不带语言后缀。** 新增文档必须**同时**在 `zh/` 与 `en/` 下创建同名文件，并在同一个提交里更新。
约定见[工程规范](./architecture/engineering_standards.md)。

唯一例外是 `history/`——归档文档保持原语言不补译，另一侧只放指向它的说明。

### 当前已存在的文档

迁移进行中，下方索引里标注但尚未创建的文档会随对应迁移步骤补齐。已经可用的是：

| 文档 | 用途 |
| --- | --- |
| [迁移拓扑分析](./architecture/migration_topology.md) | 边界、分层判定规则、目标包拓扑、门禁、Roadmap |
| [迁移任务清单](./architecture/migration_tasks.md) | 37 个可勾选步骤与每步完成定义 |
| [逐文件清单](./architecture/migration_manifest.md) | 1,512 个文件的 source→target 归类 |
| [归属映射表](./architecture/ownership_map.md) | 旧类逐个裁决到四层中的哪一层 |
| [包 API 契约](./architecture/package_api_contracts.md) | barrel 导出与接口签名 |
| [会话状态设计](./architecture/agent_conversation_state_design.md) | `AgentConversationBloc` 字段级设计 |
| [三份协议基线 + Token 计量](#protocols--协议) | Provider 适配依据 |

## architecture — 架构

- [**架构总览**](./architecture/overview.md)（[English](../en/architecture/overview.md)）⭐ — VGV 四层分层、包边界、事件管线、能力协商。新贡献者从这里开始
- [**迁移拓扑分析**](./architecture/migration_topology.md)（[English](../en/architecture/migration_topology.md)）⭐ — 旧仓库模块划分、依赖关系图、P0–P7 迁移 Roadmap
- [**迁移任务清单**](./architecture/migration_tasks.md)（[English](../en/architecture/migration_tasks.md)）⭐ — P-1 到 P8 共 37 个步骤的可勾选任务与每步完成定义
- [**逐文件清单**](./architecture/migration_manifest.md)（[English](../en/architecture/migration_manifest.md)）⭐ — 旧仓库 1,512 个跟踪文件的 source→target 归类，每个恰好一次
- [**归属映射表**](./architecture/ownership_map.md)（[English](../en/architecture/ownership_map.md)）⭐ — 旧 Controller/Store/Service 逐个裁决到 Data/Repository/Bloc/Presentation；24 处 `ChangeNotifier` 的去向
- [**包 API 契约**](./architecture/package_api_contracts.md)（[English](../en/architecture/package_api_contracts.md)）⭐ — 每个包的 barrel 导出与关键接口签名；P2 三方并行的前提
- [**会话状态设计**](./architecture/agent_conversation_state_design.md)（[English](../en/architecture/agent_conversation_state_design.md)）⭐ — `AgentConversationBloc` 五个 slice 的字段级设计、Event 清单与缓存归属
- [分层设计](./architecture/layering.md)（[English](../en/architecture/layering.md)）— Data / Repository / Bloc / Presentation 四层职责、注入方式、bloc 作用域
- [设计文档](./architecture/design_document.md)（[English](../en/architecture/design_document.md)）— 完整的运行时组合、UI 骨架与流式适配职责矩阵
- [工程规范](./architecture/engineering_standards.md)（[English](../en/architecture/engineering_standards.md)）— 架构评审规范、CI 门禁、文档双语约定

## guides — 开发

- [开发者文档](./guides/developer_guide.md)（[English](../en/guides/developer_guide.md)）— 环境、命令、包结构、Provider 接入指南、测试细则
- [**术语表**](./guides/glossary.md)（[English](../en/guides/glossary.md)）⭐ — thread / turn / entryId / bundle / capability / coalescing 等高频术语
- [国际化指南](./guides/internationalization.md)（[English](../en/guides/internationalization.md)）— 共享组件文案传参、TextCatalog 抽象、Locale 冻结

## product — 产品

- [产品需求文档](./product/product_requirements.md)（[English](../en/product/product_requirements.md)）— 目标用户、能力范围、明确不做的部分
- [故障排查与数据说明](./product/troubleshooting.md)（[English](../en/product/troubleshooting.md)）— 常见问题、`~/.zeta` 存了什么、清理与重置

## protocols — 协议

三份 Provider 协议基线是对应 Data 包的实现依据，接 Provider 前必读。

- [Codex app-server 协议版本锁定](./protocols/codex_app_server_protocol.md)（[English](../en/protocols/codex_app_server_protocol.md)）— pin 到 CLI `0.144.5`；schema 快照、双基线与 Plan experimental 降级 → `packages/codex_app_server_client`
- [Claude Code stream-json 协议基线](./protocols/claude_code_stream_json_protocol.md)（[English](../en/protocols/claude_code_stream_json_protocol.md)）— 进程参数、帧形状、身份与终态、模型目录、套餐额度 → `packages/claude_code_client`
- [Grok ACP 协议基线](./protocols/grok_acp_protocol.md)（[English](../en/protocols/grok_acp_protocol.md)）— ACP 方法、`_x.ai/` 扩展、12 种 sessionUpdate、权限模式 → `packages/grok_acp_client`
- [Claude Code Token 计量机制](./protocols/claude_code_token_metering.md)（[English](../en/protocols/claude_code_token_metering.md)）— 三层计量口径与 Zeta 对照；实现 usage 映射前必读

## release — 发布

- [发版指南](./release/release_guide.md)（[English](../en/release/release_guide.md)）— Tag 规则、质量门禁、产物与平台说明

## history — 历史归档

只作为历史证据保留，**不代表当前支持的能力**。按约定保持原语言，不补译；`docs/en/history/` 只放指向这里的说明。

- [Claude Code Provider 接入适配文档（历史提案）](./history/claude_code_provider_adapter.md) — 接入前的设计取舍与备选方案。§2 接入契约、§4 Data 层设计要点、§6 语义映射详解仍是 `packages/claude_code_client` 的设计输入；文中的旧仓库路径与类名不要照抄

## 仓库根目录的相关文件

- [README](../../README.md)（[English](../../README.en.md)）
- [贡献指南](../../CONTRIBUTING.md)（[English](../../CONTRIBUTING.en.md)）
- [更新日志](../../CHANGELOG.md)

---

> 迁移期间，本索引中标注但尚未创建的文档会随对应迁移步骤补齐；映射关系见[逐文件清单 §11](./architecture/migration_manifest.md)。
> 双语目录约定见[任务清单 §1.9](./architecture/migration_tasks.md)，由[步骤 36](./architecture/migration_tasks.md) 断言。
