# 设计文档

最后更新：2026-08-12

## 1. 设计目标

Zeta 的设计目标是让 Flutter UI、Agent provider、会话持久化和本地文件系统访问保持清晰分层。当前实现采用轻量 feature-sliced 结构，不引入大型架构框架；活跃 Provider 为 Codex app-server、Grok ACP 与 Claude Code stream-json，统一收敛到中立 provider 抽象。

## 2. 总体架构

当前代码按 `lib/src` 下的 app、core、features、ui 分层组织。重构后的核心原则是以 feature 为内聚边界，在 feature 内再按 domain、application、data、presentation 拆分职责：

- app：应用根组件、窗口启动、应用常量。
- core：日志、Zeta 数据路径与原子文本写入等跨层基础能力。
- features/agent：Agent provider 抽象、Codex app-server、Grok ACP stdio、Claude Code stream-json、传输、历史解析、事件映射、对话 view model 和 Agent pane。
- features/agent_management：Agent CLI 检测、版本与账号诊断、模型读取、配置安全编辑、
  CLI 磁盘日志读取和管理页面。
- features/ide_session：会话状态、版本化持久化、恢复计划和恢复协调。
- features/desktop_notifications：Provider 中立注意力信号的可见性判定、
  进程内未读、系统通知和平台任务栏/Dock 端口。
- features/project_threads：项目 thread 快照、列表状态、分页控制器和 presentation view model。
- features/usage_statistics：跨项目调用记录、统计口径、Codex 历史索引、套餐限额与
  使用统计页面。
- features/workspace：文件树规则、树构建、文件节点映射和文件 pane。
- ui/core：窗口框架、主题、通用面板和共享 UI primitives。
- ui/features/ide：IDE shell 视图；Provider 设置控制器位于 agent/application。

依赖方向保持为 presentation/application 依赖 domain 接口，data 实现 domain 接口，app 负责组合默认实现。UI 不直接处理 Codex 原始协议或持久化 JSON。Provider 自有 data adapter 可以按明确功能读取对应 CLI 的私有数据，但只向上返回中立模型，不暴露原始路径或 payload。

## 3. 运行时结构

```text
main()
  -> ZetaDataPaths (~/.zeta)
  -> ZetaStorageMigrator (legacy SharedPreferences -> JSON files)
  -> daily app log (~/.zeta/logs)
  -> MainApp
    -> AgentProviderRuntimeRegistry（Provider 进程唯一所有者）
    -> AgentProviderGlobalRuntime（每个 Provider ID 一个全局实例）
    -> AgentConversationBindingManager（会话映射 + 10 分钟空闲回收）
    -> IdeShellController
    -> IdeHome
      -> WindowFrame（常驻）
        -> IdeWorkbenchScaffold（常驻）
          -> Navigation slot
            -> ProjectListPane | SettingsNavigationPane
          -> Canvas slot（保活页面栈）
            -> AgentPane
            -> SettingsPageCanvas
              -> AgentManagementPage
            -> UsageStatisticsPage
          -> Inspector slot
            -> FileTreePane | Tools

IdeShellController
  -> IdeSessionStore
  -> AgentProviderSettingsController
  -> AgentThreadWorkspaceController -> 每个 Pane 持有 ConversationBinding lease
  -> AgentConversationViewModel -> 固定 Binding（不持有 Provider lease/scope/pin）
  -> ProjectThreadsController

AgentConversationViewModel
  -> AgentEventPipeline（事件资源唯一所有者）
    -> AgentProviderEventListenerGate
    -> AgentEventCoalescingPolicy + CoalescingEventBuffer
    -> BoundedEventDispatcher（Dart event-loop，每 turn 最多 64）
    -> AgentConversationEventProcessor
      -> AgentConversationReducer（live/history/replay 独立实例）
      -> AgentConversationTimelineStore
      -> AgentConversationEffectRunner
        -> turn completed / attention / model catalog / structured error log
      -> AgentConversationThreadSnapshot
  -> AgentUiUpdatePort
    -> AgentUiUpdateScheduler（presentation，按 Flutter frame 合并）
      -> SchedulerBindingAgentFrameScheduler
      -> AgentConversationUiStateStore
        -> header/composer/pending/expansion/history typed listenable
        -> live turn 增量通知 + AgentUiEffect stream
  -> AgentConversationModelSelectionController
  -> AgentConversationModeController
  -> AgentPlanExecutionHandoffController
  -> Binding / GlobalRuntime 提供的 AgentProviderBundle 端口
    -> AgentRuntimePort / AgentConversationPort
    -> AgentThreadCatalogPort? / AgentThreadSubscriptionPort? / AgentThreadNamingPort?
    -> AgentThreadArchivalPort? / AgentThreadDeletionPort? / AgentThreadCompactionPort?
    -> AgentThreadBranchingPort? / AgentTurnSteeringPort?
    -> AgentPermissionResponsePort? / AgentQuestionResponsePort? / AgentDeniedActionOverridePort?
    -> AgentModelCatalogPort?
    -> AgentLocalThreadListPort? / AgentSessionConfigurationPort? / AgentPlanApprovalPort?
    -> AgentConversationModeCatalogPort?

AgentProviderRuntimeRegistry
  -> AgentProviderBundleFactory.createBundle
    -> CodexAppServerAgentProvider -> JsonRpcPeer -> codex app-server stdio
    -> GrokAcpAgentProvider -> JsonRpcPeer -> grok agent stdio
    -> ClaudeCodeAgentProvider -> StreamJsonPeer -> claude stream-json stdio

ProjectThreadsController
  -> AgentProviderBundle
    -> AgentThreadCatalogPort? / AgentThreadNamingPort? / AgentThreadArchivalPort?
    -> AgentThreadDeletionPort? / AgentThreadBranchingPort?

AgentManagementController
  -> CodexAgentManagementRepository | GrokAgentManagementRepository
     | ClaudeCodeAgentManagementRepository
    -> CLI 身份、版本与登录态检查
    -> Codex/Grok 通过共享 runtime lease 执行无模型 turn 的协议握手
    -> Claude 认证证据走 auth status；显式连接测试只发无 Prompt initialize
    -> provider 对应配置与脱敏诊断

UsageStatisticsController
  -> UsageStatisticsRepository
    -> CompositeUsageStatisticsRepository
      -> CodexUsageStatisticsRepository
        -> 本地 Codex rollout JSONL 历史
        -> 版本化派生索引（providers.codex 分区）
        -> 可选 account/rateLimits/read（套餐）
      -> GrokUsageStatisticsRepository
        -> 本地 Grok updates.jsonl 历史
        -> 版本化派生索引（providers.grok 分区）
        -> 可选 AgentUsageQuotaProvider / `_x.ai/billing`
      -> ClaudeCode AgentUsageQuotaProvider
        -> initialize account metadata（套餐名称）
        -> 可关闭的 OAuth usage REST（额度窗口）

DesktopAttentionController
  -> GeneralSettingsController
  -> DesktopNotificationService -> flutter_local_notifications
  -> DesktopAttentionIndicator -> Windows taskbar flash / macOS Dock badge / Linux urgency
  -> IdeHome visibility + IdeShellController thread activation
```

