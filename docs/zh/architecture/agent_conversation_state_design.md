# AgentConversationBloc 状态设计

中文 ｜ [English](../../en/architecture/agent_conversation_state_design.md)

本文给出 [步骤 32](./migration_tasks.md) 的字段级设计。它是 P7 唯一的返工保险：
`agent_conversation_view_model.dart` 有 4,190 行、`agent_conversation_ui_state.dart` 有 1,098 行，
不先定 State 形状和缓存归属就动手，几乎必然要重来。

配套文档：[归属映射表 §5](./ownership_map.md)（哪些代码进 Bloc）、
[包 API 契约 §5.2](./package_api_contracts.md)（Repository 提供什么）。

---

## 1. 好消息：五个 slice 已经存在

任务清单说"State 保留 header/composer/pending/expansion/history 五个 slice"，
这不是新设计——旧仓库 `agent_conversation_ui_state.dart` 里已经是这五个不可变类：

| 旧类 | 行 | 字段数 | 迁移后 |
| --- | ---: | ---: | --- |
| `AgentHeaderState` | 13 | 17 | `AgentConversationState.header` |
| `AgentComposerState` | 100 | 31 | `AgentConversationState.composer` |
| `AgentPendingInteractionState` | 239 | 7 | `AgentConversationState.pending` |
| `AgentExpansionState` | 343 | 5 | `AgentConversationState.expansion` |
| `AgentConversationHistoryState` | 397 | 7 | `AgentConversationState.history` |
| `AgentConversationUiStateStore` | 478 | — | **删除**，由 Bloc 取代 |

**迁移工作不是重新设计 slice，而是三件事**：

1. 把 `AgentConversationUiStateStore` 的五个 `Function()` builder 回调（:521–525）换成
   Bloc 对 Repository snapshot 的订阅 + reduce。
2. 把 4,190 行 view model 的 ~50 个公开方法转成 Event（§5）。
3. 把混在 State 里的缓存和签名字段清出去（§6）。

这显著降低了 P7 的风险评估——**slice 边界已经被生产代码验证过**。

---

## 2. State 顶层结构

```dart
final class AgentConversationState extends Equatable {
  const AgentConversationState({
    required this.key,
    required this.status,
    required this.header,
    required this.composer,
    required this.pending,
    required this.expansion,
    required this.history,
    this.failure,
  });

  /// 会话身份。切换 thread 即换 key，旧 key 的异步结果一律丢弃。
  final ConversationKey key;

  /// 会话级加载状态；slice 内部另有各自的细粒度状态。
  final AgentConversationStatus status;   // initial | opening | ready | failure

  final AgentHeaderState header;
  final AgentComposerState composer;
  final AgentPendingInteractionState pending;
  final AgentExpansionState expansion;
  final AgentConversationHistoryState history;

  /// typed failure，不是可渲染文案。
  final AgentConversationFailure? failure;

  @override
  List<Object?> get props => [key, status, header, composer, pending, expansion, history, failure];
}
```

**每个 slice 独立 `Equatable`**，这样 `BlocSelector` 只订阅一个 slice 时，其他 slice 变化
不会触发 rebuild。这是长时间线性能的关键——composer 每次按键都变，但时间线不应因此重绘。

---

## 3. 各 slice 字段级设计

### 3.1 `header`（17 字段）

```dart
final class AgentHeaderState extends Equatable {
  final String title;
  final AgentThreadOpenPhase threadOpenPhase;
  final String? systemNoticeCode;        // ← 旧: systemNoticeLabel（已本地化字符串）
  final AgentStatusCapsule? statusCapsule; // ← 旧: statusCapsuleLabel
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool showRunningIndicator;
  final AgentActivityCode? runningActivity; // ← 旧: runningActivityLabel
  final DateTime? segmentStartedAt;
  final DateTime? turnStartedAt;
  final AgentTokenUsage? tokenUsage;
  final bool isTurnRunning;
  final bool isReadOnly;
  final bool canFork;
  final bool canRename;
  final bool canArchive;
  final bool isPlanMode;
}
```

**三处必须改成 typed code**：`systemNoticeLabel`、`statusCapsuleLabel`、`runningActivityLabel`
在旧代码里是已本地化的 `String`。Bloc 不得持有本地化文案（[任务清单 §1.3](./migration_tasks.md)），
改为 typed code，由 `lib/l10n/` 映射到 ARB。

