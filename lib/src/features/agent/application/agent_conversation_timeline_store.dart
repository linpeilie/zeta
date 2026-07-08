import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Agent 对话时间线与 turn 分组的运行时状态仓库。
///
/// 它负责管理：
/// - 对话消息、工具调用、审批卡片和历史事件的统一时间线
/// - 历史 turn 的分页窗口
/// - live turn / history turn / standby turn 的分组状态
/// - token 汇总与 UI 展开态
class AgentConversationTimelineStore {
  AgentConversationTimelineStore() {
    _seedInitialStandbyTimeline();
  }

  static const int _historyPageSize = 3;
  static const AgentConversationMessage welcomeMessage =
      AgentConversationMessage(
        id: 'welcome',
        role: AgentMessageRole.agent,
        text:
            'Ready. Select a file or send a request to start an Agent thread.',
      );

  /// welcome 消息和回合外系统消息所属的 standby 分组 id。
  static const String standbyTurnId = '__standby__';

  final List<AgentConversationMessage> _messages = <AgentConversationMessage>[
    welcomeMessage,
  ];
  final List<AgentToolCall> _toolCalls = <AgentToolCall>[];
  final List<AgentPermissionRequest> _permissionRequests =
      <AgentPermissionRequest>[];
  final List<AgentTimelineEntry> _timelineEntries = <AgentTimelineEntry>[
    AgentMessageTimelineEntry(message: welcomeMessage),
  ];
  final List<String> _timelineEntryTurnIds = <String>[standbyTurnId];
  final Map<String, String> _turnIdsByTimelineEntryId = <String, String>{};
  final List<String> _historicalTurnOrder = <String>[];
  final List<String> _liveTurnOrder = <String>[];
  final Map<String, AgentConversationTurnState> _turnGroups =
      <String, AgentConversationTurnState>{};
  final Map<String, int> _messageIndexesByProviderId = <String, int>{};
  final Set<String> _expandedToolCallIds = <String>{};
  final Set<String> _expandedPlanMessageIds = <String>{};
  final Set<String> _expandedCommandGroupIds = <String>{};
  final Set<String> _expandedFileEditItemIds = <String>{};
  final ValueNotifier<AgentConversationTurnState?> _liveTurnNotifier =
      ValueNotifier<AgentConversationTurnState?>(null);

  String? currentTurnGroupId;
  String? _pendingTurnGroupId;
  int _visibleHistoryStartIndex = 0;

  List<AgentConversationMessage> get messages =>
      List<AgentConversationMessage>.unmodifiable(_messages);

  List<AgentToolCall> get toolCalls =>
      List<AgentToolCall>.unmodifiable(_toolCalls);

  List<AgentPermissionRequest> get permissionRequests =>
      List<AgentPermissionRequest>.unmodifiable(_permissionRequests);

  List<AgentTimelineEntry> get timelineEntries =>
      List<AgentTimelineEntry>.unmodifiable(_timelineEntries);

  /// 按出现顺序排列的 turn 分组，每组携带自己的消息体列表。
  ///
  /// 历史只显示当前可见窗口内的 turn；live turn 和 standby 分组始终可见。
  List<AgentConversationTurnGroup> get conversationTurns {
    final visibleTurnIds = <String>[
      if (standbyTurnState case final standby? when standby.entries.isNotEmpty)
        standby.id,
      for (final turn in visibleHistoryTurnStates) turn.id,
      if (liveTurnState case final live?) live.id,
    ];
    return List<AgentConversationTurnGroup>.unmodifiable(
      <AgentConversationTurnGroup>[
        for (final turnId in visibleTurnIds) _turnGroupSnapshot(turnId),
      ],
    );
  }

  /// 当前分页窗口内的历史 turn 集合，不包含 standby/live turn。
  List<AgentConversationTurnGroup> get visibleHistoryTurns =>
      List<AgentConversationTurnGroup>.unmodifiable(
        <AgentConversationTurnGroup>[
          for (final turn in visibleHistoryTurnStates) turn.snapshot(),
        ],
      );

  AgentConversationTurnState? get standbyTurnState =>
      _turnGroups[standbyTurnId];

  List<AgentConversationTurnState> get visibleHistoryTurnStates =>
      List<AgentConversationTurnState>.unmodifiable(
        _historicalTurnOrder
            .skip(_visibleHistoryStartIndex)
            .map((turnId) => _turnGroups[turnId])
            .whereType<AgentConversationTurnState>(),
      );

