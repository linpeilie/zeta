# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Zeta 是 Flutter Desktop 的本地 Agent IDE 壳层（macOS / Windows / Linux）：在持久三栏工作台（Projects / Agent / Files）中连接本地项目目录与 Agent thread，并保留可审计的工具时间线。默认 Provider 为 Codex CLI app-server，另支持 Grok ACP；Cursor 已退役（所有边界 fail-closed，不参与运行时）。

本仓库另有两份权威文档，规则冲突时以它们为准，修改架构边界时必须同步更新：

- `AGENTS.md` — AI 协作规则（工作流、风格、依赖、Git 提交格式）。
- `docs/` — `developer_guide.md`（命令、Provider/事件管线/UI 开发细则）、`engineering_standards.md`（架构评审规范）、`design_document.md`、`codex_app_server_protocol.md`（协议版本锁定流程）。

## 常用命令

```sh
flutter pub get
dart format .          # 编辑 Dart 文件后必跑
flutter analyze        # 结束改动前必跑
flutter test           # 行为变化时必跑；dart_test.yaml 固定并发 2（大 Widget 测试防内存峰值）
flutter run -d macos   # 或 -d windows / -d linux
```

- 单个测试文件：`flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart`。
- Dart SDK 约束 `^3.12.2`；发布 CI（`.github/workflows/release.yml`）使用 Flutter stable 3.44.4。
- Codex 协议升级：先 `./tool/gen_codex_schema.sh --diff`（Windows 用 `.ps1 -Diff`）对比 `third_party/codex_app_server_schema/`（analyzer 已排除），再改适配层；随后跑 `python tool/smoke_codex_app_server.py` 与 `python tool/smoke_codex_plan_mode.py` 真实 CLI 冒烟（详见 developer_guide §3）。

## 架构

feature-sliced + 单向依赖：`main -> app -> presentation/application -> domain`，`app -> data -> domain`，`presentation -> ui/core`。

- `lib/main.dart` 仅做启动（解析 HOME、日志、一次性迁移、窗口初始化、`runApp`）；`lib/src/app` 是唯一装配点（DI、shell controller、把 `~/.zeta` 具体文件注入各 feature store）。
- `lib/src/features/<feature>/{domain,application,data,presentation}`：`agent`（Provider 抽象、事件管线、对话）、`agent_management`（CLI 检测/诊断/配置安全写入）、`ide_session`（会话恢复）、`project_threads`、`settings`、`usage_statistics`、`workspace`。新代码进对应 feature，不要回顶层宽泛目录。
- `lib/src/core` 跨功能基础设施（日志、路径、原子写入）；`lib/src/ui/core` 共享主题与工作台原语。

### Agent 事件管线（核心不变量）

Provider 原始协议只存在于 data 层。流向：provider adapter/mapper → 中立 `AgentEvent` → `AgentEventPipeline`（listener gate → coalescing policy/buffer → bounded dispatcher）→ `AgentConversationEventProcessor`（纯同步 reducer）→ `AgentConversationTimelineStore` → `AgentUiUpdatePort` 类型化 UI 更新。不可违反的规则：

- Provider 的 `sourceItemId/sourceMessageId` 仅作 metadata；entryId、message segment、reasoning phase、去重、终态一律由对应 Provider 的 adapter/reducer 决定。TimelineStore 只按规范化 id dumb merge。
- 共享层（decoder、CoalescingPolicy/Buffer、Pipeline、TimelineStore）禁止出现 Provider import/kind/id 分支或 raw 字段读取；新增 Provider 的正常范围 = 自有 data 文件 + 中立 domain contract + factory 组合 + 契约测试。评审门禁见 developer_guide §7「共享适配层修改判定」。
- live/history/replay 必须使用独立 reducer 实例；reducer 纯同步（无 Flutter scheduler、Timer、Future、外部回调），副作用走 scope-aware EffectRunner。
- 新增/修改 `AgentEvent` 前必须逐项回答 developer_guide §7 的 16 条接入清单并用测试固定。

### Provider 运行时

