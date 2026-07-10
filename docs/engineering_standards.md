# 工程规范

最后更新：2026-07-10

本文从当前 `lib/` 重构后的代码结构中提炼长期遵循的工程规范。它补充根目录 `AGENTS.md`，用于指导后续功能开发、重构和评审。

## 1. 代码组织

当前 `lib/src` 采用面向功能的分层结构：

```text
lib/
  main.dart
  src/
    app/
    core/
    features/
      agent/
        application/
        data/
        domain/
        presentation/
      agent_management/
        application/
        data/
        domain/
        presentation/
      ide_session/
        application/
        data/
        domain/
      project_threads/
        application/
        domain/
        presentation/
      workspace/
        application/
        domain/
        presentation/
    ui/
      core/
      features/ide/
```

- `main.dart` 只负责 Flutter 绑定、窗口启动、全局错误日志和 `runApp`。
- `app` 是运行时装配层，负责组合窗口、shell controller、provider factory、持久化 store 和应用根组件。
- `core` 放跨功能基础设施，例如日志、路径工具等，不依赖具体 feature。
- `features/<feature>/domain` 放纯模型、枚举、接口和领域状态。
- `features/<feature>/application` 放用例协调、恢复计划、分页加载、状态编排和跨对象协作。
- `features/<feature>/data` 放外部协议、存储、datasource、mapper 和 codec。
- `features/<feature>/presentation` 放 feature 私有 view model、pane、widget 和 UI 分组逻辑。
- `ui/core` 放跨 feature 可复用的主题、窗口框架、pane、panel 和状态展示组件。
- `agent_management` 负责 CLI 检测、版本/账号/模型诊断、配置文件安全写入、
  磁盘日志读取与管理页面；它复用 `agent` 的 provider 抽象，不复制会话协议实现。

新增代码优先进入对应 feature 内部。除非是跨 feature 的基础能力，否则不要新增宽泛的顶层 `data`、`domain` 或 `ui` 目录。

## 2. 依赖方向

依赖方向必须保持单向、清晰：

```text
main -> app -> presentation/application -> domain
                       app -> data -> domain
                       presentation -> ui/core
```

- presentation 可以读取 view model、controller 暴露的状态并触发动作，但不直接解析 provider 原始协议。
- application 负责异步流程、恢复、分页、竞态隔离和状态写入，不负责绘制 widget。
- data 实现 provider、JSON-RPC、JSONL、SharedPreferences、本地文件系统等具体细节，并把外部 payload 映射为 domain 模型。
- domain 不依赖 Flutter widget、不访问本地文件系统、不引用具体 provider 实现。
- app 可以引用具体 data 实现，因为 app 是依赖注入和默认实现装配点。

## 3. 状态与异步编排

当前重构后的核心模式是“状态容器 + 应用控制器 + 细粒度 UI 信号”。

- 纯状态容器只暴露状态和同步更新方法，例如 `ProjectThreadsViewModel`。
- 应用控制器收敛分页、恢复、缓存、provider 调用和竞态处理，例如 `ProjectThreadsController`。
- 高吞吐 UI 使用分区 `ValueListenable` 或版本号信号，避免流式输出导致整页重建。
- 对会被新请求覆盖的异步加载使用 token/version guard，旧结果返回时必须被丢弃。
- `ChangeNotifier`、`ValueNotifier` 和 timer 持有者必须在 `dispose` 中释放资源；通知前应检查 disposed 状态。
- 对外暴露的集合默认使用不可变列表、不可变 map 或 unmodifiable view。

## 4. Provider 与协议边界

`AgentProvider` 是 UI 与具体 Agent 实现之间的稳定边界。

- UI 只消费 `AgentEvent`、`AgentThreadSummary`、`AgentPermissionRequest`、`AgentToolCall` 等中立模型。
- Codex app-server 的 JSON-RPC、通知、审批 payload 和历史 JSONL 解析必须留在 agent data 层。
- 新 provider 应先评估 `AgentProvider` 接口，不足时扩展领域接口，再在 data 层实现具体协议。
- mapper 文件负责字段兼容、默认值和协议名称转换；不要在 widget 中写散落的 JSON key。
- 默认审批策略保持保守，不自动授权命令执行或文件写入。
- Codex app-server 协议以 `third_party/codex_app_server_schema` 的 pinned
  快照为准；升级 CLI 时先用 `tool/gen_codex_schema.*` 导出并 diff，再改
  适配层。流程见 `docs/codex_app_server_protocol.md`。

## 5. 持久化与恢复

持久化数据必须可演进、可恢复、可容错。

- 会话状态使用版本化 JSON；字段新增时提供默认值。
- `tryDecode` 或等价宽容读取逻辑必须处理空值、损坏 JSON、旧版本和未知字段。
- 启动恢复失败不能阻断应用进入主界面。
- provider 全局配置和项目级 session/thread 状态必须分开存储。
- 路径不存在、目录不可读、权限失败等文件系统异常应转换为可理解状态或日志。
- Agent 配置保存必须先校验语法、检测外部修改、写入同目录临时文件并保留原文件
  备份；不得直接覆盖符号链接或在失败后破坏原配置。
- Agent 日志在进入 UI 前完成凭证与用户目录脱敏。

## 6. UI 与交互

Zeta 是桌面工具，不是营销页。界面应紧凑、克制、可扫描。

- 设计系统底层是 `shadcn_flutter`（固定 `0.0.52`）+ Graphite token。语义色/字号
  走 `IdeThemeScope` / `IdeColors` / `IdeTextStyles`；第三方组件走 `sf.*`。
- 统一 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`，禁止旧
  `shadcn_ui` / `Shad*` / `showShadDialog` API。
- 新 pane 或重复项优先复用 `Pane`、`PanelCard`、`IdeChip`、`IdeContextMenu`、
  `IdeStatusCard`、`WindowFrame` 和主题常量。
- IDE 通知统一走 `showIdeToast`，不要在 feature 页散落 `sf.showToast` builder。
- 长项目路径、文件路径、thread 标题、工具调用摘要和 diff 统计必须限制行数并使用 ellipsis。
- 非文本按钮需要 tooltip；重要自定义控件需要语义标签。
- 重复的交互行应使用稳定 `ValueKey`，方便测试和状态保持。
- 流式消息、语法高亮代码块、diff 明细等高频或重绘成本高的区域应使用 `RepaintBoundary`。
- 桌面布局优先用 `Expanded`、`Flexible`、`LayoutBuilder`、scroll view 和固定高度工具栏避免溢出。

## 7. 文件系统与工作区

- 文件树保持懒加载：打开项目只读顶层，展开目录再读下一层。
- 不递归扫描整个项目，不跟随符号链接。
- `.git`、`.dart_tool`、`.idea`、`.vscode`、`build`、`node_modules` 等大目录或工具缓存目录应继续忽略。
- 目录排序保持目录优先，并按大小写无关名称排序。
- 文件系统读取失败应记录日志并给 UI 留出降级状态，不能让异常直接冒泡导致崩溃。

## 8. 测试与评审重点

新增或修改代码时，测试层级应贴近风险点：

- domain 模型、codec、mapper 和 JSON 宽容解析用单元测试。
- application controller 的分页、恢复、竞态和错误路径用单元测试。
- provider datasource 和 transport 用 fake process、fake storage 或 callback 注入。
- pane、timeline、file tree 等用户可见行为用 widget test。
- 简单视觉调整可以只运行分析和相关 widget test，但行为变化必须补测试。

评审时优先检查依赖方向、协议泄漏、异步竞态、持久化兼容性、文件系统性能和 UI 溢出风险。
