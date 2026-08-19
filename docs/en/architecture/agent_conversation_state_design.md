# AgentConversationBloc state design

[中文](../../zh/architecture/agent_conversation_state_design.md) ｜ English

This is the field-level design for [step 32](./migration_tasks.md). It is P7's only insurance against
rework: `agent_conversation_view_model.dart` is 4,190 lines and `agent_conversation_ui_state.dart` is
1,098 lines, and starting without a settled State shape and cache ownership almost guarantees a redo.

Companion documents: [ownership map §5](./ownership_map.md) (what moves into the Bloc),
[package API contracts §5.2](./package_api_contracts.md) (what the Repository provides).

---

## 1. The good news: the five slices already exist

The task list says "State keeps the five slices header/composer/pending/expansion/history". That is not a
new design — the old repo's `agent_conversation_ui_state.dart` already has exactly these five immutable
classes:

| Old class | Line | Fields | After migration |
| --- | ---: | ---: | --- |
| `AgentHeaderState` | 13 | 17 | `AgentConversationState.header` |
| `AgentComposerState` | 100 | 31 | `AgentConversationState.composer` |
| `AgentPendingInteractionState` | 239 | 7 | `AgentConversationState.pending` |
| `AgentExpansionState` | 343 | 5 | `AgentConversationState.expansion` |
| `AgentConversationHistoryState` | 397 | 7 | `AgentConversationState.history` |
| `AgentConversationUiStateStore` | 478 | — | **deleted**, replaced by the Bloc |

**So the work is not redesigning slices — it is three things**:

1. Replace the store's five `Function()` builder callbacks (:521–525) with the Bloc subscribing to and
   reducing the Repository snapshot.
2. Turn the view model's ~50 public methods into events (§5).
3. Evict the caches and signature fields currently mixed into State (§6).

This meaningfully lowers P7's risk assessment — **the slice boundaries are already validated by
production code**.

---

