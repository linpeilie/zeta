# 工程规范

最后更新：2026-07-16

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
- data 实现 provider、JSON-RPC、JSONL、版本化本地 JSON 文件等具体细节，并把外部 payload 映射为 domain 模型。
- domain 不依赖 Flutter widget、不访问本地文件系统、不引用具体 provider 实现。
- app 可以引用具体 data 实现，因为 app 是依赖注入和默认实现装配点。

## 3. 状态与异步编排

当前重构后的核心模式是“状态容器 + 应用控制器 + 细粒度 UI 信号”。

- 纯状态容器只暴露状态和同步更新方法，例如 `ProjectThreadsViewModel`。
- 应用控制器收敛分页、恢复、缓存、provider 调用和竞态处理，例如 `ProjectThreadsController`。
- 高吞吐 UI 使用分区 `ValueListenable` 或版本号信号，避免流式输出导致整页重建。
- 跨模块共享的运行时指示（如侧栏 thread busy）若依赖独立 snapshot listenable，
  stream flush 与分区 publish 都必须同步该 snapshot，不得只 bump 面板 version。
- 对会被新请求覆盖的异步加载使用 token/version guard，旧结果返回时必须被丢弃。
- 乐观持久化必须分离“当前快照”与“最近确认快照”；快速连续更新应串行、
  合并或取消过期请求，保存失败时整体回滚关联字段并保留可重试快照。
- 业务选择态与短生命周期的 UI 展开态必须分离；例如 Composer 的
  `selectedModelId` 可持久化，`expandedModelId` 只由 Popover 持有。
- `ChangeNotifier`、`ValueNotifier` 和 timer 持有者必须在 `dispose` 中释放资源；通知前应检查 disposed 状态。
- 对外暴露的集合默认使用不可变列表、不可变 map 或 unmodifiable view。

## 4. Provider 与协议边界

迁移期内，`AgentProviderBundle` 是 application / presentation 首选能力边界；
`AgentProvider` 保留为 data adapter 的兼容门面。

- UI 只消费 `AgentEvent`、`AgentThreadSummary`、`AgentPermissionRequest`、`AgentToolCall` 等中立模型。
- 已迁移能力域（`conversation`、`threadCatalog`、`threadMutations`、
  `threadBranching`、`turnSteering`、`interactions`、`modelCatalog`、
  `localThreadList`、`sessionConfiguration`、`planApproval`）优先通过 bundle 端口访问；
  controller / view model 不再通过 provider kind、`is SomeProvider` 或直接调用
  已迁移旧方法做分支。
- 每个 provider 必须通过不可变 `AgentProviderCapabilities` 声明真实能力；presentation
  隐藏不支持入口，application 和 data 层执行前仍要校验。禁止以静默 no-op 或语义不等价
  的降级伪造 thread/turn 能力。
- bundle 端口为空时，对应 capability 必须不可用；不支持功能不得靠 no-op 伪装成“已实现”。
- 启动时机由 `AgentProviderBootstrapPolicy` 描述；需要项目目录的 provider 不得在获得
  workspace 前启动，也不得参与 eager model preload。
- Codex app-server 的 JSON-RPC、通知、审批 payload 和历史 JSONL 解析必须留在 agent data 层。
- 新 provider 应先评估现有 bundle 端口是否足够；不足时优先扩展可选端口，再在 data 层
  实现具体协议。只有明确需要兼容旧调用面时，才同步补 `AgentProvider` 门面。
- 非所有 provider 都具备的账号能力使用可选接口（例如
  `AgentUsageQuotaProvider`），不要扩大 `AgentProvider` 的必选实现面。
- mapper 文件负责字段兼容、默认值和协议名称转换；不要在 widget 中写散落的 JSON key。
- 模型目录的 Reasoning 和 service tier 在 data mapper 中转为中立领域模型，保留服务端顺序和
  精确 tier id；Fast 等产品语义可在 domain/application 层识别，但不得改写 provider 协议值。
- 标准 ACP 的 session update、content block、permission option 和 session config 优先复用
  公共 mapper；厂商扩展保留在对应 adapter，不得污染 presentation。
