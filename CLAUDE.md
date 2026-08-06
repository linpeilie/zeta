# CLAUDE.md

本文件是**索引**，不是规则正文。规则只在一处维护，避免多份副本互相漂移。

## 开始工作前先读

1. **[`AGENTS.md`](AGENTS.md)** — AI 协作规则的**唯一权威源**：工作流、代码风格、架构约束、依赖、UI、测试、提交格式。动手前请完整读一遍。
2. **[`docs/architecture/overview.md`](docs/architecture/overview.md)** — 架构总览（含图），解释这些约束**为什么**存在。
3. **[`docs/guides/glossary.md`](docs/guides/glossary.md)** — 术语表。遇到 entryId、bundle、capability、coalescing、lease 这类词先查这里。

规则冲突时的优先级：`AGENTS.md` > `docs/architecture/engineering_standards.md` > `docs/guides/developer_guide.md` > 本文件。

## 项目一句话

Zeta 是 Flutter Desktop 的本地 Agent IDE 壳层（macOS / Windows / Linux）：在持久三栏工作台（Projects / Agent / Files）中连接本地项目目录与 Agent thread，并保留可审计的工具时间线。默认 Provider 为 Codex CLI app-server，另支持 Grok ACP；Cursor 已退役（所有边界 fail-closed，不参与运行时）。

## 常用命令

```sh
flutter pub get
dart format .          # 编辑 Dart 文件后必跑
flutter analyze        # 结束改动前必跑
flutter test           # 行为变化时必跑；dart_test.yaml 固定并发 2，不要改
flutter run -d macos   # 或 -d windows / -d linux
```

单个测试文件：`flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart`

Codex 协议升级：先 `./tool/gen_codex_schema.sh --diff`（Windows 用 `.ps1 -Diff`）对比 `third_party/codex_app_server_schema/`，再改适配层；随后跑 `python tool/smoke_codex_app_server.py` 与 `python tool/smoke_codex_plan_mode.py` 真实 CLI 冒烟。详见 `docs/guides/developer_guide.md` §3。

## 绝不可违反的不变量

完整规则见 `AGENTS.md`。以下几条即使不读其他文档也必须守住，因为违反后果最严重：

- **Provider 协议只存在于 data 层。** 共享层（decoder、CoalescingPolicy/Buffer、Pipeline、TimelineStore）禁止出现 Provider import、kind/id 分支或 raw 字段读取。
- **`sourceItemId` / `sourceMessageId` 只是 metadata。** entryId、message segment、reasoning phase、去重与终态由对应 Provider 的 adapter/reducer 决定，TimelineStore 只按规范化 id dumb merge。
- **reducer 纯同步。** 无 Flutter scheduler、Timer、Future、外部回调；副作用走 scope-aware EffectRunner。live/history/replay 使用独立 reducer 实例。
- **UI 按 capability 渲染。** 不按 provider kind/名称硬编码；未支持能力必须 `capability = false` 并抛 `UnsupportedError`，不得静默成功。
- **不预授权任何操作。** 权限 / 提问 / Plan 审批是三种独立领域语义；Plan 终态后的执行确认是 Zeta 本地工作流，必须新建显式 Default 回合。
- **不碰其他 CLI 的私有数据。** 严禁读取、迁移或改写 `~/.codex`、`~/.grok`、`~/.cursor` 及项目 `.cursor`。
- **不落盘敏感内容。** 派生索引与缓存只存白名单字段；禁止持久化 prompt、回复、工具输出、原始错误文本、环境变量、凭证或 Provider raw payload。
- **主题走 token。** `shadcn_flutter` 只能 `as sf` 导入；禁止 Material `ThemeData`、裸 `Color(0x...)`、手写 `BoxShadow`、临时 `BorderRadius.circular(...)`。
- **新增/修改 `AgentEvent` 前**，必须逐项回答 `docs/guides/developer_guide.md` §7 的 16 条接入清单并用测试固定。

## 每次代码修改后

1. 运行 `dart format .` → `flutter analyze` →（行为变化时）`flutter test`。
2. 回复末尾必须附【Git 提交信息】模块：Conventional Commits 格式，≤50 字符摘要，独立 `sh` 代码块包裹以便直接 `git commit -m`。格式示例见 `AGENTS.md` 末尾。

## 改了架构边界，记得同步文档

改动涉及分层、Provider 契约、事件管线或持久化格式时，同步更新 `AGENTS.md` 与 `docs/architecture/`、`docs/guides/` 下的相关文档。**面向人类贡献者的规则摘要在 `CONTRIBUTING.md`，也要跟着改。**