- `AgentProviderRuntimeRegistry` 统一拥有实例与租约；能力经 `AgentProviderBundle` 可选端口暴露；UI 一律按 capabilities 渲染，不按 provider kind/名称硬编码。未支持能力必须 capability=false 并抛 `UnsupportedError`，不得静默成功。
- 权限 / 用户提问 / Plan 审批是三种独立领域语义，不共享 request/decision 模型。Plan 终态后的「执行确认」是 Zeta 本地 application 工作流：必须新建显式 Default 回合、不预授权命令/文件/网络，与审批模型隔离。
- 模型目录只经 app 级 `AgentModelCatalogRepository`（stale-while-revalidate + single-flight，key 含配置指纹；Codex `model/list` 必须处理完整 cursor 分页，失败不得用空目录覆盖旧缓存）。
- Thread list/read 用 `ProviderOperationScheduler` 的 sharedRead；resume/fork/rename/archive/delete/compact 用 exclusive。

### UI 工作台

- `IdeHome` 是持有 `WindowFrame` + `IdeWorkbenchScaffold` 的唯一组合边界；页面只提供 Navigation/Canvas/Inspector slot 内容，不得替换顶层 workbench。
- 跨页面保活用 `IdeRetainedPageView`（禁止 `IndexedStack` 保留长时间线）；稳定 key 必须挂在可能随 slot 增删换位的 Flex 子节点上。改页面切换行为必须用真实 `IdeHome` 补 Widget 测试，验证 Element、草稿、滚动位置、面板宽度不被重置。
- 主题：shadcn_flutter 只能 `as sf` 导入；语义 token 走 `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)`。禁止 Material `ThemeData`/`ColorScheme.fromSeed`、裸 `Color(0x...)`、手写 `BoxShadow`、临时 `BorderRadius.circular(...)`；通知统一 `showIdeToast`（禁止 feature 里直接 `sf.showToast`）；已退役的 `shadcn_ui` / `Shad*` API 不得回流。
- 时间线保持 `SliverList.builder` + 稳定 viewport item + prepend 锚点修正；流式 turn、代码高亮、diff 区域加 `RepaintBoundary`。禁止 post-frame 测量、`GlobalKey` 查高、layout 后 `setState` 反馈环。

### 持久化

- Zeta 自有数据全部在 `~/.zeta/`（`config/`、`state/`、`logs/`、`cache/`），JSON 必须版本化 + 宽容 `tryDecode`（缺字段/损坏/旧版本不阻断启动）。feature store 不得在 presentation/application 自行构造 `File('~/.zeta/...')`。
- 严禁读取/迁移/改写 `~/.codex`、`~/.grok`、`~/.cursor` 及项目 `.cursor`；遗留 `cursor_sessions.json` 仅受保护保留。旧 SharedPreferences key 只作幂等迁移输入。
- 派生索引与缓存（如 `cache/agent_models_v1.json`）只保存规范化白名单字段；禁止持久化 prompt、回复、工具输出、原始错误文本、环境变量、凭证或 provider raw payload。

### 状态与异步

- 简单状态用 Flutter 内建（`StatefulWidget`、`ValueNotifier`）；复杂状态 = 不可变 domain state + application controller + typed listenable。`AgentConversationViewModel` 不是 `ChangeNotifier`，Widget 只监听所需 state slice 或一次性 effect。
- 可被后续请求覆盖的异步加载必须用 token/version 守卫；乐观持久化分离「当前快照 / 最近确认快照」，保存失败整体回滚。
- `SchedulerBinding` 只允许出现在 presentation 的 `AgentUiUpdateScheduler` 生产适配中。
- 构造函数注入依赖；测试优先 fake/stub 而非 mock，遵循 Arrange/Act/Assert；共享 decoder/Coalescing/TimelineStore 用 Provider 无关 fixture 并配架构守卫测试。

## 代码风格

- 空安全 Dart；优先 `const` 与不可变 Widget；大 build 方法拆私有 Widget 类；文件名 `snake_case.dart`。
- 禁止 `print`；保留的诊断信息用 `dart:developer` 或 `lib/src/core/logging` 封装。
- 公共 API 写 `///` 文档；新代码优先中文注释，尤其协议适配、状态机、错误处理与不直观分支，避免复述代码的空注释。
- 新增依赖前确认 Flutter/Dart 内建方案不足；在最终总结中说明每个新依赖的用途。
- 平台生成目录（linux/macos/windows）的非预期改动，保留前先说明原因。

## 每次代码修改后

1. 运行 `dart format .` → `flutter analyze` →（行为变化时）`flutter test`。
2. 回复末尾必须附【Git 提交信息】模块：Conventional Commits 格式（feat/fix/docs/refactor/chore 等），≤50 字符摘要，独立 `sh` 代码块包裹以便直接 `git commit -m`。格式示例见 `AGENTS.md` 末尾。
