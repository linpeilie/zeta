# 设计文档

最后更新：2026-07-09

## 1. 设计目标

Zeta 的设计目标是让 Flutter UI、Agent provider、会话持久化和本地文件系统访问保持清晰分层。当前实现采用轻量 feature-sliced 结构，不引入大型架构框架，但在 Agent 相关能力上预留 provider 抽象，方便未来接入 ACP、Claude Code 或其他 CLI。

## 2. 总体架构

当前代码按 `lib/src` 下的 app、core、features、ui 分层组织。重构后的核心原则是以 feature 为内聚边界，在 feature 内再按 domain、application、data、presentation 拆分职责：

- app：应用根组件、窗口启动、应用常量。
- core：日志等跨层基础能力。
- features/agent：Agent provider 抽象、Codex app-server、JSON-RPC stdio、历史解析、事件映射、对话 view model 和 Agent pane。
- features/ide_session：会话状态、版本化持久化、恢复计划和恢复协调。
- features/project_threads：项目 thread 快照、列表状态、分页控制器和 presentation view model。
- features/workspace：文件树规则、树构建、文件节点映射和文件 pane。
- ui/core：窗口框架、主题、通用面板和共享 UI primitives。
- ui/features/ide：IDE shell 视图和 provider 选择相关 view model。

依赖方向保持为 presentation/application 依赖 domain 接口，data 实现 domain 接口，app 负责组合默认实现。UI 不直接处理 Codex 原始协议或持久化 JSON。

## 3. 运行时结构

```text
main()
  -> MainApp
    -> IdeShellController
    -> IdeHome
      -> ProjectListPane
      -> AgentPane
      -> FileTreePane

IdeShellController
  -> IdeSessionStore
  -> ActiveAgentProviderController
  -> AgentConversationViewModel
  -> ProjectThreadsController

AgentConversationViewModel
  -> AgentConversationTimelineStore
  -> AgentConversationUiSignals
  -> AgentConversationModelSelectionController
  -> AgentProvider
    -> CodexAppServerAgentProvider
      -> JsonRpcPeer
        -> codex app-server --stdio
```

## 4. UI 设计

### 三栏工作台

- Projects：展示已打开项目、当前项目状态和项目下的 Agent threads。
- Agent：展示上下文栏、状态胶囊、流式消息/思考/计划时间线、回合 diff、工具与审批卡片、本地图片输入区。
- Files：展示当前项目文件树，目录按需展开，文件选择只更新 Agent 上下文。

### 主题与设计系统

- 深色「Graphite Night」：中性石墨框架底 `#0A0A0B`，面板 `#18191B`，
  强调色蔚蓝 `#1B84FF`，selected 行用 accent 半透明铺底。
- 浅色「Graphite Day」：中性浅灰底 `#EEEFF1`，白色面板，
  强调色蔚蓝 `#0B76D8`。
- 语义色独立：success 绿 / error 红 / warning 琥珀 / info 蓝；
  diff 增删行使用 success/error。
- 全部视觉取值集中在 `lib/src/ui/core/` 的 token 类：`IdeColors`（语义色）、
  `IdeRadius`/`IdeEffects`（圆角四档 6/8/12/16、阴影预设与 scrim）、
  `IdeSpacing`（4px 基准间距）、`IdeTextStyles`（语义字号）、
  `IdeMotion`（动效）。
- 主题装配通过 `buildShadTheme` 把 `IdeColors` 映射到 shadcn_ui 的
  `ShadThemeData`，ghost 按钮/option/弹层/对话框的 hover 与阴影在主题层
  统一，业务代码禁止硬编码颜色、圆角和阴影。
- 面板圆角 8、间距紧凑，适合桌面工具密度。

## 5. Agent 设计

### Provider 抽象

`AgentProvider` 是 UI 与具体 Agent CLI 之间的稳定接口，负责：

- 初始化 provider（含 capabilities / 通知 opt-out）。
- 创建和恢复 session；切换会话时 best-effort `unsubscribeThread`。
- 列出项目 threads、读取 thread 历史。
- 发送、追加和取消 turn（`sendMessage` / `steerTurn` 支持多输入项）。
- 响应权限请求；他端已解决的审批通过事件撤销本地卡片。
- 推送状态、消息、推理/计划流、工具调用、回合 diff、审批与系统提示事件。

### 默认 provider

当前默认 provider 为 Codex CLI：

```text
codex app-server --stdio
```

Codex provider 通过 JSON-RPC stdio 通信，把 `thread/*`、`turn/*` 和 `item/*`
事件转换为领域层 `AgentEvent`。UI 不直接处理 Codex 原始协议。

协议基准锁定在 `third_party/codex_app_server_schema`（由
`tool/gen_codex_schema.sh` / `.ps1` 从本机 Codex CLI 导出）。当前 pin 与
升级流程见 [Codex app-server 协议版本锁定](./codex_app_server_protocol.md)；
功能缺口与分阶段适配见
[`plan/codex_app_server_adaptation_plan.md`](../plan/codex_app_server_adaptation_plan.md)。

**适配进度（截至 Phase 2 核心 2.1–2.5）：** Phase 0 完成协议对齐；Phase 1
完成核心流式体验；Phase 2 核心完成 thread 生命周期管理（重命名/归档/删除/
分叉/回滚/压缩）、列表搜索与归档视图、配套通知同步，以及上下文占用提示。
审批表单、permissionProfile、mention 等（2.6–2.10）仍待后续切片。

### 当前已落地的对话体验

- 流式推理（思考卡，摘要优先）与流式 plan 卡。
- 回合级聚合 diff（「本回合改动」）。
- 线程状态胶囊：等待审批 / 等待输入；列表侧同步 waiting 标志。
- 模型改道、弃用通知等系统提示；token 用量含 `modelContextWindow` 占用比例。
- 18 种 ThreadItem 在实时路径与 `thread/read` / JSONL 历史中一致映射。
- 输入区支持本地图片（选图 / 粘贴落盘）随 turn 发送，时间线气泡预览。
- Thread 列表：搜索、活动/归档切换、右键重命名/归档/删除/分叉。
- 编辑上一条用户消息（`thread/rollback` + 重发）；头栏分叉与上下文压缩入口。

### 上下文策略

当前仍只自动传递：

- 当前项目路径。
- 当前文件路径。

系统不会自动读取文件内容，也不会自动授权命令或文件写入。默认审批策略为
`on-request`。用户可在输入区附加本地图片；`@mention` / 远程图片 / skill
注入等富输入见适配计划 Phase 2.10 / Phase 4。

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
- ProjectThreadsController 和 ProjectThreadsViewModel 的分页、缓存、选择和错误状态分工。
- App 或关键 Pane 的 widget 行为。

新增功能应优先选择最靠近风险点的测试层级，避免为了简单 UI 调整引入过重测试。

## 10. 演进方向

- Codex 适配 Phase 2：thread 重命名/归档/删除/分叉/回滚/压缩，以及审批表单与策略预设（见适配计划）。
- 增加 provider 配置管理界面（与 Phase 3 账户/配置能力对齐）。
- 增加文件内容预览或编辑器能力。
- 增加 Agent 执行审计记录。
- 支持更多 Agent provider。
- 把复杂 UI 状态进一步拆成更小的 view model。
- 在需要深链、多屏或 Web 支持时再引入声明式路由。
