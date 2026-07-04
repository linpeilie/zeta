# 设计文档

最后更新：2026-07-04

## 1. 设计目标

Zeta 的设计目标是让 Flutter UI、Agent provider、会话持久化和本地文件系统访问保持清晰分层。当前实现保持小型项目结构，不引入大型架构框架，但在 Agent 相关能力上预留 provider 抽象，方便未来接入 ACP、Claude Code 或其他 CLI。

## 2. 总体架构

当前代码按 `lib/src` 下的 app、core、data、domain、ui 分层组织：

- app：应用根组件、窗口启动、应用常量。
- core：日志等跨层基础能力。
- domain：Agent 中立模型和 provider 接口。
- data：Codex app-server、JSON-RPC stdio、文件系统、会话存储等具体实现。
- ui：窗口框架、主题、通用面板和 IDE 功能界面。

依赖方向保持为 UI 依赖 domain 接口，data 实现 domain 接口，app 负责组合默认实现。

## 3. 运行时结构

```text
main()
  -> MainApp
    -> IdeHome
      -> ProjectListPane
      -> AgentPane
      -> FileTreePane

IdeHome
  -> IdeSessionStore
  -> ActiveAgentProviderController
  -> AgentConversationViewModel
  -> ProjectThreadsViewModel

AgentConversationViewModel
  -> AgentProvider
    -> CodexAppServerAgentProvider
      -> JsonRpcPeer
        -> codex app-server --stdio
```

## 4. UI 设计

### 三栏工作台

- Projects：展示已打开项目、当前项目状态和项目下的 Agent threads。
- Agent：展示上下文栏、状态胶囊、消息时间线、工具调用卡片、审批卡片和输入区。
- Files：展示当前项目文件树，目录按需展开，文件选择只更新 Agent 上下文。

### 主题

当前使用深色紧凑 IDE 风格：

- 框架底色：深灰。
- 面板底色：深色卡片。
- 主强调色：绿色。
- 警示/目录色：黄色。
- 面板圆角和间距较小，适合桌面工具密度。

## 5. Agent 设计

### Provider 抽象

`AgentProvider` 是 UI 与具体 Agent CLI 之间的稳定接口，负责：

- 初始化 provider。
- 创建和恢复 session。
- 列出项目 threads。
- 读取 thread 历史。
- 发送、追加和取消 turn。
- 响应权限请求。
- 推送状态、消息、工具调用和审批事件。

### 默认 provider

当前默认 provider 为 Codex CLI：

```text
codex app-server --stdio
```

Codex provider 通过 JSON-RPC stdio 通信，把 `thread/*`、`turn/*` 和 `item/*` 事件转换为领域层事件。UI 不直接处理 Codex 原始协议。

### 上下文策略

当前 V1 只传递：

- 当前项目路径。
- 当前文件路径。

系统不会自动读取文件内容，也不会自动授权命令或文件写入。默认审批策略为 `on-request`。

## 6. 会话状态设计

IDE 会话状态目前版本为 2，持久化内容包括：

- 最近项目列表。
- 当前项目。
- 当前文件路径。
- 文件树展开目录。
- 文件树选中 key。
- 当前 Agent provider id。
- 每个项目最近使用的 Agent thread id。
- 项目 thread 面板展开状态。
- 每个项目的 thread 缓存。
- 每个项目选中的 thread id。

会话恢复遵循宽容策略：旧版本、损坏内容、缺失字段或不存在的路径都不会阻断启动。

## 7. 文件树设计

文件树使用懒加载策略：

- 打开项目时只读取顶层目录。
- 目录首次展开时再读取下一层。
- 不跟随符号链接。
- 忽略 `.git`、`.dart_tool`、`.idea`、`.vscode`、`build`、`node_modules`。
- 目录排在文件前，名称按大小写无关排序。

这个策略避免大型仓库在打开时被完整递归扫描。

## 8. 错误处理

- 全局使用 `runZonedGuarded`、`FlutterError.onError` 和 `PlatformDispatcher.instance.onError` 记录未处理错误。
- 目录读取失败通过日志和短提示反馈，不中断当前工作区。
- 会话恢复失败会清理恢复状态并继续启动。
- Agent provider 启动失败、协议失败或进程异常会转换为 UI 状态和错误消息。

## 9. 测试策略

当前测试重点应覆盖：

- Agent 模型 JSON 编解码和宽容读取。
- JSON-RPC stdio transport。
- Codex provider 事件映射。
- AgentConversationViewModel 状态机。
- ProjectThreadsViewModel 分页、缓存、选择和错误状态。
- App 或关键 Pane 的 widget 行为。

新增功能应优先选择最靠近风险点的测试层级，避免为了简单 UI 调整引入过重测试。

## 10. 演进方向

- 增加 provider 配置管理界面。
- 增加文件内容预览或编辑器能力。
- 增加 Agent 执行审计记录。
- 支持更多 Agent provider。
- 把复杂 UI 状态进一步拆成更小的 view model。
- 在需要深链、多屏或 Web 支持时再引入声明式路由。
