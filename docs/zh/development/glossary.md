# 术语表

中文 ｜ [English](../../en/development/glossary.md)

这些词在代码和文档里高频出现，含义都很具体。第一次读仓库时建议先扫一遍，之后遇到不确定的再回来查。

先看整体是怎么串起来的：[架构总览](../architecture/overview.md)。

## 会话与回合

**Thread（会话）**
一次持续的对话，归属于某个项目目录。它由 Provider 侧维护，可以列出、读取历史、恢复、分支、重命名、归档、删除——但每一项能力都取决于该 Provider 是否声明支持。UI 里显示在左侧 Projects 面板的项目节点下。

**Turn（回合）**
一次"用户发一条 → Agent 干完活"的完整往返。是使用统计的计数单位：一个 turn 算一次调用。终态有 `completed` / `failed` / `interrupted` 三种；运行中和未知状态不计入成功率分母。

**Turn steering（回合追加）**
在一个 turn 还在跑的时候，往里追加输入，而不是新开一个 turn。对应可选端口 `turnSteering`。注意：Plan 的"执行计划"**不是** steer，它必须新建回合。

**Default / Plan conversation mode（对话模式）**
Provider 提供的运行时模式目录（端口 `conversationModes`）。Default 是正常执行，Plan 是只规划不动手。模式选择作用于**下一个**回合，不修改进行中的 turn。目录为空或缺少 Default/Plan 时，模式选择器直接隐藏，退回普通对话——**不允许用 prompt 伪造 Plan 模式**。

**权限 Plan（`planningOnly`）**
权限目录里标成只读规划的档（端口 `permissionPolicy`）。和对话 Plan 不是同一能力：它限制进程能做什么，不是下一回合聊法。点本地交接「执行」必须离开该档，不能带着只读规划去「执行」。

## 时间线

**Entry / entryId（条目）**
时间线上的一个可合并单元。`entryId` 是统一层的唯一合并键，由 **Provider 自己的 adapter/reducer 决定**——这是关键：TimelineStore 拿到相同 entryId 就更新，拿到新的就新建，它不做任何推断。

**Source id（源标识）**
Provider 协议里的原始 id（`sourceItemId`、`sourceMessageId` 等）。它**只是 metadata**，保留下来是为了排查问题，不参与合并决策。把 source id 当 entryId 用是典型错误。

**Segment（消息分段）**
一条 Agent 消息内部的分段。同样由 Provider 的 reducer 决定怎么切，共享层不猜。

**Reasoning phase（推理阶段）**
Agent 思考过程的阶段划分，在时间线上折叠展示。

**File-change snapshot（文件变更快照）**
某个 tool 或 turn owner 在一次更新时的完整、有序文件变更集合。Provider-local tracker 在进入共享管线前决定 change id、动作、顺序、revision 与可回放性；Store 只机械替换。`null` 表示没有 snapshot，空 changes 表示权威清空。

**File-change evidence（文件变更证据）**
Provider 明确给出的内容证据：替换前后片段、写入内容或 unified patch；也可以只有路径/动作摘要。三种正文不能互相伪造，只有命令时不生成文件变更证据。`replayable` 可由历史/重放重建，`liveOnly` 只表示当前实时 fallback。

**Live / history / replay**
时间线的三种数据来源：正在流式接收的、从 Provider 读回的历史、本地重放。**三者必须使用各自独立的 reducer 实例**，共用会导致状态串味。

## 事件管线

**AgentEvent（领域事件）**
中立的领域事件，是 Provider 协议与 Zeta 内部的分界线。这个类型之后的所有代码都必须是 Provider 无关的。新增或修改前要走完[开发者文档 §7](developer_guide.md) 的 16 条接入清单。

**AgentEventPipeline（事件管线）**
事件资源的唯一所有者，串起 listener gate、合并缓冲和有界派发。订阅生命周期由它统一管理，不再由会话门面分散持有。
`packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart`