Agent turn 终态、权限、问题、Provider 计划审批和本地 Plan 执行交接统一转换为
`AgentAttentionSignal`。只有在目标 Agent thread 不可见时才发系统通知；点击通知
恢复窗口并选中对应 Provider thread。详细契约、幂等、脱敏和平台实现见
[Agent 桌面通知与任务栏未读提醒详细设计](desktop_agent_notification_design.md)。

## 4. UI 设计

### 统一 Workbench 页面骨架

`IdeHome` 是主要页面唯一的 Workbench 组合边界。`WindowFrame` 与
`IdeWorkbenchScaffold` 在页面切换期间保持同一 Element 和稳定 Key，首页、设置、
Agent 管理与使用统计只切换 Navigation、Canvas、Inspector slot 内容，不再创建相互
独立的顶层页面骨架。工作台外圈 padding 由 `IdeHome` 统一提供（左右/底 `space8`，
顶部 `space0` 与标题栏贴齐，中间不画分隔线）；Scaffold 外侧贴边。Feature 仍持有
自己的业务组件和离开确认逻辑，共享 Scaffold 只做布局与 Overlay 编排。

| 页面 | Navigation slot | Canvas slot | Inspector slot | 响应式策略 |
|---|---|---|---|---|
| Agent 首页 | `ProjectAgentSidebar`：Projects / Threads + Agent 统计 | 常驻 `AgentPane` | Files / Tools | Wide/Medium 内联合并 Navigation；Compact 复用 Navigation Overlay；首页不挂载 Activity Rail |
| 设置 / Agent 管理 | `SettingsNavigationPane` | `SettingsPageCanvas`，Agent 分区内承载 `AgentManagementPage` | 无 | 所有模式内联设置 Navigation，不挂载 Activity Rail |
| 使用统计 | 无 | `UsageStatisticsPage` | 无 | 所有模式只占用 Canvas，`WindowFrame` 与 Workbench 骨架继续保留，不挂载 Activity Rail |

Agent 首页的标题栏左侧 action 是合并栏唯一的显隐入口：macOS 位于三色灯 gutter
之后，Windows/Linux 位于 Logo 与菜单之前；左栏隐藏后入口仍可操作。Navigation slot
内只有一个 `ProjectAgentSidebar` / `PanelCard`，Projects / Threads 占剩余空间，
cardless Agent 统计固定在底部并默认折叠。折叠态最多展示 Provider 图标、套餐名（无
套餐时显示 Provider 名）、最短周期额度进度和今日 Token；展开态以 Provider Tabs、
右侧折叠/刷新操作和完整明细按内容自然撑高，不显示独立标题栏、拖动分隔或内部纵向滚动。Compact 模式不挤压 Canvas，而是使用
Navigation Overlay；scrim 与 Esc 均关闭浮层并把焦点还给标题栏入口。

Canvas 与 Agent 会话都使用 `IdeRetainedPageView` 延迟挂载并保活已访问页面；任一时刻
只布局活动页面和活动 `AgentPane`，离屏页保留 State、输入/滚动控制器并暂停 ticker。
Workbench 的 Canvas Flex slot 自身也使用稳定 Key，保证 Navigation/Inspector slot
增删或 Wide/Medium 断点切换时仍复用原 Element。左栏显隐、统计展开态、左栏宽度和
统计 Provider 选择投影进应用级 `IdeWorkbenchLayoutState`，随 `ide_session.json`
宽容恢复；旧高度比例字段只为历史快照保留，不再参与布局。离开其他页面
再返回时，这些偏好与 AgentPane / Thread / 草稿 / 滚动位置都保持不变。

`AgentPane` 以 compact / regular 离散宽度档位缓存结构，父级每像素 resize 只有在回调
身份或档位变化时才使缓存失效。对话时间线使用 `CustomScrollView` +
`SliverList.builder`，按稳定的 block、live activity 和 turn footer item 虚拟化；
projection 与 unified diff 以 turn render revision 缓存，代码高亮复用
`HighlightView` identity。Composer、Pending interaction 与 Active plan 在一次
`CustomMultiChildLayout` 中确定位置，不使用 post-frame 高度反馈。

设置 Feature 对 Workbench 暴露 `SettingsNavigationPane` 与 `SettingsPageCanvas`；
`SettingsPageCanvasState.confirmCanLeave()` 继续负责 Agent 配置编辑器的未保存内容确认，
业务规则没有下沉到 `IdeWorkbenchScaffold`。

### 三栏工作台

- Projects：展示已打开项目、当前项目状态和项目下的 Agent threads；项目项与
  thread 项仅保留水平 padding，不设置垂直 padding，以维持紧凑的桌面列表密度。
- Agent：展示上下文栏、状态胶囊、流式消息/思考/计划时间线、typed 文件变更证据、工具与审批卡片、本地图片输入区。
- Files：展示当前项目文件树，目录按需展开，文件选择只更新 Agent 上下文。

### Agent 管理

- 设置页提供 Agent 列表和独立详情，列表状态、搜索与筛选在返回时保留。
- 当前支持 Codex、Grok 与 Claude Code。Cursor 已退役，不出现在“全部支持”、配置、检测或安装入口中。
- 详情包含基础诊断、模型和 provider 对应配置；桌面端双栏，窄窗口上下排列。
- 自动检测只做本地版本、账号 metadata 与日志路径检查。Claude Code 的显式连接测试
  只发送无 Prompt 的 initialize control frame；它不调用模型，但 Claude CLI 仍可能维护
  自身认证/bootstrap 缓存。
- 禁用 Codex 后不再允许创建可写会话；既有会话仍可读取历史，输入区隐藏并显示
  只读提示。

### 使用统计

- 标题栏提供与设置同级的全局入口；页面支持时间、项目、Agent 和模型筛选。
- Agent 首页底部仅展示同一中立统计模型的只读摘要；前台或后台 thread 终态携带的
  Provider 会更新统计选择并触发静默刷新，但不得改写会话 active Provider、Provider
  配置或运行时绑定。
- 一次 Codex turn 计为一次调用；`completed` 为成功，`failed` 与 `interrupted`
  为失败，运行中和未知状态不进入成功率分母。
- 默认统计 CLI、VS Code、`codex exec` 和 Zeta app-server 发起的根 thread，包含
  已归档 thread，排除子 Agent 以避免重复计数。
- 历史 TTFT 只使用 Codex 明确返回的 `time_to_first_token_ms`；缺失样本不做
  近似，并在页面标明有效样本数。
- 套餐仅展示 Provider 实际返回的套餐类型、百分比窗口、重置时间与可选余额：Codex
  走 `account/rateLimits/read`，Grok 走 ACP 扩展 `_x.ai/billing`；Claude 套餐名称来自
  CLI initialize，额度详情可选走 `/api/oauth/usage`。不推算绝对 Token 总额度、币种或
  未提供的到期日，也不提供登录、购买、续费或支付动作。
- 宽屏使用双栏分析区，窄窗口切换为单栏；表格可横向滚动，任务详情使用自适应
  侧边/底部抽屉。
- `UsageStatisticsIndexStore`（v3）按 Provider 分区持久化派生会话快照：只含
  sourceId / fingerprint / thread·turn ID、时间、项目、模型、状态、时延、Token
  与错误分类；不保存 Prompt、回复正文、session 文件路径或原始错误文本。Codex 与
  Grok 均走 fingerprint 增量扫描，并行写入经 `mergeSave` 合并。

