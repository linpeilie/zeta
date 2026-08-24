

# Phase 3 开工文档：Feature 切片扩展迁移

> ⚠️ **历史迁移证据（Phase 4 已完成）。**
> 本文记录的是当时的迁移过程与决策，**不描述当前架构**——其中提到的过渡层、
> 燃尽清单与中间态符号多数已在 Phase 4 删除。
> 当前架构以 [`AGENTS.md`](../../AGENTS.md) 与 [`overview.md`](overview.md) 为准；
> Phase 4 的删除边界见 [`phase4_transition_cleanup.md`](phase4_transition_cleanup.md)。

最后更新：2026-08-24

状态：第 1–6 批代码均已关批；未形成的 14 天/平台阶段证据经 2026-08-24 显式风险接受
不再阻塞后续，Phase 3 代码迁移范围已收口并移交 Phase 4。

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
| Phase 2 稳定一个发布周期或等价真实使用证据 | ⏳ 2026-08-24 重计：本轮修复 slice 路径竞态，最早约 2026-09-07 形成连续 14 天证据（[Phase 2 §9.8](phase2_conversation_slice.md)） |
| 代表性 slice 的性能、dispose、重试、取消和回滚机制验证完成 | ✅ [Phase 2 §8 验收表](phase2_conversation_slice.md) 十条全过 |
| 每一批都有 owner 映射、依赖图和删除清单 | ✅ 本文档：第 1 批全量，第 2–6 批框架级，§9 模板作为每批开工门禁 |

**开门标准（显式）**：

1. 切片路径生产使用连续 **14 天**未出现需要把 `conversationSliceEnabled` 拨回
   `false` 的问题（2026-08-23 起算）。期间发现并修复 slice 路径 bug 后**重新计时**。
   起点锚：2026-08-23 生产启动冒烟通过（macOS，切片 flag 开启；会话恢复 +
   三 Provider 真实 CLI 连接 + 模型目录拉取，日志零错误）。
2. 本文档评审定稿。
3. 每批开工前，该批文档按 §9 模板补齐并答完 §15 十问。

> **连续观察重计（2026-08-24）**：阻塞 1/3/4 收口期间修复了 settings slice
> 首次 load/写入交错与持久化失败夹带等路径 bug。依照上面的重新计时规则，观察窗口
> 从目标态提交 `ffc06005` 后重新起算，最早约 2026-09-07 形成连续 14 天证据；提前
> 删除第 1/2 批旧路径的风险接受不豁免此门禁。

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
> **第 6 批直接目标态确认（2026-08-24）**：按明确要求不挂 flag、不保留
> compatibility/default factory 双轨，直接拆为三个 essential Provider 插件，并同步
> 清算 Phase 1 §8.1 的 core 封闭目录。该授权只覆盖第 6 批，不豁免第 1、2 批观察、
> Phase 2 连续 14 天证据或 Phase 4 的平台/发布前置条件。
>
> **第 1、2 批提前关批确认（2026-08-24）**：用户明确要求修复阶段阻塞 1、3、4，
> 并确认不等待第 1、2 批原定观察日期。因此 settings 与 Provider
> settings/management 同次删除旧 controller、ingress/Flutter Listenable、两个 flag
> 及所有 false-path，root snapshot 对应节点改为必选；这是缩短批内观察余量的显式
> 风险接受。该确认没有选择阻塞 2、5，不豁免 Phase 2 连续 14 天证据，也不把未执行的
> 迁移窗口、回退锚、三平台真实 Provider smoke 或 Profile 推断为通过。
>
> **Phase 4 准入豁免（2026-08-24）**：后续用户明确要求忽略剩余问题并开始 Phase 4。
> Phase 2 连续 14 天、迁移窗口/回退锚、三平台真实 Provider smoke 与 Windows Profile
> 均保持“未执行/未形成”，但不再作为 Phase 4 的开工或关批门禁；这项风险接受不等于
> 证据通过，也不授权删除持久化/协议的向后读取。执行口径见
> [Phase 4 执行计划书](phase4_transition_cleanup.md)。
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
>
> **第 4 批提前关批记录（2026-08-23）**：用户随后明确要求“执行关批和旧路径
> 删除”，接受缩短原定观察余量并直接执行四步节奏第 4 步。两个批内 flag、Shell
> Workspace 八个旧字段、直接目录树构造、Session coordinator false-path 与旧恢复/保存
> 入口已删除；只读 `ZetaStateSnapshot` 已建立。第 4 批固定为 MVI 单一路径，该授权
> 不改变第 1、2 批独立的观察与回滚边界。

