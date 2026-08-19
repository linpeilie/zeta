# CLAUDE.md

本文件是**入口卡片**，不承载规则正文。规则只在一处维护，避免多份副本互相漂移。

## 项目一句话

Zeta 是 Flutter Desktop 的本地 Agent IDE 壳层（macOS / Windows / Linux）：在持久三栏工作台（Projects / Agent / Files）中连接本地项目目录与 Agent thread，并保留可审计的工具时间线。默认 Provider 为 Codex CLI app-server，另支持 Grok ACP 与 Claude Code stream-json；Cursor 已彻底清退。

## 动手前先读

1. **[`AGENTS.md`](AGENTS.md)** — 约束规则的**权威源**：8 条硬门禁、按任务的路由表、风格约定、收尾协议。**动手前完整读一遍**，然后按 §2 路由表对号入座，找到你这次要动的东西对应哪几条门禁和哪些必读文档。
2. **[`docs/architecture/overview.md`](docs/architecture/overview.md)** — 架构总览（含图），解释这些约束**为什么**存在。
3. **[`docs/guides/glossary.md`](docs/guides/glossary.md)** — 术语表。遇到 entryId、bundle、capability、coalescing、lease 先查这里。

规则冲突时的优先级：`AGENTS.md` > `docs/architecture/engineering_standards.md` > `docs/guides/developer_guide.md` > 本文件。

## 八条硬门禁（标题索引，正文在 [`AGENTS.md` §1](AGENTS.md#1-硬门禁)）

违反任何一条，功能再正确也要打回。**不要凭这份索引下判断——动到相关代码就去读正文。**

| ID | 门禁 |
|----|------|
| G1 | 共享适配层零 Provider 依赖（Pipeline / CoalescingPolicy / Buffer / Dispatcher / TimelineStore / 共享 ACP mapper） |
| G2 | 身份由 Provider adapter/reducer 决定，`sourceItemId` 只是 metadata，Store 只 dumb merge |
| G3 | reducer 纯同步；副作用走 EffectRunner；live/history/replay 用独立实例 |
| G4 | 按 capability 渲染；不支持必须 `capability = false` + 抛 `UnsupportedError`，禁止静默成功 |
| G5 | 权限 / 提问 / Plan 审批 / Plan 执行交接四种语义隔离；**绝不预授权任何操作** |
| G6 | 分层依赖单向；Provider 协议只存在于 data 层；新代码进对应 feature 的四层目录 |
| G7 | 不落盘敏感内容；持久化 JSON 版本化 + 宽容解码 |
| G8 | 主题走 token；`shadcn_flutter` 只能 `as sf` 导入 |

## 常用命令

```sh
flutter pub get
dart format .          # 编辑 Dart 文件后必跑
flutter analyze        # 结束改动前必跑
flutter test           # 行为变化时必跑；dart_test.yaml 固定并发 2，不要改
flutter run -d macos   # 或 -d windows / -d linux
```

单个测试文件：`flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart`

Codex 协议升级、真实 CLI 冒烟的完整流程见 [`AGENTS.md` §2](AGENTS.md#codex-协议升级流程)。

## 每次改完代码

`dart format .` → `flutter analyze` →（行为变化时）`flutter test`，然后在回复末尾附【Git 提交信息】模块。完整格式与示例见 [`AGENTS.md` §0](AGENTS.md#0-收尾协议每次改完代码必做)。

## 定位代码

仓库已由 CodeGraph 索引，优先用 `codegraph explore "<问题或符号名>"`（或 `codegraph_explore` MCP 工具），比 grep + 逐个读文件省一个数量级的往返。

## 改了架构边界

分层、Provider 契约、事件管线、能力协商或持久化格式有变动时，`AGENTS.md`、`docs/architecture/`、`docs/guides/` 和 `CONTRIBUTING.md`（含英文版）要一起改。清单见 [`AGENTS.md` §6](AGENTS.md#6-改了架构边界同步这几处)。