  AgentConversationTurnState? get liveTurnState => _liveTurnNotifier.value;

  ValueListenable<AgentConversationTurnState?> get liveTurnListenable =>
      _liveTurnNotifier;

  bool get hasOlderTurns => _visibleHistoryStartIndex > 0;

  String? get pendingTurnGroupId => _pendingTurnGroupId;

  /// 当前 live turn 的 token 用量，用于标题栏的回合级展示。
  AgentTokenUsage? get currentTurnTokenUsage {
    final runningTurnId = selectedRunningTurnId;
    if (runningTurnId == null) {
      return null;
    }
    return _turnGroups[runningTurnId]?.tokenUsage;
  }

  /// 当前 thread 下所有 turn 的累计 token 用量，用于标题栏右侧展示总成本。
  AgentTokenUsage? get currentThreadTokenUsage {
    int? inputTokens;
    int? cachedInputTokens;
    int? outputTokens;
    int? reasoningOutputTokens;
    int? totalTokens;

    for (final turn in _turnGroups.values) {
      if (turn.isStandby) {
        continue;
      }
      final usage = turn.tokenUsage;
      if (usage == null) {
        continue;
      }
      inputTokens = _sumOptionalInt(inputTokens, usage.inputTokens);
      cachedInputTokens = _sumOptionalInt(
        cachedInputTokens,
        usage.cachedInputTokens,
      );
      outputTokens = _sumOptionalInt(outputTokens, usage.outputTokens);
      reasoningOutputTokens = _sumOptionalInt(
        reasoningOutputTokens,
        usage.reasoningOutputTokens,
      );
      totalTokens = _sumOptionalInt(totalTokens, usage.totalTokens);
    }

    if (inputTokens == null &&
        cachedInputTokens == null &&
        outputTokens == null &&
        reasoningOutputTokens == null &&
        totalTokens == null) {
      return null;
    }

    return AgentTokenUsage(
      inputTokens: inputTokens,
      cachedInputTokens: cachedInputTokens,
      outputTokens: outputTokens,
      reasoningOutputTokens: reasoningOutputTokens,
      totalTokens: totalTokens,
    );
  }

  bool get isTurnRunning => selectedRunningTurnId != null;

  String? get selectedRunningTurnId => _selectedRunningTurnId();

  bool isToolCallExpanded(String toolCallId) {
    return _expandedToolCallIds.contains(toolCallId);
  }

  bool isPlanMessageExpanded(String messageId) {
    return _expandedPlanMessageIds.contains(messageId);
  }

  bool isCommandGroupExpanded(String commandGroupId) {
    return _expandedCommandGroupIds.contains(commandGroupId);
  }

  bool isFileEditItemExpanded(String fileEditItemId) {
    return _expandedFileEditItemIds.contains(fileEditItemId);
  }

  bool hasTurn(String turnId) {
    return _turnGroups.containsKey(turnId);
  }

  /// 扩大历史窗口，一次多显示固定页数的更早 turn。
  bool loadOlderTurns() {
    final nextStartIndex = math.max(
      0,
      _visibleHistoryStartIndex - _historyPageSize,
    );
    if (nextStartIndex == _visibleHistoryStartIndex) {
      return false;
    }
    _visibleHistoryStartIndex = nextStartIndex;
    return true;
  }

  void toggleToolCall(String toolCallId) {
    if (!_expandedToolCallIds.add(toolCallId)) {
      _expandedToolCallIds.remove(toolCallId);
    }
  }

  void togglePlanMessage(String messageId) {
    if (!_expandedPlanMessageIds.add(messageId)) {
      _expandedPlanMessageIds.remove(messageId);
    }
  }

  void toggleCommandGroup(String commandGroupId) {
    if (!_expandedCommandGroupIds.add(commandGroupId)) {
      _expandedCommandGroupIds.remove(commandGroupId);
    }
  }

  void toggleFileEditItem(String fileEditItemId) {
    if (!_expandedFileEditItemIds.add(fileEditItemId)) {
      _expandedFileEditItemIds.remove(fileEditItemId);
    }
  }

