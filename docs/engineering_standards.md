# 工程规范

最后更新：2026-08-04

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
      desktop_notifications/
        application/
        data/
        domain/
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

当前重构后的核心模式是“状态容器 + 应用控制器 + 类型化 UI state”。

- 纯状态容器只暴露状态和同步更新方法，例如 `ProjectThreadsViewModel`。
- 应用控制器收敛分页、恢复、缓存、provider 调用和竞态处理，例如 `ProjectThreadsController`。
- 高吞吐 UI 使用结构相等的不可变 state slice 与分区 `ValueListenable`，不得用整数
  version/revision 作为主要刷新协议。Timeline 的 live turn 保留稳定对象和增量 mutation，
  不得因不可变状态迁移在每个 delta 复制完整历史。
- Agent UI 更新由 application 通过 `AgentUiUpdatePort` 提交类型化 request；
  `SchedulerBinding` 只允许出现在 presentation 的 `AgentUiUpdateScheduler` 生产适配中。
  普通请求按下一 Flutter frame 合并，immediate 请求吸收 pending 后在安全边界发布；
  不得重新引入固定毫秒 Timer、post-frame 释放门闩或 idle task 队列。
- `AgentConversationViewModel` 是命令入口和 typed listenable facade，不再继承
  `ChangeNotifier`。Widget 只能监听所需 state slice、稳定 live turn 或一次性 UI effect；
  Shell 只能监听 `AgentConversationThreadSnapshot`。
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

- UI 只消费 `AgentEvent`、`AgentThreadSummary`、`AgentPermissionRequest`、
  `AgentQuestionRequest`、`AgentToolCall` 等中立模型。
- 已迁移能力域（`conversation`、`threadCatalog`、`threadMutations`、
  `threadBranching`、`turnSteering`、`interactions`、`modelCatalog`、
  `localThreadList`、`sessionConfiguration`、`planApproval`、`conversationModes`、
  `permissionPolicy`）优先通过 bundle 端口访问；
  controller / view model 不再通过 provider kind、`is SomeProvider` 或直接调用
  已迁移旧方法做分支。
- 权限选项选择只走中立 `AgentPermissionPolicyPort`（`listPermissionOptions` /
  `applyPermissionSelection`）。共享层仅使用 `AgentPermissionOption` /
  `AgentPermissionSelection.optionId`；Codex approval/sandbox/profile 与 Grok mode
  协议字段只允许出现在 data adapter/codec。是否展示权限选择器由
  `bundle.permissionPolicy != null` 决定，不得再使用
  `supportsPermissionPolicySelection` / `supportsPermissionProfile*` 静态位。
- Provider 默认权限偏好持久化在 `~/.zeta` 的 provider settings V2 中，真源为单一
  `selectedPermissionOptionId`。V1 字段（`selectedApprovalPolicy` /
  `selectedSandboxPolicy` / `selectedPermissionProfileId` / `selectedPermissionMode`）
  仅由 data/config 边界的 provider-specific migrator 读取，写入不得再出现。组合层必须按
  provider kind 注册中立 migrator；V2 optionId key 存在时不得调用 legacy migrator。
  Domain `AgentProviderConfig` 只保存归一化 optionId，不提供配置 `tryDecode` 门面；V1/V2
  宽容解码、内置 Provider 补齐与 legacy 迁移全部由 data `AgentProviderSettingsCodec` 负责。
  `AgentPermissionStateStore` 是 application
  权限状态真源，按 provider runtime identity/generation + threadId 隔离不可变快照；
  provider default、thread effective、state source、last scope、warning 与持久化失败不得
  分散回 ViewModel 字段。catalog 加载由独立 `AgentPermissionCatalogController` 管理：只提交
  adapter 返回的完整成功目录，transient/malformed 失败保留 last-known-good；旧 refresh
  generation 不得覆盖新目录。Codex 只有明确 unsupported 才允许降级静态 built-ins。
- 所有权限 apply 路径必须消费完整 `AgentPermissionApplyResult`：`currentTurn` 只形成下一次
  请求的一次性 override，`currentSession` 只更新目标 thread，`runtime` 更新显式 runtime
  state 并广播全部同 runtime 消费者，`nextSession` 只更新默认/待生效状态。runtime 广播必须
  携带 identity/generation；旧 generation 结果必须丢弃，不得靠遍历改写 thread map 模拟广播。
- Provider apply 成功后的偏好持久化失败不得回滚 effective/runtime 状态；application 必须保留
  可见错误与只重试持久化的入口，重试不得再次调用 Provider apply。
