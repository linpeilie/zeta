# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

Zeta 是一个 Flutter Desktop「Agent IDE 壳层」：在常驻的三栏工作台（Projects / Agent / Files）中连接本地项目目录、Agent thread 与可审计的工具执行时间线。目标平台为 macOS、Linux、Windows。活跃 Agent provider 为 **Codex CLI app-server**（默认，JSON-RPC over stdio）与 **Grok ACP**（stdio）；**Cursor 已退役**，不参与任何运行时组合。

仓库权威规则是根目录 `AGENTS.md`（中文），架构细则见 `docs/engineering_standards.md` 与 `docs/developer_guide.md`。本文聚焦可操作命令与需要跨文件理解的大图架构。

## 常用命令

```sh
flutter pub get
dart format .          # 编辑 Dart 后必跑
flutter analyze        # 结束改动前必跑
flutter test           # 修改/新增行为时必跑
flutter test test/src/features/agent/presentation/agent_conversation_widget_test.dart   # 单个测试文件
flutter run -d windows  # 或 macos / linux
```

- 测试镜像 `lib/src` 结构，位于 `test/src`；纯逻辑用单元测试，UI 用 widget test，端到端才用 integration test。测试优先 fake/stub 注入，慎用 mock 包。
- 运行态目录文件（`*_test.dart` 同级或同树）按需复制时，保持与 lib 下一致的路径。
- 性能采样（Windows resize 热路径）必须用 Profile 而非 Debug：`flutter run -d windows --profile`。
- 代码生成（仅当使用 json_serializable 等）：`dart run build_runner build --delete-conflicting-outputs`。
- 升级 Codex CLI / 审计协议时，先用 pinned schema 导出并 diff 再改适配层：

```sh
./tool/gen_codex_schema.sh --diff        # 或 PowerShell: ./tool/gen_codex_schema.ps1 -Diff
```

- 对真实 `codex app-server` 冒烟（输出已脱敏，不得包含业务内容）：

```sh
python tool/smoke_codex_app_server.py --expected-version <version>
python tool/smoke_codex_plan_mode.py --expected-version <version>
```

## 架构

### 分层与依赖方向

`lib/src` 采用 feature-sliced 结构，每个 feature 内部分 `domain / application / data / presentation` 四层：

```
main.dart -> lib/src/app（装配/DI）-> features/*/{presentation,application,data} -> domain
                                      app -> data -> domain
                                      presentation -> ui/core
```

- `main.dart` 只做启动、全局错误日志、窗口初始化和 `runApp`；应用装配全在 `lib/src/app`（`MainApp` 接受测试注入的 store/provider/factory）。
- `core` 放跨 feature 基础设施（日志、`~/.zeta` 路径、原子写入、安全），不依赖具体 feature。
- 依赖方向单向：presentation 消费 controller/view model 的状态与动作，不直接解析 provider 原始协议；application 负责异步编排、恢复、分页、竞态隔离；data 实现协议/存储并把外部 payload 映射成 domain 模型；domain 纯净、不依赖 Flutter/widget/文件系统。新增代码优先进入对应 feature，不要新开顶层宽泛的 `data`/`domain`/`ui` 目录。

### 工作台组合边界

- `IdeHome`（`lib/src/ui/features/ide/views/ide_home.dart`）是主要页面唯一的 Workbench 组合边界：一个常驻 `WindowFrame` + `IdeWorkbenchScaffold`，只切换 **Navigation / Canvas / Inspector** 三个 slot 的内容。首页、设置、Agent 管理、使用统计都只能提供 slot 内容，**不得替换整个 Workbench**。
- Canvas 与 Agent 会话保活使用 `IdeRetainedPageView`（延迟挂载、只布局活动页）；**禁止用 `IndexedStack` 保留长页面/会话**。页面切换必须保护 Agent 状态、草稿、滚动位置、面板宽度与可见性；稳定 Key 挂在会随 slot 增删而换位的 Flex 子节点上。
- `IdeConstraintBucketBuilder` 的稳定回调可跨父级 resize 复用 child；resize 只按布局语义档位更新业务树。

### Agent 事件管线（核心）

```
Provider（Codex app-server JSON-RPC / Grok ACP stdio）
  -> data adapter/mapper（协议细节、source id 兼容、脱敏）
  -> 中立 AgentEvent
  -> CoalescingEventBuffer（有界 keyed 合并）-> BoundedEventDispatcher（FIFO，每 turn 64 事件，Timer.run 让位）
  -> AgentConversationEventProcessor -> AgentConversationReducer（纯同步，无 Timer/Future/外部端口）
  -> TimelineStore（dumb merge）+ 类型化 UI state / ThreadSnapshot -> presentation
```

- 身份规则：Provider 原始 `sourceItemId`/`sourceMessageId` 只作 source metadata；`entryId` 是 Zeta 规范化时间线唯一合并键，由各 Provider 的 **data adapter/reducer** 决定。同一连续条目 delta 复用 entryId，turn 之间即使复用 source id 也必须得到不同 entryId。
- **共享适配层纯度门禁**：`AcpSessionUpdateDecoder`、`AgentEventCoalescingPolicy`、`CoalescingEventBuffer`、`BoundedEventDispatcher`、`AgentConversationTimelineStore`、ViewModel/UI 是 Provider 无关的机制层——禁止 import 具体 Provider、按 providerId/kind/名称分支、或从 raw/source id 猜测 entryId/segment/boundary。新增 Provider 的正常改动只落在 Provider data 层 + 组合边界 + 契约测试，不应改动共享层。
- live / history / replay 复用同一 reducer 算法但必须使用**独立 reducer 实例**，不共享 identity/去重/终态状态。
- UI 更新：application 通过 `AgentUiUpdatePort` 提交 typed request，presentation `AgentUiUpdateScheduler` 用 `SchedulerBinding` 在下一 frame 安全发布；禁止固定毫秒 Timer、post-frame 门闩或 idle task 队列。