  /// 新回合启动前，先创建一个临时分组承载用户消息与后续增量。
  String startPendingLiveTurn() {
    final pendingTurnId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    _pendingTurnGroupId = pendingTurnId;
    currentTurnGroupId = pendingTurnId;
    _turnStateFor(
      pendingTurnId,
      isStandby: false,
      isHistorical: false,
    ).updateMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: DateTime.now(),
    );
    return pendingTurnId;
  }

  void clearPendingTurnGroupId() {
    _pendingTurnGroupId = null;
  }

  String? selectedCancelableTurnId() {
    final turnId = selectedRunningTurnId;
    if (turnId == null || turnId == _pendingTurnGroupId) {
      return null;
    }
    return turnId;
  }

  void syncLiveTurnBinding() {
    final nextLiveTurn = _currentLiveTurnState();
    if (identical(_liveTurnNotifier.value, nextLiveTurn)) {
      return;
    }
    _liveTurnNotifier.value = nextLiveTurn;
  }

  void clearConversation() {
    for (final turn in _turnGroups.values.toList()) {
      turn.dispose();
    }
    _messages.clear();
    _toolCalls.clear();
    _permissionRequests.clear();
    _timelineEntries.clear();
    _timelineEntryTurnIds.clear();
    _turnIdsByTimelineEntryId.clear();
    _historicalTurnOrder.clear();
    _liveTurnOrder.clear();
    _turnGroups.clear();
    _liveTurnNotifier.value = null;
    _messageIndexesByProviderId.clear();
    _expandedToolCallIds.clear();
    _expandedPlanMessageIds.clear();
    _expandedCommandGroupIds.clear();
    _expandedFileEditItemIds.clear();
    currentTurnGroupId = null;
    _pendingTurnGroupId = null;
    _visibleHistoryStartIndex = 0;
  }

  /// 清空当前对话，并恢复到仅包含 welcome 消息的初始待机态。
  void resetToWelcomeState() {
    clearConversation();
    _messages.add(welcomeMessage);
    _timelineEntries.add(AgentMessageTimelineEntry(message: welcomeMessage));
    _timelineEntryTurnIds.add(standbyTurnId);
    _seedInitialStandbyTimeline();
  }

  void applyHistorySnapshot(
    AgentThreadHistorySnapshot history,
    AgentThreadSummary thread,
  ) {
    clearConversation();
    if (history.turns.isEmpty) {
      addConversationMessage(
        AgentConversationMessage(
          id: 'selected-${DateTime.now().microsecondsSinceEpoch}',
          role: AgentMessageRole.system,
          text: 'Selected thread: ${thread.displayName}',
        ),
      );
      return;
    }

    String? runningTurnId;
    for (final turn in history.turns) {
      final isRunningTurn = turn.status == AgentHistoryTurnStatus.running;
      _registerHistoryTurn(turn, asLive: isRunningTurn);
      currentTurnGroupId = turn.id;
      if (isRunningTurn) {
        runningTurnId = turn.id;
      }
      for (final entry in turn.entries) {
        switch (entry) {
          case AgentHistoryMessageEntry():
            _messageIndexesByProviderId[entry.id] = _messages.length;
            addConversationMessage(
              AgentConversationMessage(
                id: entry.id,
                role: entry.role,
                text: entry.text,
                kind: _messageKindFromRaw(role: entry.role, raw: entry.raw),
                phase: entry.phase,
                status: entry.status,
                duration: entry.duration,
                raw: entry.raw,
              ),
            );
          case AgentHistoryToolEntry():
            upsertToolCall(entry.toolCall);
          case AgentHistoryEventEntry():
            appendTimelineEntry(AgentHistoryEventTimelineEntry(event: entry));
        }
      }
    }
    _visibleHistoryStartIndex = _defaultVisibleHistoryStartIndexForLength(
      _historicalTurnOrder.length,
    );
    currentTurnGroupId = runningTurnId;
    syncLiveTurnBinding();
  }

  String addConversationMessage(AgentConversationMessage message) {
    _messages.add(message);
    return appendTimelineEntry(AgentMessageTimelineEntry(message: message));
  }

  /// 追加时间线条目，并打上当前 turn 分组 id。
  String appendTimelineEntry(AgentTimelineEntry entry) {
    final turnId = currentTurnGroupId ?? standbyTurnId;
    _timelineEntries.add(entry);
    _timelineEntryTurnIds.add(turnId);
    _turnIdsByTimelineEntryId[entry.id] = turnId;
    _turnStateFor(
      turnId,
      isStandby: turnId == standbyTurnId,
      isHistorical:
          currentTurnGroupId != null &&
          _historicalTurnOrder.contains(turnId) &&
          !_liveTurnOrder.contains(turnId),
    ).appendEntry(entry);
    return turnId;
  }

  String? replaceTimelineMessage(AgentConversationMessage message) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentMessageTimelineEntry && entry.message.id == message.id,
    );
    if (index == -1) {
      return null;
    }
    final updatedEntry = AgentMessageTimelineEntry(message: message);
    _timelineEntries[index] = updatedEntry;
    final turnId = _timelineEntryTurnIds[index];
    _turnGroups[turnId]?.replaceEntry(updatedEntry);
    return turnId;
  }

  String? replaceTimelineTool(AgentToolCall toolCall) {
    final index = _timelineEntries.indexWhere(
      (entry) =>
          entry is AgentToolTimelineEntry && entry.toolCall.id == toolCall.id,
    );
    if (index == -1) {
      return null;
    }
    final updatedEntry = AgentToolTimelineEntry(toolCall: toolCall);
    _timelineEntries[index] = updatedEntry;
    final turnId = _timelineEntryTurnIds[index];
    _turnGroups[turnId]?.replaceEntry(updatedEntry);
    return turnId;
  }

  String addPermissionRequest(AgentPermissionRequest request) {
    _permissionRequests.add(request);
    return appendTimelineEntry(AgentPermissionTimelineEntry(request: request));
  }

  void removePermissionRequest(String requestId) {
    _permissionRequests.removeWhere((item) => item.id == requestId);
    var index = 0;
    while (index < _timelineEntries.length) {
      final entry = _timelineEntries[index];
      if (entry is AgentPermissionTimelineEntry &&
          entry.request.id == requestId) {
        final turnId = _timelineEntryTurnIds[index];
        _timelineEntries.removeAt(index);
        _timelineEntryTurnIds.removeAt(index);
        _turnIdsByTimelineEntryId.remove(entry.id);
        _turnGroups[turnId]?.removeEntry(entry.id);
      } else {
        index += 1;
      }
    }
  }

  /// 合并流式消息增量。
  ///
  /// 同一个 provider messageId 首次出现时创建气泡，后续 delta 追加到同一条消息。
  void appendMessageDelta(AgentMessageDeltaEvent event) {
    final existingIndex = _messageIndexesByProviderId[event.messageId];
    final kind = _messageKindFromRaw(role: event.role, raw: event.raw);
    if (existingIndex == null) {
      _messageIndexesByProviderId[event.messageId] = _messages.length;
      addConversationMessage(
        AgentConversationMessage(
          id: event.messageId,
          role: event.role,
          text: event.delta,
          kind: kind,
          phase: event.phase,
          status: event.status,
          duration: event.duration,
          raw: event.raw,
        ),
      );
      return;
    }
    final existing = _messages[existingIndex];
    final updated = existing.copyWith(
      text: '${existing.text}${event.delta}',
      kind: kind == AgentConversationMessageKind.plan ? kind : existing.kind,
      phase: event.phase,
      status: event.status,
      duration: event.duration,
      raw: event.raw.isEmpty ? null : event.raw,
    );
    _messages[existingIndex] = updated;
    replaceTimelineMessage(updated);
  }

  /// 用 completed item 通知更新已有消息 metadata。
  void updateMessage(AgentMessageUpdatedEvent event) {
    final existingIndex = _messageIndexesByProviderId[event.messageId];
    final role = event.role ?? AgentMessageRole.agent;
    final kind = _messageKindFromRaw(role: role, raw: event.raw);
    if (existingIndex == null) {
      final text = event.text?.trim();
      if (text == null || text.isEmpty) {
        return;
      }
      _messageIndexesByProviderId[event.messageId] = _messages.length;
      addConversationMessage(
        AgentConversationMessage(
          id: event.messageId,
          role: role,
          text: text,
          kind: kind,
          phase: event.phase,
          status: event.status,
          duration: event.duration,
          raw: event.raw,
        ),
      );
      return;
    }

    final existing = _messages[existingIndex];
    final updated = existing.copyWith(
      role: event.role,
      text: event.text,
      kind: kind == AgentConversationMessageKind.plan ? kind : existing.kind,
      phase: event.phase,
      status: event.status,
      duration: event.duration,
      raw: event.raw.isEmpty ? null : event.raw,
    );
    _messages[existingIndex] = updated;
    replaceTimelineMessage(updated);
  }

  /// 将 Agent 计划更新渲染为可折叠的 markdown 消息。
  void upsertPlanMessage(AgentPlanUpdatedEvent event) {
    final messageId = '${event.turnId ?? 'current'}-plan';
    final message = AgentConversationMessage(
      id: messageId,
      role: AgentMessageRole.agent,
      text: _planMarkdownFromEntries(event.entries),
      kind: AgentConversationMessageKind.plan,
      raw: <String, Object?>{
        'type': 'plan',
        'entries': <Map<String, String?>>[
          for (final entry in event.entries)
            <String, String?>{
              'content': entry.content,
              'status': entry.status,
              'priority': entry.priority,
            },
        ],
      },
    );
    final existingIndex = _messageIndexesByProviderId[messageId];
    if (existingIndex == null) {
      _messageIndexesByProviderId[messageId] = _messages.length;
      addConversationMessage(message);
      return;
    }
    _messages[existingIndex] = message;
    replaceTimelineMessage(message);
  }

  /// 插入或更新工具卡片。
  void upsertToolCall(AgentToolCall toolCall) {
    final index = _toolCalls.indexWhere((item) => item.id == toolCall.id);
    if (index == -1) {
      _toolCalls.add(toolCall);
      appendTimelineEntry(AgentToolTimelineEntry(toolCall: toolCall));
      return;
    }
    _toolCalls[index] = toolCall;
    replaceTimelineTool(toolCall);
  }

  /// turn 真正启动时，把 sendMessage 建立的临时分组重命名为真实 turn id，
  /// 并记录运行状态与起始时间。后续条目都会归到该分组。
  void beginLiveTurnGroup(AgentTurn turn) {
    final pendingId = _pendingTurnGroupId;
    if (pendingId != null && pendingId != turn.id) {
      _renameTurnGroup(pendingId, turn.id);
    }
    currentTurnGroupId = turn.id;
    _pendingTurnGroupId = null;
    final turnState = _turnStateFor(
      turn.id,
      isStandby: false,
      isHistorical: false,
    );
    turnState.updateMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: turnState.startedAt ?? DateTime.now(),
      completedAt: turnState.completedAt,
      duration: turnState.duration,
      tokenUsage: turnState.tokenUsage,
    );
  }

  /// turn 结束时更新分组元数据；后续条目回到 standby 分组。
  ///
  /// [status] 为回合终态（完成/中断/失败）；[duration] 优先使用 provider
  /// 上报的耗时，缺失时按本地开始时间估算。
  void completeLiveTurnGroup(
    String turnId, {
    AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
    Duration? duration,
  }) {
    final turnState = _turnGroups[turnId];
    if (turnState == null) {
      currentTurnGroupId = null;
      _pendingTurnGroupId = null;
      return;
    }
    final oldHistoryLength = _historicalTurnOrder.length;
    final oldDefaultStartIndex = _defaultVisibleHistoryStartIndexForLength(
      oldHistoryLength,
    );
    final historyExpanded = _visibleHistoryStartIndex < oldDefaultStartIndex;
    final previousVisibleCount = oldHistoryLength - _visibleHistoryStartIndex;
    final completedAt = DateTime.now();
    turnState.updateMetadata(
      status: status,
      startedAt: turnState.startedAt,
      completedAt: completedAt,
      duration:
          duration ??
          (turnState.startedAt == null
              ? null
              : completedAt.difference(turnState.startedAt!)),
      tokenUsage: turnState.tokenUsage,
    );
    _promoteTurnToHistorical(turnId);
    if (historyExpanded) {
      _visibleHistoryStartIndex = math.max(
        0,
        _historicalTurnOrder.length - previousVisibleCount,
      );
    } else {
      _visibleHistoryStartIndex = _defaultVisibleHistoryStartIndexForLength(
        _historicalTurnOrder.length,
      );
    }
    currentTurnGroupId = null;
  }

  /// 用 provider 上报的 token 用量更新对应回合分组的元数据。
  ///
  /// 优先按事件中的 turnId 定位分组；缺失时回退到当前运行回合。
  void updateTurnTokenUsage(AgentTokenUsageEvent event) {
    final pendingId = _pendingTurnGroupId;
    if (event.turnId != null &&
        pendingId != null &&
        !_turnGroups.containsKey(event.turnId) &&
        _turnGroups.containsKey(pendingId)) {
      _renameTurnGroup(pendingId, event.turnId!);
      _pendingTurnGroupId = null;
    }
    final turnId = event.turnId ?? selectedRunningTurnId ?? currentTurnGroupId;
    if (turnId == null) {
      return;
    }
    final turnState = _turnStateFor(
      turnId,
      isStandby: false,
      isHistorical: false,
    );
    turnState.updateMetadata(
      status: turnState.status,
      startedAt: turnState.startedAt,
      completedAt: turnState.completedAt,
      duration: turnState.duration,
      tokenUsage: event.tokenUsage,
    );
  }

  bool isHistoryTurnId(String turnId) {
    return turnId == standbyTurnId || _historicalTurnOrder.contains(turnId);
  }

  bool isLiveTurnId(String turnId) {
    return _liveTurnOrder.contains(turnId) || currentTurnGroupId == turnId;
  }

  void dispose() {
    clearConversation();
    _liveTurnNotifier.dispose();
  }

  void _seedInitialStandbyTimeline() {
    final standbyGroup = _turnStateFor(
      standbyTurnId,
      isStandby: true,
      isHistorical: false,
    );
    standbyGroup.appendEntry(_timelineEntries.single);
    _turnIdsByTimelineEntryId[_timelineEntries.single.id] = standbyTurnId;
  }

  void _renameTurnGroup(String oldId, String newId) {
    for (var index = 0; index < _timelineEntryTurnIds.length; index += 1) {
      if (_timelineEntryTurnIds[index] == oldId) {
        _timelineEntryTurnIds[index] = newId;
      }
    }
    final historicalIndex = _historicalTurnOrder.indexOf(oldId);
    if (historicalIndex != -1) {
      _historicalTurnOrder[historicalIndex] = newId;
    }
    final liveIndex = _liveTurnOrder.indexOf(oldId);
    if (liveIndex != -1) {
      _liveTurnOrder[liveIndex] = newId;
    }
    final group = _turnGroups.remove(oldId);
    if (group != null) {
      group.rename(newId);
      _turnGroups[newId] = group;
      for (final entry in group.entries) {
        _turnIdsByTimelineEntryId[entry.id] = newId;
      }
    }
    if (currentTurnGroupId == oldId) {
      currentTurnGroupId = newId;
    }
    if (_pendingTurnGroupId == oldId) {
      _pendingTurnGroupId = newId;
    }
  }

  void _registerHistoryTurn(AgentHistoryTurn turn, {required bool asLive}) {
    _turnStateFor(
      turn.id,
      isStandby: false,
      isHistorical: !asLive,
    ).updateMetadata(
      status: turn.status,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      duration: turn.duration,
      tokenUsage: turn.tokenUsage,
    );
  }

  AgentConversationTurnState _turnStateFor(
    String turnId, {
    required bool isStandby,
    required bool isHistorical,
  }) {
    final existing = _turnGroups[turnId];
    if (existing != null) {
      if (!isStandby) {
        if (isHistorical) {
          _promoteTurnToHistorical(turnId);
        } else {
          _promoteTurnToLive(turnId);
        }
      }
      return existing;
    }
    if (!isStandby) {
      if (isHistorical) {
        _promoteTurnToHistorical(turnId);
      } else {
        _promoteTurnToLive(turnId);
      }
    }
    final created = AgentConversationTurnState(
      id: turnId,
      isStandby: isStandby,
    );
    _turnGroups[turnId] = created;
    return created;
  }

  AgentConversationTurnGroup _turnGroupSnapshot(String turnId) {
    final group = _turnGroups[turnId];
    if (group == null) {
      return AgentConversationTurnGroup(
        id: turnId,
        entries: const <AgentTimelineEntry>[],
        isStandby: turnId == standbyTurnId,
      );
    }
    return group.snapshot();
  }

  AgentConversationTurnState? _currentLiveTurnState() {
    final activeTurnGroupId = currentTurnGroupId;
    if (activeTurnGroupId != null) {
      final current = _turnGroups[activeTurnGroupId];
      if (current != null && current.isRunning) {
        return current;
      }
    }
    final runningTurnId = _selectedRunningTurnId();
    if (runningTurnId == null) {
      return null;
    }
    return _turnGroups[runningTurnId];
  }

  void _promoteTurnToLive(String turnId) {
    _historicalTurnOrder.remove(turnId);
    if (!_liveTurnOrder.contains(turnId)) {
      _liveTurnOrder.add(turnId);
    }
  }

  void _promoteTurnToHistorical(String turnId) {
    _liveTurnOrder.remove(turnId);
    if (!_historicalTurnOrder.contains(turnId)) {
      _historicalTurnOrder.add(turnId);
    }
  }

  int _defaultVisibleHistoryStartIndexForLength(int historyLength) {
    return math.max(0, historyLength - _historyPageSize);
  }

  String? _selectedRunningTurnId() {
    final activeTurnGroupId = currentTurnGroupId;
    if (_turnGroups[activeTurnGroupId]?.status ==
        AgentHistoryTurnStatus.running) {
      return activeTurnGroupId;
    }

    for (var index = _liveTurnOrder.length - 1; index >= 0; index -= 1) {
      final turnId = _liveTurnOrder[index];
      if (_turnGroups[turnId]?.status == AgentHistoryTurnStatus.running) {
        return turnId;
      }
    }

    for (var index = _historicalTurnOrder.length - 1; index >= 0; index -= 1) {
      final turnId = _historicalTurnOrder[index];
      if (_turnGroups[turnId]?.status == AgentHistoryTurnStatus.running) {
        return turnId;
      }
    }

    for (final entry in _turnGroups.entries) {
      if (entry.value.status == AgentHistoryTurnStatus.running) {
        return entry.key;
      }
    }
    return null;
  }
}