- create/resume/fork/send 必须携带不可变 `AgentPermissionRequestSnapshot`，由
  application 按 thread-effective → provider default → catalog default 解析。Codex
  client/encoder 只能在该快照没有 selection 时使用 Provider 构造时冻结的 config
  fallback；用户选择或 `thread/settings/updated` 不得改写跨 thread 共享的请求权限状态。
  旧裸 `permissionSelection` 参数、`AgentTurnConfiguration.permissionSelection` 与 Provider
  内兼容合并 setter/facade 均不得恢复。
- `thread/settings/updated` 的 Codex profile/approval/sandbox 必须由 data codec 一次性解码
  为 `AgentPermissionSelection`；domain event 不得暴露协议字段。reducer 允许权限事实按事件
  threadId 路由到 store，即使该 thread 不是当前 Canvas；同一通知不得更新 provider default、
  不得再次调用 Provider apply，模型和协作模式仍只作用于当前 thread。
- 每个 provider 必须通过不可变 `AgentProviderCapabilities` 声明真实能力；presentation
  隐藏不支持入口，application 和 data 层执行前仍要校验。禁止以静默 no-op 或语义不等价
  的降级伪造 thread/turn 能力。
- bundle 端口为空时，对应 capability 必须不可用；不支持功能不得靠 no-op 伪装成“已实现”。
- 启动时机由 `AgentProviderBootstrapPolicy` 描述；需要项目目录的 provider 不得在获得
  workspace 前启动，也不得参与 eager model preload。
- `AgentProviderRuntimeRegistry` 是应用进程内 Provider 实例和子进程的唯一所有者。
  对话、Project Threads、用量统计和 Agent 管理探测只能获取可释放租约，不得直接调用
  `AgentProviderFactory.create` 后自行持有或销毁。正常运行时每个 Provider ID 最多一个实例；
  影响启动的配置变化必须先使旧实例及租约失效，再创建新实例。
- 多个 Pane 共享 Provider 时，thread/session 状态必须按 ID 隔离。启动或恢复另一个会话
  不得隐式退订、清空或使其他会话的 reducer 失效；退订只由明确关闭对应会话的调用方发起。
- 桌面窗口关闭必须等待运行时注册表关闭全部 Provider，再 flush 日志并退出，避免遗留
  app-server 或 stdio 孤儿进程。
- Codex app-server 的 JSON-RPC、通知、审批 payload 和历史 JSONL 解析必须留在 agent data 层。
- 权限审批、用户提问和计划审批必须保持独立领域语义：
  `respondToPermission` 只接受 approve/deny/cancel 决策，
  `respondToQuestion` 只接受结构化 answers（空 map 表示 Skip），计划审批继续通过
  `AgentPlanApprovalPort` 回写。三者可以共享 Pending Interaction Dock，但不得复用
  request/decision 模型或 pending registry。
- Plan 回合完成后的“是否执行”属于 Zeta 本地 application 交接，不属于 Provider
  计划审批。它使用独立的 `AgentPlanExecutionRequest`，不调用 approval/permission/question
  端口，不持久化，并在 thread、workspace、provider 或可写性边界变化时清除。
- 本地交接只能由成功的 Plan 终态和非空计划内容触发。执行动作必须通过新的 Default
  `turn/start` 发起；继续规划保持 Plan draft；任何动作都不得预授权后续工具或文件修改。
- 只有支持独立用户提问协议的 Provider 才实现 `AgentQuestionResponseProvider`；
  permission-only Provider 不得用空 answers、no-op 或权限拒绝伪造提问能力。
- 新 provider 应先评估现有 bundle 端口是否足够；不足时优先扩展可选端口，再在 data 层
  实现具体协议。只有明确需要兼容旧调用面时，才同步补 `AgentProvider` 门面。
- 非所有 provider 都具备的账号能力使用可选接口（例如
  `AgentUsageQuotaProvider`），不要扩大 `AgentProvider` 的必选实现面。
- mapper 文件负责字段兼容、默认值和协议名称转换；不要在 widget 中写散落的 JSON key。
- 模型目录的 Reasoning 和 service tier 在 data mapper 中转为中立领域模型，保留服务端顺序和
  精确 tier id；Fast 等产品语义可在 domain/application 层识别，但不得改写 provider 协议值。
- 需要系统提醒的事件必须先映射为 Provider 中立的 `AgentAttentionSignal`。
  Provider adapter/reducer 决定 identity 来源，workspace 只补齐定位上下文，通知 Store
  只按规范化 identity 去重和清除，不得增加厂商分支。