### Provider 运行时与能力

- `AgentProviderRuntimeRegistry`（app 组合层）是进程内 Provider 实例与子进程的**唯一所有者**。任何功能（对话、project threads、用量统计、连接检测）只能获取/释放**租约**；`AgentProviderFactory.create` 只允许由注册表调用。配置变化必须先使旧实例/租约失效再创建新实例；窗口关闭等待注册表清理完 Provider 再退出。
- 每个 Provider 通过不可变 `AgentProviderCapabilities` 声明真实能力，presentation 隐藏不支持入口、data/application 执行前仍校验；禁止静默 no-op 降级。`AgentProviderBundle` 是 application/presentation 首选能力边界（conversation、threadCatalog、threadMutations、modelCatalog、planApproval、conversationModes、skills 等可选端口）。
- Thread 操作必须复用 `ProviderOperationScheduler`：变更用 `exclusive`（FIFO），list/read 用 `sharedRead`；禁止同键重入。
- 权限审批 / 结构化用户提问 / 计划审批是**独立领域语义**：`respondToPermission`、`respondToQuestion`（空 map=Skip，仅实现 `AgentQuestionResponseProvider` 的 Provider 支持）、`AgentPlanApprovalPort`。三者可共享 Pending Interaction Dock，但不得复用 request/decision 模型或 registry。
- **Plan 执行确认是 Zeta 本地 application 交接**（`AgentPlanExecutionHandoffController`），不是 Provider 计划审批：只由成功 Plan 终态触发，执行必须新建显式 Default `turn/start`，不预授权命令/文件/网络，不持久化，thread/workspace/provider 或可写性边界变化时清除。
- Conversation mode（Plan/Default）来自 `bundle.conversationModes` 运行时目录，是 thread 粘性、逐 turn 提交的状态；显式 mode 必须冻结进 `AgentTurnConfiguration`。Codex `collaborationMode` JSON 只存在于 data 层。
- 模型目录由 app 级 `AgentModelCatalogRepository` 统一共享：启动只非阻塞预热 active provider，普通读取 stale-while-revalidate + single-flight（fresh 1h / max-stale 7d），single-flight key 含安全配置指纹；缓存持久化到 `~/.zeta/cache/agent_models_v1.json`，只保存规范化白名单字段。Codex `model/list` 必须完整处理 cursor 分页，失败不得用空目录覆盖旧缓存。

### 持久化与数据边界

- Zeta 自有配置/状态/日志/缓存统一在 `~/.zeta`：`config/providers.json`、`state/ide_session.json`、`state/usage_statistics_index.json`、`state/migration_marker.json`、`logs/zeta-YYYY-MM-DD.log`、`cache/agent_models_v1.json`。
- HOME 解析与目录布局在 `core`；presentation/application **不得自行构造 `File('~/.zeta/...')`**，feature store 由 app 注入具体文件。持久化 JSON 必须版本化、`tryDecode` 宽容读取，损坏/旧版本不能阻断启动。
- **严禁**移动、重写或读取 `~/.codex`、`~/.grok`、`~/.cursor`、项目 `.cursor/*` 及用户源码工作区下的 CLI 配置/会话历史。旧 SharedPreferences 只是迁移输入，迁移必须幂等、以目标文件优先、标记写入 `migration_marker.json`。退役遗留的 `cursor_sessions.json` 是受保护用户数据，不读取、不迁移、不改写。

### UI 系统

- 设计系统 = `shadcn_flutter`（固定 `0.0.52`）+ Graphite 语义 token。shadcn_flutter 只能 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`；颜色/字号走 `IdeThemeScope` / `IdeColors.of(context)` / `IdeTextStyles.of(context)`，禁止裸 `Color(0x...)`、手写 `BoxShadow`、临时 `BorderRadius.circular(...)`、Material `ThemeData`/`ColorScheme.fromSeed` 拼装。
- 通知统一 `showIdeToast`（`lib/src/ui/core/ide_toast.dart`），不在 feature 页面散落 `sf.showToast`。
- 新 pane/重复项优先复用 `ui/core` 原语：`Pane`、`PanelCard`、`IdeTabs`/`IdeTab`、`IdeChip`、`IdeContextMenu`、`IdeStatusCard`、`WindowFrame` 等。长路径/标题/工具摘要必须省略号截断。
- 时间线使用稳定 viewport item + `SliverList.builder`，turn grouping / diff / 高亮分别受 render revision / projection cache / `HighlightView` identity 约束；高频区域加 `RepaintBoundary`。

## 其他约定

- 新实现中，公共 API、协议适配、状态机、错误处理和不直观分支优先补充**中文注释**（`///` 或简短行内），但避免只复述代码字面行为的空注释。
- 不使用 `print`；需要保留的诊断用 `dart:developer` 或项目日志封装（`core/logging`）。
- 主题、依赖、导航、测试、仓库卫生等完整约定见 `AGENTS.md`；每次改动结束必须按要求附加【Git 提交信息】模块（Conventional Commits）。
- 可用技能：`.agents/skills/` 下有 dart/flutter 专项技能（widget test、静态分析、路由、本地化、JSON 序列化、响应式布局、shadcn-flutter 组件文档等），处理对应聚焦任务时优先使用。