int? _sumOptionalInt(int? left, int? right) {
  if (right == null) {
    return left;
  }
  return (left ?? 0) + right;
}

AgentConversationMessageKind _messageKindFromRaw({
  required AgentMessageRole role,
  required Map<String, Object?> raw,
}) {
  if (role != AgentMessageRole.agent) {
    return AgentConversationMessageKind.regular;
  }
  return _rawContainsPlanType(raw)
      ? AgentConversationMessageKind.plan
      : AgentConversationMessageKind.regular;
}

bool _rawContainsPlanType(Map<String, Object?> raw) {
  return _normalizedMessageType(_stringFromObject(raw['type'])) == 'plan' ||
      _normalizedMessageType(
            _stringFromObject(_mapFromObject(raw['item'])['type']),
          ) ==
          'plan' ||
      _normalizedMessageType(
            _stringFromObject(_mapFromObject(raw['payload'])['type']),
          ) ==
          'plan' ||
      _normalizedMessageType(
            _stringFromObject(
              _mapFromObject(_mapFromObject(raw['payload'])['item'])['type'],
            ),
          ) ==
          'plan';
}

String _planMarkdownFromEntries(List<AgentPlanEntry> entries) {
  if (entries.isEmpty) {
    return 'Plan';
  }
  return entries
      .map((entry) {
        final marker = switch (_normalizedMessageType(entry.status)) {
          'completed' || 'complete' || 'done' => '- [x]',
          'pending' || 'inprogress' || 'running' || 'started' => '- [ ]',
          _ => '-',
        };
        return '$marker ${entry.content}';
      })
      .join('\n');
}