### 主题与设计系统

- **表面阶梯是严格单调的**，深浅主题共用一条规则：`frame` 永远是离内容最远的
  一档，往内依次 canvas → pane → control → popover。深色（Graphite Night）由外
  向内逐档提亮，落在 `sf.Colors.neutral` 的 950 → 800 区间，是单色炭黑；浅色
  （Graphite Day）方向相反，frame 最灰、canvas 纯白。**具体色值由
  `IdeColors.fromShadcnColorScheme` 从 `sf.Colors` 程序化派生，本文不复制 hex**，
  以免文档与代码漂移。
- **零阴影法则**：层级只靠上面这条明度阶梯加 1px 极低透明度描边表达。业务代码
  不允许手写 `BoxShadow`，也不允许 Material `elevation`。唯一豁免是脱离文档流的
  浮层（菜单 / popover / toast / 窄屏浮层面板），它们用 `IdeEffects.overlayShadow`
  的极淡投影做兜底，主分层手段仍是更亮的 popover 表面加描边。
  守卫见 `test/src/ui/core/ide_visual_token_guard_test.dart`。
- **描边与交互态是半透明叠加**而非不透明色：`white @ 8%` 叠在炭黑上是一条发丝线，
  换成不透明灰就变成一条灰带。同理 hover 是「把背景提亮 5%」，因此它必须能叠在
  任意表面上，元素自身颜色不变。
- 点缀色克制：品牌蓝向中性灰回拉一档降饱和（HSL 饱和度 < 0.8），且只在发送按钮、
  选中指示线这类核心行动点出现；列表与 Tab 的选中态一律用中性半透明叠加。
- 语义色独立：success 绿 / error 红 / warning 琥珀 / info 蓝；
  diff 增删行使用 success/error。`intelligenceAccent`（紫）是单色体系里唯一
  存活的第二色相，它编码「最高推理档位」这个真实状态，属于有意的语义豁免。
- 前景色守 WCAG AA：`textPrimary` / `textSecondary` / `textTertiary` 在四档表面上
  都必须 ≥ 4.5:1。10px 的时间戳用的就是 `textTertiary`，最容易踩线——层级弱化靠
  字号和字重，不靠压对比度。回归断言在 `test/src/ui/core/ide_colors_test.dart`。
- 全部视觉取值集中在 `lib/src/ui/core/` 的 token 类：`IdeColors`（语义色）、
  `IdeRadius`/`IdeShapes`/`IdeEffects`（圆角四档、容器形状与浮层阴影、scrim）、
  `IdeSpacing`（4px 基准间距）、`IdeTextStyles`（语义字号）、
  `IdeMetrics`（组件尺寸与响应式断点）、`IdeMotion`（动效）。
- 圆角四档 **4 / 6 / 8 / 12** + pill，按「元素有多大」分配：
  micro 4（标签、hover 高亮、行内小块）、small 6（按钮、输入框、代码块、列表行）、
  medium 8（卡片、状态卡、Composer 外卡）、large 12（侧栏面板、画布、浮层）。
  **嵌套时内层必须严格小于外层**，典型链路是面板 12 → 卡片 8 → 代码块 6 → 行内高亮 4。
- **`shadcn_flutter` 的 `ThemeData.radius` 必须保持 `0.5`**。shadcn 把这个乘数
  展开成固定阶梯 `radius × 4/8/12/16/20/24`，取 0.5 才能让它精确落在 `IdeRadius`
  上（sm→4 / md→6 / lg→8 / xxl→12）。改成别的值会立刻产生两套相差 1~2px 的平行
  圆角体系——差距不够大到像有意为之，只够大到让并排的 sf 控件和 Ide 控件
  看起来「圆角没对齐」。
- **只有面板档（12px）使用平滑圆角**（`RoundedSuperellipseBorder`，Flutter 3.32+
  内置的 rounded superellipse），通过 `IdeShapes.panel()` 消费，生效于 `IdeSurface`
  的 pane/popover/canvas 与 `PanelCard`。控件档一律保持圆形圆角：superellipse 的
  路径差异随半径线性放大，4~8px 上肉眼不可辨，而 `BoxDecoration` 无法表达
  superellipse，全量迁移要把大量热路径组件改成 `ShapeDecoration`，纯成本无收益。
  注意 `shadcn_flutter` 的组件参数只接受 `BorderRadius`、不接受 `ShapeBorder`，
  所以 sf 渲染的表面必然是圆形圆角——把平滑圆角限制在面板档也避开了这层
  无法统一的混合状态。
- 字体分工：界面文本用内置 Geist（`bundledUiFontFamily`），
  **机器标识符与数值一律用内置 JetBrains Mono**（`bundledCodeFontFamily`）。
  对应 token 为 `identifier`（模型 ID、Provider 名、thread ID）、
  `numeric`（表格数字列，启用 `tabularFigures` 并右对齐）、
  `metricValue`（指标大数字，同样等宽 + `tabularFigures`），
  路径类次级标识符继续用 `codeSmall`。
  UI 样式按界面字号缩放，等宽样式按代码字号缩放，两者在设置页各自可调。
- Geist 不含中日韩字形，中文由 `resolvePlatformUiFontFamilyFallback`
  的平台回退链（PingFang SC / Microsoft YaHei UI / Noto Sans CJK SC）承接；
  外观设置里「跟随应用默认」解析到内置 Geist，用户仍可显式改回系统字体。
- Graphite token 通过 `IdeThemeScope` / `IdeThemeData` 成为运行时真源；
  `buildShadcnTheme` 只把项目 token 投影到 `shadcn_flutter` 的 `sf.ThemeData`，
  不再反向从第三方 theme 回读语义色。
- 第三方组件统一 `import ... as sf;`；业务页面优先消费 `ui/core` primitives
  （`Pane` / `PanelCard` / `IdeTabs` / `IdeTab` / `IdeChip` / `IdeButton` /
  `IdeSelect` / `IdeContextMenu` / `showIdeToast` 等）。
- 业务代码禁止硬编码颜色、圆角、阴影和字号；需要新字号时加 token，
  不要在调用点写 `fontSize:`（那会绕过用户的字号设置）。
- 面板圆角 12、卡片 8、间距紧凑，适合桌面工具密度：页面内边距按 IDE 而不是
  移动端取值，省下的空间还给内容行数。
- **会话区是文档流，不是卡片流**：Agent 正文、最终答复、工具调用、命令组、
  文件编辑一律无边框无底色，文字直接落在画布上。回合之间只用「大留白 + 一条
  全宽 1px `borderSubtle` 发丝线」分隔，元信息作为落款贴在线下右侧。
  仍保留容器的只有**待用户操作的交互面**（Plan 交接卡、权限卡、提问卡）和
  **需要显眼的错误/警告**（`IdeStatusCard`）；代码块底色属于可扫描性，不算容器。
- **身份锚点靠对比度和字重，不靠颜色**：用户消息用 `textTertiary` 的 2px 左竖线
  + 等宽 w600 角色前缀 + w500 正文，与 Agent 长文的 w400 拉开一档。单色体系里
  染色不是可用手段。
- **操作记录块内紧、块外松**：连续操作组之间只留 2px，与正文交界处留 10px，
  折叠箭头放在行首而不是行尾——右对齐的箭头会被标题推到画布最右，中间的空白
  在视觉上读成一条横规。改这些间距时必须同步
  `agent_timeline_extent_descriptor.dart` 的高度估算，否则长会话滚动会跳动。