**Listener gate（监听闸门）**
控制事件流的准入。切换 thread、重启 Provider、dispose 交叉发生时，靠它保证旧的事件流不会投影到新会话上。

**Coalescing（事件合并）**
高频事件的合并策略：同一 item 的文本/推理增量追加、同一 turn 的 token/文件变更完整快照取最新、同一工具的进度按协议语义追加或替换。目的是降低 UI 更新频率，不改变语义。完整事件、终态、审批、错误会先 flush 缓冲再立即发布。

**Bounded dispatcher（有界派发器）**
FIFO 派发事件，每个 Dart event-loop turn 默认最多 64 个，续批用 `Timer.run`。它和 Flutter 的 frame 调度相互独立。

**Reducer（归约器）**
把事件变成状态迁移的纯函数式组件。**必须纯同步**：不许有 `Timer`、`Future`、Flutter scheduler 或外部回调。产出 nextState（`AgentConversationSessionState`）、timeline mutation、UI request 与 effect；副作用一律走 EffectRunner。
`agent_conversation_reducer.dart`

**SessionState（会话状态）**
单个会话由事件归约产生的不可变值对象。纯数据、可单测、可 diff。不包含命令侧令牌、模型选择控制器或 Binding 活动令牌。
`agent_conversation_session_state.dart`

**EffectRunner（副作用执行器）**
reducer 唯一的副作用出口。带作用域校验（generation / runtime / thread），保证陈旧的副作用不会执行。
`agent_conversation_effect_runner.dart`

**TimelineStore（时间线存储）**
只做三件事：同 entryId 更新、异 entryId 新建、同 tool id upsert。不推断开放条目、不改写 id、不判断 UI 紧急程度。写方法在值真正变化时点亮脏区，供 processor 派生 UI region。
`agent_conversation_timeline_store.dart`

**Handler 注册表**
按 `AgentEvent.runtimeType` 分发归约的共享表。默认 handler 在 `packages/zeta_agent_core/lib/src/application/reduction/`；Provider 只能在自己的 bundle 里 `register<E>()` 覆盖非审批事件。四种审批语义 handler 不允许覆盖（G5）。
`agent_event_handler_registry.dart`

**覆盖 handler**
Provider 用自己的 `AgentEventHandler<E>` 替换共享默认实现。必须能回答「共享实现为什么不适用」；不得放宽审批或 Plan 交接语义。

**脏区（dirty region）**
TimelineStore 在写入后举起的数据变化标记（history / liveTurn / liveTurnBinding / activity / expansion / pendingInteraction / usage / contextUsage）。它只描述哪块数据变了，不描述界面长什么样；processor 把它映射成 `AgentUiRegion`，再与 SessionState 字段 diff 合并后发布。reducer 不再硬编码 UI region。

**AgentUiRegion（UI 分区）**
processor 从脏区 + SessionState diff 派生的界面分区（header / composer / pendingInteraction / expansion / history / liveTurn 等）。Widget 按 region 订阅。

**Conversation Slice（会话切片）**
一个 Binding 对应一份 UI 区域状态。`AgentConversationSliceStore` 是 owner；Riverpod family 只镜像。未知 BindingKey fail-closed。发布链路是两跳：RuntimeController → SliceStore → selector / `AgentRegionBuilder`。不得再经 ViewModel、UiStateStore 或 SliceComposition 转手。

**AgentConversationRuntimeController**
会话 application 聚合：pipeline、region 投影、`AgentUiUpdateScheduler`、CommandPort 与 effect。Workspace entry 持有它；不再有 `AgentConversationViewModel`。
`agent_conversation_runtime_controller.dart`

**AgentCommandOutcome（命令结果）**
命令显式返回 succeeded、ignored(reason) 或 failed(kind)。Session config 缺端口在执行层抛 UnsupportedError，由 UI 边界翻译为 unsupported；未执行不能被判成功，currentValue 仍等 Provider 事件更新。

