

# Phase 3 开工文档：Feature 切片扩展迁移

> 对应 [目标架构 §14 Phase 3](target_architecture_riverpod_mvi_plugins_packages.md)。
> 这份文档是 Phase 3 的**前置条件交付物**：钉死批次顺序、开门/关门标准、每批 owner
> 映射与删除清单。第 1 批（settings）细到字段映射与 §15 门禁答卷；第 2–6 批在本文档
> 给框架级盘点，**各自开工前**按 §9 模板补齐同深度的批次文档——这不是降低前置条件
> "每一批都有 owner 映射、依赖图和删除清单"，而是把它拆成分批交付：一次写全六批的
> 字段级映射只会产出五份注定过时的文档（Phase 2 的 review 修复已经证明计划会漂移）。
>
> 规则优先级：`AGENTS.md` > `engineering_standards.md` > 本文件。

---

## 0. 前置条件对照与开门标准

| Phase 3 前置条件 | 状态 |
| --- | --- |
| Phase 2 稳定一个发布周期或等价真实使用证据 | ⏳ 计时中：2026-08-23 起生产全量启用切片路径（[Phase 2 §9.8](phase2_conversation_slice.md)） |
| 代表性 slice 的性能、dispose、重试、取消和回滚机制验证完成 | ✅ [Phase 2 §8 验收表](phase2_conversation_slice.md) 十条全过 |
| 每一批都有 owner 映射、依赖图和删除清单 | ✅ 本文档：第 1 批全量，第 2–6 批框架级，§9 模板作为每批开工门禁 |

**开门标准（显式）**：

1. 切片路径生产使用连续 **14 天**未出现需要把 `conversationSliceEnabled` 拨回
   `false` 的问题（2026-08-23 起算）。期间发现并修复 slice 路径 bug 后**重新计时**。
   起点锚：2026-08-23 生产启动冒烟通过（macOS，切片 flag 开启；会话恢复 +
   三 Provider 真实 CLI 连接 + 模型目录拉取，日志零错误）。
2. 本文档评审定稿。
3. 每批开工前，该批文档按 §9 模板补齐并答完 §15 十问。

允许提前开门，但必须回到本文档记录理由（问题已修复且复测通过 / 显式接受更短
观察期）。宁可推迟，不降标准。

> **提前开门记录（2026-08-23）**：经拍板，提前开门到第 1 批的"挂 flag"阶段
> （四步节奏第 1–2 步）。理由：settings 是低风险 context（无 Provider 协议、
> 消费面小），且 flag 默认 false，**生产行为零变化**；翻 flag 仍等窗口期满
> 或另行显式确认。批次文档见
> [phase3_batch1_settings.md](phase3_batch1_settings.md)。
>
> **显式翻旗确认（2026-08-23）**：双路径门禁通过后，经另行显式确认接受较短
> 观察期，`main.dart` 已传 `settingsSliceEnabled: true`，第 1 批进入至少三天的
> 生产观察，最早于 2026-08-26 关批。观察期出现需回退的问题时一行拨回 false，
> 修复复测后重新起算。原计划关批前不进入第 2 批；本文件 §4 后续记录的显式确认
> 只覆盖“默认关闭 flag 的开工接缝”，当时不授权第 2 批生产翻旗。
>
> **第 2 批显式翻旗确认（2026-08-23）**：2a–2c 双路径与完整重构门禁通过后，
> 经再次显式确认接受第 1、2 批生产观察窗口重叠的风险，`main.dart` 已传
> `providerManagementSliceEnabled: true`。第 2 批风险为中高，取至少 7 天观察期，
> 最早于 2026-08-30 关批；第 1 批仍按原窗口独立观察。任一批发生问题只回退自身
> flag，修复复测后重新起算该批观察期。
>
> **第 3 批提前开工记录（2026-08-23）**：经显式要求，接受第 1、2 批仍在生产
> 观察时启动第 3 批。当前授权只覆盖字段级契约与 3a Project Threads 的默认关闭
> flag、切片实现和双路径对照；`main.dart` 显式保持
> `projectThreadsSliceEnabled: false`，因此不扩大生产路径风险。3a 翻旗与 3b Usage
> Statistics 开工分别另行推进。批次契约见
> [第 3 批开工文档](phase3_batch3_project_threads_usage_statistics.md)。
>
> **第 3 批 3a 显式翻旗确认（2026-08-23）**：完整双路径与重构门禁通过后，经
> 后续显式确认，`main.dart` 已传 `projectThreadsSliceEnabled: true`。3a 风险为中，
> 取至少 5 天观察期，最早于 2026-08-28 关批；第 1、2、3a 的观察窗口独立计时，
> 任一批回退不连带切换其他 flag。
>
> **第 3 批 3b 显式翻旗确认（2026-08-23）**：完整统计页与 Agent Usage Panel 的
> 两个纯 Dart owner、app effect runner/组合、Riverpod 只读镜像和根组合双路径对照
> 通过后，经后续“继续下一步”显式确认，`main.dart` 已传
> `usageStatisticsSliceEnabled: true`。3b 风险为中，取至少 5 天观察期，最早于
> 2026-08-28 关批；3a 与 3b 独立回滚、独立计时。
>
> **第 3 批提前关批记录（2026-08-23）**：用户随后明确要求“直接进行下一阶段”，
> 接受缩短 3a/3b 原定观察余量并直接执行四步节奏第 4 步。三个旧
> `ChangeNotifier` owner、两个批内 flag、Shell usage 装配链和 false-path 已删除；
> 第 3 批固定为 MVI 单一路径。该授权不改变第 1、2 批独立的观察与回滚边界。
>
> **第 4 批 4a/4b 默认关闭路径落地记录（2026-08-23）**：经“继续进行第 4 批”和
> 后续“继续”显式确认，依次迁移 Workspace 与 IDE Session context；
> `workspaceSliceEnabled`、`ideSessionSliceEnabled` 均在生产入口显式保持 `false`。
> 新 store dormant 时不接收业务写入，旧 Shell 字段仍是生产唯一 owner；两批完整
> 重构门禁均已通过。生产翻旗、root snapshot 和关批均未获授权。字段契约见
> [第 4 批开工文档](phase3_batch4_workspace_ide_session.md)。
>
> **第 4 批 4a/4b 显式翻旗确认（2026-08-23）**：默认关闭双路径与完整重构门禁
> 通过后，经后续“继续”显式确认，生产入口同时传
> `workspaceSliceEnabled: true`、`ideSessionSliceEnabled: true`。两个 flag 保持独立
> 回滚，第 4 批按中高风险取至少 7 天观察期，最早于 2026-08-30 关批；任一路径回退
> 只重置自身观察窗口。root snapshot、旧路径删除和关批仍未获授权。