- 极简边框：分隔一律是 1px `borderSubtle`。横向用
  `IdeRowDivider`，纵向用 `IdeColumnDivider`；不要使用 Material
  `Divider` / `VerticalDivider`。进度指示统一走 `IdeBusySpinner`
  （支持不确定态与 `value` 确定态）和 `IdeLoadingIndicator`。

## 5. Agent 设计

### Provider 抽象

Application / Presentation 只以 `AgentProviderBundle` 的中立端口作为能力入口。
工厂通过 `AgentProviderBundleFactory.createBundle` 直接创建原生 Bundle；Provider
实现类只实现自己真实支持的端口。旧 `AgentProvider` 大接口与 `adapt()` 已删除。

`AgentProviderBundle` 当前负责把会话与线程能力拆成明确端口：

- 必选：`runtime`、`conversation`。
- 可选：`threadCatalog`、`threadSubscription`、`threadNaming`、`threadArchival`、
  `threadDeletion`、`threadCompaction`、`threadBranching`、`turnSteering`、
  `permissionResponses`、`questions`、`deniedActionOverride`、`modelCatalog`、
  `localThreadList`、`sessionConfiguration`、`planApproval`、`permissionPolicy`、
  `conversationModes`、`skills`、`usageQuota`。

`AgentRuntimePort` / `AgentConversationPort` 与各可选端口承载具体 CLI 对接和
运行时边界，核心职责包括：

- 通过 `AgentProviderCapabilities` 声明 session、history、turn、thread、input、
  interaction、config、telemetry 和 bootstrap 能力；厂商默认值由 data 组合层注入。
- 初始化 provider（含握手后的 capability 收敛 / 通知 opt-out）。
- 创建和恢复 session；切换会话时 best-effort `unsubscribeThread`。
- 列出项目 threads、读取 thread 历史。
- 发送、追加和取消 turn（`sendMessage` / `steerTurn` 支持多输入项）。
- 响应权限请求；他端已解决的审批通过事件撤销本地卡片。
- 推送状态、消息、推理/计划流、工具调用、文件变更快照、审批与系统提示事件。

当前 `AgentConversationViewModel` 与 `ProjectThreadsController` 通过 bundle
消费上述端口；Agent 管理页中的模型探测也统一走 `bundle.modelCatalog`。应用层不再
需要通过 provider kind 或运行时类型判断决定这些功能域。

capability 与 bundle 端口都采用保守声明：端口缺失或 capability=false 的操作不进入
Project thread 菜单、Agent header 或 composer，应用层误调用时抛出
`UnsupportedError`。`AgentProviderBootstrapPolicy` 额外约束 provider 是否必须在
workspace 下启动、是否允许 eager model preload。

所有 JSON-RPC provider 在裸 transport 外统一使用 `ProviderRuntimeJsonRpcPeer`。该边界
维护 `stopped / starting / initializing / ready / failed / closing / closed` 生命周期，
为每次连接生成 `runtimeId + connectionEpoch`，并把 scope 注入服务端反向请求。进入
`closing` 后拒绝新的 client RPC；关闭 transport 后等待已入场的 start、RPC 和
server-request handler 排空。Codex 的 `AgentRuntimeInfo` 同步暴露 runtime identity，
Grok 通过 `AgentRuntimePort.lifecycleState` 暴露中立生命周期，不把协议状态泄漏到 UI。

Provider 事件进入对话详情前由 `AgentEventPipeline` 集中管理。每次绑定以
`runtimeId + connectionEpoch + providerId + threadId + listenerGeneration` 标识；新监听先安装、
旧监听后取消，且旧监听退出只能释放自身 generation。Codex/Grok 均通过可选
`AgentRuntimeScopeProvider` 提供当前连接作用域，因此快速切换 Thread、Provider 重启和 dispose
交叉不会把旧流投影到新会话。Pipeline 先使 listener scope 失效并停止接收，再取消 source；
Thread 切换、替换与 dispose 清除旧缓存和 dispatcher 队列，只有当前 generation 的自然
`onDone` 才会有界 drain 已接收事件；detached runtime 仅在 scope 仍当前时按既有 critical
allowlist 接收。subscription、gate、buffer 与 dispatcher 不再由 ViewModel 分散持有。

高频事件在 Application 投影边界由 `AgentEventCoalescingPolicy` 与
`CoalescingEventBuffer` 合并：同 item 文本/reasoning delta 追加，同 turn token/文件变更完整快照取
最新，同工具 progress 按协议语义追加或替换。算法只维护 keyed FIFO、pending 上限和 barrier
flush，Agent key/merge/barrier 规则留在 policy。Transport
和 Provider mapper 仍无损消费；完整 item、工具/turn 终态、审批、错误和连接状态会先 flush
缓冲再立即发布。缓冲上限只产生不含正文的计数诊断，并触发即时 flush。输出由
`BoundedEventDispatcher` FIFO 交付；每个 Dart event-loop turn 默认最多 64 个，续批使用
`Timer.run`，与 Flutter frame 调度相互独立。

流式身份链路固定为：Provider raw notification → 协议 decoder → Provider-local
adapter/reducer → 语义完整的 `AgentEvent` → `AgentEventPipeline` →
`AgentConversationEventProcessor`。Processor 使用纯同步 `AgentConversationReducer` 产生
typed state、`AgentTimelineMutation`、ThreadSnapshot、`AgentUiUpdateRequest` 与
`AgentConversationEffect`，再按固定顺序应用。source id 保存协议身份，entryId 是统一层唯一
合并键；TimelineStore 只执行同 entryId 更新、异 entryId 新建和同 tool id upsert，不猜开放
条目、narrative boundary 或 UI urgency。外部回调与异步工作只由 scope-aware EffectRunner
执行。新增 Provider 只扩展 data adapter/reducer 及其契约测试，无需修改 Store。

#### 流式适配职责矩阵

