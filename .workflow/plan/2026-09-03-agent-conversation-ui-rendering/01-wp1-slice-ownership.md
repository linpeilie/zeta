# WP-1 · 切片 owner 归位 + ViewModel 拆分

| 项 | 值 |
|----|----|
| 状态 | 已完成（T0–T6） |
| 规模 | 10–14 人天，4 个 PR |
| 依赖 | 建议 WP-2 完成后启动；**T0 前置：WP-7 T3**（scheduler 的 providers 依赖切除，0.5 人天，先合入） |
| 门禁焦点 | G3、G6、「一份状态只能有一个 owner」（AGENTS.md §3） |
| 性质 | **重构**：每个 PR 收尾 `bash tool/test_full.sh` |

> 阅读前提：本文档所有「现状」代码均为 2026-09-03 从仓库逐字摘录，行号可能随后续提交漂移，以符号名为准。

---

## 0. 背景与现状代码

### 0.1 当前链路（四跳）

```
TimelineStore（core 事实源）
 → ViewModel._publishScheduledUiChanges          (agent_conversation_view_model.dart:4189)
 → AgentUiUpdateScheduler                         (presentation，帧合并)
 → AgentConversationUiStateStore.publish          (agent_conversation_ui_state.dart:100，5 个 ValueNotifier)
 → AgentConversationSliceComposition（microtask 再攒批）(app/conversation_slice/…:98-149)
 → AgentConversationSliceStore.dispatch           (application，手写 listener)
 → AgentConversationSliceNotifier（「只做镜像」）  (agent_conversation_slice_providers.dart:63-88)
 → selector → AgentRegionBuilder → Widget
```

### 0.2 关键现状代码（改造锚点）

**`AgentConversationUiStateStore.publish`**（`agent_conversation_ui_state.dart:100-134`）——它实际做四件事：

```dart
void publish(AgentUiUpdateRequest request) {
  if (_closed || _isDisposed() || request.isEmpty) return;
  if (request.regions.contains(AgentUiRegion.liveTurnBinding)) {
    _timeline.syncLiveTurnBinding();                    // ① live 旁路：timeline 操作
  }
  if (request.regions.contains(AgentUiRegion.history)) {
    _publishIfChanged(_history, _buildHistoryState());  // ② region 投影 + 发布
  }
  // ... header / composer / pendingInteraction / expansion 同模式 ...
  if (request.regions.contains(AgentUiRegion.liveTurn)) {
    _timeline.liveTurnState?.markDirty();               // ③ live 旁路：标脏 + 立即冲刷
    _timeline.liveTurnState?.flushNow();
  }
  for (final effect in request.effects) {
    _effectController.add(effect);                      // ④ 一次性 effect broadcast
  }
}
```

**`AgentConversationSliceComposition._flush`**（`app/conversation_slice/agent_conversation_slice_composition.dart:120-149`）：把 5 个 region 的脏标记合并成**一次** `AgentConversationRegionsRefreshed` intent——「同帧五 region 只 publish 一次」是帧预算硬要求，迁移后必须保持。

**`AgentConversationSliceNotifier.build`**（`agent_conversation_slice_providers.dart:70-87`）：现状是纯镜像（`store.addListener(() => state = store.state)`）。

**`AgentConversationSliceStore` 有两块职责**（`application/.../agent_conversation_slice_store.dart`）：

- **region 镜像**（`refreshRegions` → `AgentConversationRegionsRefreshed` intent）——这是要消灭的双轨；
- **命令编排**（`sendMessage` / `respondToPermission` / …，铸造 `OperationId` + scope 快照、dispatch command intent、经 `AgentConversationSliceEffectRunner` 调 `AgentConversationCommandPort`、stale 结果计数）——**这是真正的 application 逻辑，保留**。

**`AgentUiUpdateScheduler`**（`agent_ui_update_scheduler.dart:108-126`）：构造只依赖 `AgentFrameScheduler` 端口（frame 调度已端口化，`SchedulerBindingAgentFrameScheduler` 是唯一的 Flutter 接触点）+ `ZetaMetricsPort` + `AgentMetricLabels.forProviderId`（唯一的 providers import，WP-7 T3 切除）。**结论：scheduler 本体可以原样搬进 application 层。**

**两个窄端口已在 application 层**（`application/conversation_slice/agent_conversation_slice_ports.dart`）：`AgentConversationRegionSource`（:24-44）与 `AgentConversationCommandPort`（:53-120，21 个方法），ViewModel 是它们的唯一生产实现（`agent_conversation_view_model.dart:51-52`）。

## 1. 目标与非目标

### 目标链路（两跳）

```
TimelineStore / EventProcessor
 →（AgentUiUpdateRequest）
 → AgentUiUpdateScheduler（application；frame 调度仍走注入的 AgentFrameScheduler 端口）
 → AgentConversationSliceStore（application，唯一 owner：region 投影 + 命令编排）
 → AgentConversationSliceNotifier（Riverpod 适配器， sanctioned 模式）
 → selector → AgentRegionBuilder → Widget
```

1. **删除**：`AgentConversationUiStateStore`、`AgentConversationSliceComposition`。**为什么 composition 是冗余**（2026-09-03 review 修正）：`AgentUiUpdateRequest` 本身就携带 region **集合**；现状 `UiStateStore.publish` 把一个 request 拆进 5 个 ValueNotifier（5 次 `_publishIfChanged`），SliceComposition 再用 microtask 把同帧最多 5 次通知合并回一次 `RegionsRefreshed` dispatch——一拆一合是迁移中间态的纯浪费。目标态 SliceStore 直接消费 request：一次 dispatch 更新所有涉及的 region，「同帧一次 dispatch」天然成立。注意 scheduler 的帧合并在**另一根轴**上（合并一帧内的多个 request，immediate 会吸收 pending 后直发，见 `agent_ui_update_scheduler.dart:180-229`），与 region 拆合无关，予以保留。
2. **保留**：`AgentConversationSliceStore`（收缩为纯 application store：region 投影 + 命令编排）、`AgentUiUpdateScheduler`（搬到 application）、live turn 旁路（语义不变，见 D3）。
3. **ViewModel 拆分**：runtime 编排 → `AgentConversationRuntimeController`（application）；纯函数归位；`dart:io` → attachment port；ViewModel 最终删除。