String? _normalizedMessageType(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
}

String? _stringFromObject(Object? value) {
  return value is String ? value : null;
}

Map<String, Object?> _mapFromObject(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      map[key] = entry.value;
    }
  }
  return map;
}

/// Agent 消息在 UI 中的展示类型。
enum AgentConversationMessageKind { regular, plan }

/// Agent 面板中的单条对话消息。
class AgentConversationMessage {
  const AgentConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    this.kind = AgentConversationMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
    this.raw = const <String, Object?>{},
  });

  final String id;
  final AgentMessageRole role;
  final String text;
  final AgentConversationMessageKind kind;
  final AgentMessagePhase? phase;
  final AgentMessageStatus? status;
  final Duration? duration;
  final Map<String, Object?> raw;

  bool get isPlan => kind == AgentConversationMessageKind.plan;

  bool get isCompletedCommentary {
    return role == AgentMessageRole.agent &&
        phase == AgentMessagePhase.commentary &&
        status == AgentMessageStatus.completed;
  }

  AgentConversationMessage copyWith({
    AgentMessageRole? role,
    String? text,
    AgentConversationMessageKind? kind,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
    Map<String, Object?>? raw,
  }) {
    return AgentConversationMessage(
      id: id,
      role: role ?? this.role,
      text: text ?? this.text,
      kind: kind ?? this.kind,
      phase: phase ?? this.phase,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      raw: raw ?? this.raw,
    );
  }
}