`canFork` / `canRename` / `canArchive` 直接来自 `bundle.capabilities`，**不缓存在 Repository**。

`segmentStartedAt` / `turnStartedAt` 是时间戳而非"已过秒数"——elapsed 由 Widget 用
`AgentElapsedTicker` 的替代物（Bloc 内 `Timer.periodic` 发 `_ElapsedTicked` 事件）计算，
**不把每秒变化的整数放进 State**，否则整个 header 每秒重建。

> **性能取舍**：更好的做法是让 Widget 自己持有 1 秒 ticker，State 只给时间戳。
> Bloc 完全不需要 timer。**推荐后者**——旧代码的 `AgentElapsedTicker` 本就是
> `ChangeNotifier`，迁移时直接变成 Widget 局部的 `TickerProvider`。
> 这样 `close()` 也少一个要取消的 timer。

### 3.2 `composer`（31 字段）

旧类有 31 个字段，是五个 slice 里最重的。**按来源分三组**：

| 组 | 字段 | 来源 |
| --- | --- | --- |
| 能力位 | `canSubmitMessage`、`canAttachImages`、`canMentionResources`、`canUseSkills`、`showModelSelection`、`showPermissionPolicy`、`isReadOnly` | `bundle.capabilities` |
| 外部目录 | `conversationModeOptions`、`permissionOptions`、`sessionConfigOptions`、`modelConfigState.catalog` | `agent_provider_repository` |
| **交互选择** | `selectedConversationMode`、`selectedPermissionOptionId`、`modelConfigState.selection`、`conversationModeAppliesToNextTurn` | **Bloc 独有** |
| 状态与提示 | `conversationModeStatus`、`conversationModeStatusCode`、`permissionApplyScopeCode`、`unavailableProviderCode` | **Bloc 独有**，typed code |
| 上下文 | `contextUsage`、`isTurnRunning`、`threadOpenPhase` | Repository snapshot 派生 |

**删除两个签名字段**：

```dart
final Object _modelConfigSignature;    // ← 删除
final Object _sessionConfigSignature;  // ← 删除
final Object conversationModeContextId; // ← 删除
```

它们是旧 Store 手写的变化检测机制。`Equatable` 的 `props` 已经提供同等语义，保留它们
既冗余又会在 `props` 里引入不稳定的 `Object` 比较。

`conversationModeStatusMessage` 同样改 typed code。

**composer 的文本内容不在 State 里**：`composer_document.dart` 是富文本编辑器的文档模型，
由 Widget 持有（`TextEditingController` 同理）。Bloc 只在提交时通过事件收到最终文本。
把每次按键推进 Bloc 会让 event storm 期间的输入卡顿。

### 3.3 `pending`（7 字段）

```dart
final class AgentPendingInteractionState extends Equatable {
  final List<AgentPermissionRequest> permissions;
  final List<AgentQuestionRequest> questions;
  final List<AgentPlanApprovalRequest> planApprovals;
  final AgentPlanExecutionRequest? planExecutionHandoff;
  final bool isReadOnly;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;
  // final Object _semanticSignature;  ← 删除
}
```

**这个 slice 的四个列表必须保持物理隔离**，见 §7。

`permissions` / `questions` / `planApprovals` 来自 Repository snapshot；
`planExecutionHandoff` 是 **Bloc 独有**——它是 Zeta 本地工作流，不来自任何 Provider
（[Codex 协议 §8.2](../protocols/codex_app_server_protocol.md)）。

### 3.4 `expansion`（5 字段）— 纯 Bloc

```dart
final class AgentExpansionState extends Equatable {
  final Set<String> toolCallIds;
  final Set<String> planMessageIds;
  final Set<String> activePlanTurnIds;
  final Set<String> commandGroupIds;
  final Set<String> fileEditItemIds;
}
```

**完全不与 Repository 交互。** 这是判定程序第 3 问的标准答案：UI 全关后这些 id 集合毫无意义。

旧 view model 有 5 个 `isXxxExpanded()` 查询 + 5 个 `toggleXxx()` 方法（:1110–1170）。
迁移后：查询由 `BlocSelector` 完成，toggle 变成 5 个同步事件（无 transformer，无异步）。