- 厂商阻塞请求必须覆盖成功、拒绝/跳过、取消、超时和 provider 清理路径；每条路径都要
  回包、释放 timer 并移除 presentation pending state，未知 request 明确返回 `-32601`。
- 通用 CLI 名称（例如 Cursor 的 `agent`）不得只按 basename 判定产品身份；定位器必须
  组合无副作用版本/帮助探测，并在 ACP initialize 的 `agentInfo` 上二次校验。
- workspace-scoped provider 的子进程 cwd 与 session cwd 必须一致；workspace 变化时关闭
  旧 peer、清理待响应请求并重新握手，禁止跨项目复用进程。
- JSON-RPC provider 必须复用 `ProviderRuntimeJsonRpcPeer` 的生命周期 gate。`closing` 后
  禁止新 client RPC；反向请求以 `(runtimeId, connectionEpoch, requestId)` 为权威身份，
  dispose 必须关闭 transport 并等待已入场的 start、RPC 与 handler 排空后才进入 `closed`。
- Provider 事件消费者必须使用 listener generation，并以
  `(runtimeId, connectionEpoch, providerId, threadId, listenerGeneration)` 隔离旧流；旧
  listener 的退出回调不得清理新 generation，Thread/Provider 切换应在首个 `await` 前
  使旧 generation 失效。
- Transport 与 Provider mapper 不得丢弃协议事件。Application 投影层只允许合并同一
  thread/turn/item/kind 的连续文本或 reasoning delta、token/diff 最新快照和工具 progress；
  item/工具/turn 终态、审批、错误和连接状态必须先 flush 缓冲后立即发布。背压诊断不得包含正文。
- Provider Thread 操作必须复用 `ProviderOperationScheduler`。同一 Thread 的变更使用
  `exclusive` 并保持 FIFO，list/read 使用 Project/Thread `sharedRead`；禁止同键重入，
  dispose 必须拒绝未入场任务并等待已入场任务释放资源键。
- JSON-RPC transport 日志不得记录 prompt、文件内容、认证参数或 stderr 原文。
- 默认审批策略保持保守，不自动授权命令执行或文件写入。
- Codex app-server 协议以 `third_party/codex_app_server_schema` 的 pinned
  快照为准；升级 CLI 时先用 `tool/gen_codex_schema.*` 导出并 diff，再改
  适配层。流程见 `docs/codex_app_server_protocol.md`。

### 4.1 Agent 流式身份与叙事边界

Agent 时间线必须区分 Provider 原始身份和 Zeta 展示身份：

- `sourceItemId` / `sourceMessageId`（统称 source id）保存 Provider 协议给出的
  message/item/event 身份，用于关联、去重和诊断；它不是 UI 合并键。
- `entryId` 是 Zeta 规范化时间线条目身份，也是 EventBuffer、TimelineStore 和 UI
  的唯一合并键。迁移期内 `AgentMessageDeltaEvent.messageId`、
  `AgentMessageUpdatedEvent.messageId` 和 `AgentReasoningDeltaEvent.itemId` 字段名暂时
  保留，但语义均为 entryId。
- 同一连续可见条目的 delta 必须复用 entryId；条目被关闭后不得复用。两个 turn
  即使复用同一个 source id，也必须得到不同 entryId；不得用固定 `unknown` 作为
  message/reasoning entryId。
- Provider 的 completed/snapshot 必须通过 source→entry 关联更新已有条目。若一个
  source message 已被拆成多个 segment 且协议没有 segment 信息，完整 snapshot 不得
  猜测性覆盖任一 segment，只能更新可安全关联的 metadata。

`narrative boundary` 是会改变可见时间线顺序、并关闭当前 message segment 或
reasoning phase 的事件。边界至少包括：source message id 改变、正文与 reasoning
互相切换、首次出现的 tool、plan、permission/user question/plan approval、实际进入
时间线的 warning/system 条目以及 turn terminal。以下情况不额外创建边界：同一 tool id
的状态更新、usage/status/config 更新和重复 raw event。连续 reasoning chunk 属于同一
phase；被正文、tool、plan 或交互打断后的 reasoning 必须使用新 entryId。