**关门标准（每批合入的条件）**，逐条来自目标架构 Phase 3 验收标准：

- 该批业务事实唯一 owner 已迁移，无 controller/notifier 双写；
- 本批旧入口**当批删除**，不拖到 Phase 4；
- 行为、持久化格式（schema version 不变）、真实 wire 参数零变化；
- 架构守卫全绿，且本批涉及的燃尽清单条目只减不增（§2.11 联动表）；
- 批内 feature flag 可独立回退（关批时随旧入口一起删除）。

---

## 1. 批次总览

| 批次 | 范围 | 现任状态 owner（迁移源） | 风险 | 本批主要删除物 |
| --- | --- | --- | --- | --- |
| 1 | settings（appearance / general） | `AppearanceSettingsController`、`GeneralSettingsController` | 低：消费面小，无 Provider 协议 | 两个 ChangeNotifier controller、settings domain 的 Flutter 类型 |
| 2 | provider 配置 / 管理 / 模型目录 | `AgentProviderSettingsController`（实现 `AgentProviderSettingsPort`）、`AgentManagementController`（785 行）、`AgentModelCatalogRepository` | 中高：port 被 agent / project_threads / agent_management 多处消费；G4 能力位 | provider settings 的 ChangeNotifier 形态、management 的 controller 形态 |
| 3（已关批） | project threads + usage statistics | 迁移源 `ProjectThreadsViewModel`、`UsageStatisticsController`、`AgentUsagePanelController` 均已删除；当前 owner 为三个纯 Dart store | 中：跨 provider 聚合、分页、防抖、恢复 | ✅ 三个 ChangeNotifier、两个 flag 已删；usage 组装链已移出 Shell |
| 4 | workspace + ide session | 文件树/项目状态直接长在 `IdeShellController`（1416 行）上、`WorkspaceFileIndexController`、`IdeSessionPersistenceCoordinator` | 中高：启动恢复流程、文件树热路径 | `IdeShellController` 的树/项目/会话状态字段与 repository 构造 |
| 5 | desktop attention + conversation workspace 外壳 | `DesktopAttentionController`、`IdeShellController` 的 entry↔列表同步管线、三个 conversation 级 controller（mode / model selection / skills） | 中高：G5 审批语义、entry 生命周期、Binding lease | conversation 级 ChangeNotifier ×3、`agent_thread_workspace_controller` 的反向依赖 |
| 6 | 三个显式 Provider 插件 | `CompatibilityAgentProviderPlugin`（使用点计数 1，测试断言）+ `DefaultAgentProviderFactory` 的 kind switch | 低：kernel 契约测试齐全（665 行 registry 测试） | 兼容层账本兑现：`CompatibilityAgentProviderPlugin`、`ZetaPluginCatalog.compatibility` |