**AgentConversationSessionHandle**
Slice registry 的解析结果：`store` + 可选 `controller`。只测切片镜像的容器里 controller 可空。

**AgentRegionBuilder**
presentation 订阅一个 region selector：`ref.watch(selector(bindingKey))`。发送走 `agentConversationCommandProvider`。

## Provider 抽象

**Provider**
一个 Agent CLI 的接入实现。当前活跃的是 Codex（默认）、Grok 与 Claude Code；Cursor 已彻底清退。

**AgentProviderBundle（能力包）**
Provider 能力的严格中立入口，由 `AgentProviderBundleFactory.createBundle` 直接创建。必选端口 `runtime` 和 `conversation`；其余（`threadCatalog`、`threadSubscription`、`threadNaming`、`threadArchival`、`threadDeletion`、`threadCompaction`、`threadBranching`、`turnSteering`、`permissionResponses`、`questions`、`deniedActionOverride`、`modelCatalog`、`localThreadList`、`sessionConfiguration`、`planApproval`、`conversationModes`、`skills`、`permissionPolicy`、`usageQuota`）都是可选的。不支持的端口必须为 `null`。旧 `AgentProvider` 大接口已删除。
`agent_provider_bundle.dart`

**Capability（能力声明）**
Provider 声明自己支持什么。**UI 一律按 capability 与端口是否非空渲染，不按 provider 名字硬编码。** 不支持的能力必须 `capability = false` 并抛 `UnsupportedError`，不得静默成功。`AgentProviderCapabilities` 是中立值对象；厂商默认值由 data 组合层的 `AgentProviderStaticCapabilities` 注入。
`agent_provider_capabilities.dart`

**Runtime lease（运行时租约）**
Registry 对 Provider 实例的可释放引用。它只在基础设施与 global runtime/Binding 内流转，RuntimeController 和 Pane 不直接持有。

**Conversation Binding（会话绑定）**
一个逻辑会话的 application 聚合根，以 draft 或 thread key 唯一标识。它维护可选 session runtime、过滤旧 generation 的事件流、单 Binding 不可变权限快照和活跃操作；只有 `beginTurn()` 能创建 runtime。Binding Manager 负责映射、草稿晋升以及 10 分钟空闲回收。已绑定真实 thread 的 Binding 不原地改绑；Workspace 为它创建固定身份的 RuntimeController，切换 thread 会选择另一 entry。fork 结果按新建 thread 登记并获得独立 Binding。

**Global runtime（全局运行时）**
每个 Provider ID 唯一且不参与空闲回收的实例，用于历史、thread 管理、模型、Skill、用量和连接探测等会话前/全局信息。

**runtimeId / connectionEpoch（运行时标识 / 连接纪元）**
每次连接生成一对标识，用来判断某个事件或副作用是否还属于当前连接。加上 `providerId + threadId + listenerGeneration`，构成事件绑定的完整作用域。

**ProviderOperationScheduler（操作调度器）**
区分并发语义：thread 的 list/read 用 `sharedRead`（可并发），resume/fork/rename/archive/delete/compact 用 `exclusive`（互斥）。
`data/datasources/transport/provider_operation_scheduler.dart`

## 交互与审批

**Permission request（权限审批）**
Provider 请求执行命令、写文件或访问网络。默认策略保守，**不会自动授权任何操作**。

**Question request（用户提问）**
Provider 需要用户回答才能继续。

**Plan approval（计划审批）**
Provider 请求批准一份计划。

> 上面三种是**独立的领域语义**，不共享 request/decision 模型。它们可以复用同一个 Pending Interaction 展示区，但模型不能混。

**Plan execution handoff（计划执行交接）**
Zeta 自己的本地工作流，**不是** Provider 计划审批。Plan 回合成功并产出非空计划后出现，点"执行计划"会**新建一个显式 Default 回合**，且不预授权计划里的任何操作。执行权限默认恢复进入 Plan 前仍有效的用户选择，失效时回落到 Provider catalog 默认；卡内改选只影响这一个新回合。非持久化状态，重启即消失。
`agent_plan_execution_models.dart`