> **第 5 批直接关批记录（2026-08-23）**：用户明确要求直接采用新方案，不先保留
> 旧方案再逐步修改。因此本批没有建立新 flag 或双轨 owner；Desktop Attention、
> Conversation Workspace 与 Composer owner 一次迁入目标结构，同时删除 Phase 2
> Conversation fallback。字段级契约与验收见
> [第 5 批关批文档](phase3_batch5_desktop_attention_conversation_workspace.md)。

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
| 4（已关批） | workspace + ide session | 迁移源 Shell Workspace 字段与 Session false-path 已删除；当前 owner 为 `WorkspaceSliceStore`、`IdeSessionSliceStore` | 中高：启动恢复流程、文件树热路径 | ✅ 两个 flag、八个 Workspace 字段、直接树构造与 Session false-path 已删 |
| 5（已关批） | desktop attention + conversation workspace 外壳 | 迁移源 `DesktopAttentionController`、`AgentThreadWorkspaceController` 与 Shell 重复状态均已删除；当前 owner 为 `DesktopAttentionSliceStore`、`AgentConversationWorkspaceStore`、`AgentConversationComposerStateOwner` | 中高：G5 审批语义、entry 生命周期、Binding lease | ✅ 三个 application Flutter 燃尽项、旧 workspace controller、Conversation flag/fallback 已删 |
| 6（已关批） | 三个显式 Provider 插件 + 开放 Provider type | 当前 owner 为三个 Provider 插件 definition、`ResolvedAgentProviderPlugins` 与 runtime registry | 低：kernel 契约与三类 native Bundle 矩阵齐全 | ✅ compatibility/default factory/core 封闭目录均删除，生产直接走三插件聚合 |

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

目标架构 Phase 3 要求的只读 root snapshot 已在**第 4 批关批时**建立：它聚合各
feature 切片的只读投影，仅供诊断与恢复测试，生产 Widget 禁止订阅（§11.3 告警项 +
守卫）。Conversation/Management 只进入无正文安全摘要；第 1、2 批尚未关批时对应节点
允许为空，后续关批再收敛为必选。

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
| `knownApplicationToPresentation`（第 5 批后当前 0，基线 2） | ~~`project_threads_controller`~~ | ✅ 第 3 批 3a 已清零 |
| | ~~`agent_thread_workspace_controller`~~ | ✅ 第 5 批迁到 app 组合层并删除旧文件 |
| `knownApplicationFlutterImports`（当前 0，基线 12） | ~~settings ×2（appearance / general controller）~~ | ✅ 第 1 批关批清零 |
| | ~~`agent_provider_settings_controller`、`agent_provider_settings_port`、`agent_management_controller`~~ | ✅ 第 2 批关批清零 |
| | ~~`usage_statistics_controller`、`agent_usage_panel_controller`~~ | ✅ 第 3 批已清零 |
| | ~~`workspace_file_index_controller`~~ | ✅ 第 4 批 4a 已清零 |
| | ~~`agent_conversation_mode_controller`、`agent_conversation_model_selection_controller`、`agent_skills_catalog_controller`、`agent_thread_workspace_controller`~~ | ✅ 第 5 批清零：前三者改为纯 Dart listener，workspace 迁到 app store |
| `knownDomainImpurities`（4a 后当前 0，基线 4） | ~~settings domain ×3（`appearance_settings` / `general_settings` / `system_font_family`）~~ | ✅ 第 1 批已清零（§3.2 决策点 A） |
| | ~~`workspace_directory_rules`~~ | ✅ 第 4 批 4a 清理过期清单项 |
| ~~`_knownExternalViolations`（7，全在 `core/`）~~ | ~~`app_logging` ×2、`sensitive_data_redactor`、`atomic_text_file`、`zeta_data_paths`、`path_utils`、`system_file_manager`~~ | ✅ 2026-08-23 已清零（开工文档起草当天，独立于任何迁移批）：IO 下沉 `app/storage` / `app/logging` / `ui/core`，路径与脱敏注入化 |
| ~~`_agentCoreFlutterBaseline = 17`~~（当前 0） | ~~`zeta_agent_core` 的 `flutter/foundation` 依赖~~ | ✅ 2026-08-24 改用纯 Dart listenable，并在 presentation 建 Flutter adapter；manifest 与源码门禁收紧为零容忍 |

---

## 3. 第 1 批：settings —— 详细设计（已关批）

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
| 4 | 桌面通知联动：通知开关变化仍触发 `DesktopAttentionSliceStore` 门控行为 | 订阅点改造（§3.5）无遗漏 |
| 5 | 全局主题构建：appearance 变化驱动主题；general 变化不触发主题重建 | selector 隔离 |
| 6 | 守卫基线：`knownApplicationFlutterImports` −2、`knownDomainImpurities` −3 | 燃尽联动兑现 |
| 7 | 关批删除验证：两个旧 controller 全仓无引用 | 旧入口当批删除 |

### 3.8 删除清单（关批时）

- `appearance_settings_controller.dart`、`general_settings_controller.dart`；
- `settings_page.dart` / `ide_home.dart` / `app.dart` 的 controller 传参与
  `listenable` 消费点；
- domain 的 `ThemeMode` 引用（`appearance_settings.dart` 纯化）；
- `settingsSliceEnabled` flag。

**关批记录（2026-08-24）**：按 §0 的显式提前关批确认，上述删除项全部执行；
settings 固定为 slice 单一路径，root snapshot 节点必选。

---