### 非目标

- 不动 core 包；不改 `AgentRegionBuilder` 与 5 个 selector 签名；不改 live turn 的 Widget 订阅方式。
- `AgentUiEffect` 仍是**无 replay** 一次性流，只换承载通道（见 D2）。

## 2. 设计决策（实现前读完）

**D1 · scheduler 进 application 的前提**。`AgentUiUpdateScheduler` 依赖三项：`AgentFrameScheduler`（已是端口，core 定义）、`ZetaMetricsPort`（foundation 端口）、`AgentMetricLabels.forProviderId`（providers 包）。WP-7 T3 把最后一项改为构造注入 `ZetaMetricLabel Function(String providerId)` 后，scheduler 只剩纯 Dart + foundation/core 依赖，整体移入 `application/conversation_slice/agent_ui_update_scheduler.dart`。`SchedulerBindingAgentFrameScheduler`（Flutter 实现）留在 presentation（挪到 `agent_flutter_listenable_adapter.dart` 同文件或独立小文件），由组合根注入。

**D2 · `AgentUiEffect` 通道**（2026-09-03 终审修正：初版写「scheduler 内部挂 StreamController」，与 T2 骨架矛盾——以骨架为准）。effect 不需要帧合并，由 **controller 自持** `StreamController<AgentUiEffect>.broadcast(sync: true)`（`dart:async` 在 application 合法），在 scheduler 的发布回调里随 request 的 effects 一起转发——与现状 `UiStateStore` 内 `StreamController.broadcast(sync: true)`（`agent_conversation_ui_state.dart:33`）完全同构。Widget 侧订阅点本 WP 内不变（`viewModel.uiEffects` getter 委托 controller），T5 删 ViewModel 时统一切换。语义不变：无 replay、只服务当前挂载的活动 AgentPane。

**D3 · live turn 旁路归 runtime controller**（2026-09-03 终审修正时点表述）。`publish` 里的 ①③（`syncLiveTurnBinding` / `markDirty` + `flushNow`）是 TimelineStore 操作，由持有 timeline 的 controller 在 **scheduler 的发布回调里**应用（即 T2 骨架 `_applyUiUpdate` 开头）——与现状同为 publish 时点。**不要**提前到「交给 scheduler 之前」：那会让 liveTurn 的 flushNow 按 request 粒度执行，破坏帧合并。Widget 侧 `ListenableBuilder(viewModel.liveTurnListenable)` 不变——`liveTurnListenable` 改由 controller 暴露（core `AgentValueNotifier`），presentation 仍经 `AgentFlutterValueListenableAdapter` 投影。

**D4 · region 投影的归属**。现在 `buildHeaderState` 等 5 个闭包由 ViewModel 传给 `UiStateStore` 工厂。它们是「timeline + session state + 各 controller → region state」的纯投影，随 runtime 一起搬进 controller，成为 5 个包内私有方法（或独立纯函数文件 `agent_conversation_region_projection.dart`，便于单测）。SliceStore 收到 `RegionsRefreshed` 时直接调它们取新值。

**D5 · 命令面先稳后搬**。`AgentConversationCommandPort` 21 个方法签名冻结。ViewModel 逐块委托给 controller；widgets 从「拿 ViewModel」切到「ref.read 命令 provider」放最后一个 PR。

**D6 · 无构造环的装配顺序**（2026-09-03 review 修正，取代原「工厂注入」方案）。依赖看似成环（controller 要 scheduler、scheduler 的 onPublish 要 store、store 的投影要 controller），用**订阅模式**拆开，无需任何工厂/thunk：

1. 先建 controller：构造体内用**自身方法 tear-off** 创建 scheduler（`_scheduler = AgentUiUpdateScheduler(_applyUiUpdate, ...)`）——与 ViewModel 今日 `:117-122` 的写法完全相同，Dart 允许构造期 tear-off 实例方法。
2. 再建 SliceStore：`regions: controller, commands: controller`（与今日 `AgentConversationSliceComposition(regions: viewModel, commands: viewModel)` 同构），构造体内调 `controller.addUiUpdateListener(_onUiUpdate)` 订阅批处理输出。
3. `AgentConversationRegionSource` 接口同步瘦身：删去 5 个 region 各自的 `addRegionListener/removeRegionListener`（原订阅粒度），改为单一的 `addUiUpdateListener(void Function(AgentUiUpdateRequest))` / `removeUiUpdateListener`；5 个投影 getter 与 `currentCommandScope` 保留。`AgentConversationSliceRegion` 枚举随之删除。

## 3. 任务拆分

### T0 · 前置：WP-7 T3 合入（0.5 人天）

- [x] 见 `07-wp7-hygiene.md` T3。把 scheduler 的 `AgentMetricLabels.forProviderId` 改为注入。这是 D1 的解锁条件。

### T1 · 现状测绘（0.5 人天）

- [x] 跑以下命令，把结果整理成「region 字段 × 生产者 × 消费者」矩阵贴进 PR-1 描述：

```sh
grep -rn "AgentConversationViewModel" lib test --include=*.dart | wc -l
grep -rn "uiEffects\|liveTurnListenable\|threadSnapshotListenable\|contextPanelVisible" lib/src --include=*.dart
grep -rn "_buildHeaderState\|_buildComposerState\|_buildPendingInteractionState\|_buildExpansionState\|_buildHistoryState" lib/src/features/agent/presentation/agent_conversation_view_model.dart
```