| 层级 | 输入与输出 | 拥有的决策 | 明确禁止 |
|------|------------|------------|----------|
| shared transport / decoder / codec | 原始帧 → typed protocol update | 通用协议语法、传输生命周期、字段类型 | mutable identity 状态、Provider 名称/kind/id 分支 |
| Provider mapper / adapter / reducer | typed/raw Provider update → 完整 `AgentEvent` | 厂商字段兼容、source→entry、segment/phase、boundary、去重、终态和迟到事件 | 把未决语义交给 Store/ViewModel 猜测 |
| `AgentEventPipeline` | `Stream<AgentEvent>` → 已隔离、有界交付的事件 | subscription/scope/gate/buffer/dispatcher 所有权与 close 顺序 | UI region、Widget、Provider raw identity |
| `AgentEventCoalescingPolicy` | `AgentEvent` → key/merge/barrier 决策 | normalized identity/kind/detail 的 Agent 合并规则 | 订阅生命周期、UI urgency、厂商 raw 字段 |
| `CoalescingEventBuffer` / `BoundedEventDispatcher` | policy 输出 → FIFO 事件批 | pending 上限、barrier flush、每 turn 上限与 event-queue yield | Agent 业务分支、Flutter frame 调度 |
| `AgentConversationReducer` | 规范化 `AgentEvent` + 只读 context → `AgentConversationMutation` | 接收规则、typed state、timeline/UI/snapshot/effect 描述 | Flutter 调度、Timer、Future、外部回调 |
| `AgentConversationEventProcessor` | `AgentConversationMutation` → 已应用状态 | state/timeline/snapshot 刷新请求/UI/effect 的确定顺序与 outcome 合成 | Widget、ChangeNotifier、Flutter build-phase 判断、Provider 协议分支 |
| `AgentConversationTimelineStore` | `AgentTimelineMutation` → timeline state | 同 entryId 更新、异 entryId 新建、同 tool id upsert | Provider 分支、开放条目推断、segment 分配、id 改写、UI urgency |
| `AgentConversationEffectRunner` | scope-aware `AgentConversationEffect` → 外部工作 | generation/runtime/thread 校验与一次性执行 | 修改 Timeline、在 reducer 内执行异步 |
| `AgentUiUpdateScheduler` / typed state store | `AgentUiUpdateRequest` → 局部 listenable/effect | Flutter frame 合并、结构相等发布、一次性 UI effect | 解释 `AgentEvent`、通知 Shell、持久化历史 |
| ViewModel / UI | typed state/timeline/domain state → 展示 | 中立 facade、局部监听与交互 | 完整 ViewModel listener、解析协议 payload、根据 Provider 猜 identity/plan |

依赖方向是单向的：共享层定义中立机制和契约，Provider data 层依赖这些契约并产出完整语义；
共享层不得反向 import Provider 实现，也不得通过 raw map、魔法字符串或隐藏 flag 接收单一
Provider 的业务策略。只有经过建模、命名与测试证明为协议级或跨 Provider 共性的 typed 语义，
才允许扩展共享契约。否则差异必须保留在 Grok/Codex 各自的 adapter/reducer 内。

因此，“新增一个 Provider 是否需要修改 CoalescingPolicy/Buffer 或 TimelineStore”也是架构健康度指标：正常
答案应为否。若答案为是，设计评审必须先证明是共享 domain contract 缺失，而不是 Provider
quirk、协议证据不足或 mapper/reducer 未完成归一化。

#### 文件变更证据契约与三 Provider 映射

文件变更统一为 `AgentFileChangeSnapshot`，但不强迫 Provider 伪造相同内容。snapshot 由
Provider-local tracker 按 tool 或 turn owner 维护稳定 change id、顺序、动作、单调 revision
与 replayability；同一 owner 的每次更新都是完整替换。`null` 表示没有结构化文件证据，空
`changes` 是权威清空。共享 Store 只按既有 tool/turn identity 机械携带，presentation 只按
`AgentTextReplacementEvidence`、`AgentWrittenContentEvidence`、
`AgentUnifiedPatchEvidence` 或无正文摘要渲染。

| Provider 输入 | 中立证据与降级 |
| --- | --- |
| Grok ACP `content[type=diff]` | `path + oldText + newText` → replacement；重复、status-only 与终态由 Grok tracker 带回完整快照 |
| Claude Code `Edit` | `file_path + old_string + new_string + replace_all` → replacement；`tool_result` 复用 `tool_use` 快照 |
| Claude Code `Write` | `file_path + content` → written content；动作无协议保证时保持 unknown |
| Claude Code `NotebookEdit` / `MultiEdit` | 只有已确认的路径/unknown 摘要，不解析未知正文 |
| Codex `fileChange` / `patchUpdated` / history ThreadItem | 结构化 changes → replayable tool-scoped unified patch |
| Codex `turn/diff/updated` | 仅在没有 tool 证据时产生 typed `liveOnly` turn fallback；后到 tool 证据由 Codex tracker 清除 fallback |
| Codex `commandExecution` | 保持命令工具，不解析命令、审批参数或工作区结果，不生成文件变更快照 |

unified patch 只用于展示高亮和统计，不能从 header 反推路径、动作或 identity。可回放证据的
live/history/replay 各自使用独立 tracker/reducer；替换片段、写入内容与 patch 只存在于内存
时间线，不进入日志、缓存、通知、thread summary 或持久化 JSON。

Agent Canvas 支持多 thread 常驻 entry。`AgentProviderRuntimeRegistry` 是进程唯一
所有者；`AgentProviderGlobalRuntime` 为每个 Provider ID 保留一个永不空闲回收的
全局实例，承载用量、目录、历史和 thread 操作。`AgentConversationBindingManager`
按草稿 key 或 thread key 唯一维护 Binding；Workspace entry 只持有 Binding lease。
Workspace 是 thread 身份的组合边界：创建 entry 时一次性注入 thread summary 与匹配的
Binding；ViewModel 没有 `switchThread` 或带恢复参数的通用 workspace 更新入口，只能更新
project/file context。打开另一个 thread 必须选择或创建另一个 entry/ViewModel。
打开草稿、打开已有 thread 和读取历史均不创建 session Provider，只有第一次提交输入
调用 `Binding.beginTurn()` 后才启动，并在已有 thread 上 resume。草稿取得 threadId 后
原子晋升，碰到已有 key 时 fail-closed。

Binding 持有该逻辑会话的可选 runtime、generation 过滤后的事件流、权限状态和活跃操作
计数。运行中 turn 与短 RPC 都阻止回收；终态/操作完成时间是新的 TTL 起点。Manager 每
分钟 single-flight 扫描一次，空闲满 10 分钟后按精确 runtime identity 条件失效，避免
ABA；registry 还保证旧进程 dispose 完成前同 scope 的 acquire 等待。回收后保留会话权限
默认值与 session effective，清除 runtime-only 状态；下一次提交才重建。配置失效或窗口
退出时统一关闭关联进程，global runtime 永不参与空闲回收。
Registry 的 `acquire` 必须显式传入 global/session scope；使用统计面板只通过
`AgentProviderGlobalRuntime` 获取配额，不保留 lease loader 或原始 Provider loader 兼容路径。
Project Threads 侧栏对**已打开** thread 的执行中/等待指示，以 entry 的
`AgentConversationThreadSnapshot` 为真源，经 shell 调用 `syncRuntimeSnapshot` 更新
`runningThreadIds`、摘要 `status`/waiting 与内存态 `completedThreadIds`。分区 UI 信号
（history/header/live 等）不替代 snapshot：任何改变 `isTurnRunning` 或 runtime status 的
路径（含 stream flush）必须同步推送 snapshot，避免详情已结束而列表持续 busy。
Processor 只登记 snapshot 刷新请求；实际 listenable 写入与 typed UI state 共用
presentation scheduler 的安全发布边界，build phase 内的 immediate 请求必须延至下一帧。

Provider 的 Thread 访问统一经过 `ProviderOperationScheduler`。列表使用 Project 级
`sharedRead`，历史读取使用 Thread 级 `sharedRead`；resume、fork、重命名、归档、删除和
压缩等变更使用 Thread 级 `exclusive`。同一资源上的连续读取可并发，独占操作保持 FIFO
并阻塞后续读取；不同资源仍可并发。Provider dispose 先停止调度器接收新任务，再关闭
连接并等待已入场操作结束，避免队列任务在关闭阶段重新发起 RPC。

### 默认 provider

当前活跃 provider 为 Codex CLI、Grok ACP 与 Claude Code stream-json，默认 active
provider 为 Codex CLI：

