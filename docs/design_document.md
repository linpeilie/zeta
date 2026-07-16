# 设计文档

最后更新：2026-07-16

## 1. 设计目标

Zeta 的设计目标是让 Flutter UI、Agent provider、会话持久化和本地文件系统访问保持清晰分层。当前实现采用轻量 feature-sliced 结构，不引入大型架构框架，但在 Agent 相关能力上预留 provider 抽象，方便未来接入 ACP、Claude Code 或其他 CLI。

## 2. 总体架构

当前代码按 `lib/src` 下的 app、core、features、ui 分层组织。重构后的核心原则是以 feature 为内聚边界，在 feature 内再按 domain、application、data、presentation 拆分职责：

- app：应用根组件、窗口启动、应用常量。
- core：日志、Zeta 数据路径与原子文本写入等跨层基础能力。
- features/agent：Agent provider 抽象、Codex app-server、Grok/Cursor ACP stdio、JSON-RPC stdio、历史解析、事件映射、对话 view model 和 Agent pane。
- features/agent_management：Agent CLI 检测、版本与账号诊断、模型读取、配置安全编辑、
  CLI 磁盘日志读取和管理页面。
- features/ide_session：会话状态、版本化持久化、恢复计划和恢复协调。
- features/project_threads：项目 thread 快照、列表状态、分页控制器和 presentation view model。
- features/usage_statistics：跨项目调用记录、统计口径、Codex 历史索引、套餐限额与
  使用统计页面。
- features/workspace：文件树规则、树构建、文件节点映射和文件 pane。
- ui/core：窗口框架、主题、通用面板和共享 UI primitives。
- ui/features/ide：IDE shell 视图和 provider 选择相关 view model。

依赖方向保持为 presentation/application 依赖 domain 接口，data 实现 domain 接口，app 负责组合默认实现。UI 不直接处理 Codex 原始协议或持久化 JSON。

## 3. 运行时结构

```text
main()
  -> ZetaDataPaths (~/.zeta)
  -> ZetaStorageMigrator (legacy SharedPreferences -> JSON files)
  -> daily app log (~/.zeta/logs)
  -> MainApp
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
  -> ActiveAgentProviderController
  -> AgentConversationViewModel
  -> ProjectThreadsController

AgentConversationViewModel
  -> AgentConversationTimelineStore
  -> AgentConversationUiSignals
  -> AgentConversationModelSelectionController
  -> AgentProvider
    -> CodexAppServerAgentProvider | GrokAcpAgentProvider | CursorAcpAgentProvider
      -> JsonRpcPeer
        -> codex app-server / grok agent stdio / agent acp

AgentManagementController
  -> CodexAgentManagementRepository | GrokAgentManagementRepository
     | CursorAgentManagementRepository
    -> CLI 身份、版本与登录态检查
    -> 无计费 initialize / authenticate 握手
    -> provider 对应配置与脱敏诊断

UsageStatisticsController
  -> UsageStatisticsRepository
    -> CodexUsageStatisticsRepository
      -> AgentProvider thread/list + thread/read
      -> 本地 Codex JSONL 历史
      -> account/rateLimits/read
      -> 版本化派生统计索引
```

## 4. UI 设计

### 统一 Workbench 页面骨架

`IdeHome` 是主要页面唯一的 Workbench 组合边界。`WindowFrame` 与
`IdeWorkbenchScaffold` 在页面切换期间保持同一 Element 和稳定 Key，首页、设置、
Agent 管理与使用统计只切换 Navigation、Canvas、Inspector slot 内容，不再创建相互
独立的顶层页面骨架。Feature 仍持有自己的业务组件和离开确认逻辑，共享 Scaffold 只做
布局与 Overlay 编排。

| 页面 | Navigation slot | Canvas slot | Inspector slot | 响应式策略 |
|---|---|---|---|---|
| Agent 首页 | Projects / Context | 常驻 `AgentPane` | Files / Tools | Wide 可内联左右 Pane；Medium 内联 Navigation、Inspector 按需 Overlay；Compact 左右 Pane 均按需 Overlay |
| 设置 / Agent 管理 | `SettingsNavigationPane` | `SettingsPageCanvas`，Agent 分区内承载 `AgentManagementPage` | 无 | Wide/Medium 内联设置导航；Compact 由 Rail 打开统一 Navigation Overlay |
| 使用统计 | 无 | `UsageStatisticsPage` | 无 | 所有模式只占用 Canvas，左右 Rail 与 Workbench 骨架继续保留 |