- [x] 5 个 region state 的字段清单已在 `agent_conversation_region_state.dart`（代码现状：`AgentHeaderState` 17 / `AgentComposerState` 22 / `AgentPendingInteractionState` **7 存储字段** / `AgentExpansionState` 5 / `AgentConversationHistoryState` **5 存储字段**；初版「8 / 6」含派生 getter）。逐个标注投影数据源见 [附录 A](#附录-a--t1-测绘结果-2026-09-03)。
- [x] **Widget 只读面清单**：生产 `viewModel.` 84 个成员、测试独占 48 个；按「controller 查询 / region 字段 / composerStateOwner / CommandPort / Shell 编排」分类，见附录 A §2–§3。
- [x] **验收**：矩阵覆盖 5 个 region 全部存储字段；生产侧 ViewModel 引用点（命令面 + 只读面）无遗漏。

### T2 · runtime controller 下沉（PR-1，3–4 人天）

- [x] 把 ViewModel `:74-152`（core 三件套装配，**删去其中 UiStateStore 创建**）、`:4189-4199`（`_publishScheduledUiChanges` 全部四件事：threadSnapshot 同步、live 旁路、region 发布、管线指标）、5 个 `_buildXxxState`、`_openBoundThread`（`:2222` 起）、`switchActiveProvider`（`:902`）、provider 事件订阅全部平移进 controller。
- [x] scheduler 搬到 application（D1）；`AgentConversationUiStateStore` 删除。其诊断（`publishCount` / `debugLastAcceptedRequest`）的断言迁移到 scheduler 诊断或 SliceStore 诊断（`dispatchCount`/`publishCount` 已存在）——逐条核对引用测试，不允许静默删除。
- [x] ViewModel 对应成员改为 `final AgentConversationRuntimeController _runtime;` + 同名 getter 委托（`AgentConversationRegionSource` 的 5 个 getter 改调 `_runtime`）。
- [x] SliceComposition 删除；SliceStore 新增 `_onUiUpdate(AgentUiUpdateRequest request)`：按 `request.regions` 包含的 region 逐个调 `_regions.<region>State` 取新值，组装成**一次** `AgentConversationRegionsRefreshed` dispatch（字段缺省 = 未变化）。**注意这里有一次 intent 形状变更**：现状 `AgentConversationRegionsRefreshed` 的 5 个字段全非空（composition._flush 每次都全量取 5 个投影），目标态改为可空（null = 该 region 未变化，reducer 保留旧值）——reducer 与既有切片测试随迁。装配处在 `agent_conversation_workspace_store.dart:565-616` 段按 D6 顺序建 controller → store（`regions: controller, commands: controller`，构造体内 `controller.addUiUpdateListener(_onUiUpdate)`）。
- [x] `AgentConversationSliceComposition` 里的 `_AgentConversationCommandEffectRunner`（`:183-333`，含两次 scope 校验）**整体平移**进 SliceStore 所在层（它本来就是 application 逻辑，只是物理放在 app 层文件）。

**新文件** `application/conversation_slice/agent_conversation_runtime_controller.dart` 骨架：

```dart
/// 会话 runtime 编排：持有 core 事件管线三件套，暴露 region 投影与 live 旁路。
/// 纯 Dart + core/foundation；不 import Flutter / Riverpod / zeta_agent_providers。
final class AgentConversationRuntimeController
    implements AgentConversationRegionSource, AgentConversationCommandPort {
  AgentConversationRuntimeController({
    required AgentProviderSettingsPort providerController,
    required AgentConversationBinding conversationBinding,
    required AgentProviderGlobalRuntime globalRuntime,
    required AgentConversationComposerStateOwner composerStateOwner,
    AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
    AgentFrameScheduler? uiFrameScheduler,
    ZetaMetricLabel Function(String providerId) providerMetricLabel =
        ZetaMetricLabel.hashed,
    // ... 其余参数从 ViewModel 构造函数平移（metrics / turnContextStore / 各回调）
  }) : /* 平移 ViewModel :74-152 的装配（删去其中 UiStateStore 的创建） */ {
    // D6：构造体内 tear-off 自身方法建 scheduler，与 ViewModel 今日 :117-122 同写法。
    _scheduler = AgentUiUpdateScheduler(
      _applyUiUpdate,
      frameScheduler: uiFrameScheduler,
      metrics: metrics,
      providerId: conversationBinding.providerId,
      providerMetricLabel: providerMetricLabel,   // WP-7 T3 注入
    );
  }

  late final AgentConversationTimelineStore _timeline;
  late final AgentConversationEventProcessor _eventProcessor;
  late final AgentConversationEffectRunner _effectRunner;
  late final AgentUiUpdateScheduler _scheduler;
  late final ValueNotifier<AgentConversationThreadSnapshot> _threadSnapshotListenable;
  late final AgentPipelineMetricsReporter _pipelineMetrics;

  /// D2：一次性 effect 流（与现状 UiStateStore 内 broadcast(sync: true) 同构）。
  final StreamController<AgentUiEffect> _effectController =
      StreamController<AgentUiEffect>.broadcast(sync: true);
  bool _threadSnapshotRefreshPending = false;

  /// 批处理输出的订阅者（SliceStore 在装配时注册；通常只有一个）。
  final List<void Function(AgentUiUpdateRequest)> _uiUpdateListeners = [];

  /// scheduler 的 onPublish：先应用 live 旁路与快照，再广播给订阅者。
  /// 平移 ViewModel._publishScheduledUiChanges（:4189-4199）的全部四件事——
  /// review 修正：初版骨架漏了 threadSnapshot 同步与管线指标上报。
  void _applyUiUpdate(AgentUiUpdateRequest request) {
    if (_threadSnapshotRefreshPending) {
      _threadSnapshotRefreshPending = false;
      _syncThreadSnapshotListenable();
    }
    if (request.regions.contains(AgentUiRegion.liveTurnBinding)) {
      _timeline.syncLiveTurnBinding();                    // D3
    }
    if (request.regions.contains(AgentUiRegion.liveTurn)) {
      _timeline.liveTurnState?.markDirty();
      _timeline.liveTurnState?.flushNow();
    }
    for (final listener in List.of(_uiUpdateListeners)) {
      listener(request);                                  // → SliceStore._onUiUpdate
    }
    for (final effect in request.effects) {
      _effectController.add(effect);                      // D2
    }
    _pipelineMetrics.report(_eventPipeline?.diagnostics); // 帧边界采样，语义不变
  }

  // D4：5 个 region 投影（从 ViewModel 的 _buildXxxState 平移，作为 RegionSource 实现）
  @override
  AgentHeaderState get headerState => /* 平移 */;
  // ... composerState / pendingInteractionState / expansionState / historyState ...

  /// live 旁路暴露（Widget 订阅面不变）。
  AgentValueNotifier<AgentConversationTurnState?> get liveTurnListenable =>
      _timeline.liveTurnListenable;

  /// D2：一次性 effect 流（controller 内自持 broadcast sync controller）。
  Stream<AgentUiEffect> get uiEffects => _effectController.stream;
}
```

**步骤**：

1. 把 ViewModel `:74-152`（core 三件套装配，**删去其中 UiStateStore 创建**）、`:4189-4199`（`_publishScheduledUiChanges` 全部四件事：threadSnapshot 同步、live 旁路、region 发布、管线指标）、5 个 `_buildXxxState`、`_openBoundThread`（`:2222` 起）、`switchActiveProvider`（`:902`）、provider 事件订阅全部平移进 controller。
2. scheduler 搬到 application（D1）；`AgentConversationUiStateStore` 删除。其诊断（`publishCount` / `debugLastAcceptedRequest`）的断言迁移到 scheduler 诊断或 SliceStore 诊断（`dispatchCount`/`publishCount` 已存在）——逐条核对引用测试，不允许静默删除。
3. ViewModel 对应成员改为 `final AgentConversationRuntimeController _runtime;` + 同名 getter 委托（`AgentConversationRegionSource` 的 5 个 getter 改调 `_runtime`）。
4. SliceComposition 删除；SliceStore 新增 `_onUiUpdate(AgentUiUpdateRequest request)`：按 `request.regions` 包含的 region 逐个调 `_regions.<region>State` 取新值，组装成**一次** `AgentConversationRegionsRefreshed` dispatch（字段缺省 = 未变化）。**注意这里有一次 intent 形状变更**：现状 `AgentConversationRegionsRefreshed` 的 5 个字段全非空（composition._flush 每次都全量取 5 个投影），目标态改为可空（null = 该 region 未变化，reducer 保留旧值）——reducer 与既有切片测试随迁。装配处在 `agent_conversation_workspace_store.dart:565-616` 段按 D6 顺序建 controller → store（`regions: controller, commands: controller`，构造体内 `controller.addUiUpdateListener(_onUiUpdate)`）。
5. `AgentConversationSliceComposition` 里的 `_AgentConversationCommandEffectRunner`（`:183-333`，含两次 scope 校验）**整体平移**进 SliceStore 所在层（它本来就是 application 逻辑，只是物理放在 app 层文件）。

**验收**：Widget 树零改动；`grep -n "AgentConversationUiStateStore\|AgentConversationSliceComposition" lib test` 零命中；`feature_layering_guard_test` 绿。

**测试**：`agent_conversation_widget_test.dart` 全量（38 用例是回归网）；切片 wiring 两个测试文件适配装配变化；scheduler 测试随迁（改 import 即可，行为不变）。

**落地偏差**：

- `frameScheduler` 在 application scheduler 上改为必填，生产由 ViewModel 注入 `SchedulerBindingAgentFrameScheduler`。
- presentation **不得** `export` application scheduler / RuntimeController（`deleted_transition_api_guard_test` 禁止 `lib/src` 过渡 re-export）。
- reasoning AND-gate 的源码守卫改钉 `agent_conversation_runtime_controller.dart`。
- 删除 SliceComposition 后，两次 `immediate` toggle 不再被 microtask 合并成一次 dispatch。

### T3 · 纯函数下沉（PR-2，1 人天）

- [x] 把 `_latestHistorySelectionPatch` / `_mergeThreadSelectionPatches` / `_selectionPatchFromHistoryTurn` 下沉为顶层纯函数。
- [x] 把 skill 候选过滤下沉为 `filterAgentSkillCandidates`。
- [x] 把 `_flattenFileNodes` 下沉为 `flattenWorkspaceFileNodes`。
- [x] 表驱动单测（每函数 ≥3 组：空输入、典型、边界）；RuntimeController 改委托。

**平移清单与落点**：

| 现状（T2 后在 RuntimeController） | 落点 | 目标签名 |
|---|---|---|
| `_latestHistorySelectionPatch` / `_mergeThreadSelectionPatches` / `_selectionPatchFromHistoryTurn` | `application/conversation_slice/agent_thread_selection_patch.dart` | `AgentThreadSelectionPatch? mergeAgentThreadSelectionPatches(...)` 纯函数 |
| `skillCandidates` 的能力门控 + catalog 过滤 | `application/agent_skill_candidates.dart` | `List<AgentSkillMetadata> filterAgentSkillCandidates(...)` |
| `_flattenFileNodes` | `workspace/domain/workspace_file_query.dart` | `List<WorkspaceNode> flattenWorkspaceFileNodes(...)` |

**步骤**：逐函数平移 → 改静态/顶层纯函数 → 表驱动单测（每函数 ≥3 组用例：空输入、典型、边界）→ RuntimeController 删原方法改委托。

**验收**：三个函数各有独立单测；`test_affected.sh` 绿。

**落地偏差**：

- T2 后这些方法已不在 ViewModel，源在 RuntimeController；ViewModel 继续薄委托。
- 过滤函数返回 `AgentSkillMetadata`（picker 真实类型），不是计划草稿里的 `AgentSkillRef`。
- flatten 是通用树行走，落在 workspace domain，与既有 `fuzzyRankWorkspaceFiles` 同文件。
- RuntimeController 只减约百行，不到原估 350（T2 已先搬走装配代码）。

### T4 · 附件 port：dart:io 移出 presentation（PR-2，1 人天）

- [x] application 端口 `AgentComposerAttachmentPort` + fail-closed provider。
- [x] data `AgentComposerAttachmentStore`（可注入 tempDir / Clock）；只 discard 自己写出的路径。
- [x] 生产 override 在 `lib/main.dart`；`zetaTestComposition` / harness 装内存 fake。
- [x] `AgentPane` 去掉 `dart:io`；粘贴走端口；嗅探走顶层纯函数。
- [x] 单测覆盖暂存/嗅探/清理；粘贴 → 发送 widget 测试。

**现状**：`agent_pane.dart:903-924` `_persistClipboardImage` 用 `Directory.systemTemp` + `File.writeAsBytes` 直写临时文件；`_looksLikeImagePath` 做扩展名嗅探。

**设计**：

```dart
// application 层：agent_composer_attachment_port.dart
/// Composer 图片附件的暂存端口。实现放 data 层（含 dart:io）；
/// 路径属敏感信息（G7）：不落盘、不进日志与指标。
abstract interface class AgentComposerAttachmentPort {
  /// 把剪贴板图片字节暂存为临时文件，返回可供 Provider 消费的本地路径。
  Future<String> stageClipboardImage(Uint8List bytes, {required String extension});
  /// 路径是否指向可支持的图片（扩展名嗅探）。
  bool looksLikeImagePath(String path);
  /// 清理本会话不再引用的暂存文件。
  Future<void> discard(List<String> paths);
}
```

```dart
// data 层：agent_composer_attachment_store.dart
final class AgentComposerAttachmentStore implements AgentComposerAttachmentPort {
  AgentComposerAttachmentStore({required Directory Function() tempDirProvider}); // 测试注入内存 FS 语义
  @override
  Future<String> stageClipboardImage(Uint8List bytes, {required String extension}) {
    // 平移 _persistClipboardImage 现状逻辑：文件名 = 时间戳+随机后缀，写 tempDir
  }
  // ...
}
```

**接线**：组合根（`ZetaAppComposition.create` 链路的 overrides）装生产实现；`zetaTestComposition` 装内存 fake；`AgentPane` State 里 `_persistClipboardImage` 改为 `ref.read(agentComposerAttachmentPortProvider)`。

**验收**：`grep -n "dart:io" lib/src/features/agent/presentation` 零命中（或仅剩注释说明的特例）；粘贴图片 → 发送的 widget 测试绿；fake 单测覆盖暂存/嗅探/清理。

**落地偏差**：

- 扩展名嗅探是顶层纯函数 `looksLikeAgentComposerImagePath`：`Pasteboard.files` 过滤不必读 fail-closed provider。
- `discard` 只删本端口 `stageClipboardImage` 写出的路径，文件选择器 / 剪贴板文件路径不得误删。
- 生产 override 装在 `lib/main.dart`（与 `systemDirectoryPickerOverride` 同模式），不进 `ZetaAppComposition.create`，否则测试无法覆盖。
- 文件名仍是 `paste-<microseconds>.<ext>`，无随机后缀（与搬迁前一致）。
- `AgentPane` 改为 `ConsumerStatefulWidget`，只在暂存/清理时懒读端口。
- 发送后从 Composer 跟踪集移除路径，不立即删文件——路径已交给 turn。
- RuntimeController 仍 import `dart:io`（`ProcessException`），留给 T5/T6。

### T5 · ViewModel 删除与命令面切换（PR-3，2 人天）

**步骤**：

1. 新增 `agentConversationCommandProvider`（family by `AgentConversationBindingKey`，返回 `AgentConversationCommandPort`）。**终审修正：不要发明第二个 registry provider**——现状已有 `agentConversationSliceStoreRegistryProvider`（fail-closed 声明在 `agent_conversation_slice_providers.dart:22`，装配在 `zeta_app_composition.dart:105,306`，`ide_home.dart:104` 消费）。复用它：把 `AgentConversationSliceStoreRegistry` 的注册值从单 `AgentConversationSliceStore` 扩为句柄（如 `({AgentConversationSliceStore store, AgentConversationRuntimeController controller})` record，或 controller 自持 store 引用），命令面解析到 controller（**它是 CommandPort 的实现**——注意现状 `AgentConversationSliceStore` 并不 implements `AgentConversationCommandPort`，命令编排方法是自有签名，T2 平移时由 controller 实现端口并委托 store）：

```dart
final agentConversationCommandProvider = Provider.family
    <AgentConversationCommandPort, AgentConversationBindingKey>((ref, key) {
  return ref.watch(agentConversationSliceStoreRegistryProvider).resolve(key).controller;
}, name: 'agentConversationCommand');
```

2. widgets 逐个从 `viewModel.xxx(...)` 改为 `ref.read(agentConversationCommandProvider(key)).xxx(...)`；`AgentRegionBuilder` 的 `viewModel` 参数改为直接收 `AgentConversationBindingKey`（它本来就只用 `viewModel.conversationBinding.key`，见 `agent_region_builder.dart:28`）。
3. 删除 `agent_conversation_view_model.dart`；`AgentConversationRegionSource` 按 D6 瘦身后的形态若只剩 controller 一个实现，则删除接口、controller 直接暴露（`AgentConversationSliceRegion` 枚举应已在 T2 随 listener 粒度切换删除）。
4. `agent_pane_test_harness.dart`（753 行）适配；`agent_conversation_view_model_test.dart`（5114 行 / 107 用例）逐条核对归属迁入 controller / projection / store 测试，**不允许静默删除用例**。

**验收**：`grep -rn "AgentConversationViewModel" lib test` 零命中。

**落地偏差**：

- Registry 解析 `AgentConversationSessionHandle { store, controller? }`；`controller` 在只测切片镜像的容器里可空。
- 同时新增 `agentConversationCommandProvider` 与 `agentConversationRuntimeProvider`（后者 fail-closed）。未进 CommandPort 的命令仍走 RuntimeController，本 PR 不扩端口。
- 非 ConsumerWidget 的 pane part 仍直接调 `controller.xxx`（WP-2 再拆）；`AgentPane._sendMessage` 已改 `ref.read(agentConversationCommandProvider(key))`。
- 上下文面板显隐留在 `AgentPane` State 的 `ValueNotifier`，不进 RuntimeController。
- Flutter listenable 由 presentation 扩展 `AgentConversationFlutterListenables` 投影。
- Workspace 构造 RuntimeController 时默认 `SchedulerBindingAgentFrameScheduler`（app 层可 import presentation scheduler）。
- 原 ViewModel region ValueNotifier 的 `!=` 门闩，测试改为 `addUiUpdateListener` + 同条件计数，用例未删。
- RuntimeController 仍 import `dart:io`（`ProcessException`），留给后续卫生项；T6 DoD 只要求 presentation 层为零。

### T6 · 全量门禁与文档同步（PR-4，1–2 人天）

- [x] `bash tool/test_full.sh` 全绿。
- [x] §6 文档同步：`docs/architecture/overview.md`(+en) 状态发布链路图、`engineering_standards.md` §3.0、`developer_guide.md` 切片接入说明、`glossary.md`（region/slice 术语如变化）。
- [x] 登记 `00-index.md` §6「开发记录」。

**落地偏差**：

- 同步范围按 AGENTS.md §6 扩到 `design_document.md`、`CONTRIBUTING.md`(+en)、`desktop_agent_notification_design.md`。
- RuntimeController 的 `dart:io` / `ProcessException` 未在本任务切除（application 允许；presentation 已为零）。
- CHANGELOG 无条目（纯内部重构）。

## 4. 风险与回滚

| 风险 | 缓解 |
|------|------|
| 「同帧一次 dispatch」语义破坏导致流式渲染抖动 | scheduler 帧合并本在 request 粒度工作；widget 测试的流式/滚动用例是回归网；PR-1 独立合入可整体 revert |
| 命令 effect 的两次 scope 校验在平移中丢失 | `_AgentConversationCommandEffectRunner` 整体平移不改逻辑；对应单测随迁 |
| 测试迁移漏覆盖 | 107 + 38 用例逐条核对；删除任何用例需在 PR 描述说明归属 |
| 与 WP-2 并行冲突 | 按 DR-003 顺序执行 |

## 5. 完成定义（DoD）

- [x] 链路两跳；`AgentConversationUiStateStore` / `AgentConversationSliceComposition` / `AgentConversationViewModel` 零命中。
- [x] presentation 层 agent feature 无 `dart:io`、无 `zeta_agent_providers` import。
- [x] `flutter analyze` 零告警；`tool/test_full.sh` 绿；架构守卫绿。
- [x] 文档同步完成；CHANGELOG 无条目（纯内部重构）。

---

## 附录 A · T1 测绘结果（2026-09-03）

扫描基准：`feature/wp7-t3-scheduler-metric-label` 工作树（T0 已合入本分支、尚未提交）。行号以符号名为准。

### A.0 扫描规模

| 命令 / 口径 | 结果 |
|---|---|
| `AgentConversationViewModel` 匹配行（`lib`+`test`，含 `.dart`） | **70 行 / 24 文件**（生产 12 + 测试 12） |
| 生产 `viewModel.<member>` 不同成员 | **84**（`lib/`，不含 ViewModel 自身） |
| 测试独占成员（生产未调用） | **48**（已剔除 ProjectThreads 的 `applyProjectState` 误伤） |
| `_buildHeaderState` | `:4084` |
| `_buildComposerState` | `:4107` |
| `_buildPendingInteractionState` | `:4136` |
| `_buildExpansionState` | `:4148` |
| `_buildHistoryState` | `:4158` |

只读面 hint 的四处订阅点（均仍存在）：

| 符号 | 生产订阅 |
|---|---|
| `uiEffects` | `agent_pane.dart:259,295` |
| `liveTurnListenable` | `agent_pane.dart:401`；`agent_pane_sections.dart:339`；`agent_pane_plan_panel.dart:36`；`agent_pane_context_panel.dart:74` |
| `threadSnapshotListenable` | workspace store `:86`；`agent_pane_context_panel.dart:88` |
| `contextPanelVisible` | `agent_pane.dart:355` |

Selector 未改签名：`agentConversationHeader/Composer/PendingInteraction/Expansion/HistoryProvider`（`agent_conversation_slice_providers.dart:91-140`）。Widget 经 `AgentRegionBuilder` 订阅；`IdeHome:283-305` 另从 `entry.sliceStore.state` 读 header/history/pending 做 Shell 快照。

### A.1 Region 字段矩阵

数据源缩写：**TL** = `AgentConversationTimelineStore`；**SS** = `AgentConversationSessionState`（`_state`）；**Cap** = `activeCapabilities`（runtime / global / settings 端口）；**Mode** = `_conversationModeController`；**Model** = `_modelSelectionController`；**Perm** = `_permissionSelectionController`；**PlanH** = `_planExecutionHandoffController`；**Text** = `_textCatalog`；**Bind** = `conversationBinding`；**Settings** = `providerController`。

#### AgentHeaderState（17）· `_buildHeaderState` `:4084`

| 字段 | 投影源 | 生产消费者 |
|---|---|---|
| `title` | SS `_currentThreadTitle` | `agent_pane_header.dart` 标题 / 重命名初值 |
| `threadOpenPhase` | SS | header 状态文案；`_threadOpenStatusText`；`IdeHome` 快照 |
| `systemNoticeLabel` | SS `_modelRerouteNotice` | header 次要提示（idle 时） |
| `statusCapsuleLabel` | SS waiting/runtime + Text | header 胶囊；live activity 条等待文案 |
| `waitingOnApproval` | SS | header / live activity 图标 |
| `waitingOnUserInput` | SS | 同上 |
| `showRunningIndicator` | TL `isTurnRunning` ∧ 无胶囊 | **生产 Widget 未读该 bool**；live 条用 `isTurnRunning` + 胶囊代替。测试读 ViewModel getter |
| `runningActivityLabel` | TL `currentActivity` + Text | `_liveActivityStatusText` |
| `segmentStartedAt` | TL activity | `_liveActivityStatusText` 段耗时 |
| `turnStartedAt` | TL `currentTurnStartedAt` | `_liveActivityStatusText` 回合耗时 |
| `tokenUsage` | TL `currentThreadTokenUsage` | header 累计 Token 标签 / tooltip |
| `isTurnRunning` | TL | live activity 显隐；`IdeHome` 快照 |
| `isReadOnly` | Settings 是否启用当前 provider | `IdeHome` 快照（header 菜单不读此字段） |
| `canFork` | Cap + `canSubmitMessage` + `onCreatedThread` | header 更多菜单 |
| `canRename` | Cap + `sessionId` + `!isReadOnly` | header 更多菜单 |
| `canArchive` | Cap + `sessionId` + `!isReadOnly` | header 更多菜单 |
| `isPlanMode` | Mode `confirmedMode.kind == plan` | header Plan 徽章 |

#### AgentComposerState（22）· `_buildComposerState` `:4107`

| 字段 | 投影源 | 生产消费者 |
|---|---|---|
| `canSubmitMessage` | SS phase + Settings 只读 + Cap `canPrompt`/`canSteerTurn` + TL running | `_AgentComposerBar`；`agent_pane` 发送门闩仍直读 ViewModel |
| `isTurnRunning` | TL | Composer 取消按钮 / applies-next-turn |
| `threadOpenPhase` | SS | Composer 加载/失败态 |
| `contextUsage` | TL last usage ⊕ Model `contextWindowTokens` | Composer 窗口占用 |
| `isReadOnly` | Settings | `agent_pane.dart` 只读占位 vs Composer |
| `canAttachImages` | Cap `supportsLocalImageInput` | Composer 附件入口；**pane 仍直读 ViewModel 做粘贴门闩** |
| `canMentionResources` | Cap `supportsResourceInput` | Composer；**pane 仍直读做 @ picker** |
| `canUseSkills` | Cap `supportsSkillInput` | Composer；**pane 仍直读做 /skills** |
| `conversationModeStatus` | Mode | 模式选择器状态 |
| `conversationModeOptions` | Mode presets | 模式选择器；**pane 斜线菜单仍直读 ViewModel** |
| `selectedConversationMode` | Mode draft | 选择器；**pane `/plan` 仍直读** |
| `conversationModeAppliesToNextTurn` | Mode | 选择器「下回合生效」 |
| `conversationModeStatusMessage` | Mode + Text | **生产 Widget 未读**（只进相等性） |
| `conversationModeContextId` | Bind provider/thread | 选择器隔离 key |
| `showModelSelection` | Cap `supportsModelSelection` | Composer / cards 模型入口 |
| `modelConfigState` | Model + Cap + VM `_modelsRefreshing` | 模型 popover |
| `showPermissionPolicy` | Perm.hasPort ∨ bundle.permissionPolicy | Composer 权限选择器 |
| `permissionPolicyLabel` | Perm | 选择器标签 |
| `permissionOptions` | Perm | Composer；**plan 卡经 `viewModel.composerState.permissionOptions` 旁路** |
| `selectedPermissionOptionId` | Perm | 选择器 |
| `permissionApplyScopeHint` | Perm | Composer toast 前仍经 `takePermissionApplyHint()` |
| `sessionConfigOptions` | SS 过滤后的动态配置 | Composer |

#### AgentPendingInteractionState（7 存储 + 派生）· `_buildPendingInteractionState` `:4136`

| 字段 | 投影源 | 生产消费者 |
|---|---|---|
| `permissions` | TL | `agent_pane_sections` 权限卡 |
| `questions` | TL | 提问卡 |
| `planApprovals` | TL | 计划审批卡 / 时间线插入 |
| `planExecutionHandoff` | PlanH | 执行交接卡 |
| `isReadOnly` | Settings | 待处理区整体禁用 |
| `autoReviewsByTurnId` | SS | 经 `state.autoReviewForTurn(turnId)` |
| `latestDeniedAutoReview` | SS | Guardian 放行按钮显隐 |
| `blocksComposer`（派生） | 上列非空 | `agent_pane` 隐藏主 Composer |
| `hasBlockingPlanDocument`（派生） | plan 审批/交接 | 隐藏 live 活动条 |

#### AgentExpansionState（5）· `_buildExpansionState` `:4148`

| 字段 | 投影源 | 生产消费者 |
|---|---|---|
| `toolCallIds` | TL | cards `isToolCallExpanded` |
| `planMessageIds` | TL | messages `isPlanMessageExpanded` |
| `activePlanTurnIds` | TL | plan_panel `isActivePlanExpanded` |
| `commandGroupIds` | TL | cards / extent descriptor |
| `fileEditItemIds` | TL | cards / extent descriptor |

#### AgentConversationHistoryState（5 存储 + 派生）· `_buildHistoryState` `:4158`

| 字段 | 投影源 | 生产消费者 |
|---|---|---|
| `standbyTurn` | TL standby snapshot（空 entries 则 null） | `agent_pane_sections` overlay |
| `visibleTurns` | TL | 历史虚拟列表；`agent_pane` 空态；`IdeHome` `visibleTurnCount` |
| `threadOpenPhase` | SS | 经 `isLoading` |
| `providerId` | SS/session/`_selectedProviderId`/Bind | 空态 provider 图标 |
| `providerName` | Settings displayName | 空态文案 |
| `isLoading`（派生） | `threadOpenPhase == loadingHistory` | `agent_pane` 历史骨架 |

### A.2 生产 `viewModel.` 去向（84）

T5 只切 CommandPort；下列只读/额外命令必须在 T2 就有归属，否则 T5 删 ViewModel 时会断。

#### controller 查询 / 旁路订阅（T2 随 runtime controller 暴露）

| 成员 | 调用方 | T5 去向 |
|---|---|---|
| `liveTurnListenable` | pane / sections / plan_panel / context_panel | controller → Flutter adapter（D3，订阅方式不变） |
| `liveTurnState` | pane / sections / plan_panel | 同上 |
| `threadSnapshot` / `threadSnapshotListenable` | workspace store；context_panel | controller 自持 `ValueNotifier`（application 用 core notifier，presentation 再适配） |
| `uiEffects` | `agent_pane` | controller `_effectController`（D2） |
| `contextPanelVisible` / `toggleContextPanel` / `hideContextPanel` | pane / header / context_panel | **不进 region**。建议留 presentation `ValueNotifier`，或 controller 窄端口 |
| `elapsedClockListenable` / `elapsedNow` / `toolElapsedAt` | cards / messages / styles | controller 持有 `AgentElapsedTicker` |
| `mentionCandidateFiles` / `isWorkspaceFileIndexReady` / `workspaceFileCorpus` | pane @mention | T3 纯函数 + `WorkspaceFileCorpusPort`；查询挂 controller |
| `shouldShowActivePlan` | plan_panel | controller 查询（组合 TL + pending + SS waiting） |
| `expansionState` | plan_panel 展开判定 | 可改为 `AgentRegionBuilder<AgentExpansionState>`，与 cards 对齐 |
| `composerState` | cards 模型卡；messages 交接权限选项 | **旁路 region**。T5 前改为 selector / 把 permissionOptions 传入交接卡 |
| `conversationBinding` | `AgentRegionBuilder` 只取 `.key` | T5 改为直接收 `BindingKey` |
| `textCatalog` | pane / context_panel | 注入到 presentation 或经 region/context |
| `projectName` / `projectPath` | header | **未进 HeaderState**。T2 可并入 header 投影，或 controller 查询 |
| `currentThreadTitle` / `sessionId` / `currentThreadTokenUsage` / `threadCreatedAt` / `threadLastActiveAt` / `messages` / `timelineEntries` / `activeProviderName` | context_panel | 面板只读面：controller 查询（或专有 context-panel 投影，本 WP 非目标） |
| `providerController` | context_panel **subscribe 触发 setState** | 越层。T5 前改为 settings 端口订阅或把目录快照打进投影 |
| `initialization` / `threadOpenPhase` / `currentSession` / `retryOpenThread` | Shell | controller / CommandPort（`retryOpenThread` 已在端口） |
| `activeProviderId` | Shell | Bind.key.providerId，可不经 ViewModel |
| `permissionSnapshotForThread` | Shell fork 工作流 | controller 查询（Perm） |
| `dispose` | workspace store | controller.dispose |

#### 与 Composer region 重复、pane 仍直读 ViewModel 的能力位

`canSubmitMessage` / `canAttachImages` / `canMentionResources` / `canUseSkills` / `canSelectConversationMode` / `canCompactCurrentThread` / `conversationModeOptions` / `selectedConversationMode` / `canEditLastUserMessage` / `lastEditableUserMessageId`

T5：pane 门闩改为读 `agentConversationComposerProvider`（或局部已有的 `composerState`），避免双源。

#### composerStateOwner 命令（**不在 CommandPort**，T5 必须扩端口或另开 command family）

| 成员 | 调用方 |
|---|---|
| `selectConversationMode` | pane `/plan`；Composer 选择器 |
| `selectModel` / `selectReasoningEffort` / `selectFastEnabled` / `resolveModelCompatibilityConflict` / `retryModelConfigurationSave` / `clearModelConfigurationTransientState` | Composer / cards |
| `selectPermissionOption` / `takePermissionApplyHint` | Composer |
| `selectSessionConfigOption` | Composer |
| `selectPlanExecutionPermissionOption` | messages 交接卡 |
| `skillCandidates` / `ensureSkillsCatalog` | pane 斜线菜单（后者已在 CommandPort） |

#### 已在 `AgentConversationCommandPort`（23 个，文档旧称 21）

生产 Widget/Shell 已调用：`sendMessage` `cancelActiveTurn` `editLastUserMessageAndRetry` `retryOpenThread` `respondToPermission` `respondToQuestion` `respondToPlanApproval` `revisePlanExecution` `startPlanExecution` `dismissPlanExecution` `approveGuardianDeniedAction` `forkCurrentThread` `renameCurrentThread` `archiveCurrentThread` `compactCurrentThread` `loadModels` `ensureSkillsCatalog` `toggleToolCall` `togglePlanMessage` `toggleActivePlan` `toggleCommandGroup` `toggleFileEditItem`。

`retryConversationModes`：端口有，**无生产 `viewModel.` 调用**；走 slice composition effect runner。

#### Shell 编排（非 AgentPane；T5 切 command provider / controller）

`loadSettings` `updateContext` `switchActiveProvider` `syncThreadTitleIfCurrent` `loadModels` `sendMessage` `retryOpenThread` `initialization`。

`loadSettings` **不在 CommandPort**。

### A.3 测试独占成员（49）· 不允许 T5 静默删除

多数是投影源的直读（`isTurnRunning` `permissionRequests` `visibleHistoryTurns` `headerState` `historyState` …）或 `@visibleForTesting` 诊断（`eventCoalescingBufferDiagnostics` `uiStateDiagnostics` `uiUpdateSchedulerDiagnostics` `debugLastUiUpdateRequest`）。迁入 controller / scheduler / store 测试时按符号搬家，不断言删除。

扫描时 `project_threads_slice_runner_test` 的 `viewModel.applyProjectState` 是 **ProjectThreads** 测试 double，与 `AgentConversationViewModel` 无关，T5 可忽略。

### A.4 T2 必带缺口（本测绘新发现）

1. **CommandPort 覆盖不足**：模型/模式/权限/session config/交接权限选择、`loadSettings`、`updateContext`、`switchActiveProvider`、上下文面板开关均不在 23 个端口方法里。T5「widgets 改 `ref.read(commandProvider)`」之前必须扩端口或拆第二端口，否则这些调用无处可去。
2. **双源直读**：pane 对 `canSubmitMessage` / 附件 / mention / skills / 模式 同时走 ViewModel 与 Composer region。T2 委托期可暂留；T5 必须收口到 region。
3. **未进 region 的头栏字段**：`projectName` / `projectPath` 仍直读 ViewModel。
4. **死投影字段**：`AgentHeaderState.showRunningIndicator`、`AgentComposerState.conversationModeStatusMessage` 无生产读取；T2 平移投影时保留（相等性/测试），不要当无主删除。
5. **context_panel 订阅 `providerController`**：presentation 直接听 settings 端口。T5 前要有替代订阅，否则删 ViewModel 后面板目录不刷新。

> 2026-09-06 后继：Management 已按 [lib cohesion WP-3M](../2026-09-05-lib-cohesion/03-wp3-state-ownership.md) 迁移 application Notifier；Conversation 的后继由 WP-3C 承接。此记录不修改本文件的历史目标和验收证据。

> 2026-09-06 后继：Project Threads 已按 [lib cohesion WP-3P](../2026-09-05-lib-cohesion/03-wp3-state-ownership.md) 迁移 application Notifier，BindingManager 提升至 app。Conversation / Workspace 的 owner 与完整 Shell 前移仍由 WP-3C 承接；不改本文件历史证据。

## 后继收口（2026-09-06）

本页保留原阶段目标与验收证据。Store/镜像/registry 已由 [2026-09-05 WP-3C](../2026-09-05-lib-cohesion/03-wp3-state-ownership.md) 继续收口为稳定 ownerKey 与单 Notifier，完整生命周期和当次门禁见该阶段验收记录。