```text
codex app-server
```

Codex provider 通过 JSON-RPC stdio 通信，把 `thread/*`、`turn/*` 和 `item/*`
事件转换为领域层 `AgentEvent`。UI 不直接处理 Codex 原始协议。

Grok provider 使用 ACP stdio、本地历史和 xAI 扩展。标准 ACP
`session/update` 由无状态 `AcpSessionUpdateDecoder` 解码，再由 Grok mapper/reducer
确定流式身份；permission、content block 和 session config 分别复用
`AcpPermissionMapper`、`AcpContentCodec` 与 `AcpSessionConfigMapper`。session config option 与带稳定 id、
可多选的用户问答选项使用中立领域模型，供后续 ACP provider 共用。
`updates.jsonl` history 每次解析都会创建 fresh Grok mapper/reducer；messageId/eventId 仅作
source metadata，正文按 boundary 分段，reasoning 按连续 phase 聚合，tool update 按 id 在
原位置更新。History 与 live 不共享 epoch 或 mutable state，只以 canonical signature 对齐。

Claude Code provider 使用常驻 stream-json stdio；Provider 在写 user 帧前自行 mint
turnId，并在自有 identity/reducer 内完成消息分段、reasoning phase、tool upsert、去重和
终态。历史只读扫描 `~/.claude/projects/<encoded-cwd>/*.jsonl`，使用独立 history
identity/reducer；隐藏记录只写 Zeta 自有版本化列表，不改 Claude 文件。权限和 Plan
审批分别使用独立 registry；模型切换与 `/compact` 都在当前 Binding 的空闲边界执行。
模型目录和套餐名称由独立无 Prompt initialize 投影，额度详情才按可关闭配置读取 OAuth
凭据并请求 usage API；两条路径都留在 Claude-local data 层。
实际 wire 与升级门禁见
[Claude Code stream-json 协议基线](../protocols/claude_code_stream_json_protocol.md)。

Cursor 不再参与运行时组合。旧 `cursor` id 与 `cursorAcp` kind 只用于配置 decode、
unavailable 展示和安全 fallback；`DefaultAgentProviderFactory` 对二者 fail-closed。
catalog、设置、Agent 管理、deep link、workspace 恢复和历史入口都不能创建 Cursor
provider 或启动进程。退役不会迁移或改写任何 Cursor 用户数据。

### 管理适配

`AgentManagementController` 负责管理页异步编排，并复用
`AgentProviderSettingsController` 的全局 provider 配置。各活跃 CLI 使用独立 management
repository；协议 transport 不记录 prompt、文件内容或 stderr 原文。

Claude Code 自动检测执行 `--version`、`claude auth status --json` 与日志路径枚举，不按
凭据文件名猜登录态。显式连接测试创建临时、`--no-session-persistence` 的 metadata peer，
只等待匹配 request id 的 initialize response；不发送 Prompt、不创建 session、不等待模型
result。认证证据与 initialize 可用性独立，CLI 仍可能维护自身认证/bootstrap/cache。

检测摘要和真实 CLI 路径保存在 provider `extra` 中；项目 thread 仍只保存稳定的
`providerId`。管理 feature 不解析 thread/turn 原始协议，也不替代现有 provider。

协议基准锁定在 `third_party/codex_app_server_schema`（由
`tool/gen_codex_schema.sh` / `.ps1` 从本机 Codex CLI 导出）。当前 pin 与
升级流程见 [Codex app-server 协议版本锁定](../protocols/codex_app_server_protocol.md)；
功能缺口与分阶段适配见
`plan/codex_app_server_adaptation_plan.md`（已随 `plan/` 目录移除，仅存于 Git 历史）。

**适配进度（截至 2026-07-23）：** Phase 0 完成协议对齐；Phase 1 完成
核心流式体验；Phase 2 已完成 Provider Bundle 与多 Provider 能力端口迁移，并覆盖：

- thread 生命周期管理（重命名/归档/删除/分叉/按历史 turn 创建分支/压缩）。
- `AgentConversationViewModel` 的会话、历史、steer、权限响应、独立用户提问响应、
  Guardian 放行、模型目录与计划审批路由。
- `ProjectThreadsController` 的列表、重命名、归档、删除与分叉。
- Codex / Grok / Claude Code 的 bundle 端口一致性契约测试，以及 Cursor 退役不可达性测试。
- Codex Default / Plan 运行时目录、逐 turn mode 快照、settings/history 回写与
  Composer 紧凑选择器；不支持 mode 的 Provider 保持原布局和普通发送路径。

权限选项选择已收口到中立 `AgentPermissionPolicyPort`：application/presentation 只消费
option 目录与 optionId；Codex/Grok/Claude Code 协议映射留在 data adapter/codec。Provider 配置 V2
仅持久化 `selectedPermissionOptionId`。V1 多字段由 data/config 的
`AgentProviderPermissionMigrationRegistry` 按 provider kind 路由到 Codex/Grok 专属实现；
组合层负责注册，V2 key 存在时短路迁移。Domain config 只保存归一化 optionId。旧
`listPermissionProfiles` / `updatePermissionSelection`、共享层 fat snapshot、
`AgentPermissionPreset` / `AgentPermissionProfileSummary` 及
`supportsPermissionPolicySelection` / `supportsPermissionProfile*` 已删除。
Codex create/resume/fork/send 全部消费 application 冻结的
`AgentPermissionRequestSnapshot`；data codec 在单次 RPC 编码点展开 profile、approval 与
sandbox。Provider 构造时的 config snapshot 仅作缺省 fallback，不再由用户选择或 thread
settings 修改，因此共享 Provider 的多 thread / 多 Canvas 请求彼此隔离。
配置 JSON 的 V1/V2 宽容解码完全属于 data `AgentProviderSettingsCodec`；domain 不再保留
`AgentProviderConfig.tryDecode` / `AgentProviderSettings.tryDecode` 过渡门面。Provider API、
bundle port 与 turn configuration 也只接受显式 request snapshot，不再接受裸 selection。

最终依赖方向如下；箭头反向依赖均不允许：

```text
presentation
  -> Binding-owned selection/catalog controller
  -> AgentConversationPermissionState (one immutable snapshot per Binding)
  -> immutable AgentPermissionRequestSnapshot
  -> domain bundle port
  -> data provider adapter
  -> Codex/Grok codec + RPC/ACP wire

Codex settings wire -> data notification codec -> neutral domain event
  -> matching Binding permission state only
Grok live apply -> neutral runtime result -> owning Binding runtime selection
```

权限运行态由每个 `AgentConversationBinding` 独占的
`AgentConversationPermissionState` 统一拥有。它只保存本逻辑会话的 threadId、provider
default、session effective、一次性 current-turn override、runtime selection、source、last
scope、warning 与持久化失败，不再维护 provider/runtime/thread map 或 active runtime 注册表。
Provider runtime registry 为每个进程实例分配递增的
`AgentProviderRuntimeIdentity(providerId, generation)`，这里只把精确 identity 当作迟到结果
门闩。`AgentPermissionCatalogController` 独立承担目录加载、完整
last-known-good、非阻断错误和旧 generation 防回写；selection controller 只编排 apply result
与持久化。Codex catalog adapter 将错误分为 unsupported/transient/malformed：仅明确
unsupported 返回 built-ins，其他失败抛出；分页失败不提交部分结果，重复 cursor 安全终止。
Provider config 在 Binding 建立时只 seed 默认值，之后不再作为该 Binding 请求默认的并行真源；
Project Threads fork 优先从已有 Binding 冻结快照，没有 Binding 时才由 provider default 与
catalog default 解析。只有中立快照缺少 selection 时，data provider 才使用构造期不可变
config fallback 维持旧运行时兼容。