Canvas 使用延迟挂载的保活页面栈：`AgentPane` 始终挂载，设置和使用统计在首次访问后
保留。页面切换只暂停非活动页 ticker，不销毁 Agent 的 State、输入控制器或滚动控制器。
Workbench 的 Canvas Flex slot 自身也使用稳定 Key，保证 Navigation/Inspector slot
增删导致 Canvas 在 `Row` 中换位时仍复用原 Element。Pane 宽度和用户控制的可见状态由
`IdeHome` 持有，离开其他页面再返回时保持不变。

设置 Feature 对 Workbench 暴露 `SettingsNavigationPane` 与 `SettingsPageCanvas`；
`SettingsPageCanvasState.confirmCanLeave()` 继续负责 Agent 配置编辑器的未保存内容确认，
业务规则没有下沉到 `IdeWorkbenchScaffold`。

### 三栏工作台

- Projects：展示已打开项目、当前项目状态和项目下的 Agent threads。
- Agent：展示上下文栏、状态胶囊、流式消息/思考/计划时间线、回合 diff、工具与审批卡片、本地图片输入区。
- Files：展示当前项目文件树，目录按需展开，文件选择只更新 Agent 上下文。

### Agent 管理

- 设置页提供 Agent 列表和独立详情，列表状态、搜索与筛选在返回时保留。
- 当前内置 Codex、Grok 与默认关闭的 Cursor Beta；未安装时仍在“全部支持”中展示，
  但不提供应用内安装或自动更新。
- 详情包含基础诊断、模型和 provider 对应配置；桌面端双栏，窄窗口上下排列。
- 连接测试只执行版本、账号与协议握手；Cursor 不创建 session、不发送计费 prompt，
  握手成功后才允许显式启用。
- 禁用 Codex 后不再允许创建可写会话；既有会话仍可读取历史，输入区隐藏并显示
  只读提示。

### 使用统计

- 标题栏提供与设置同级的全局入口；页面支持时间、项目、Agent 和模型筛选。
- 一次 Codex turn 计为一次调用；`completed` 为成功，`failed` 与 `interrupted`
  为失败，运行中和未知状态不进入成功率分母。
- 默认统计 CLI、VS Code、`codex exec` 和 Zeta app-server 发起的根 thread，包含
  已归档 thread，排除子 Agent 以避免重复计数。
- 历史 TTFT 只使用 Codex 明确返回的 `time_to_first_token_ms`；缺失样本不做
  近似，并在页面标明有效样本数。
- 套餐仅展示 `account/rateLimits/read` 实际返回的套餐类型、百分比窗口、重置时间
  与可选余额，不推算绝对 Token 总额度或到期日。
- 宽屏使用双栏分析区，窄窗口切换为单栏；表格可横向滚动，任务详情使用自适应
  侧边/底部抽屉。
- `UsageStatisticsIndexStore` 只持久化 thread/turn ID、时间、项目、模型、状态、
  时延、Token 和错误分类，不保存 Prompt、回复正文、session 文件路径或原始错误文本。

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
- Graphite token 通过 `IdeThemeScope` / `IdeThemeData` 成为运行时真源；
  `buildShadcnTheme` 只把项目 token 投影到 `shadcn_flutter` 的 `sf.ThemeData`，
  不再反向从第三方 theme 回读语义色。
- 第三方组件统一 `import ... as sf;`；业务页面优先消费 `ui/core` primitives
  （`Pane` / `PanelCard` / `IdeTabs` / `IdeTab` / `IdeContextMenu` / `showIdeToast` 等）。
- 业务代码禁止硬编码颜色、圆角和阴影。
- 面板圆角 8、间距紧凑，适合桌面工具密度。

## 5. Agent 设计

### Provider 抽象

`AgentProvider` 是 UI 与具体 Agent CLI 之间的稳定接口，负责：

- 通过 `AgentProviderCapabilities` 声明 session、history、turn、thread、input、
  interaction、config、telemetry 和 bootstrap 能力。
- 初始化 provider（含握手后的 capability 收敛 / 通知 opt-out）。
- 创建和恢复 session；切换会话时 best-effort `unsubscribeThread`。
- 列出项目 threads、读取 thread 历史。
- 发送、追加和取消 turn（`sendMessage` / `steerTurn` 支持多输入项）。
- 响应权限请求；他端已解决的审批通过事件撤销本地卡片。
- 推送状态、消息、推理/计划流、工具调用、回合 diff、审批与系统提示事件。

capability 采用保守声明：不支持的操作不进入 Project thread 菜单、Agent header 或
composer，应用层误调用时抛出 `UnsupportedError`。`AgentProviderBootstrapPolicy`
额外约束 provider 是否必须在 workspace 下启动、是否允许 eager model preload。