## 4. 第 2 批：provider 配置 / 管理 / 模型目录（已关批）

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
>
> **关批记录（2026-08-24）**：按本文件 §0 的显式提前关批确认，两个旧 controller、
> Flutter Listenable port、flag 与 false-path 已删除；Provider settings 与 management
> 固定为唯一 slice owner，root snapshot 节点必选。

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

## 6. 第 4 批：workspace + ide session（已关批）

- **workspace**：文件树/展开/选择状态已由 `WorkspaceSliceStore` 唯一持有；懒加载
  展开（`WorkspaceNode.updateNode` + 按需读子层）机制原样，索引就绪信号由已纯化的
  `WorkspaceFileIndexController` 注入。
  `@mention` 语料链（index controller → workspace controller → ViewModel）
  改走 port，不在 presentation 拼装。
- **ide session**：`IdeSessionPersistenceCoordinator`（防抖保存 + restore
  token）语义原样；`IdeSessionState` v4 与 `state builder` / `sanitize` 不动。
  切片的持久化 effect 调用现有 coordinator，**不重写保存流程**。
- **删除完成**：两个 flag、Shell 八个 Workspace 字段、直接目录树构造、Session
  coordinator false-path 与旧恢复/保存入口均已删除。
- **根投影**：`ZetaStateSnapshot` 已建立为无监听按需读取对象，Conversation 与
  Management 只保存无正文摘要，生产 Widget 继续只 watch feature selector。
- `IdeShellController` 已不再拥有 Workspace/Session feature 状态，只保留项目、thread
  与 conversation 的跨 feature workflow；后者继续在第 5 批迁移。

---

## 7. 第 5 批：desktop attention + conversation workspace 外壳（框架级）

**状态：已关批（2026-08-24，直接目标态）。**

- **desktop attention**：`DesktopAttentionSliceStore` 独占未读 identity、可见性与
  notification id；纯 reducer 只返回 typed effect，app runner 独占系统通知、任务栏
  indicator、设置订阅与 activation。旧 controller 已删除。
- **conversation workspace 外壳**：`AgentConversationWorkspaceStore` 独占 entry、选择、
  project home 与 project→thread 映射，并在内部统一订阅 runtime entry；Shell 只做
  Project Threads / Session 跨 feature 协调。旧 application controller、Shell 的
  listener 表与重复字段已删除。
- **composer**：mode / model selection / skills 保留原有迟到判定，改为纯 Dart listener，
  并由 `AgentConversationComposerStateOwner` 按 Conversation 生命周期统一创建与释放。
- **Conversation UI**：每个 entry 必建 `AgentConversationSliceBinding`；注册表在
  `IdeHome.initState` 同步绑定。`conversationSliceEnabled`、enabled provider、nullable
  store 与 `legacyListenable` 分支均已删除，未知 BindingKey fail-closed。
- G5 四种审批模型、Provider wire、TimelineStore、IDE Session v4 与 live delta 局部刷新
  均未改变。完整十问、删除项与验证记录见本节开头链接。

---

## 8. 第 6 批：三个显式 Provider 插件 + 开放 Provider type（已关批）

2026-08-24 直接切到目标态，详见
[第 6 批关批文档](phase3_batch6_provider_plugins.md) 与
[重构证据](../../.workflow/refactor/2026-08-24-phase3-batch6-provider-plugins/)。

- `CodexAgentProviderPlugin`、`GrokAgentProviderPlugin`、
  `ClaudeCodeAgentProviderPlugin` 均为 essential 同步插件，各自贡献 definition 与单域
  bundle factory；
- `config.id` 继续是可自定义的配置实例身份，插件按开放
  `AgentProviderTypeId` 路由；JSON `kind` key、版本与三种既有值未变；
- `ResolvedAgentProviderPlugins` 在未激活、degraded、零贡献、essential 插件贡献数不是
  1、重复 ID/type 时拒绝
  resolve；ID/type 还必须是非空无首尾空白的 canonical 值；聚合 factory 对未知 type
  抛错，不回落任一内置 Provider；启动解析失败会关闭此前已激活的 handle；
- compatibility plugin、default factory、旧 catalog 入口与 core 的内置 ID/default
  config/display-name switch 已物理删除；Phase 1 §1.3/§8.1 账本同步结清；
- runtime registry 仍是 bundle/runtime/CLI 唯一 owner，插件 handle 不创建或关闭进程；
- 三类 native Bundle 端口矩阵、custom config id、V1/V2 codec、权限迁移、静态能力、
  degraded/duplicate/unknown 路径与零旧符号守卫均已覆盖。

六批代码现在均已关批。§0 与第 6 批文档 §10 记录的阶段证据没有形成；2026-08-24
后续显式决定已将它们记为 `WAIVED` 并移出 Phase 4 门禁，Phase 3 代码迁移范围据此收口。
未执行证据不得在后续文档中写成通过。

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
- `zeta_agent_core` 保持纯 Dart；Flutter import 与 manifest SDK 依赖均为零容忍；
- 不趁机"统一"两条 settings 持久化语义（§3.1）——那是行为变化，另立任务。