**必须做 GC**：thread 切换或时间线裁剪后，清理已不存在的 entryId，否则这五个 Set 会无界增长。
在 `_ConversationSnapshotReceived` 处理器里做集合求交。

### 3.5 `history`（7 字段）

```dart
final class AgentConversationHistoryState extends Equatable {
  final AgentConversationTurnGroup? standbyTurn;
  final List<AgentConversationTurnGroup> visibleTurns;
  final AgentThreadOpenPhase threadOpenPhase;
  final String providerId;
  final AgentProviderKind providerKind;
  final String providerName;
  // final Object _semanticSignature;  ← 删除
}
```

`visibleTurns` 是**已投影的 UI slice**，不是完整时间线。真正的完整聚合在
`agent_conversation_repository` 的 `ConversationSnapshot` 里。

> **这是全文最重要的性能决策。** 如果把完整时间线（可能上万条 entry）放进 State，
> 每次 delta 事件都会触发一次全量 `Equatable` 比较。正确做法：
>
> - Repository 持有完整 `ConversationSnapshot`（可变内部结构 + 不可变对外视图）。
> - Bloc State 只持有**当前可见窗口**的 turn group 列表。
> - 虚拟滚动请求更多内容时，派发 `AgentHistoryWindowChanged(range)` 事件。
>
> `AgentConversationTurnGroup` 内部持有 entryId 列表而非 entry 对象；
> Widget 按 id 从 Repository 的同步 snapshot 取详情，或从 Presentation 缓存取投影结果。

---

## 4. 三个缓存与调度器的归属

这是任务清单没回答、但决定性能成败的问题。

| 组件 | 旧位置 | 新归属 | 理由 |
| --- | --- | --- | --- |
| `agent_markdown_cache.dart` | presentation | **Presentation**，Widget 持有 | 渲染结果，以 entryId 为 key |
| `agent_timeline_projection_cache.dart` | presentation | **Presentation**，Page 级 | domain → UI slice 的记忆化 |
| `agent_file_change_projection_cache.dart` | presentation | **Presentation**，Page 级 | 同上 |
| `agent_ui_update_scheduler.dart` | presentation | **Presentation** | 帧合并，需要 `SchedulerBinding` |
| `agent_timeline_extent_descriptor.dart` | presentation | **Presentation** | 虚拟滚动尺寸 |
| `agent_timeline_grouping.dart` | presentation | **Presentation** | 视觉分组 |

**全部不进 State。** 原因在[归属映射表 §7](./ownership_map.md)已说明：State 必须 `Equatable`
且比较廉价。

### 4.1 帧合并放在哪

旧架构：Repository/application 发 `AgentUiUpdateRequest` → presentation 的 scheduler 合并 → 重绘。

新架构有两层合并，**都要保留**：

```text
Provider 事件洪流
  ↓
[Repository] AgentEventCoalescingPolicy + BoundedEventDispatcher
  ↓  合并后的 domain snapshot（已经显著降频）
[Bloc] restartable() 订阅 → emit State
  ↓
[Presentation] AgentUiUpdateScheduler 按帧合并 → 重绘
```

- **Repository 层合并**解决"同一条消息的 100 个 delta 合成 1 次"。
- **Presentation 层合并**解决"一帧内多次 emit 只重绘一次"。

**不要**因为有了 Bloc 就删掉 Presentation 的 scheduler。Bloc 的 `emit` 是同步的，
一帧内可能 emit 多次；`BlocBuilder` 会各触发一次 `setState`。`agent_ui_update_request.dart`
的 `AgentUiRegion` / urgency 因此保留给 scheduler 使用（[归属映射表 §3.4](./ownership_map.md)）。

---

## 5. Event 清单

旧 view model 的 ~50 个公开方法映射为事件。**每个异步事件必须显式声明 transformer**
（[任务清单 §1.3](./migration_tasks.md)）。

### 5.1 会话生命周期

| Event | 来源方法 | transformer |
| --- | --- | --- |
| `AgentConversationOpened` | 构造 + `retryOpenThread` | `sequential()` |
| `AgentConversationClosed` | `dispose` | `sequential()` |
| `AgentProviderSwitched` | `switchActiveProvider` | `restartable()` |
| `AgentContextUpdated` | `updateContext` | `sequential()` |
| `_ConversationSnapshotReceived`（内部） | Repository stream | `restartable()` 订阅 |

### 5.2 消息与回合