批次内部可再拆小步（如第 2 批拆 2a/2b/2c），但**一次只迁一个 context**，不合并
两个高风险 context（目标架构 Phase 3 禁区）。

---

## 2. 横切规则（每批必守）

### 2.1 批次节奏（四步关批）

Phase 2 的经验是"新旧并存 + flag 二选一"；Phase 3 的差异是**关批即删旧路径**。
每批按固定节奏走：

1. **挂 flag**：新切片落地，批内全局 flag（沿用 [Phase 2 §9.8](phase2_conversation_slice.md)
   的全局 bool 模式，如 `settingsSliceEnabled`）默认 false，生产行为不变；
2. **对照验证**：渲染等价、行为语义、守卫、（涉及热路径时）Phase 0 帧预算双路径各测一次；
3. **翻 flag**：生产切到新路径，进入观察窗口（建议 ≥ 3 天，按批次风险调整）；
4. **关批**：删除本批旧入口与 flag，更新燃尽清单与守卫基线，提交批次文档（§9 模板）。

### 2.2 owner 与投影

- 每个业务事实只有一个 store owner；Riverpod provider 暴露 owner 不复制 owner。
- 跨 context 只传 ID、不可变 snapshot、typed event 或 port（目标架构 §4.2 所有权规则）。
- 迁移是"搬家"不是"重造"：字段一一映射，**新增业务事实必须为 0**（Phase 2 §2.8 先例）。

### 2.3 MVI 契约

- Intent / State / Effect / result intent 命名按 [Phase 1 §3](phase1_boundaries.md)；
  变体用发生的事命名，不建通用基类框架。
- reducer 纯同步（G3）：现有 controller 里的防抖（project threads 搜索 300ms、
  workspace 重建索引 400ms、会话保存防抖）、串行队列（general settings 的
  `_enqueue`）全部留在 adapter / effect 层，不进 reducer。
- 迟到结果按 `OperationId` + scope 丢弃（Phase 2 §4.3 的两次校验模式）。

### 2.4 Riverpod adapter

- family 按 key 隔离；select 基于不可变值；autoDispose 只管 UI 订阅，
  **不得**决定 CLI runtime、Binding lease 或 thread 生命周期（§12.11）。
- 组合层注入沿用 Phase 2 的 resolver 模式（`NotifierProvider` + 首帧后 bind）。
- selector 先粗后细：先用 Phase 0 基线证明 rebuild 超预算，再细化（§12.19）。

### 2.5 持久化零变化（G7）

- 本阶段**不新增、不修改**任何持久化 schema：`appearance.json` v1、
  `general.json` v3、`providers.json` v2、`ide_session.json` v4、
  `usage_statistics_index.json` v4、`agent_models_v1.json` 全部原样。
- codec / store 实现文件不动；切片只换"谁在内存里持有状态"，不换"怎么落盘"。
- 白名单、原子写（`AtomicTextFile`）、单写者串行化语义保持。

### 2.6 `IdeShellController` 只减不增

它是 app 层最大的跨 feature ChangeNotifier 组合点（1416 行，import 面跨 5 个
feature）。本阶段规则：

- 每批把对应职责移出后，该职责**禁止回流**；最终形态只剩跨 feature workflow
  协调（项目打开编排、entry 选择接线），目标架构 §13 的定位。
- 新增组合需求一律进 Riverpod 组合层或 `lib/src/app`，不往 shell 里加字段。
- 各批移出的时机见 §1；全部六批结束后它应当不再是任何业务事实的 owner。

### 2.7 `ZetaStateSnapshot`（只读根投影）

目标架构 Phase 3 要求的只读 root snapshot，排在**第 4 批之后**建立：它聚合的是
各 feature 切片的只读投影，太早建只是空壳。约束：仅供诊断与恢复测试，生产
Widget 禁止订阅（§11.3 告警项 + 守卫）。

### 2.8 兼容层纪律

- 本阶段唯一预期兼容物是**批内 feature flag**（四步节奏里第 4 步删除）。
- 任何新兼容 API 必须登记账本（owner、使用点计数、删除批），参照
  [Phase 1 §1.3](phase1_boundaries.md) 的格式。

### 2.9 capability 与审批语义（G4 / G5）

- 第 2 批起涉及 `AgentProviderCapabilities` 的 UI 一律按 capability 渲染，
  不按 provider kind 硬编码；端口缺失照旧抛 `UnsupportedError`。