身份决策与状态隔离遵循以下边界：

- 共享 ACP decoder 只能解析协议语法和 typed 字段，必须无状态；Grok、Cursor 等
  Provider data adapter/reducer 负责解释 source id、delta/snapshot、segment、phase、
  去重和 lifecycle。Store/ViewModel/UI 不得读取 raw payload 推断 identity 或 plan。
- live、replay、history 可以复用同一 reducer 算法和 entry-id builder，但必须使用不同
  实例，不得共享 current segment、seen event/tool、terminal 或 generation 状态。
- live 状态至少按 `(runtimeId, connectionEpoch, providerId, sessionId, turnId)` 隔离；
  新 turn、cancel、prompt 失败、peer close、provider dispose、epoch 变化和 session
  删除/切换必须使旧状态失效。replay/history 在 build、失败或取消后也必须释放状态。
- EventBuffer 只允许合并同 entryId、同事件 kind 和同必要 detail 的事件；任一非合并
  事件先 flush。它不得推断“最后一个开放气泡”或替代 Provider boundary 状态机。
- TimelineStore 的目标行为是同 entryId 更新、异 entryId 新建，不改写 id、不分配
  segment。迁移期现有 open/`#segN` 兜底必须保留到 Grok identity 与 Cursor 退役门禁
  全部通过，但不得新增 Provider-specific 分支或扩大该兜底职责。
- eventId、messageId 稳定性和 delta/snapshot 语义必须由带 Provider/CLI 版本的脱敏
  fixture 证明；缺少真实证据时明确阻塞对应门禁，禁止复制其他 Provider 的假设。

## 5. 持久化与恢复

持久化数据必须可演进、可恢复、可容错。

- Zeta 自有配置、状态、派生索引、日志和预留缓存统一位于 `~/.zeta`：
  `config/providers.json`、`config/appearance.json`、`state/ide_session.json`、
  `state/cursor_sessions.json`、`state/usage_statistics_index.json`、
  `state/migration_marker.json`、`logs/zeta-YYYY-MM-DD.log` 与 `cache/`。
- HOME 解析、目录布局和安全文本替换属于 `core`；各 feature 的 data store 只接收
  app 注入的具体文件并负责自身 codec，presentation/application 不拼接 `~/.zeta` 路径。
- 旧 SharedPreferences 仅由 app 启动迁移器读取。迁移以已存在的目标文件为准，全部
  成功后写 marker；部分失败时本次运行使用内存状态，避免空文件覆盖待迁移数据，
  且不得标记完成或阻断主界面启动。
- 会话状态使用版本化 JSON；字段新增时提供默认值。
- `tryDecode` 或等价宽容读取逻辑必须处理空值、损坏 JSON、旧版本和未知字段。
- 启动恢复失败不能阻断应用进入主界面。
- provider 全局配置和项目级 session/thread 状态必须分开存储。
- provider 模型偏好按 `modelId` 保存为版本化条目；当前 selection 和偏好 map 必须同快照写入，
  宽容解码忽略损坏条目并用最新 capability 重新归一化。
- 路径不存在、目录不可读、权限失败等文件系统异常应转换为可理解状态或日志。
- Agent 配置保存必须先校验语法、检测外部修改、写入同目录临时文件并保留原文件
  备份；不得直接覆盖符号链接或在失败后破坏原配置。
- Agent 日志在进入 UI 前完成凭证与用户目录脱敏。
- 应用根日志同时保留 developer 输出并按本地日期追加到 `~/.zeta/logs`；文件 sink
  必须串行写入、脱敏消息，写入失败不能递归进入根 Logger，并在正常关闭窗口前
  排空待写队列。
- 使用统计派生索引只保存聚合所需元数据；禁止写入 Prompt、回复正文、工具输出、
  session 文件路径和原始错误文本。索引必须版本化并支持损坏后重建。