| Event | 来源方法 | transformer | 理由 |
| --- | --- | --- | --- |
| `AgentMessageSubmitted` | `sendMessage` | `sequential()` | 顺序敏感，禁止重复副作用 |
| `AgentTurnCancelled` | `cancelActiveTurn` | `sequential()` | |
| `AgentLastUserMessageEdited` | `editLastUserMessageAndRetry` | `sequential()` | 会 fork + 重发 |
| `AgentThreadForked` | `forkCurrentThread` | `droppable()` | 防重复点击 |
| `AgentThreadRenamed` | `renameCurrentThread` | `sequential()` | |
| `AgentThreadArchived` | `archiveCurrentThread` | `sequential()` | |
| `AgentThreadCompacted` | `compactCurrentThread` | `sequential()` | |

### 5.3 四种安全语义（全部 `sequential()`）

| Event | 来源方法 | Repository 方法 |
| --- | --- | --- |
| `AgentPermissionResponded` | `respondToPermission` | `respondToPermission()` |
| `AgentQuestionResponded` | `respondToQuestion` | `respondToQuestion()` |
| `AgentPlanApprovalResponded` | `respondToPlanApproval` | `respondToPlanApproval()` |
| `AgentPlanExecutionStarted` | `startPlanExecution` | `submit()`（新 Default 回合） |
| `AgentPlanExecutionRevised` | `revisePlanExecution` | 仅改 Bloc State |
| `AgentPlanExecutionDismissed` | `dismissPlanExecution` | 仅改 Bloc State |
| `AgentDeniedActionApproved` | `approveGuardianDeniedAction` | `approveDeniedAction()` |

### 5.4 选择与配置

| Event | 来源方法 | transformer |
| --- | --- | --- |
| `AgentModelSelected` | `selectModel` | `restartable()` |
| `AgentReasoningEffortSelected` | `selectReasoningEffort` | `restartable()` |
| `AgentServiceTierSelected` | `selectServiceTier` | `restartable()` |
| `AgentFastToggled` | `selectFastEnabled` | `restartable()` |
| `AgentModelConflictResolved` | `resolveModelCompatibilityConflict` | `sequential()` |
| `AgentModelConfigSaveRetried` | `retryModelConfigurationSave` | `droppable()` |
| `AgentModelConfigTransientCleared` | `clearModelConfigurationTransientState` | 同步 |
| `AgentPermissionOptionSelected` | `selectPermissionOption` | `sequential()` |
| `AgentPermissionPersistenceRetried` | `retryPermissionPreferencePersistence` | `droppable()` |
| `AgentConversationModeSelected` | `selectConversationMode` | 同步（发送时才生效） |
| `AgentConversationModesRetried` | `retryConversationModes` | `droppable()` |
| `AgentSessionConfigOptionSelected` | `selectSessionConfigOption` | `sequential()` |
| `AgentPlanExecutionPermissionSelected` | `selectPlanExecutionPermissionOption` | 同步 |

### 5.5 目录加载

| Event | 来源方法 | transformer |
| --- | --- | --- |
| `AgentModelsRequested` | `loadModels` | `restartable()` |
| `AgentSkillsCatalogRequested` | `ensureSkillsCatalog` | `droppable()` |
| `AgentSettingsRequested` | `loadSettings` | `restartable()` |

### 5.6 纯同步 UI（无 transformer）

| Event | 来源方法 |
| --- | --- |
| `AgentToolCallToggled` | `toggleToolCall` |
| `AgentPlanMessageToggled` | `togglePlanMessage` |
| `AgentActivePlanToggled` | `toggleActivePlan` |
| `AgentCommandGroupToggled` | `toggleCommandGroup` |
| `AgentFileEditItemToggled` | `toggleFileEditItem` |
| `AgentContextPanelToggled` | `toggleContextPanel` / `hideContextPanel` |
| `AgentHistoryWindowChanged` | 虚拟滚动新增 |

`isXxxExpanded()` 五个查询方法**不映射为事件**——它们变成 `BlocSelector` 或
`state.expansion.toolCallIds.contains(id)`。

`syncThreadTitleIfCurrent` / `requestThreadSnapshotRefresh` / `publish` 三个方法**删除**：
它们是旧架构里 application 反向推 presentation 的通道，Bloc 架构下不存在。

---

## 6. 从 State 中清除的内容