- 第 5 批触碰 conversation 外壳时，四种审批语义（权限 / 提问 / Plan 审批 /
  Plan 执行交接）的 request/decision 模型与回写端口**保持隔离**，切片 Intent
  不得合并它们。

### 2.10 测试口径

- 每批的等价性证据 = 行为测试（旧/新路径对照）+ 契约测试（持久化宽容解码、
  wire 参数）+ 架构守卫 +（热路径）Phase 0 帧预算。
- fake provider 的 Widget 测试不替代真实平台验收；批内不新增真实 CLI 冒烟要求
  （协议没动），但第 5 批结束建议做一次三 Provider 手工冒烟。

### 2.11 燃尽清单联动表

守卫清单（`feature_layering_guard_test` 与 `package_boundary_candidate_graph_test`）
里的既有条目，按批次分配清零。**只减不增**是每批关批检查项：

| 燃尽清单 | 条目 | 随哪批清零 |
| --- | --- | --- |
| `knownApplicationToPresentation`（当前 1，基线 2） | ~~`project_threads_controller`~~ | ✅ 第 3 批 3a 已清零 |
| | `agent_thread_workspace_controller` | 第 5 批 |
| `knownApplicationFlutterImports`（4a 后当前 9，基线 12） | settings ×2（appearance / general controller） | 第 1 批 |
| | `agent_provider_settings_controller`、`agent_provider_settings_port`、`agent_management_controller` | 第 2 批 |
| | ~~`usage_statistics_controller`、`agent_usage_panel_controller`~~ | ✅ 第 3 批已清零 |
| | ~~`workspace_file_index_controller`~~ | ✅ 第 4 批 4a 已清零 |
| | `agent_conversation_mode_controller`、`agent_conversation_model_selection_controller`、`agent_skills_catalog_controller`、`agent_thread_workspace_controller` | 第 5 批 |
| `knownDomainImpurities`（4a 后当前 0，基线 4） | ~~settings domain ×3（`appearance_settings` / `general_settings` / `system_font_family`）~~ | ✅ 第 1 批已清零（§3.2 决策点 A） |
| | ~~`workspace_directory_rules`~~ | ✅ 第 4 批 4a 清理过期清单项 |
| ~~`_knownExternalViolations`（7，全在 `core/`）~~ | ~~`app_logging` ×2、`sensitive_data_redactor`、`atomic_text_file`、`zeta_data_paths`、`path_utils`、`system_file_manager`~~ | ✅ 2026-08-23 已清零（开工文档起草当天，独立于任何迁移批）：IO 下沉 `app/storage` / `app/logging` / `ui/core`，路径与脱敏注入化 |
| `_agentCoreFlutterBaseline = 17` | `zeta_agent_core` 的 `flutter/foundation` 依赖 | 不绑单批：随相关监听方改造递减，Phase 4 前清零；日志 sink 单例例外（§12.10）在其取消条件满足（内核用日志的类改构造注入）时一并删除 |

---

## 3. 第 1 批：settings —— 详细设计

### 3.1 现状盘点

**`AppearanceSettingsController`**（`features/settings/application/`，
`extends ChangeNotifier`）：

- 状态 = `AppearanceSettings { themeMode: ThemeMode, uiFontChoice, codeFontChoice,
  uiFontSize(10–20), codeFontSize(10–24) }`（不可变，`copyWith`/`==`/`tryDecode`）；
- 字体选项目录 `loadUiFontChoices()` / `loadCodeFontChoices()` 来自
  `SystemFontCatalogService`（系统字体目录，异步加载）；
- **语义 A（乐观）**：setter 先改内存并 notify，再 `store.save`；失败仅记日志，
  内存不回滚；
- 持久化 `~/.zeta/config/appearance.json`，version 1，version≠1 回落默认；
- 消费方：`app.dart`（全局主题构建 `ValueListenableBuilder`）、`ide_home.dart`、
  `settings_page.dart`（`_AppearanceSettingsPane`）。

**`GeneralSettingsController`**（同目录，`extends ChangeNotifier`）：

- 状态 = `GeneralSettings { sendMessageShortcut, notifications
  {enabled, turnTerminalEnabled, actionRequiredEnabled}, appLanguage }`；
- **语义 B（persist-first）**：所有操作经 `_enqueue` 串行队列，`store.save`
  成功才更新内存；失败返回 `persistenceFailed`，内存不变，UI 弹 toast；
- 持久化 `~/.zeta/config/general.json`，codec v3（宽容解码 v1/v2）；
- 消费方：`ide_home.dart`、`settings_page.dart`（`_GeneralSettingsPane`）、
  `desktop_attention_controller.dart`（`addListener` 订阅通知开关）。

