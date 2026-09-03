# WP-1 · 切片 owner 归位 + ViewModel 拆分

| 项 | 值 |
|----|----|
| 状态 | 未开始 |
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

- [ ] 跑以下命令，把结果整理成「region 字段 × 生产者 × 消费者」矩阵贴进 PR-1 描述：

```sh
grep -rn "AgentConversationViewModel" lib test --include=*.dart | wc -l
grep -rn "uiEffects\|liveTurnListenable\|threadSnapshotListenable\|contextPanelVisible" lib/src --include=*.dart
grep -rn "_buildHeaderState\|_buildComposerState\|_buildPendingInteractionState\|_buildExpansionState\|_buildHistoryState" lib/src/features/agent/presentation/agent_conversation_view_model.dart
```

- [ ] 5 个 region state 的字段清单已在 `agent_conversation_region_state.dart`（`AgentHeaderState` 17 字段 / `AgentComposerState` 22 字段 / `AgentPendingInteractionState` 8 字段 / `AgentExpansionState` 5 字段 / `AgentConversationHistoryState` 6 字段）；逐个标注投影数据源（读 timeline 还是 session state 还是 controller）。
- [ ] **Widget 只读面清单**（review 补充：T5 只覆盖命令面，只读访问器也必须各有归属）：`liveTurnListenable` / `liveTurnState` / `threadSnapshotListenable` / `contextPanelVisible` / `uiEffects` / `toolElapsedAt` / `mentionCandidateFiles` / `isWorkspaceFileIndexReady` / `workspaceFileCorpus` / `loadSettings` / `canUseSkills` 等——grep 全部 `viewModel.` 调用点，按「controller 查询方法 / region state 字段 / composerStateOwner」分类标注去向。
- [ ] **验收**：矩阵覆盖 5 个 region 全部字段；ViewModel 引用点（命令面 + 只读面）清单无遗漏。

### T2 · runtime controller 下沉（PR-1，3–4 人天）

**目的**：把「持有 core runtime + 投影 + 历史加载 + provider 切换」从 ViewModel 搬到 application。

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

### T3 · 纯函数下沉（PR-2，1 人天）

**平移清单与落点**：

| 现状（ViewModel） | 落点 | 目标签名 |
|---|---|---|
| `_latestHistorySelectionPatch` / `_mergeThreadSelectionPatches`（`:1686-1760`） | `application/conversation_slice/agent_thread_selection_patch.dart` | `AgentThreadSelectionPatch? mergeAgentThreadSelectionPatches(...)` 纯函数 |
| skills 候选过滤（`:851-900`） | `application/` 侧 skills 查询文件 | `List<AgentSkillRef> filterAgentSkillCandidates(...)` |
| `mentionCandidateFiles` / `_flattenFileNodes`（`:949-1038`） | 经 `WorkspaceFileCorpusPort` 的 application 查询 | `List<WorkspaceNode> flattenWorkspaceFileNodes(...)`（若通用则下沉 workspace feature） |

**步骤**：逐函数平移 → 改静态/顶层纯函数 → 表驱动单测（每函数 ≥3 组用例：空输入、典型、边界）→ ViewModel 删原方法改委托。

**验收**：三个函数各有独立单测；ViewModel 减少约 350 行；`test_affected.sh` 绿。

### T4 · 附件 port：dart:io 移出 presentation（PR-2，1 人天）

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

### T6 · 全量门禁与文档同步（PR-4，1–2 人天）

- [ ] `bash tool/test_full.sh` 全绿。
- [ ] §6 文档同步：`docs/architecture/overview.md`(+en) 状态发布链路图、`engineering_standards.md` §3.0、`developer_guide.md` 切片接入说明、`glossary.md`（region/slice 术语如变化）。
- [ ] 登记 `00-index.md` §6「开发记录」。

## 4. 风险与回滚

| 风险 | 缓解 |
|------|------|
| 「同帧一次 dispatch」语义破坏导致流式渲染抖动 | scheduler 帧合并本在 request 粒度工作；widget 测试的流式/滚动用例是回归网；PR-1 独立合入可整体 revert |
| 命令 effect 的两次 scope 校验在平移中丢失 | `_AgentConversationCommandEffectRunner` 整体平移不改逻辑；对应单测随迁 |
| 测试迁移漏覆盖 | 107 + 38 用例逐条核对；删除任何用例需在 PR 描述说明归属 |
| 与 WP-2 并行冲突 | 按 DR-003 顺序执行 |

## 5. 完成定义（DoD）

- [ ] 链路两跳；`AgentConversationUiStateStore` / `AgentConversationSliceComposition` / `AgentConversationViewModel` 零命中。
- [ ] presentation 层 agent feature 无 `dart:io`、无 `zeta_agent_providers` import。
- [ ] `flutter analyze` 零告警；`tool/test_full.sh` 绿；架构守卫绿。
- [ ] 文档同步完成；CHANGELOG 无条目（纯内部重构）。