## 2. Top-level State

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

  /// Conversation identity. Switching thread swaps the key; async results
  /// carrying an old key are discarded.
  final ConversationKey key;

  /// Conversation-level load status; slices carry their own finer-grained state.
  final AgentConversationStatus status;   // initial | opening | ready | failure

  final AgentHeaderState header;
  final AgentComposerState composer;
  final AgentPendingInteractionState pending;
  final AgentExpansionState expansion;
  final AgentConversationHistoryState history;

  /// A typed failure, never renderable copy.
  final AgentConversationFailure? failure;

  @override
  List<Object?> get props => [key, status, header, composer, pending, expansion, history, failure];
}
```

**Each slice is independently `Equatable`**, so a `BlocSelector` watching one slice does not rebuild when
another changes. This is the key to long-timeline performance: the composer changes on every keystroke,
but the timeline must not repaint because of it.

---

## 3. Field-level design per slice

### 3.1 `header` (17 fields)

```dart
final class AgentHeaderState extends Equatable {
  final String title;
  final AgentThreadOpenPhase threadOpenPhase;
  final String? systemNoticeCode;           // was: systemNoticeLabel (localized string)
  final AgentStatusCapsule? statusCapsule;  // was: statusCapsuleLabel
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool showRunningIndicator;
  final AgentActivityCode? runningActivity; // was: runningActivityLabel
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

**Three fields must become typed codes**: `systemNoticeLabel`, `statusCapsuleLabel` and
`runningActivityLabel` are already-localized `String`s in the old code. A Bloc must not hold localized
copy ([tasks §1.3](./migration_tasks.md)), so they become typed codes mapped to ARB by `lib/l10n/`.

`canFork` / `canRename` / `canArchive` come straight from `bundle.capabilities` and are **not cached in
the Repository**.

`segmentStartedAt` / `turnStartedAt` are timestamps, not "seconds elapsed". Elapsed time is computed by
the widget, so **an integer that changes every second never enters State** — otherwise the whole header
rebuilds once per second.

> **Trade-off**: the better option is to let the widget own the 1-second ticker while State supplies only
> timestamps, so the Bloc needs no timer at all. **Prefer that.** The old `AgentElapsedTicker` was itself
> a `ChangeNotifier`, so it becomes a widget-local `TickerProvider` directly — and `close()` has one less
> timer to cancel.

### 3.2 `composer` (31 fields)

The heaviest of the five slices. **Group by source**:

| Group | Fields | Source |
| --- | --- | --- |
| Capability bits | `canSubmitMessage`, `canAttachImages`, `canMentionResources`, `canUseSkills`, `showModelSelection`, `showPermissionPolicy`, `isReadOnly` | `bundle.capabilities` |
| External catalogs | `conversationModeOptions`, `permissionOptions`, `sessionConfigOptions`, `modelConfigState.catalog` | `agent_provider_repository` |
| **Interaction selection** | `selectedConversationMode`, `selectedPermissionOptionId`, `modelConfigState.selection`, `conversationModeAppliesToNextTurn` | **Bloc only** |
| Status and hints | `conversationModeStatus`, `conversationModeStatusCode`, `permissionApplyScopeCode`, `unavailableProviderCode` | **Bloc only**, typed codes |
| Context | `contextUsage`, `isTurnRunning`, `threadOpenPhase` | derived from the Repository snapshot |

**Delete three signature fields**:

```dart
final Object _modelConfigSignature;     // <- delete
final Object _sessionConfigSignature;   // <- delete
final Object conversationModeContextId; // <- delete
```

They are the old store's hand-rolled change detection. `Equatable`'s `props` already provides the same
semantics; keeping them is redundant and introduces unstable `Object` comparisons into `props`.

`conversationModeStatusMessage` likewise becomes a typed code.

**The composer's text is not in State**: `composer_document.dart` is the rich-text editor's document
model, owned by the widget (as is `TextEditingController`). The Bloc receives the final text via an event
at submit time. Pushing every keystroke through the Bloc would stall typing during an event storm.

### 3.3 `pending` (7 fields)

```dart
final class AgentPendingInteractionState extends Equatable {
  final List<AgentPermissionRequest> permissions;
  final List<AgentQuestionRequest> questions;
  final List<AgentPlanApprovalRequest> planApprovals;
  final AgentPlanExecutionRequest? planExecutionHandoff;
  final bool isReadOnly;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;
  // final Object _semanticSignature;  <- delete
}
```

**The four lists in this slice must stay physically isolated**; see §7.

`permissions` / `questions` / `planApprovals` come from the Repository snapshot;
`planExecutionHandoff` is **Bloc-only** — it is a local Zeta workflow that comes from no provider
([Codex protocol §8.2](../protocols/codex_app_server_protocol.md)).

### 3.4 `expansion` (5 fields) — pure Bloc

```dart
final class AgentExpansionState extends Equatable {
  final Set<String> toolCallIds;
  final Set<String> planMessageIds;
  final Set<String> activePlanTurnIds;
  final Set<String> commandGroupIds;
  final Set<String> fileEditItemIds;
}
```

**No Repository interaction at all.** This is the model answer to question 3 of the decision procedure:
once the UI closes, these id sets are meaningless.

The old view model had five `isXxxExpanded()` queries plus five `toggleXxx()` methods (:1110–1170). After
migration: queries are answered by `BlocSelector`, and the toggles become five synchronous events (no
transformer, no async).

**Garbage collection is mandatory**: after a thread switch or timeline trim, drop entry ids that no
longer exist, or these five sets grow without bound. Do the set intersection inside the
`_ConversationSnapshotReceived` handler.

### 3.5 `history` (7 fields)

```dart
final class AgentConversationHistoryState extends Equatable {
  final AgentConversationTurnGroup? standbyTurn;
  final List<AgentConversationTurnGroup> visibleTurns;
  final AgentThreadOpenPhase threadOpenPhase;
  final String providerId;
  final AgentProviderKind providerKind;
  final String providerName;
  // final Object _semanticSignature;  <- delete
}
```

`visibleTurns` is an **already-projected UI slice**, not the full timeline. The real complete aggregate
lives in the `ConversationSnapshot` inside `agent_conversation_repository`.

> **This is the single most important performance decision in the document.** Putting the full timeline
> (potentially tens of thousands of entries) into State makes every delta event trigger a full
> `Equatable` comparison. The correct approach:
>
> - The Repository holds the complete `ConversationSnapshot` (mutable internals, immutable public view).
> - Bloc State holds only the **currently visible window** of turn groups.
> - When virtual scrolling needs more, dispatch `AgentHistoryWindowChanged(range)`.
>
> `AgentConversationTurnGroup` holds entry *ids*, not entry objects; widgets fetch details by id from the
> Repository's synchronous snapshot or from the presentation projection cache.

---

## 4. Ownership of the three caches and the scheduler

The task list does not answer this, yet it decides whether performance holds.

| Component | Old location | New owner | Reason |
| --- | --- | --- | --- |
| `agent_markdown_cache.dart` | presentation | **Presentation**, widget-owned | render output keyed by entryId |
| `agent_timeline_projection_cache.dart` | presentation | **Presentation**, page-scoped | memoized domain → UI slice |
| `agent_file_change_projection_cache.dart` | presentation | **Presentation**, page-scoped | same |
| `agent_ui_update_scheduler.dart` | presentation | **Presentation** | frame coalescing; needs `SchedulerBinding` |
| `agent_timeline_extent_descriptor.dart` | presentation | **Presentation** | virtual scroll extents |
| `agent_timeline_grouping.dart` | presentation | **Presentation** | visual grouping |

**None of them enter State.** The reason is given in [ownership map §7](./ownership_map.md): State must
be `Equatable` and cheap to compare.

### 4.1 Where frame coalescing goes

Old architecture: the repository/application layer emitted an `AgentUiUpdateRequest` → the presentation
scheduler coalesced it → repaint.

The new architecture has two coalescing layers and **both must be kept**:

```text
provider event flood
  ↓
[Repository] AgentEventCoalescingPolicy + BoundedEventDispatcher
  ↓  coalesced domain snapshots (already far lower frequency)
[Bloc] restartable() subscription → emit State
  ↓
[Presentation] AgentUiUpdateScheduler coalesces per frame → repaint
```

- **Repository-layer coalescing** solves "100 deltas of one message become 1".
- **Presentation-layer coalescing** solves "several emits within a frame repaint once".

**Do not** delete the presentation scheduler just because there is now a Bloc. `emit` is synchronous and
may fire several times within a frame, and `BlocBuilder` would call `setState` for each. That is why
`AgentUiRegion` / urgency from `agent_ui_update_request.dart` is retained for the scheduler
([ownership map §3.4](./ownership_map.md)).

---

## 5. Event catalogue

The view model's ~50 public methods map to events. **Every async event declares a transformer
explicitly** ([tasks §1.3](./migration_tasks.md)).

### 5.1 Conversation lifecycle

| Event | Source method | Transformer |
| --- | --- | --- |
| `AgentConversationOpened` | constructor + `retryOpenThread` | `sequential()` |
| `AgentConversationClosed` | `dispose` | `sequential()` |
| `AgentProviderSwitched` | `switchActiveProvider` | `restartable()` |
| `AgentContextUpdated` | `updateContext` | `sequential()` |
| `_ConversationSnapshotReceived` (internal) | repository stream | `restartable()` subscription |

### 5.2 Messages and turns

| Event | Source method | Transformer | Reason |
| --- | --- | --- | --- |
| `AgentMessageSubmitted` | `sendMessage` | `sequential()` | order-sensitive; no duplicate side effects |
| `AgentTurnCancelled` | `cancelActiveTurn` | `sequential()` | |
| `AgentLastUserMessageEdited` | `editLastUserMessageAndRetry` | `sequential()` | forks and resends |
| `AgentThreadForked` | `forkCurrentThread` | `droppable()` | guards double-clicks |
| `AgentThreadRenamed` | `renameCurrentThread` | `sequential()` | |
| `AgentThreadArchived` | `archiveCurrentThread` | `sequential()` | |
| `AgentThreadCompacted` | `compactCurrentThread` | `sequential()` | |

### 5.3 The four security semantics (all `sequential()`)

| Event | Source method | Repository method |
| --- | --- | --- |
| `AgentPermissionResponded` | `respondToPermission` | `respondToPermission()` |
| `AgentQuestionResponded` | `respondToQuestion` | `respondToQuestion()` |
| `AgentPlanApprovalResponded` | `respondToPlanApproval` | `respondToPlanApproval()` |
| `AgentPlanExecutionStarted` | `startPlanExecution` | `submit()` (a new Default turn) |
| `AgentPlanExecutionRevised` | `revisePlanExecution` | Bloc State only |
| `AgentPlanExecutionDismissed` | `dismissPlanExecution` | Bloc State only |
| `AgentDeniedActionApproved` | `approveGuardianDeniedAction` | `approveDeniedAction()` |

### 5.4 Selection and configuration

| Event | Source method | Transformer |
| --- | --- | --- |
| `AgentModelSelected` | `selectModel` | `restartable()` |
| `AgentReasoningEffortSelected` | `selectReasoningEffort` | `restartable()` |
| `AgentServiceTierSelected` | `selectServiceTier` | `restartable()` |
| `AgentFastToggled` | `selectFastEnabled` | `restartable()` |
| `AgentModelConflictResolved` | `resolveModelCompatibilityConflict` | `sequential()` |
| `AgentModelConfigSaveRetried` | `retryModelConfigurationSave` | `droppable()` |
| `AgentModelConfigTransientCleared` | `clearModelConfigurationTransientState` | synchronous |
| `AgentPermissionOptionSelected` | `selectPermissionOption` | `sequential()` |
| `AgentPermissionPersistenceRetried` | `retryPermissionPreferencePersistence` | `droppable()` |
| `AgentConversationModeSelected` | `selectConversationMode` | synchronous (applies at send time) |
| `AgentConversationModesRetried` | `retryConversationModes` | `droppable()` |
| `AgentSessionConfigOptionSelected` | `selectSessionConfigOption` | `sequential()` |
| `AgentPlanExecutionPermissionSelected` | `selectPlanExecutionPermissionOption` | synchronous |

### 5.5 Catalog loading

| Event | Source method | Transformer |
| --- | --- | --- |
| `AgentModelsRequested` | `loadModels` | `restartable()` |
| `AgentSkillsCatalogRequested` | `ensureSkillsCatalog` | `droppable()` |
| `AgentSettingsRequested` | `loadSettings` | `restartable()` |

### 5.6 Purely synchronous UI (no transformer)

| Event | Source method |
| --- | --- |
| `AgentToolCallToggled` | `toggleToolCall` |
| `AgentPlanMessageToggled` | `togglePlanMessage` |
| `AgentActivePlanToggled` | `toggleActivePlan` |
| `AgentCommandGroupToggled` | `toggleCommandGroup` |
| `AgentFileEditItemToggled` | `toggleFileEditItem` |
| `AgentContextPanelToggled` | `toggleContextPanel` / `hideContextPanel` |
| `AgentHistoryWindowChanged` | new, for virtual scrolling |

The five `isXxxExpanded()` queries **do not become events** — they become `BlocSelector` calls or
`state.expansion.toolCallIds.contains(id)`.

`syncThreadTitleIfCurrent`, `requestThreadSnapshotRefresh` and `publish` are **deleted**: they are the old
architecture's channel for the application layer to push into presentation, which does not exist under
Bloc.

---

## 6. What is removed from State

| Old member | Handling |
| --- | --- |
| `_modelConfigSignature`, `_sessionConfigSignature`, `_semanticSignature` (×2) | delete; `Equatable.props` replaces them |
| `conversationModeContextId` | delete; use `ConversationKey` + generation |
| `systemNoticeLabel`, `statusCapsuleLabel`, `runningActivityLabel`, `conversationModeStatusMessage`, `permissionPolicyLabel`, `permissionApplyScopeHint`, `unavailableProviderReason` | convert to typed codes |
| `AgentConversationUiStateDiagnostics.publishCount` | move to repository diagnostics or delete |
| the store's five builder callbacks | delete; the Bloc reduces directly |
| `Stream<AgentUiEffect> get effects` | consume State changes via `BlocListener`; one-shot effects use a nullable "signal" field |

### 6.1 Expressing one-shot effects

The old code used an `effects` stream for one-shot effects (auto-scroll, focus). Bloc State is an
idempotent snapshot and cannot express "this happened once" directly. Two options:

```dart
// Recommended: a signal field with an id, compared by BlocListener
final AgentAutoScrollSignal? autoScroll;  // {id, target}
```

`BlocListener` fires once using `listenWhen: (a, b) => a.autoScroll?.id != b.autoScroll?.id`.
**Do not** dispatch an event from the listener to clear the signal — that costs an extra emit round.

---

## 7. Isolating the four security semantics (non-negotiable)

[Step 32](./migration_tasks.md) requires: "permission response, question response, plan approval and
plan execution handoff use separate events and repository methods", with tests proving "no event
pre-authorizes another semantic".

### 7.1 Physical isolation checklist

| Layer | Isolation requirement |
| --- | --- |
| Protocol | each provider's pending registries are separate (see the three protocol docs) |
| contracts | `AgentPermissionRequest/Decision`, `AgentQuestionRequest/Response` and `AgentPlanApprovalRequest/Decision` are three independent sealed families with **no conversion constructors** |
| Repository | three methods — `respondToPermission` / `respondToQuestion` / `respondToPlanApproval` — **never merged into one method with an enum parameter** |
| Bloc events | four independent event classes that **share no base-class fields** |
| State | the four `pending` fields never derive from one another |
| UI | three distinct card widgets; **no shared "generic approval card"** |

### 7.2 What makes plan execution handoff special

`planExecutionHandoff` is the only pending item that **does not come from a provider**:

- The Bloc creates it locally after observing a successful plan turn.
- "Run plan" dispatches `AgentMessageSubmitted` (a new Default turn) — it is **not** an approval write-back.
- It **does not** pre-authorize the plan's commands, files or network access; each still goes through
  normal permission approval.
- "Dismiss" clears Bloc State only and sends nothing to the server.

### 7.3 Required negative tests

```dart
blocTest<AgentConversationBloc, AgentConversationState>(
  'approving a plan does not pre-authorize its commands',
  act: (bloc) => bloc.add(AgentPlanApprovalResponded(approve)),
  verify: (_) {
    verifyNever(() => repository.respondToPermission(any(), any()));
    verifyNever(() => repository.respondToQuestion(any(), any()));
  },
);
```

Across all pairs of the four semantics, that is 12 `verifyNever` assertions, all of which must exist.

---

## 8. Subscriptions and lifecycle

### 8.1 Generation / key guards

```dart
final class AgentConversationBloc extends Bloc<AgentConversationEvent, AgentConversationState> {
  StreamSubscription<ConversationSnapshot>? _snapshotSub;
  int _generation = 0;

  Future<void> _onOpened(AgentConversationOpened e, Emitter emit) async {
    final generation = ++_generation;
    await _snapshotSub?.cancel();                                  // (1) cancel the old subscription

    final bundle = _providerRepository.bundleFor(e.providerId);    // (2) fetch the bundle
    final handle = await _conversationRepository.openConversation( // (3) pass it to the conversation repo
      bundle: bundle, key: e.key, context: e.context,
    );
    if (generation != _generation) {                               // (4) discard stale results
      await handle.release();
      return;
    }
    _snapshotSub = _conversationRepository.snapshots(e.key).listen(
      (s) => add(_ConversationSnapshotReceived(s, generation)),
    );
  }
}
```

- The `_ConversationSnapshotReceived` handler first checks `event.generation == _generation` and drops
  the event otherwise.
- **`AgentConversationOpened` uses `restartable()`**, so switching thread cancels an in-flight open.
- The order of the two repository calls is fixed: fetch the bundle from the provider repository, then pass
  it to the conversation repository — the cross-domain orchestration prescribed by
  [topology §4.4](./migration_topology.md).

### 8.2 What `close()` must release

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

[Step 32](./migration_tasks.md) requires `close()` to release "subscriptions, the conversation key,
cache leases and timers". Following §3.1's recommendation (ticker in the widget), the Bloc holds no timer.

### 8.3 Bloc scope

[Step 35](./migration_tasks.md): **one `AgentConversationBloc` instance per workspace entry, closed
with the entry.** Not a global singleton, and not one per route.

---

## 9. Performance budget

[Step 33](./migration_tasks.md) requires "no regression" against the recorded baseline of the old
`dev`. That baseline **must be measured and recorded in the old repository first**, or there is nothing
to compare against:

| Metric | How to measure | Threshold |
| --- | --- | --- |
| P95 frame time when scrolling a long timeline | fixed fixture (≥5,000 entries), scrolled | ≤ old baseline |
| Coalescing ratio under high-frequency deltas | event-storm fixture; emits / events | ≤ old baseline |
| Peak memory | DevTools snapshot on the same fixture | ≤ old baseline |
| Time from opening a thread to interactive | cold-start timing | ≤ old baseline |

**Measure the old one first, then write the new one.** This step comes before P7 starts, not at the end.

### 9.1 Three common performance traps

1. **Putting the full timeline into State** → every delta triggers a full `Equatable` comparison. See §3.5.
2. **Putting composer text into State** → every keystroke runs the Bloc and compares all slices. See §3.2.
3. **Using `BlocBuilder` on the whole State** → any slice change repaints the entire page. Use
   `BlocSelector` per slice.

---

## 10. Testing requirements

| Category | Requirement |
| --- | --- |
| Every handler | `blocTest()` covering success, failure and boundary cases |
| Every transformer | ordering, cancellation and duplicate-event scenarios |
| Stale results | snapshots from an old generation are discarded after a thread switch |
| Security semantics | the 12 `verifyNever` assertions from §7.3 |
| Capabilities | each of the 21 ports has a "no entry point when the port is null" test |
| Resource release | after `close()`, every mocked `cancel`/`release` was called |
| Event storm | on the fixed fixture: no reordering, no ghost updates, no duplicated side effects |
| Slice isolation | changing the composer does not change the history slice's `==` |

The last row is this design's core assertion — it directly verifies §2's claim that each slice is
independently `Equatable`.

---

## 11. Implementation order

A suggested order within P7, where every step is independently verifiable:

1. Define the five slices and `AgentConversationState`; write `Equatable` tests including the slice
   isolation assertion.
2. Define all event classes and their transformer declarations, without implementing handlers yet.
3. Implement the conversation lifecycle (§5.1) plus generation guards and `close()`; run the resource
   release tests.
4. Implement the four security semantics (§5.3) and the 12 negative tests. **Do this before the other
   interactions** — it carries the highest risk.
5. Implement selection and catalog loading (§5.4, §5.5).
6. Implement messages and turns (§5.2).
7. Implement the synchronous UI events (§5.6) and expansion GC.
8. Wire up presentation: split subscriptions with `BlocSelector`, keep the frame scheduler, attach caches.
9. Run the performance comparison (§9) against the baseline recorded before step 0.