**AgentAttentionSignal（注意力信号）**
把回合终态、权限、提问、计划审批、执行交接统一成的中立信号，是桌面通知与未读提醒的唯一输入。通知正文不含 prompt、回复、命令或完整路径。
`agent_attention_models.dart`

## 输入与 Composer

**Composer（输入框）**
底部的富文本输入区。支持粘贴/选择图片、`$` 插入 Skill、`/` 唤出命令菜单、`@` 引用项目文件。

**Skill token**
Composer 里的原子 chip，用 `U+FFFC` 占位符 + `WidgetSpan` 渲染成 `$name`，退格整块删除。发送时序列化为文本并附带 `type: skill` 输入项。仅 Codex 支持（`supportsSkillInput`）。

**Pending interaction（待处理交互）**
固定在输入框上方的审批/提问卡片区。响应后自动移除，且不在时间线里重复出现。

## UI 骨架

**Workbench（工作台）**
`WindowFrame` + `IdeWorkbenchScaffold` 组成的常驻骨架。`IdeHome` 是唯一的组合边界，页面切换只换 slot 内容。

**Slot（槽位）**
三个位置：Navigation（左）、Canvas（中）、Inspector（右）。feature 页面只提供 slot 内容，**不得替换顶层 workbench**。

**IdeRetainedPageView（保活页面栈）**
跨页面保活的容器。延迟挂载、保留已访问页面的 State 和滚动位置、暂停离屏 ticker。**不要用 `IndexedStack` 替代**——它会一直保留长时间线的布局开销。

**Graphite token（设计 token）**
深色 Graphite Night / 浅色 Graphite Day 两套语义 token，真源是 `IdeThemeScope`。`shadcn_flutter` 的 theme 只是投影，不能反向回读。业务代码禁止硬编码颜色、圆角和阴影。表面遵循严格单调的明度阶梯（frame → canvas → pane → control → popover），层级只靠阶梯加 1px 半透明描边表达，除浮层的极淡兜底投影外全局零阴影。
`lib/src/ui/core/`

## 界面语言

**AppLanguage（界面语言）**
首期仅 `english` / `simplifiedChinese`，持久化码 `en` / `zh-Hans`。Flutter `Locale` 不是领域模型，只在 app/UI 组合层出现。

**文本目录（text catalog）**
feature 在 domain 边界声明的不可变纯 Dart 接口，例如 `AgentUiTextCatalog`。application / data / reducer 用它生成当前进程的 Zeta 文案，不持有 `BuildContext`、generated l10n 或 Flutter `Locale`。

**启动冻结 Locale**
`MainApp` 在常规设置加载后把本次进程语言固定下来。设置页改的是下次启动语言；当前进程不跟随系统 locale，也不重挂 Workbench。

**第一系统 locale**
首次安装只看 `PlatformDispatcher` 首选语言列表的第一项。第一项不受支持（含繁体中文）时直接回退英语，不继续往后找。

## 数据与诊断