`AgentPermissionApplyResult` 的提交规则固定为：`currentTurn` 生成一次性 request override；
`currentSession` 更新当前 Binding；`runtime` 更新该 Binding 所属 CLI 实例的显式 runtime
state，不广播到其他 Binding；`nextSession` 更新默认/待生效提示。旧 generation 的迟到结果
不能提交。Provider
apply 成功但配置保存失败时不回滚运行态，并暴露只重试持久化、不重复 apply 的入口。

Codex `thread/settings/updated` 权限反馈在 data mapper 处经专属 codec 原子收敛为中立
`AgentPermissionSelection`；domain event 不再承载 approval/sandbox/profile。reducer 将权限
变化独立路由到事件 thread 的 `serverSettings` effective，因此共享 Provider 下的非当前
thread 也不会丢失反馈；该路径不改 provider default、不调用 Provider apply，模型和
conversation mode 的 UI 回写仍受当前 thread gate 约束。

权限域的状态、请求、事件、迁移与 catalog 边界已完成收口。旧 `AgentProvider` 中仍可能存在的
其它门面只涉及非权限能力，不构成权限运行态的第二真源。

### 当前已落地的对话体验

- 流式推理（思考卡，摘要优先）与流式 plan 卡。
- 中立文件变更证据：替换片段、写入内容、unified patch 与仅摘要四种诚实展示；
  Codex turn aggregate 只作为明确标注的实时 fallback。
- 线程状态胶囊：等待审批 / 等待输入；列表侧同步 waiting 标志。
- 权限、用户提问与计划审批统一显示在 Composer 上方的 Pending Interaction Dock；
  `AgentPermissionRequest`、`AgentQuestionRequest` 与 `AgentPlanApprovalRequest` 分属三条
  领域链，只共享 Dock 布局；对应结果分别经 permission decision、question answers
  和 plan approval decision 回写。提问 Skip 是空 answers，不等价于 deny/cancel。
  Dock 使用独立 pending 列表、按权限优先顺序展示，限高为 Agent 面板高度的 35%
  （最高 360px）并内部滚动，时间线不重复渲染待处理卡片。
- 成功的 Plan 回合在归档 live turn 前捕获最终 Plan 消息或结构化步骤，由
  `AgentPlanExecutionHandoffController` 创建一次性的本地执行交接。Pending Dock
  提供 Run plan、Keep planning 与 Dismiss：Run plan 显式把下一回合切到 Default 并发送
  本地执行提示；Keep planning 保持 Plan 并把焦点交回 Composer；Dismiss 只关闭卡片。
  Provider Plan 审批只有显式声明 `localExecutionHandoff` 才进入该流程，默认仍由 Provider
  自行续接。执行权限恢复进入 Plan 前同 Binding/thread/runtime generation 仍有效的选择；
  失效时回落到 catalog 默认，卡内改选仅冻结进新 turn 快照。该状态不持久化、不调用
  permission apply，也不代表任何命令、文件或网络权限已获批准。
- 模型改道、弃用通知等系统提示；token 用量含 `modelContextWindow` 占用比例。
- Composer 使用单一模型配置入口：Popover 以模型列表为一级信息，选中后在该行下
  内嵌 Reasoning effort 与 Fast，运行中更改明确标记为下一回合生效。
- Composer 在 Provider 支持时显示 Default / Plan 模式选择器。模式选择是 thread 粘性、
  下一回合生效的 draft，不覆盖用户保存的模型偏好；显式 Plan 使用 preset 的有效模型与
  reasoning，切回 Default 通过下一次 turn 明确提交。
- 18 种 ThreadItem 在实时路径与 `thread/read` / JSONL 历史中一致映射。
- 输入区支持本地图片（选图 / 粘贴落盘）随 turn 发送，时间线气泡预览。
- Thread 列表：搜索、活动/归档切换、右键重命名/归档/删除/分叉。
- 编辑上一条用户消息时保留原 thread，并通过 `thread/fork.lastTurnId` 创建分支；fork
  返回的 session 按新建 thread 登记到列表，Shell 复用标准 thread 选择流程创建并选中独立
  Entry/Binding，再由新 ViewModel 重发编辑后的内容。源 Binding 不改绑，工作区文件改动
  也不会随会话分支而回滚。

### Conversation mode 配置

Conversation mode 遵循“运行时能力目录 → application 状态机 → turn 不可变快照 →
data 精确编码”的单向流：

- Domain 用 `AgentConversationModeId`、preset、selection 和 catalog 表达 Provider 中立
  语义；`AgentProviderBundle.conversationModes` 是可选能力端口。
- `AgentConversationModeController` 按 Provider/thread scope 管理 draft、confirmed、
  pending、错误和 generation。快速切换 Provider/thread 时，旧异步结果不得覆盖新上下文。
- `AgentConversationViewModel` 在发送前冻结 mode 与有效模型配置到
  `AgentTurnConfiguration`。活动 turn 中改变选择只更新下一回合 draft，不修改当前 turn。
- Codex data 层独占 `collaborationMode/list`、`turn/start.collaborationMode` 和
  `thread/settings/updated` JSON；显式 mode 与顶层 model / effort 互斥。
- 本地 thread 快照是重启恢复的真源之一，服务端 settings 是确认态。`thread/read` 缺少
  mode 时不覆盖本地值；收到有效 settings 后收敛。未知 mode 可只读展示但不可主动选择。
- experimental 探测失败只关闭 mode 入口；普通 Default 会话不依赖该端口，Grok/Cursor
  不通过 Prompt 或全局 Provider 状态伪造 Plan。
- “Plan 已生成，是否执行”是 Zeta application 层工作流，不是 App Server approval。
  只有成功终态、已确认 Plan 模式且存在非空 Plan 内容时才创建请求；失败、中断、空计划、
  只读会话、thread/workspace/provider 切换都必须清除。Provider 独立计划审批继续经
  `AgentPlanApprovalPort` 回写，两者不得共享 request/decision 模型。

### 输入框模型配置

模型配置遵循“领域能力→应用编排→不可变 UI 快照→局部交互态”的单向流：

- `AgentModelInfo` 提供模型、Reasoning 顺序、service tier 和可用性；
  `AgentModelPreference` 保存每个 `modelId` 最后一次有效的 Reasoning / Fast 组合。
- Provider 只有在运行时确实接受推理档位时才声明 `supportsReasoningOptions`；Claude 将
  initialize 的 `supportedEffortLevels` 映射为该能力的数据，并通过 `--effort` 应用。
- Provider 历史解析器将协议别名归一化到唯一的 typed
  `AgentHistoryTurn.reasoningEffort`，并区分 unknown、Provider default 与 explicit value，
  供历史 footer 和恢复选择消费；共享 Store/ViewModel/UI 不读取 raw payload 猜测。
