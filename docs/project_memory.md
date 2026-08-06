# 项目记忆

最后更新：2026-07-17

本文记录跨任务应长期保留的项目事实、决策和约束。后续开发中，如果事实变化，应同步更新本文。

## 1. 项目身份

- 项目名：Zeta。
- 类型：Flutter Desktop 本地应用。
- 当前产品定位：本地 AI IDE 壳层，核心是项目上下文、Agent thread 和可审计对话时间线。
- 入口文件：`lib/main.dart`。
- 当前活跃 Provider 为 Codex 与 Grok；Cursor 已退役，Codex 保持默认 active provider。

## 2. 当前技术栈

- Flutter + Dart。
- `shadcn_flutter: 0.0.52` + 自建 Graphite 设计 token（深浅双主题）；
  token 真源是 `IdeThemeScope`，第三方 theme 只做投影。
- `multi_split_view` 用于三栏可调整布局。
- `flutter_treeview` 用于文件树。
- `window_manager` 用于桌面窗口体验（隐藏原生标题栏、自定义标题栏）。
- macOS 原生「文件 - 打开项目」菜单通过 `zeta/menu` MethodChannel 桥接到 Flutter。
- `file_selector` 用于选择本地目录。
- `shared_preferences` 仅用于读取旧版 Zeta key 并一次性迁移。
- Zeta 自有配置、会话状态与派生索引使用 `~/.zeta` 下的版本化 JSON 文件。
- 统一 `AppLogger` 同时输出 developer 日志与
  `~/.zeta/logs/zeta-YYYY-MM-DD.log`，业务代码通过 `loggerFor(scope)` 获取实例。

## 3. 架构决策

- 保持轻量 feature-sliced 分层，不提前引入大型架构框架。
- feature 内按 domain、application、data、presentation 拆分；新功能优先进入对应 feature。
- UI / Application 依赖 domain 层的 Agent 抽象、`AgentProviderBundle` 和
  `AgentProviderCapabilities`，不直接处理 provider 原始协议。
- data 层负责把 provider 协议映射成中立领域事件。
- Agent 上下文当前只传项目路径和当前文件路径，不自动读取文件内容；用户可附加本地图片（`localImage`）。
- 默认 Codex 审批策略保持 `on-request`，不自动授权命令或文件修改。
- Cursor 因缺少可验证的稳定协议契约而退役；旧接入计划、synthetic fixture 与发布门禁
  只作为历史证据保留，不代表当前支持。
- 文件树采用懒加载，不递归扫描整个仓库。
- 会话恢复必须宽容失败，不能阻断应用启动。
- `core` 统一解析 `~/.zeta` 与原子写入，feature data store 接收 app 注入的文件；
  迁移器不得访问或改写 Agent CLI 自有配置和 session 历史。

## 4. 重要模块记忆

- `MainApp` 支持测试注入目录选择器、会话存储和 Agent provider factory。
- `IdeShellController` 协调项目选择、文件树状态、会话恢复、Agent workspace 同步和项目 thread 控制器；
  将各 workspace entry 的 `threadSnapshot` 同步到 `ProjectThreadsController`。
- `IdeHome` 组合三栏 UI，保持页面层职责轻量。
- `AgentConversationViewModel` 对外暴露 Agent 面板状态，并委托 timeline store、UI signals、model selection controller 处理细分职责；
  `_publishUiChanges` / `_flushStreamChangesNow` 均须刷新 `threadSnapshotListenable`。
- `ProjectThreadsController` 负责项目下 thread 分页、恢复、缓存快照、provider 交互和竞态隔离；
  打开中 thread 的 busy 态以 `syncRuntimeSnapshot` 为准。
- `ProjectThreadsViewModel` 是项目 thread 列表的纯状态容器（含 `runningThreadIds` /
  `completedThreadIds` 与 sticky active 收束）。
- 当前迁移期内，`AgentProviderBundle` 是应用层能力入口，`AgentProvider` 是 provider
  中立兼容门面；capabilities 仍是入口显隐和执行校验的事实来源。
- `CodexAppServerAgentProvider` 是当前默认 provider 实现；协议 pin 见 `third_party/codex_app_server_schema`。
- `CursorRetirementPolicy` 保留旧配置 decode、unavailable 展示和内存 fallback；catalog、
  factory、deep link、恢复和管理路径均不得创建 Cursor 运行时。
- `JsonRpcPeer` 负责 stdio JSON-RPC 通信。
- `IdeSessionState` 当前版本为 2。
- Agent 时间线已消费流式 reasoning/plan、回合 diff、waiting 状态、系统提示与本地图片气泡。

## 5. 开发约束

- Dart 改动后运行 `dart format .`。
- 结束代码变更前运行 `flutter analyze`。
- 修改行为或新增逻辑时运行 `flutter test`。
- 新公共 API、协议适配、状态机和错误处理优先写中文 `///` 注释。
- 异步分页、恢复和流式输出应使用 token/version、分区 listenable 或节流信号隔离竞态与重建范围。
- 不提交 build 输出和 `.dart_tool`。
- 平台目录改动需要确认来源，不能无解释保留意外生成变更。

## 6. 设计约束

- 这是工具型桌面应用，界面应保持克制、密集、可扫描。
- 避免把功能做成营销页或装饰性布局。
- 三栏职责要清晰：Projects 管项目和 threads，Agent 管对话，Files 管文件上下文。
- 非文本按钮需要 tooltip。
- 文件和项目路径展示必须考虑超长文本省略。

## 7. 风险点

- Codex app-server 协议变化可能导致 provider 映射失效；升级前先用
  `tool/gen_codex_schema.* --diff` 对照 `third_party/codex_app_server_schema`
  （流程见 `docs/codex_app_server_protocol.md`）。
- JSON-RPC stdio 的请求、通知和服务端 request 处理需要保持严格测试覆盖。
- Cursor 重新接入必须另立方案并重新采集真实协议 fixture；不得复用退役前的 synthetic
  fixture 推断协议语义。
- 会话恢复涉及真实文件系统，路径不存在和权限失败必须被宽容处理。
- Agent 运行中切换 thread 容易造成状态竞争，需要继续用 token 或状态检查隔离旧结果。
- 文件树如果误改为递归扫描，会显著影响大型项目打开性能。

## 8. 待确认方向

- 是否引入内置文件预览或编辑器。
- 是否在具备独立方案和真实协议证据后重新评估 Cursor 支持。
- 是否支持多个项目并行 Agent session。
- 是否需要审计和导出 Agent 执行记录。
- 是否需要跨设备同步项目会话。