**两条语义并存是历史现状，不是缺陷**。本批如实保留（§3.4），统一化列为
迁移后清理项，不在本批顺手改——行为零变化是关批条件。

### 3.2 切片状态与字段映射

一个 feature、**两个切片**（决策点 B）：`AppearanceSettingsSlice` 与
`GeneralSettingsSlice` 各自一个 NotifierProvider + selector。理由：主题/字号
变更不应重建 general 面板，反之亦然；两份持久化文件、两种语义天然是两个
bounded context。

| 现有字段 | 切片字段 | 事实 owner | 备注 |
| --- | --- | --- | --- |
| `themeMode: ThemeMode` | `themeMode: ZetaThemeModePreference` | appearance 切片 | **决策点 A**：`ThemeMode` 是 Flutter 类型，domain 不许持有；新建纯 Dart 枚举，presentation/app 映射回 `ThemeMode` |
| `uiFontChoice` / `codeFontChoice` | 同名 | appearance 切片 | `AppearanceFontChoice {kind, fontFamily?}` 已是纯 Dart |
| `uiFontSize` / `codeFontSize` | 同名 | appearance 切片 | 边界 clamp 逻辑留在 reducer（纯函数） |
| 字体选项列表 + 加载态 | `uiFontOptions` / `codeFontOptions` + `fontCatalogPhase` | **`SystemFontCatalogService`（切片只投影）** | 派生缓存四元组：source of truth = 系统字体目录服务；key = root + ui/code；invalidation = 显式 load 请求；budget = 进程内，列表本身有限 |
| `sendMessageShortcut` | 同名 | general 切片 | |
| `notifications`（3 bool） | 同名 | general 切片 | |
| `appLanguage` | 同名 | general 切片 | "下次启动生效、当前进程冻结 locale"语义不变（`app.dart` 现状） |

新增业务事实：**0**。`isLoading` 派生 getter、`displayNameFor` 一类的展示辅助
留 presentation selector。

### 3.3 Intent 清单

appearance：`AppearanceSettingsLoadRequested / Loaded / LoadFailed(kind)`、
`ThemeModeSelected(ZetaThemeModePreference)`、`UiFontChoiceSelected(choice)`、
`CodeFontChoiceSelected(choice)`、`UiFontSizeAdjusted(value)`、
`CodeFontSizeAdjusted(value)`、`UiFontCatalogRequested / Loaded`、
`CodeFontCatalogRequested / Loaded`。

general：`GeneralSettingsLoadRequested / Loaded / LoadFailed(kind)`、
`MessageSendShortcutSelected(shortcut)`、`AppLanguageSelected(language)`、
`NotificationsEnabledToggled(value)`、`TurnTerminalNotificationsToggled(value)`、
`ActionRequiredNotificationsToggled(value)`。

### 3.4 Effect 与语义保持

| Effect | result intent | 语义 |
| --- | --- | --- |
| `LoadAppearanceSettingsEffect` | `AppearanceSettingsLoaded` / `LoadFailed` | 经 data store 端口读文件；损坏/version≠1 回落默认（现状） |
| `PersistAppearanceSettingsEffect(settings)` | `AppearanceSettingsPersisted` / `PersistFailed(kind)` | **语义 A**（主题 / 字号）：reducer 收到 Intent 即应用新值，持久化失败只产出诊断 result（不改状态、不弹错——现状如此） |
| `ResolveAppearanceFontChoiceEffect` | `AppearanceFontChoiceResolved` / `Rejected` | **字体选择是先解析后应用**（实现时核对 controller 原文修正）：系统字体须经字体目录异步解析、代码字体要求等宽、槽位 kind 规则由 runner 执行；解析成功才应用+持久化，被拒绝则不应用不落盘。槽位在途身份独立追踪（界面/代码各一），迟到解析结果丢弃 |
| `LoadGeneralSettingsEffect` | `GeneralSettingsLoaded` / `LoadFailed` | codec 宽容解码 v1/v2/v3（现状） |
| `PersistGeneralSettingsEffect(settings)` | `GeneralSettingsPersisted(outcome)` / `GeneralSettingsPersistFailed(kind)` | **语义 B**：reducer 只登记在途（身份 + **在途值**——后续修改基于在途值计算，复刻串行队列，否则丢未应用的修改）；`Persisted` 才写状态；失败保持旧值并暴露给 UI 弹 toast（现状 `persistenceFailed` → `settingsLanguageSaveFailed`） |

`OperationId` scope：`settings.appearance.persist` / `settings.general.persist`
（general 的串行队列 `_enqueue` 语义搬到 effect runner，保持单写者）。