- 操作系统通知不得包含 prompt、回复、命令、问题、错误原文、完整路径或 raw payload；
  payload 只保留定位与幂等必需的版本、Provider/thread 和 identity。
- 窗口获得焦点、Agent Canvas 可见且当前 thread 一致时必须抑制系统通知并清除
  该 thread 未读。任务栏/Dock 只是内部未读的投影，不是业务真源。
- Conversation mode 通过可选 `conversationModes` 端口和运行时目录发现，不按 provider kind
  或 CLI 版本硬编码。模式是 thread 粘性、逐 turn 提交的状态，由 application controller
  管理 draft / confirmed / pending；不得写入 Provider 全局可变配置。
- 显式 mode 必须冻结进 `AgentTurnConfiguration`。活动 turn 中修改 draft 只影响下一次
  `turn/start`；退出 sticky Plan 必须显式发送 Default。Codex data encoder 负责嵌套
  `collaborationMode.settings`，且 mode 存在时不得再发送冲突的顶层 model / effort。
- experimental 模式目录探测失败时只禁用模式入口，不影响普通 Default 对话。临时 transport
  失败可重试，method-not-found 或损坏目录在当前 runtime generation 内保守降级；重建
  Provider 后重新探测。
- 标准 ACP 的 session update 语法只通过无状态 `AcpSessionUpdateDecoder` 解码；content
  block、permission option 和 session config 继续复用各自 codec/mapper。厂商 source id、
  segment/phase、去重和终态策略必须留在对应 Provider adapter/reducer，不得放回共享层。
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
- 每个对话事件源必须由 `AgentEventPipeline` 集中持有 subscription、listener scope/gate、
  `CoalescingEventBuffer` 和 `BoundedEventDispatcher`。关闭时先使 scope 失效并停止接收，
  再取消 source；Thread 切换、替换与 dispose 清空旧缓存和 dispatcher 队列，只有当前
  generation 的自然 `onDone` 才会有界 drain 已接收事件。detached runtime 事件仅可在
  scope 仍当前时按既有 critical allowlist 接收，旧 `onDone` 不得释放新 Pipeline。
- Transport 与 Provider mapper 不得丢弃协议事件。`AgentEventCoalescingPolicy` 只定义
  Agent key、merge 与 barrier；通用 `CoalescingEventBuffer` 只实现有界 keyed 合并。
  Application 投影层只允许合并同一
  thread/turn/item/kind 的连续文本或 reasoning delta、token/diff 最新快照和工具 progress；
  item/工具/turn 终态、审批、错误和连接状态必须先 flush 缓冲后立即发布。背压诊断不得包含正文。
- `BoundedEventDispatcher` 保持 FIFO，默认每个 Dart event-loop turn 最多处理 64 个事件，
  continuation 使用 `Timer.run` 让步；名称和职责不得与 Flutter frame 调度混淆。
- 规范化事件必须由 `AgentConversationEventProcessor` 编排。`AgentConversationReducer`
  只能同步产生 typed state、`AgentTimelineMutation`、ThreadSnapshot、
  `AgentUiUpdateRequest` 与 `AgentConversationEffect`；不得导入 Flutter scheduler、创建
  Timer、执行 Future 或调用外部端口。live/history/replay 必须使用隔离的 reducer/context，
  不得共享可变 identity、错误去重或 deprecation 状态。
- Processor 只登记 ThreadSnapshot 刷新；实际 listenable 写入必须与 typed UI state 共用
  presentation scheduler 的安全发布回调，不得在 Flutter build phase 同步通知 Shell。
- TimelineStore 可以继续执行增量 mutation，但不得决定 UI urgency、读取 Provider raw 字段
  或增加 Codex/Grok 分支。外部回调、模型目录持久化和结构化错误日志由 EffectRunner 执行，
  且执行前必须校验 listener generation、runtime/epoch 与必要 thread scope。
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
- `entryId` 是 Zeta 规范化时间线条目身份，也是 CoalescingPolicy/Buffer、TimelineStore 和 UI
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

- 当前活跃 Provider 只有 Codex 与 Grok。共享 ACP decoder 只能解析协议语法和 typed
  字段，必须无状态；Grok data adapter/reducer 负责解释 source id、segment/phase、去重
  和 lifecycle，Codex mapper 按 app-server item 生命周期确定 entryId。共享层不得提供带
  eventId/turn scope 叙事假设的 identity mapper；Store/ViewModel/UI 不得读取 raw payload
  推断 identity 或 plan。