/// thread 打开阶段。
enum AgentThreadOpenPhase { idle, loadingHistory, openFailed }

/// Agent 面板的统一时间线条目。
sealed class AgentTimelineEntry {
  const AgentTimelineEntry({required this.id});

  /// UI 时间线中的稳定 id。
  final String id;
}

/// 时间线消息条目。
class AgentMessageTimelineEntry extends AgentTimelineEntry {
  AgentMessageTimelineEntry({required this.message})
    : super(id: 'message-${message.id}');

  final AgentConversationMessage message;
}

/// 时间线工具调用条目。
class AgentToolTimelineEntry extends AgentTimelineEntry {
  AgentToolTimelineEntry({required this.toolCall})
    : super(id: 'tool-${toolCall.id}');

  final AgentToolCall toolCall;
}

/// 时间线审批请求条目。
class AgentPermissionTimelineEntry extends AgentTimelineEntry {
  AgentPermissionTimelineEntry({required this.request})
    : super(id: 'permission-${request.id}');

  final AgentPermissionRequest request;
}

/// 时间线历史事件条目。
class AgentHistoryEventTimelineEntry extends AgentTimelineEntry {
  AgentHistoryEventTimelineEntry({required this.event})
    : super(id: 'history-event-${event.id}');

  final AgentHistoryEventEntry event;
}