### 3.5 生命周期与订阅改造

| 对象 | 创建者 | 释放者 |
| --- | --- | --- |
| 两个切片 store | app 组合层 Riverpod provider（app session 寿命，非 autoDispose） | 容器销毁 |
| `AppearanceSettingsStore` / `GeneralSettingsStore` 文件实现 | `MainApp`（现状注入点不变） | app |
| `SystemFontCatalogService` | app 组合层 | app |

订阅点改造清单：

- `app.dart` 全局主题构建：`ValueListenableBuilder` → selector（枚举→`ThemeMode`
  映射在此层）；
- `settings_page.dart` 两个 pane：controller 直调 → dispatch Intent + selector；
- **`desktop_attention_controller.dart`**：现在 `addListener` 订阅
  `GeneralSettingsController`。改为注入纯 Dart 回调订阅（切片 store 自维护
  listener 列表，Phase 2 §review 修复同款模式），顺带消除它对 settings
  controller 的直接类型依赖。

### 3.6 §15 门禁答卷（第 1 批）

1. **唯一 owner**：持久化偏好归两个 settings 切片（经 store 端口）；字体选项
   目录归 `SystemFontCatalogService`，切片只投影。无第二 owner。
2. **Intent / State / Effect / Result**：见 §3.2–3.4。
3. **越界类型**：`ThemeMode` 换纯 Dart 枚举（决策点 A）；切片纯 Dart
   （`package:meta`）；Riverpod 只在 presentation/组合层；`dart:io` 只在 data
   store（app 注入，现状）。
4. **创建/释放**：见 §3.5；store 文件实例由 `MainApp` 注入，切片不拼 `~/.zeta` 路径。
5. **迟到结果**：persist effect 携带 `OperationId`；general 单写者队列天然无
   并发覆盖；appearance 乐观语义下迟到 persist 失败不回滚（现状行为）。
6. **正文/频率**：无正文字段；设置变更天然低频；两个切片隔离保证主题切换不
   重建 general 面板（验收测试钉住）。
7. **缓存**：仅字体选项目录（四元组见 §3.2）；不新增其他缓存。
8. **持久化白名单 / schema**：不变（§2.5）。
9. **回滚**：`settingsSliceEnabled` 全局 bool（§2.1 四步节奏）；无双写；关批时
   删旧 controller 与 flag，回滚 = revert 关批提交。
10. **等价性证据**：§3.7。

### 3.7 验收测试清单

| # | 测试 | 证明 |
| --- | --- | --- |
| 1 | settings 两 pane 渲染等价（批内 flag 双路径对照） | 迁移是搬家不是重造 |
| 2 | 语义 A/B 保持：appearance 保存失败内存仍更新；general 语言保存失败弹 toast 且状态不变 | 两条持久化语义如实迁移 |
| 3 | 宽容解码回归：appearance version≠1 回落默认；general v1/v2/v3 迁移 | 既有 codec 测试保留全绿 |
| 4 | 桌面通知联动：通知开关变化仍触发 `DesktopAttentionController` 门控行为 | 订阅点改造（§3.5）无遗漏 |
| 5 | 全局主题构建：appearance 变化驱动主题；general 变化不触发主题重建 | selector 隔离 |
| 6 | 守卫基线：`knownApplicationFlutterImports` −2、`knownDomainImpurities` −3 | 燃尽联动兑现 |
| 7 | 关批删除验证：两个旧 controller 全仓无引用 | 旧入口当批删除 |

### 3.8 删除清单（关批时）

- `appearance_settings_controller.dart`、`general_settings_controller.dart`；
- `settings_page.dart` / `ide_home.dart` / `app.dart` 的 controller 传参与
  `listenable` 消费点；
- domain 的 `ThemeMode` 引用（`appearance_settings.dart` 纯化）；
- `settingsSliceEnabled` flag。

---

## 4. 第 2 批：provider 配置 / 管理 / 模型目录（框架级）

建议拆三个小步：

- **2a provider settings 切片**：`AgentProviderSettingsController`（实现
  `AgentProviderSettingsPort`）是本批核心。port 接口是稳定契约
  （目标架构 §5.1），**签名不动**；实现从 ChangeNotifier 换成 MVI store +
  Riverpod adapter，消费方（workspace controller、project threads、
  management、app）逐个切到 selector/port。`updateProviderConfig` 内联的
  模型目录失效 + runtime 失效编排拆成 effect（G3）。
  `providers.json` v2 与 V1→V2 权限迁移原样。