| 旧成员 | 处理 |
| --- | --- |
| `_modelConfigSignature`、`_sessionConfigSignature`、`_semanticSignature`（×2） | 删除，`Equatable.props` 取代 |
| `conversationModeContextId` | 删除，用 `ConversationKey` + generation |
| `systemNoticeLabel`、`statusCapsuleLabel`、`runningActivityLabel`、`conversationModeStatusMessage`、`permissionPolicyLabel`、`permissionApplyScopeHint`、`unavailableProviderReason` | 改 typed code |
| `AgentConversationUiStateDiagnostics.publishCount` | 移到 Repository 诊断或删除 |
| `AgentConversationUiStateStore` 的五个 builder 回调 | 删除，Bloc 直接 reduce |
| `Stream<AgentUiEffect> get effects` | 改为 `BlocListener` 消费 State 变化；一次性效果用 nullable "signal" 字段 + 消费后清空 |

### 6.1 一次性效果怎么表达

旧代码用 `effects` stream 发一次性效果（自动滚动、聚焦）。Bloc State 是幂等快照，
不能直接表达"发生了一次"。两种做法：

```dart
// 推荐：带 id 的 signal 字段，BlocListener 比较 id 变化
final AgentAutoScrollSignal? autoScroll;  // {id, target}
```

`BlocListener` 用 `listenWhen: (a, b) => a.autoScroll?.id != b.autoScroll?.id` 触发一次。
**不要**在 listener 里派发事件清空 signal——那会引入额外一轮 emit。

---

## 7. 四种安全语义的隔离（不可妥协）

[步骤 32](./migration_tasks.md) 要求："permission response、question response、plan approval、
plan execution handoff 使用独立 event 和 repository method"，且"测试任一事件不会预授权其他语义"。

### 7.1 物理隔离清单

| 层 | 隔离要求 |
| --- | --- |
| 协议 | 三个 Provider 各自的 pending registry 互不共用（见三份协议文档） |
| contracts | `AgentPermissionRequest/Decision`、`AgentQuestionRequest/Response`、`AgentPlanApprovalRequest/Decision` 是三个独立 sealed family，**无互转构造函数** |
| Repository | `respondToPermission` / `respondToQuestion` / `respondToPlanApproval` 三个方法，**不合并为带 enum 参数的单方法** |
| Bloc Event | 四个独立 Event 类，**不共用基类字段** |
| State | `pending` 的四个字段互不派生 |
| UI | 三种卡片各自的 Widget，**不共用"通用审批卡"** |

### 7.2 Plan 执行交接的特殊性

`planExecutionHandoff` 是唯一**不来自 Provider** 的 pending 项：

- 它由 Bloc 在观察到成功的 Plan turn 后本地创建。
- 「Run plan」= 派发 `AgentMessageSubmitted`（新 Default 回合），**不是**审批回写。
- 它**不构成**对计划中命令、文件、网络的预授权——那些仍逐项走权限审批。
- 「Dismiss」只清 Bloc State，不向服务端发任何东西。

### 7.3 必须存在的负向测试

```dart
blocTest<AgentConversationBloc, AgentConversationState>(
  '批准 Plan 不会预授权计划中的命令',
  act: (bloc) => bloc.add(AgentPlanApprovalResponded(approve)),
  verify: (_) {
    verifyNever(() => repository.respondToPermission(any(), any()));
    verifyNever(() => repository.respondToQuestion(any(), any()));
  },
);
```

四种语义两两组合，共 12 个 `verifyNever` 断言，全部必须存在。

---

## 8. 订阅与生命周期

### 8.1 generation / key 守卫

```dart
final class AgentConversationBloc extends Bloc<AgentConversationEvent, AgentConversationState> {
  StreamSubscription<ConversationSnapshot>? _snapshotSub;
  int _generation = 0;

  Future<void> _onOpened(AgentConversationOpened e, Emitter emit) async {
    final generation = ++_generation;
    await _snapshotSub?.cancel();               // ① 先取消旧订阅

    final bundle = _providerRepository.bundleFor(e.providerId);   // ② 取 bundle
    final handle = await _conversationRepository.openConversation( // ③ 传给会话仓储
      bundle: bundle, key: e.key, context: e.context,
    );
    if (generation != _generation) {            // ④ 过期结果直接丢弃
      await handle.release();
      return;
    }
    _snapshotSub = _conversationRepository.snapshots(e.key).listen(
      (s) => add(_ConversationSnapshotReceived(s, generation)),
    );
  }
}
```

