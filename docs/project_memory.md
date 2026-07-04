# 项目记忆

最后更新：2026-07-04

本文记录跨任务应长期保留的项目事实、决策和约束。后续开发中，如果事实变化，应同步更新本文。

## 1. 项目身份

- 项目名：Zeta。
- 类型：Flutter Desktop 本地应用。
- 当前产品定位：本地 AI IDE 壳层，核心是项目上下文、Agent thread 和可审计对话时间线。
- 入口文件：`lib/main.dart`。
- 当前根 README 仍是 Flutter 默认模板文案，尚未反映真实产品定位。

## 2. 当前技术栈

- Flutter + Dart。
- Material 3 深色紧凑主题。
- `multi_split_view` 用于三栏可调整布局。
- `flutter_treeview` 用于文件树。
- `window_manager` 用于桌面窗口体验（隐藏原生标题栏、自定义标题栏）。
- macOS 原生「文件 - 打开项目」菜单通过 `zeta/menu` MethodChannel 桥接到 Flutter。
- `file_selector` 用于选择本地目录。
- `shared_preferences` 用于会话和 provider 配置持久化。
- `logging` 用于应用日志。

## 3. 架构决策

- 保持简单分层，不提前引入大型架构框架。
- UI 依赖 domain 层的 Agent 抽象，不直接处理 Codex 原始协议。
- data 层负责把 provider 协议映射成中立领域事件。
- Agent 上下文当前只传项目路径和当前文件路径，不自动读取文件内容。
- 默认 Codex 审批策略保持 `on-request`，不自动授权命令或文件修改。
- 文件树采用懒加载，不递归扫描整个仓库。
- 会话恢复必须宽容失败，不能阻断应用启动。

## 4. 重要模块记忆

- `MainApp` 支持测试注入目录选择器、会话存储和 Agent provider factory。
- `IdeHome` 组合三栏 UI，负责项目选择、文件树状态、会话恢复和 Agent workspace 同步。
- `AgentConversationViewModel` 负责 Agent 消息、工具调用、审批请求和状态机。
- `ProjectThreadsViewModel` 负责项目下 thread 列表、分页、缓存、选择和展开状态。
- `AgentProvider` 是 provider 能力接口。
- `CodexAppServerAgentProvider` 是当前默认 provider 实现。
- `JsonRpcPeer` 负责 stdio JSON-RPC 通信。
- `IdeSessionState` 当前版本为 2。

## 5. 开发约束

- Dart 改动后运行 `dart format .`。
- 结束代码变更前运行 `flutter analyze`。
- 修改行为或新增逻辑时运行 `flutter test`。
- 新公共 API、协议适配、状态机和错误处理优先写中文 `///` 注释。
- 不提交 build 输出和 `.dart_tool`。
- 平台目录改动需要确认来源，不能无解释保留意外生成变更。

## 6. 设计约束

- 这是工具型桌面应用，界面应保持克制、密集、可扫描。
- 避免把功能做成营销页或装饰性布局。
- 三栏职责要清晰：Projects 管项目和 threads，Agent 管对话，Files 管文件上下文。
- 非文本按钮需要 tooltip。
- 文件和项目路径展示必须考虑超长文本省略。

## 7. 风险点

- Codex app-server 协议变化可能导致 provider 映射失效。
- JSON-RPC stdio 的请求、通知和服务端 request 处理需要保持严格测试覆盖。
- 会话恢复涉及真实文件系统，路径不存在和权限失败必须被宽容处理。
- Agent 运行中切换 thread 容易造成状态竞争，需要继续用 token 或状态检查隔离旧结果。
- 文件树如果误改为递归扫描，会显著影响大型项目打开性能。

## 8. 待确认方向

- 是否引入内置文件预览或编辑器。
- 是否暴露 provider 管理 UI。
- 是否支持多个项目并行 Agent session。
- 是否需要审计和导出 Agent 执行记录。
- 是否需要跨设备同步项目会话。