- live、replay、history 可以复用同一 reducer 算法和 entry-id builder，但必须使用不同
  实例，不得共享 current segment、seen event/tool、terminal 或 generation 状态。
- live 状态至少按 `(runtimeId, connectionEpoch, providerId, sessionId, turnId)` 隔离；
  新 turn、cancel、prompt 失败、peer close、provider dispose、epoch 变化和 session
  删除/切换必须使旧状态失效。replay/history 在 build、失败或取消后也必须释放状态。
- CoalescingPolicy/Buffer 只允许合并同 entryId、同事件 kind 和同必要 detail 的事件；任一非合并
  事件先 flush。它不得推断“最后一个开放气泡”或替代 Provider boundary 状态机。
- TimelineStore 只执行 dumb merge：同 entryId 更新、异 entryId 新建、同 tool id 原地
  upsert，不读取最后条目猜边界、不改写 id、不分配 segment，也不包含 Provider 分支。
  新增 Provider 只需在 data 层实现 decoder/adapter/reducer 并输出完整 `AgentEvent`，无需
  修改 CoalescingPolicy/Buffer 或 TimelineStore。
- eventId、messageId 稳定性和 delta/snapshot 语义必须由带 Provider/CLI 版本的脱敏
  fixture 证明；缺少真实证据时明确阻塞对应门禁，禁止复制其他 Provider 的假设。
- History parser 只能只读来源文件；Grok 每次解析必须创建 fresh reducer，缺少稳定 turn id
  时使用确定性的 history turn ordinal。live/history canonical regression 必须逐位置比较 turn/entry
  ordinal、entry type、message/reasoning phase、source id、规范化文本和 tool kind/status。
- Cursor 已退役，不参与 catalog、UI、Provider 组合、live/replay/load、ACP 扩展或进程启动。
  仅允许保留旧配置 decode/fallback、明确 unavailable、退役证据和用户数据未改写回归；
  `~/.cursor`、项目 `.cursor` 与 `cursor_sessions.json` 不得读取、迁移、改写或删除。

### 4.2 共享适配层纯度门禁

本节中的“共享适配层”包括共享协议 decoder/codec/transport、
`AgentEventPipeline`、`AgentEventCoalescingPolicy`、`CoalescingEventBuffer`、
`BoundedEventDispatcher`、`AgentConversationTimelineStore`，以及消费中立
`AgentEvent` 的 application/presentation 投影。它们是 Provider 无关的机制层，
不是安放厂商兼容逻辑的兜底层。Grok、Codex 等 Provider 自有的 mapper、adapter、
reducer 和 history parser 不属于共享适配层。

共享适配层只允许承担以下职责：

- 按公开的通用协议契约做无状态语法解码，并输出 typed protocol update；
- 按中立 domain 字段执行可由类型直接证明的通用行为，例如同 entryId 合并、
  同 tool id upsert、按事件 kind 维持 flush barrier；
- 执行与 Provider 无关的生命周期、缓冲、存储和 UI 投影，不补充任何协议语义。

以下行为一律禁止：

- import 或依赖 Grok、Codex、已退役 Cursor 等具体 Provider 实现；
- 根据 `providerId`、Provider kind、实现类型、显示名称或 CLI 名称分支；
- 从 raw/extra payload、厂商字段、eventId 或 source id 猜测 entryId、message segment、
  reasoning phase、plan、叙事边界、去重、终态或错误恢复策略；
- 在 CoalescingPolicy/Buffer、TimelineStore、ViewModel 或 UI 中为某个 Provider
  修复乱序、缺 id、
  delta/snapshot 差异或终态竞态；
- 为接入新 Provider 修改 Store 的合并规则，或在共享层增加以 `unknown`、最后开放条目、
  `#segN` 等启发式生成/修复身份。

如果共享层确实需要新的行为，必须先把它建模为名称和语义均与 Provider 无关的 typed
domain contract，并证明至少是协议级或跨 Provider 的共同语义。仅由单个 Provider 原始字段
驱动的行为不得通过 raw map、魔法字符串或隐藏 flag 穿透到共享层；它应由该 Provider
adapter/reducer 消化后输出语义完整的 `AgentEvent`。共享 decoder 的协议版本兼容也只能基于
通用协议证据，不得以 Provider 名称作为条件。