- `AgentConversationModelSelectionController` 是配置真源，负责 capability 归一化、
  Fast / `xhigh` 冲突解决、provider 运行态更新及持久化。快速连续修改串行合并，
  过期请求不得覆盖新快照。
- 保存采用乐观更新；失败时同步回滚 selection、模型偏好和 provider 运行态，
  并保留失败快照供卡片内原子重试。
- `AgentModelConfigUiState` 只是不可变渲染快照。`selectedModelId` 属于持久业务状态；
  `expandedModelId` 是 Popover 局部运行态，每次打开重置，不写入 provider 配置。
- `AgentProviderConfig.modelPreferences` 按 `modelId` 写入版本化
  `~/.zeta/config/providers.json`；老版单一 selection 在首次模型列表归一化时迁移，
  损坏或过期的偏好条目被宽容忽略或降级到服务端默认值。

模型目录由 app 组合层创建的 `AgentModelCatalogRepository` 跨首页、常驻 thread 和 Agent
管理入口共享。IDE 载入 provider 设置后只对 active provider 发起非阻塞预热；新鲜缓存
直接使用，超过 1 小时的缓存先发布给 Composer，再通过 single-flight 刷新，最长保留
7 天作为离线降级。显式“测试连接/刷新”会绕过内存缓存强制请求 provider。Codex 的
`initialize` 只完成协议握手，`model/list` 在目录真正需要时按 cursor 拉完所有分页；失败
不会写入空目录，后续请求仍可重试。Claude 则由独立、无 Prompt 的
`control_request.initialize` 返回当前 CLI 有效选项快照；它不是实时远端全量 catalog，
也没有 REST/静态 fallback。Claude probe 失败或返回空目录时，同样只保留 stale cache；
首次失败由 Composer 显式报错。共享仓储是 TTL 的唯一真源：一旦决定刷新，loader 必须
绕过 provider 实例缓存。刷新任务按配置指纹和 provider generation 隔离，旧配置完成后
不得覆盖新配置；Provider 运行时主动推送的完整目录只在内容变化时回写，目录请求自身产生
的事件不重复落盘。

### 上下文策略

当前仍只自动传递：

- 当前项目路径。
- 当前文件路径。

系统不会自动读取文件内容，也不会自动授权命令或文件写入。默认审批策略为
`on-request`。用户可在输入区附加本地图片；`@mention` / 远程图片 / skill
注入等富输入见适配计划 Phase 2.10 / Phase 4。

## 6. 会话状态设计

### Zeta 自有存储边界

Zeta 通过 `ZetaDataPaths` 统一解析 `~/.zeta`，由 app 装配层把文件注入 feature data
store。配置位于 `config/providers.json` 与 `config/appearance.json`；IDE 会话、使用统计
派生索引和迁移 marker 位于 `state/`；应用日志按本地日期写入
`logs/zeta-YYYY-MM-DD.log`；规范化模型目录缓存位于
`cache/agent_models_v1.json`。JSON store 使用同目录临时文件、flush 与 rename 替换，
并在读取损坏或 I/O 失败时按 feature 语义降级。模型缓存只保存中立白名单字段，不保存
provider 原始 payload、环境变量值或凭证；文件变更的替换片段、写入内容与 patch 也只留在
当前内存时间线，不进入任何 Zeta store 或日志。

启动迁移只读取 Zeta 旧版 SharedPreferences key，目标文件存在时不覆盖，全部处理成功
后才写 `migration_marker.json`。迁移不会删除旧值，以便旧版应用临时降级；新版本运行时
不再把这些状态写回 SharedPreferences。若迁移中途失败，本次运行改用内存 store，避免
空启动状态抢先创建目标文件；marker 保持未完成并在下次启动重试。

`~/.codex`、`~/.grok`、`~/.cursor`、项目 `.cursor/*` 和用户项目源码不属于 Zeta 自有
存储。Provider 自有 data adapter 可按明确功能读取 Agent CLI 配置、session、日志和账号
metadata；读取权限不自动授权迁移、复制、改写或删除，原始内容也不得进入 Zeta
持久化。Agent CLI 配置及 session/rollout 正文保持原位；退役遗留的
`state/cursor_sessions.json` 不再被运行时读取或写入，只作为受保护用户数据保留。

### IDE 会话快照

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
- 应用日志保留 developer 输出，并以脱敏单行格式追加到 `~/.zeta/logs/zeta-YYYY-MM-DD.log`；
  文件写入失败不回灌 Logger，避免递归错误；窗口正常关闭前会等待日志队列排空。
- 目录读取失败通过日志和短提示反馈，不中断当前工作区。
- 会话恢复失败会清理恢复状态并继续启动。
- Agent provider 启动失败、协议失败或进程异常会转换为 UI 状态和错误消息。
- Agent 管理错误附带统一失败阶段、原始摘要和建议操作；单个检测步骤失败不会丢弃
  已成功获得的版本、路径或日志信息。
- 配置保存会检测外部修改、拒绝符号链接、创建备份并以同目录临时文件替换。

## 9. 测试策略

当前测试重点应覆盖：

- Agent 模型 JSON 编解码和宽容读取。
- 模型配置的模型级恢复、capability 归一化、Fast 冲突确认、快速修改合并、
  保存失败回滚/重试，以及 Popover 键盘、动画与下一回合提示。
- JSON-RPC stdio transport。
- Codex provider 事件映射。
- Grok decoder/adapter/reducer、live/history 状态隔离、canonical ordering regression、history
  reader 只读性，以及 TimelineStore 的 dumb merge/history 应用顺序。
- Claude Code stream-json peer、process argv、Provider-local identity/mapper、权限与 Plan
  wire、live/history canonical parity、模型切换、`/compact` 与只读历史边界。
- 共享层架构守卫：decoder/CoalescingPolicy/Buffer/TimelineStore 不 import 具体 Provider，不按
  providerId/kind/type 分支，也不从 raw/source/eventId 推断 identity 或 narrative boundary。
- Provider-local 序列契约：每个 Provider 在进入共享层前完成 source→entry、segment/phase、
  tool upsert、终态竞态和迟到事件决策；共享层 fixture 保持 Provider 无关。
- Cursor 旧配置 fallback、运行时不可达、process spy 与用户数据未改写回归；历史证据
  见 `docs/cursor_acp_release_validation.md`。
- AgentConversationViewModel 状态机。
- Agent 管理的版本比较、配置校验/冲突/备份、日志脱敏和禁用只读联动。
- ProjectThreadsController 和 ProjectThreadsViewModel 的分页、缓存、选择和错误状态分工。
- App 或关键 Pane 的 widget 行为。

新增功能应优先选择最靠近风险点的测试层级，避免为了简单 UI 调整引入过重测试。

## 10. 演进方向

- Codex 适配 Phase 2：thread 重命名/归档/删除/分叉/按 turn 创建分支/压缩，以及审批表单与策略预设（见适配计划）；不再承诺已弃用的 `thread/rollback`。
- Cursor 如需重新支持，必须另立方案、重新采集真实协议 fixture，并从 catalog 到运行时
  重新完成全部协议与数据边界门禁。
- 增加文件内容预览或编辑器能力。
- 增加 Agent 执行审计记录。
- 支持更多 Agent provider。
- 把复杂 UI 状态进一步拆成更小的 view model。
- 在需要深链、多屏或 Web 支持时再引入声明式路由。