**Zeta 数据目录（文档中常写作 `~/.zeta/`）**
Zeta 自有数据根目录：`config/`（配置）、`state/`（会话状态与派生索引）、`logs/`（按天日志）、`cache/`（可丢弃缓存）。实际位置由 `path_provider` 按平台解析，当前为**系统文档目录下的 `.zeta` 文件夹**（macOS / Linux `~/Documents/.zeta`，Windows `%USERPROFILE%\Documents\.zeta`），不是用户主目录下的 `~/.zeta`。文档中沿用 `~/.zeta/` 作为简写。用户视角的逐文件说明见[数据与隐私](../guide/data-and-privacy.md#zeta-在你电脑上写的文件)。

**派生索引（derived index）**
可重建的统计缓存，只存规范化白名单字段。禁止落盘 prompt、回复正文、工具输出、原始错误文本、凭证或 Provider raw payload。

**脱敏（redaction）**
写日志或展示诊断前的处理：认证头、`Bearer` token、`sk-` 密钥、`api_key`/`token`/`secret`/`password` 类键值会被打码，用户主目录替换为 `~`。
`lib/src/core/security/sensitive_data_redactor.dart`

**Pinned schema（协议快照）**
`third_party/codex_app_server_schema/` 下的 Codex app-server JSON Schema 快照。升级协议前先跑 `tool/gen_codex_schema.sh --diff` 对比差异，再改适配层。

**Smoke（真实 CLI 冒烟）**
`tool/smoke_codex_app_server.py` 与 `tool/smoke_codex_plan_mode.py`，对真实 CLI 跑核心链路。使用临时只读 workspace，输出不含任何业务内容。

## 测试执行

**受影响测试（affected tests）**
从 git 变更集出发、沿 import 图做**反向闭包**算出的、可能因本次改动而改变行为的测试集合。`bash tool/test_affected.sh` 是开发循环的默认档；选择逻辑在 `tool/test_select.dart`，设计上只允许"多选"不允许"漏选"。全量的强制点在 CI，不在本地终端。

**分片（shard / runner）**
根 `test/` 被 `tool/test_shards.dart` 的 `kRootTestShards` 切成的 6 组，CI 每组一个并行 Job（`fail-fast: false`）。分片按**语义分组**且按目录前缀匹配——测试落进已有目录自动归片，不用登记。本地跑单片用 `bash tool/test_shard.sh <id>`。

**分片覆盖守卫**
`test/src/architecture/test_shard_coverage_guard_test.dart`：断言每个测试文件恰好属于一个分片、清单路径真实存在、CI 矩阵与清单一致。没有它，新增测试可能不属于任何分片而永远不被执行。

**全量兜底触发（full-run trigger）**
`pubspec.yaml`、`dart_test.yaml`、`analysis_options.yaml`、`.github/workflows/`、选择器自身——这些"地基"文件一变，import 图算不出影响面，`tool/test_affected.sh` 直接退化成全量。

## Provider 插件包与 manifest

- `provider_api`：宿主装配所需的中立契约，不包含厂商实现。
- `provider_sdk`：共享协议机制与独立 testing 入口。
- `provider_<vendor>`：单一厂商的协议实现及独立测试。
- `manifest`：`lib/src/app/plugins/agent_provider_manifest.dart`，编译期登记 definitions、settings、工厂和专属宿主注入；不进行运行时发现。

`AgentManagementContribution` 提供管理定义与仓库工厂；`AgentUsageContribution` 按 providerType 提供用量工厂。宿主经独立可覆盖接缝取得同一份激活并校验的贡献快照。原过渡 import 已清零，依赖约束见[工程规范 §2.1](../architecture/engineering_standards.md#21-provider-插件包边界)。

- **贡献类型**：`zeta.agent.provider-bundle-factory` 为 Bundle 工厂，`zeta.agent.management-repository` 为管理定义/工厂，`zeta.agent.token-usage-source` 为用量来源；每个激活 Provider 三类齐备且归属一致。
- **D7 持久化身份红线**：包结构变化不得改动 providerId/type、配置版本、用量索引与私有增强键的持久化字节。
- **D8 文案目录下沉**：中立 API 接口及不可变 fallback 下沉，宿主保留 ARB 实现；用量来源沿用五成员窄目录和原默认文本。
- **动态 package 矩阵**：CI 通过 `test_packages.sh --list-json` 发现测试包，每个 job 用 `--only` 运行对应包；不涉及运行时插件发现。

**Provider 图标描述（`AgentProviderSvgIcon`）**：api 中的纯 Dart 静态元数据，包含所属包名、SVG 相对路径和着色策略。由插件 Definition 声明，宿主统一渲染；不代表协议能力，不参与激活或持久化。