- `~/.codex`、`~/.grok`、`~/.cursor`、项目 `.cursor/*` 与用户源码始终由 CLI/用户
  原地管理。迁移器不得遍历、复制或改写这些目录；退役遗留的
  `cursor_sessions.json` 不再被运行时读取或写入，只作为受保护用户数据保留。

## 6. UI 与交互

Zeta 是桌面工具，不是营销页。界面应紧凑、克制、可扫描。

- `IdeHome` 是主要页面唯一的 Workbench 组合边界。首页、设置、Agent 管理和使用统计
  必须由同一个常驻 `WindowFrame` + `IdeWorkbenchScaffold` 承载，只切换
  Navigation、Canvas、Inspector slot；Feature 页面不得另建或替换顶层骨架。
- Workbench 负责布局模式、Pane 表面与 Overlay，Feature 负责业务内容、控制器和离开
  确认。设置页应通过 `SettingsNavigationPane` 与 `SettingsPageCanvas` 接入 slot，
  不把设置分区或 Agent 配置规则下沉到共享 Scaffold。
- 跨页面保活的 Canvas 必须保证关键 State、`ScrollController`、输入控制器和当前 Thread
  不被销毁。可能因兄弟 slot 增删而换位的 Flex 子节点必须直接使用稳定 Key；仅给内部
  Widget 加 Key 不足以保证父级 Element 复用。
- 设计系统底层是 `shadcn_flutter`（固定 `0.0.52`）+ Graphite token。语义色/字号
  走 `IdeThemeScope` / `IdeColors` / `IdeTextStyles`；第三方组件走 `sf.*`。
- 统一 `import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;`，禁止旧
  `shadcn_ui` / `Shad*` / `showShadDialog` API。
- 新 pane 或重复项优先复用 `Pane`、`PanelCard`、`IdeTabs` / `IdeTab`、`IdeChip`、
  `IdeContextMenu`、`IdeStatusCard`、`WindowFrame` 和主题常量。
- IDE 通知统一走 `showIdeToast`，不要在 feature 页散落 `sf.showToast` builder。
- 长项目路径、文件路径、thread 标题、工具调用摘要和 diff 统计必须限制行数并使用 ellipsis。
- 非文本按钮需要 tooltip；重要自定义控件需要语义标签。
- 重复的交互行应使用稳定 `ValueKey`，方便测试和状态保持。
- Popover 中的可选列表应支持 roving focus、禁用项原因、Esc 关闭与焦点恢复；
  展开动画必须遵循 reduce motion，不得在用户滚动时强制自动定位。
- 流式消息、语法高亮代码块、diff 明细等高频或重绘成本高的区域应使用 `RepaintBoundary`。
- 桌面布局优先用 `Expanded`、`Flexible`、`LayoutBuilder`、scroll view 和固定高度工具栏避免溢出。
- 统计页等宽数据面板在宽屏可双栏排列，窄屏必须回退为单栏；宽表格使用受限的
  横向滚动，不得挤压文本到不可读宽度。

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
- 包含多字段配置的 application controller 必须覆盖快速连续更新、过期请求、
  确认态回滚、完整快照重试与损坏持久化输入。
- provider datasource 和 transport 用 fake process、fake storage 或 callback 注入。
- pane、timeline、file tree 等用户可见行为用 widget test。
- 主要页面切换必须使用实际 `IdeHome` 做集成级 Widget 测试。Agent → Settings → Agent
  与 Agent → Usage → Agent 至少验证常驻骨架、AgentPane Element、当前 Thread、草稿、
  非零滚动位置、Pane 宽度和 Pane 可见状态保持。
- 简单视觉调整可以只运行分析和相关 widget test，但行为变化必须补测试。
- 外部 CLI 的自动化测试不能替代真实平台验收。Beta provider 发布前使用脱敏 smoke，分别
  记录 OS/架构、CLI 版本、包装器类型和结果；没有设备或凭据时必须标记“待执行/阻塞”，
  不得推断通过。真实 smoke 使用临时 workspace、最小权限和非破坏性 prompt。

评审时优先检查依赖方向、协议泄漏、异步竞态、持久化兼容性、文件系统性能和 UI 溢出风险。