所有 JSON-RPC provider 在裸 transport 外统一使用 `ProviderRuntimeJsonRpcPeer`。该边界
维护 `stopped / starting / initializing / ready / failed / closing / closed` 生命周期，
为每次连接生成 `runtimeId + connectionEpoch`，并把 scope 注入服务端反向请求。进入
`closing` 后拒绝新的 client RPC；关闭 transport 后等待已入场的 start、RPC 和
server-request handler 排空。Codex 的 `AgentRuntimeInfo` 同步暴露 runtime identity，
Grok/Cursor 通过可选 `AgentRuntimeLifecycleProvider` 暴露中立生命周期，不把协议状态泄漏到 UI。

Provider 的 Thread 访问统一经过 `ProviderOperationScheduler`。列表使用 Project 级
`sharedRead`，历史读取使用 Thread 级 `sharedRead`；resume、fork、重命名、归档、删除和
压缩等变更使用 Thread 级 `exclusive`。同一资源上的连续读取可并发，独占操作保持 FIFO
并阻塞后续读取；不同资源仍可并发。Provider dispose 先停止调度器接收新任务，再关闭
连接并等待已入场操作结束，避免队列任务在关闭阶段重新发起 RPC。

### 默认 provider

当前内置 provider 为 Codex CLI、Grok ACP 与 Cursor ACP；Cursor 默认关闭，默认 active
provider 仍为 Codex CLI：

```text
codex app-server
```

Codex provider 通过 JSON-RPC stdio 通信，把 `thread/*`、`turn/*` 和 `item/*`
事件转换为领域层 `AgentEvent`。UI 不直接处理 Codex 原始协议。

Grok provider 使用 ACP stdio、本地历史和 xAI 扩展。标准 ACP
`session/update`、permission、content block 和 session config 已分别下沉到
`AcpSessionUpdateMapper`、`AcpPermissionMapper`、`AcpContentCodec` 与
`AcpSessionConfigMapper`；
`GrokAcpNotificationMapper` 只保留厂商扩展适配。session config option 与带稳定 id、
可多选的用户问答选项使用中立领域模型，供后续 ACP provider 共用。

Cursor provider 使用官方 `agent acp`，启动前由 `CursorCliLocator` 组合校验产品标识、
版本输出和 ACP 帮助，不能仅凭通用 basename `agent` 判定身份。provider 进程与 workspace
绑定：首次创建 session 时在项目目录启动，切换项目即关闭旧 peer 并重新 initialize /
authenticate。Phase 2–4 已支持核心对话、权限响应与取消、本地 session 索引、
`session/load` 历史恢复、动态 config options、legacy mode 回退，以及 Cursor 提问、计划、
todo、子任务和图片状态扩展。阻塞请求在超时、turn cancel、workspace 切换、进程退出和
provider dispose 时统一收尾；图片与 resource 入口只有握手明确声明 capability 后才开放。
真实 CLI 发布门禁由 `tool/smoke_cursor_acp.py` 执行：默认临时 Git workspace、拒绝工具权限，
验证握手、核心 turn、进程重启后的 replay 和取消。各平台/架构结果独立记录，自动化测试
不能替代缺失的真实设备证据。

### 管理适配

`AgentManagementController` 负责管理页异步编排，并复用
`ActiveAgentProviderController` 的全局 provider 配置。各 CLI 使用独立 management
repository。Cursor repository 负责多候选身份探测、版本/账号检查和无 session、无 prompt
的 ACP 握手；保存的 `cliPath` 必须已经通过身份校验。协议 transport 不记录 prompt、文件
内容或 stderr 原文。

检测摘要和真实 CLI 路径保存在 provider `extra` 中；项目 thread 仍只保存稳定的
`providerId`。管理 feature 不解析 thread/turn 原始协议，也不替代现有 provider。

协议基准锁定在 `third_party/codex_app_server_schema`（由
`tool/gen_codex_schema.sh` / `.ps1` 从本机 Codex CLI 导出）。当前 pin 与
升级流程见 [Codex app-server 协议版本锁定](./codex_app_server_protocol.md)；
功能缺口与分阶段适配见
[`plan/codex_app_server_adaptation_plan.md`](../plan/codex_app_server_adaptation_plan.md)。

**适配进度（截至 Phase 2 核心 2.1–2.5）：** Phase 0 完成协议对齐；Phase 1
完成核心流式体验；Phase 2 核心完成 thread 生命周期管理（重命名/归档/删除/
分叉/按历史 turn 创建分支/压缩）、列表搜索与归档视图、配套通知同步，以及上下文
占用提示。Permission Profile 当前仅承诺稳定的发现能力，不承诺实验性选择能力。