- **2b 模型目录投影**：`AgentModelCatalogRepository` 已经是非 ChangeNotifier
  的应用层仓储（stale-while-revalidate：freshFor 1h / maxStaleFor 7d /
  configFingerprint 失配丢弃 / single-flight），**仓储不动**，只在 Riverpod
  层加 selector 投影。缓存四元组已天然满足 §7.4，写进批次文档即可。
- **2c management 页面切片**：`AgentManagementController`（785 行：检测、配置
  编辑、日志、连接测试）按页面 scope 的 application state 切片化，TOML 编辑器
  的草稿态留 presentation（§7.3 Widget scope）。

开工前须按 §9 模板补齐：字段映射（当前 `AgentProviderConfig` 14 个存储字段 +
settings 外层/派生 4 项逐一对照）、
capability 位与 UI 入口的 G4 对照表、`AgentProviderSettingsPort` 消费方清单与
切换顺序、删除清单。

> **开工记录（2026-08-23）**：经显式确认，第 1 批观察期间启动第 2 批；当前只推进
> flag 默认 false 的挂旗与对照阶段，生产行为不变。字段级契约、依赖图、生命周期与
> 删除清单见 [第 2 批开工文档](phase3_batch2_provider_management.md)。第 2 批生产翻旗
> 仍需另行确认。
>
> **执行记录（2026-08-23）**：2a Provider settings store/runner 与 2b 模型目录
> keyed Riverpod 投影已落地；目录 repository、TTL、single-flight、generation、缓存
> schema 与 Composer selection owner 均未改动。2c management page
> store/runner/Riverpod 接缝随后完成，配置草稿仍归 Widget；双路径与完整重构门禁通过。
>
> **生产翻旗记录（2026-08-23）**：经再次显式确认接受与第 1 批观察重叠，生产入口
> 已传 `providerManagementSliceEnabled: true`，进入至少 7 天观察；旧路径只作为独立
> flag 回滚面保留，未创建双 owner 或双写。

---

## 5. 第 3 批：project threads + usage statistics（已关批）

- **Project Threads**：`ProjectThreadsSliceStore` 是按项目列表状态的唯一 owner；
  `ProjectThreadsController` 只保留 Provider 查询、能力校验、写操作与 300 ms 搜索
  防抖。presentation 只读 Riverpod selector，application→presentation 反向依赖已清零。
  跨 Provider 上限 50、`agg:` 游标、session snapshot codec 与 G4 行为均未改变。
- **Usage Statistics**：`UsageStatisticsSliceStore` 与
  `AgentUsagePanelSliceStore` 分别拥有页面和侧栏状态。QueryService、两个 query
  repository、quota source 与 source registry 已从 `IdeShellController` 移到 app
  composition；分区索引 v4、fingerprint 和 Provider 私有 parser 未改变。
- **删除完成**：`ProjectThreadsViewModel`、`UsageStatisticsController`、
  `AgentUsagePanelController`、`projectThreadsSliceEnabled`、
  `usageStatisticsSliceEnabled` 及所有 false-path 均已删除。Riverpod store provider
  改为非空、漏装配即抛错。

3a/3b 均先完成默认关闭实现、双路径等价验证和生产翻旗；用户随后显式要求直接进入
下一阶段，接受缩短原定观察余量并授权关批。字段映射、生命周期、竞态、测试证据与
回滚规则见
[第 3 批关批文档](phase3_batch3_project_threads_usage_statistics.md)。

---

## 6. 第 4 批：workspace + ide session（生产观察中）

- **workspace**：文件树/展开/选择状态的 owner 现在是 `IdeShellController`
  本身（`_workspaceTree`、`_expandedDirectoryPaths`、`_selectedTreePath`、
  `_currentFilePath`），不是 workspace feature——本批把它迁成
  `WorkspaceSliceState`，懒加载展开（`WorkspaceNode.updateNode` + 按需读子层）
  机制原样，索引就绪信号从 `WorkspaceFileIndexController`（本批去
  ChangeNotifier 化，改自维护 listener 列表）注入。
  `@mention` 语料链（index controller → workspace controller → ViewModel）
  改走 port，不在 presentation 拼装。
- **ide session**：`IdeSessionPersistenceCoordinator`（防抖保存 + restore
  token）语义原样；`IdeSessionState` v4 与 `state builder` / `sanitize` 不动。
  切片的持久化 effect 调用现有 coordinator，**不重写保存流程**。
- 本批结束后建只读 `ZetaStateSnapshot`（§2.7）。
- 这是 `IdeShellController` 拆解的主菜：树/项目/会话状态全部移出后，shell
  只剩跨 feature workflow。

---

## 7. 第 5 批：desktop attention + conversation workspace 外壳（框架级）