/// Agent 面板按 turn 聚合后的分组，供 UI 分回合渲染。
class AgentConversationTurnGroup {
  const AgentConversationTurnGroup({
    required this.id,
    required this.entries,
    required this.isStandby,
    this.status,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.tokenUsage,
  });

  final String id;
  final List<AgentTimelineEntry> entries;
  final bool isStandby;
  final AgentHistoryTurnStatus? status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final AgentTokenUsage? tokenUsage;
}

/// 单个 turn 的运行时状态。
///
/// 历史区使用快照渲染；live 区直接监听这个对象，避免流式增量时整页重建。
class AgentConversationTurnState extends ChangeNotifier {
  AgentConversationTurnState({required this.id, required this.isStandby});

  String id;
  final bool isStandby;
  final List<AgentTimelineEntry> _entries = <AgentTimelineEntry>[];
  AgentHistoryTurnStatus? _status;
  DateTime? _startedAt;
  DateTime? _completedAt;
  Duration? _duration;
  AgentTokenUsage? _tokenUsage;
  bool _dirty = false;

  List<AgentTimelineEntry> get entries => UnmodifiableListView(_entries);

  AgentHistoryTurnStatus? get status => _status;

  DateTime? get startedAt => _startedAt;

  DateTime? get completedAt => _completedAt;