### 当前已落地的对话体验

- 流式推理（思考卡，摘要优先）与流式 plan 卡。
- 回合级聚合 diff（「本回合改动」）。
- 线程状态胶囊：等待审批 / 等待输入；列表侧同步 waiting 标志。
- 权限、用户提问与计划审批统一显示在 Composer 上方的 Pending Interaction Dock；
  Dock 使用独立 pending 列表、按权限优先顺序展示，限高为 Agent 面板高度的 35%
  （最高 360px）并内部滚动，时间线不重复渲染待处理卡片。
- 模型改道、弃用通知等系统提示；token 用量含 `modelContextWindow` 占用比例。
- Composer 使用单一模型配置入口：Popover 以模型列表为一级信息，选中后在该行下
  内嵌 Reasoning effort 与 Fast，运行中更改明确标记为下一回合生效。
- 18 种 ThreadItem 在实时路径与 `thread/read` / JSONL 历史中一致映射。
- 输入区支持本地图片（选图 / 粘贴落盘）随 turn 发送，时间线气泡预览。
- Thread 列表：搜索、活动/归档切换、右键重命名/归档/删除/分叉。
- 编辑上一条用户消息时保留原 thread，并通过 `thread/fork.lastTurnId` 创建分支后
  重发；工作区文件改动不会随会话分支而回滚。

### 输入框模型配置

模型配置遵循“领域能力→应用编排→不可变 UI 快照→局部交互态”的单向流：

- `AgentModelInfo` 提供模型、Reasoning 顺序、service tier 和可用性；
  `AgentModelPreference` 保存每个 `modelId` 最后一次有效的 Reasoning / Fast 组合。
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
store。配置位于 `config/providers.json` 与 `config/appearance.json`；IDE 会话、Cursor
最小索引、使用统计派生索引和迁移 marker 位于 `state/`；应用日志按本地日期写入
`logs/zeta-YYYY-MM-DD.log`，并创建空 `cache/` 预留目录。JSON store 使用同目录临时
文件、flush 与 rename 替换，并在读取损坏或 I/O 失败时按 feature 语义降级。

启动迁移只读取 Zeta 旧版 SharedPreferences key，目标文件存在时不覆盖，全部处理成功
后才写 `migration_marker.json`。迁移不会删除旧值，以便旧版应用临时降级；新版本运行时
不再把这些状态写回 SharedPreferences。若迁移中途失败，本次运行改用内存 store，避免
空启动状态抢先创建目标文件；marker 保持未完成并在下次启动重试。

`~/.codex`、`~/.grok`、`~/.cursor`、项目 `.cursor/*` 和用户项目源码不属于 Zeta 自有
存储。Agent CLI 配置及 session/rollout 正文保持原位；Cursor 的
`state/cursor_sessions.json` 只含 Zeta 最小索引，不是 Cursor 官方历史正文。

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
- Cursor CLI 身份冲突、workspace peer 重建、session 索引与恢复、ACP 流式映射、动态配置、
  权限/提问/计划响应，以及超时、取消、dispose 和进程早退收尾。
- Cursor 真实 CLI smoke 的中文/空格 workspace、包装器、重启恢复和拒绝权限路径；平台
  证据矩阵见 `docs/cursor_acp_release_validation.md`。
- AgentConversationViewModel 状态机。
- Agent 管理的版本比较、配置校验/冲突/备份、日志脱敏和禁用只读联动。
- ProjectThreadsController 和 ProjectThreadsViewModel 的分页、缓存、选择和错误状态分工。
- App 或关键 Pane 的 widget 行为。

新增功能应优先选择最靠近风险点的测试层级，避免为了简单 UI 调整引入过重测试。

## 10. 演进方向

- Codex 适配 Phase 2：thread 重命名/归档/删除/分叉/按 turn 创建分支/压缩，以及审批表单与策略预设（见适配计划）；不再承诺已弃用的 `thread/rollback`。
- 在 Windows、macOS、Linux/WSL 完成两个 Cursor CLI 版本的真实 smoke 后，再评估提升
  Cursor Beta 的默认展示层级；provider 继续默认禁用。
- 增加文件内容预览或编辑器能力。
- 增加 Agent 执行审计记录。
- 支持更多 Agent provider。
- 把复杂 UI 状态进一步拆成更小的 view model。
- 在需要深链、多屏或 Web 支持时再引入声明式路由。