- **desktop attention**：`DesktopAttentionController` 已是良好形状（final、
  非 ChangeNotifier、纯端口依赖）。切片 = attention 状态（未读 identity 表、
  可见性）的只读投影 + Intent（`AttentionMarkedRead`、
  `AttentionVisibilityChanged`）；系统通知与任务栏 indicator 仍是 data 端口
  的 effect。信号流（ViewModel → workspace → shell 回调 → attention）不变。
- **conversation workspace 外壳**：`IdeShellController` 的 entry↔列表同步管线
  （`_handleAgentWorkspaceChanged`、`_refreshWorkspaceEntryBindings` 等）与
  entry 列表/选择状态迁成 workspace 外壳切片；三个 conversation 级
  ChangeNotifier controller（conversation mode / model selection / skills
  catalog）并入 Phase 2 切片的 composer region 管辖（字段映射在 Phase 2
  §2.3 已预留）。`agent_thread_workspace_controller` 的 application→presentation
  燃尽条目在此清零。G5 四种审批语义的隔离由既有测试 + 切片 Intent 命名守卫。

---

## 8. 第 6 批：三个显式 Provider 插件 + 删 compatibility（框架级）

现状事实（开工时复核）：

- `CompatibilityAgentProviderPlugin`（pluginId
  `zeta.agent.compatibility-provider-factory`，essential），使用点计数 = 1
  （`zeta_plugin_catalog_test` 扫描断言）；
- `ZetaPluginCatalog.resolveAgentProviderBundleFactory()` 目前 fail-closed 于
  "恰好 1 个贡献"（0 个或 >1 个都抛）；
- `DefaultAgentProviderFactory` 按 `config.kind` switch 分派三个 bundle 工厂。

设计方向（批次文档细化）：

1. 新建 `packages/zeta_agent_providers/lib/{codex,grok,claude_code}_plugin.dart`
   三个显式插件（目标架构 §9.3 的理想改动面），各自 descriptor + 独立
   `AgentProviderPluginContribution`；kind switch 逻辑消解进各自插件；
2. catalog 的 resolve 规则从"恰好 1 个"改为"按贡献声明的 provider 域聚合，
  未覆盖的 providerId fail-closed 抛错"——不允许静默回落；
3. 三个插件均 essential：注册失败进入 degraded state（与现状
   compatibility essential 语义一致）；
4. **兼容层账本兑现**：删除 `CompatibilityAgentProviderPlugin` 文件与
   `ZetaPluginCatalog.compatibility` 入口，更新
   `zeta_plugin_catalog_test` 的使用点计数断言与 [Phase 1 §1.3](phase1_boundaries.md)
   账本（标记已删除）；
5. 契约测试更新清单：plugin registry 契约（665 行）不因三插件改变；
   `agent_providers_contracts_test` 的工厂断言迁移到各插件测试；
   新增"三插件同激活 + 反序关闭"与"单一插件失败 → degraded"测试。

---

## 9. 批次开工文档模板（每批开工前必填）

新文件 `phase3_batch<N>_<名称>.md`，至少包含：

> 第 1 批的批次文档已备：[phase3_batch1_settings.md](phase3_batch1_settings.md)
> （2026-08-23 按本模板起草，含消费方依赖图与切换顺序）。

1. 范围与不迁清单（对应目标架构 Phase 3"不应该同时进行"）；
2. 字段映射表：现状字段 → 切片字段，逐条标注事实 owner；**新增业务事实 = 0**；
3. Intent / Effect / result intent 清单（命名按 Phase 1 §3）；
4. 操作身份与迟到结果判定（`OperationId` scope + 校验时机）；
5. 生命周期与 dispose 归属表；
6. §15 十问逐条作答；
7. 验收测试清单（行为等价 + 守卫基线变化 + 热路径帧预算）；
8. 删除清单（关批时删掉的文件 / 类 / 入口）；
9. 回滚方式（批内 flag 名 + 关批 revert 策略）。

---

## 10. 不做清单（重申）

目标架构 Phase 3 禁区全部有效：

- 一次迁移两个高风险 context（conversation、runtime、session restore）；
- 新路由框架、全局状态库或代码生成体系；
- 云同步、第三方插件 SDK、移动端支持；
- 大规模视觉 redesign 或 Provider 协议重构。

本阶段特有补充：

- 不动 G1 五文件、entryId / coalescing / reducer identity；
- 不改任何持久化 schema（§2.5 的六个文件版本号冻结）；
- `core/` 七处 `dart:io` 清理不与任何迁移批混在同一 PR；
- `zeta_agent_core` 的 17 文件基线不因无关重构波动（只随监听方改造递减）；
- 不趁机"统一"两条 settings 持久化语义（§3.1）——那是行为变化，另立任务。