  Duration? get duration => _duration;

  AgentTokenUsage? get tokenUsage => _tokenUsage;

  bool get isRunning => _status == AgentHistoryTurnStatus.running;

  void appendEntry(AgentTimelineEntry entry) {
    _entries.add(entry);
    _dirty = true;
  }

  void replaceEntry(AgentTimelineEntry entry) {
    final index = _entries.indexWhere((item) => item.id == entry.id);
    if (index == -1) {
      return;
    }
    _entries[index] = entry;
    _dirty = true;
  }

  void removeEntry(String entryId) {
    final removedCount = _entries.length;
    _entries.removeWhere((entry) => entry.id == entryId);
    if (_entries.length != removedCount) {
      _dirty = true;
    }
  }

  void rename(String nextId) {
    if (id == nextId) {
      return;
    }
    id = nextId;
    _dirty = true;
  }

  void updateMetadata({
    AgentHistoryTurnStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    Duration? duration,
    AgentTokenUsage? tokenUsage,
  }) {
    _status = status;
    _startedAt = startedAt;
    _completedAt = completedAt;
    _duration = duration;
    _tokenUsage = tokenUsage;
    _dirty = true;
  }

  void markDirty() {
    _dirty = true;
  }

  void flushNow() {
    if (!_dirty) {
      return;
    }
    _dirty = false;
    notifyListeners();
  }

  AgentConversationTurnGroup snapshot() {
    return AgentConversationTurnGroup(
      id: id,
      entries: List<AgentTimelineEntry>.unmodifiable(_entries),
      isStandby: isStandby,
      status: _status,
      startedAt: _startedAt,
      completedAt: _completedAt,
      duration: _duration,
      tokenUsage: _tokenUsage,
    );
  }
}