该边界是新增 Provider 和流式改动的评审门禁：正常接入只修改 Provider data 层、组合边界和
Provider 契约测试。若 PR 因 Provider 差异修改 CoalescingPolicy/Buffer 或 TimelineStore，
必须先证明这是中立
契约缺口；否则应退回 Provider adapter/reducer。共享层测试应使用 Provider 无关 fixture，
并持续断言无具体 Provider import、kind/id 分支和 raw identity 推断。

## 5. 持久化与恢复

持久化数据必须可演进、可恢复、可容错。

- Zeta 自有配置、状态、派生索引、日志和预留缓存统一位于 `~/.zeta`：
  `config/providers.json`、`config/appearance.json`、`state/ide_session.json`、
  `state/cursor_sessions.json`、`state/usage_statistics_index.json`、
  `state/migration_marker.json`、`logs/zeta-YYYY-MM-DD.log` 与
  `cache/agent_models_v1.json`。
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
- provider 模型目录由 app 级共享仓储统一读取和缓存。启动预热不得阻塞主界面，只预热
  active provider；普通读取采用 stale-while-revalidate 与 single-flight，显式刷新绕过
  provider 内存缓存。共享仓储是 TTL 的唯一真源；refresh loader 必须读取 Provider 权威
  来源。single-flight identity 必须包含安全配置指纹，并以 generation/version 守卫阻止
  失效配置的旧任务回写。协议分页必须完整拉取，失败不得覆盖最近一次可用目录。
- 相同模型目录的 response 与 runtime event 不得重复持久化；实际内容未变化的主动事件应
  保留现有快照，成功的 TTL 刷新即使目录未变化也必须更新获取时间并持久化。
- 模型目录缓存只持久化规范化 domain 白名单字段、不含密钥的配置指纹与获取时间；不得
  保存 provider raw payload、环境变量值或凭证。损坏、版本不兼容、配置变化和超期均应
  宽容失效。
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
  Widget 加 Key 不足以保证父级 Element 复用。保活实现必须只布局活动页面；禁止用
  `IndexedStack` 保留包含长时间线的页面或会话。
- 连续 resize 只允许按布局语义档位更新业务树。`IdeConstraintBucketBuilder` 的稳定
  callback 不得因父级每像素重建而失效；捕获了新配置的 callback 必须显式改变身份。
- Agent 时间线必须使用 block / activity / footer 粒度的稳定 viewport item 与
  `SliverList.builder`。隐藏会话 layout 增量必须为 0，可见 item 构建数必须受 viewport
  限制，不得随全部历史长度线性增长。
- turn grouping、unified diff 和代码高亮分别使用 render revision cache、projection
  cache 与稳定 `HighlightView` identity；数据未变化的 resize 解析增量必须为 0。
- Footer、Pending interaction 与 Active plan 必须在单次 layout 内定位；禁止
  post-frame 读取高度后 `setState`。
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
- resize 相关测试至少覆盖外窗 1197/1196/1195px、Agent Canvas 641/640/639px、隐藏
  retained page 的 build/layout 增量、viewport item 构建上界、缓存命中和 transient
  callback 不增长。
- 主要页面切换必须使用实际 `IdeHome` 做集成级 Widget 测试。Agent → Settings → Agent
  与 Agent → Usage → Agent 至少验证常驻骨架、AgentPane Element、当前 Thread、草稿、
  非零滚动位置、Pane 宽度和 Pane 可见状态保持。
- 简单视觉调整可以只运行分析和相关 widget test，但行为变化必须补测试。
- 外部 CLI 的自动化测试不能替代真实平台验收。Beta provider 发布前使用脱敏 smoke，分别
  记录 OS/架构、CLI 版本、Schema/包装器类型和结果；没有设备或凭据时必须标记“待执行/阻塞”，
  不得推断通过。真实 smoke 使用临时 workspace、最小权限和非破坏性 prompt。
- smoke 记录不得包含 Prompt、回复、文件内容、凭证、原始协议 payload、thread/turn id 或
  stderr 原文；实验协议缺少预期事件时必须记录实际差异并返回失败，不能用 stable Schema
  或 fake peer 结果替代。
- Windows resize 性能改动必须用 `flutter run -d windows --profile` 采样，不得以
  Debug、估算或主观手感代替。固定场景记录 UI/Raster p95 与慢帧率；如未达 16.7ms /
  5%，只能在同构基线和结构计数均满足时引用相对改善，缺失基线不得补值。

评审时优先检查依赖方向、协议泄漏、异步竞态、持久化兼容性、文件系统性能和 UI 溢出风险。