- `_ConversationSnapshotReceived` 的 handler 首先检查 `event.generation == _generation`，不等则丢弃。
- **`AgentConversationOpened` 用 `restartable()`**，切换 thread 时自动取消进行中的 open。
- 两个 Repository 的调用顺序固定：先 provider 取 bundle，再传给 conversation
  ——这是[拓扑 §4.4](./migration_topology.md) 规定的跨领域编排方式。

### 8.2 `close()` 必须释放的资源

```dart
@override
Future<void> close() async {
  await _snapshotSub?.cancel();
  await _skillsChangedSub?.cancel();
  await _configChangesSub?.cancel();
  _handle?.release();                  // conversation lease
  await _conversationRepository.closeConversation(_state.key);
  return super.close();
}
```

[步骤 32](./migration_tasks.md) 要求 `close()` 释放 "subscription、conversation key、cache lease 和 timer"。
按 §3.1 的推荐（ticker 放 Widget），Bloc 内没有 timer。

### 8.3 Bloc 作用域

[步骤 35](./migration_tasks.md)：**每个 workspace entry 一个 `AgentConversationBloc` 实例，
随 entry 关闭**。不是全局单例，也不是每个 route 一个。

---

## 9. 性能预算

[步骤 33](./migration_tasks.md) 要求"不得回退"于旧 `dev` 的记录基线。迁移前**必须先在旧仓库
测量并记录**，否则无从比较：

| 指标 | 测量方法 | 门槛 |
| --- | --- | --- |
| 长时间线滚动帧耗时 P95 | 固定 fixture（≥5,000 entry）滚动 | ≤ 旧基线 |
| 高频 delta 的合并率 | event-storm fixture，统计 emit 次数 / 事件数 | ≤ 旧基线 |
| 内存峰值 | 同 fixture 下 DevTools 快照 | ≤ 旧基线 |
| 首次打开 thread 到可交互 | 冷启动计时 | ≤ 旧基线 |

**先测旧的，再写新的。** 这一步排在 P7 开工之前，不是收尾时才做。

### 9.1 三个常见性能陷阱

1. **把完整时间线放进 State** → 每次 delta 触发全量 `Equatable` 比较。见 §3.5。
2. **把 composer 文本放进 State** → 每次按键走一遍 Bloc + 全 slice 比较。见 §3.2。
3. **用 `BlocBuilder` 订阅整个 State** → 任何 slice 变化都重绘全页。必须用 `BlocSelector`
   订阅单个 slice。

---

## 10. 测试要求

| 类别 | 要求 |
| --- | --- |
| 每个 handler | `blocTest()` 覆盖成功、失败、边界 |
| 每个 transformer | 顺序、取消、重复事件三种场景 |
| 过期结果 | 切换 thread 后旧 generation 的 snapshot 被丢弃 |
| 安全语义 | §7.3 的 12 个 `verifyNever` |
| capability | 21 个端口各有"端口为 null 时入口不渲染" |
| 资源释放 | `close()` 后所有 mock 的 `cancel`/`release` 被调用 |
| event storm | 固定 fixture 下无乱序、无幽灵更新、无重复副作用 |
| slice 隔离 | 改 composer 不导致 history slice 的 `==` 变化 |

最后一条是本设计的核心断言——它直接验证了 §2 "每个 slice 独立 `Equatable`" 的成立。

---

## 11. 落地顺序

P7 内部建议顺序，每步都可独立验证：

1. 定义五个 slice + `AgentConversationState`，写 `Equatable` 测试（含 slice 隔离断言）。
2. 定义全部 Event 类与 transformer 声明，暂不实现 handler。
3. 实现会话生命周期（§5.1）+ generation 守卫 + `close()`，跑资源释放测试。
4. 实现四种安全语义（§5.3）+ 12 个负向测试。**先于其他交互**，因为它风险最高。
5. 实现选择与目录加载（§5.4、§5.5）。
6. 实现消息与回合（§5.2）。
7. 实现同步 UI 事件（§5.6）+ expansion GC。
8. 接 Presentation：`BlocSelector` 拆分订阅、保留帧调度器、接缓存。
9. 跑性能对比（§9），与步骤 0 前记录的基线比。
