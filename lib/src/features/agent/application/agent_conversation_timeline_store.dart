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
  final List<AgentPlanApprovalRequest> _planApprovalRequests =
      <AgentPlanApprovalRequest>[];
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

  /// reasoning itemId → 摘要/原文双缓冲，供流式 delta 聚合。
  final Map<String, _ReasoningStreamBuffers> _reasoningBuffersByItemId =
      <String, _ReasoningStreamBuffers>{};
  final Set<String> _expandedToolCallIds = <String>{};
  final Set<String> _expandedPlanMessageIds = <String>{};
  final Set<String> _expandedCommandGroupIds = <String>{};
  final Set<String> _expandedFileEditItemIds = <String>{};
  final ValueNotifier<AgentConversationTurnState?> _liveTurnNotifier =
      ValueNotifier<AgentConversationTurnState?>(null);

  String? currentTurnGroupId;
  String? _pendingTurnGroupId;
  int _visibleHistoryStartIndex = 0;

  /// 当前会话的累计 token 用量（直接来自 Codex `total` breakdown）。
  AgentTokenUsage? _threadTokenUsage;

  /// 当前 live turn 主活动段；无 running turn 时为 idle。
  AgentTurnActivitySnapshot _currentActivity = AgentTurnActivitySnapshot.idle;

  /// 主活动段自上次读取后是否变化（供 ViewModel 决定是否刷新 header）。
  bool _activityDirty = false;

  List<AgentConversationMessage> get messages =>
      List<AgentConversationMessage>.unmodifiable(_messages);

  List<AgentToolCall> get toolCalls =>
      List<AgentToolCall>.unmodifiable(_toolCalls);

  List<AgentPermissionRequest> get permissionRequests =>
      List<AgentPermissionRequest>.unmodifiable(_permissionRequests);

  List<AgentPlanApprovalRequest> get planApprovalRequests =>
      List<AgentPlanApprovalRequest>.unmodifiable(_planApprovalRequests);

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

  /// 当前 live turn 的 token 用量（相对上一 turn 的增量）。
  AgentTokenUsage? get currentTurnTokenUsage {
    final runningTurnId = selectedRunningTurnId;
    if (runningTurnId == null) {
      return null;
    }
    return _turnGroups[runningTurnId]?.tokenUsage;
  }

  /// 当前 thread 的会话累计 token 用量，直接取自最新上报，不再对各 turn 求和。
  AgentTokenUsage? get currentThreadTokenUsage => _threadTokenUsage;

  /// 当前 thread 最近一次请求的 token 用量。
  ///
  /// 优先使用最新 turn 上报的 `last_*` breakdown；若 provider 没有拆分
  /// `last_token_usage`，则回退到该 turn 的增量 breakdown。
  AgentTokenUsage? get currentThreadLastTokenUsage {
    final usage = _latestAvailableTurnTokenUsage();
    if (usage == null) {
      return null;
    }
    final normalized = AgentTokenUsage(
      inputTokens: usage.lastInputTokens ?? usage.inputTokens,
      cachedInputTokens: usage.lastCachedInputTokens ?? usage.cachedInputTokens,
      outputTokens: usage.lastOutputTokens ?? usage.outputTokens,
      totalTokens: usage.lastTotalTokens ?? usage.totalTokens,
      modelContextWindow:
          usage.modelContextWindow ?? _threadTokenUsage?.modelContextWindow,
    );
    if (normalized.inputTokens == null &&
        normalized.cachedInputTokens == null &&
        normalized.outputTokens == null &&
        normalized.totalTokens == null) {
      return null;
    }
    return normalized;
  }

  bool get isTurnRunning => selectedRunningTurnId != null;

  String? get selectedRunningTurnId => _selectedRunningTurnId();

  /// 当前主活动段快照。
  AgentTurnActivitySnapshot get currentActivity => _currentActivity;

  /// 当前 running turn 的本地开始时间。
  DateTime? get currentTurnStartedAt {
    final turnId = selectedRunningTurnId;
    if (turnId == null) {
      return null;
    }
    return _turnGroups[turnId]?.startedAt;
  }

  /// 读取并清除活动段脏标记。
  bool takeActivityDirty() {
    final dirty = _activityDirty;
    _activityDirty = false;
    return dirty;
  }

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

  AgentTokenUsage? _latestAvailableTurnTokenUsage() {
    for (final turnId in _liveTurnOrder.reversed) {
      final usage = _turnGroups[turnId]?.tokenUsage;
      if (usage != null) {
        return usage;
      }
    }
    for (final turnId in _historicalTurnOrder.reversed) {
      final usage = _turnGroups[turnId]?.tokenUsage;
      if (usage != null) {
        return usage;
      }
    }
    return null;
  }

  bool hasTurn(String turnId) {
    return _turnGroups.containsKey(turnId);
  }

  /// 返回指定消息所属 turn 的前一个历史 turn，供“从此前分支”使用。
  ///
  /// Codex 0.144.5 的 `lastTurnId` 是包含式边界，因此编辑某个 turn 的用户消息
  /// 时必须传它的前一 turn，才能让新分支排除待替换的整回合。
  String? forkBoundaryBeforeMessage(String messageId) {
    final targetTurnId = _turnIdsByTimelineEntryId['message-$messageId'];
    if (targetTurnId == null) {
      return null;
    }
    final targetIndex = _historicalTurnOrder.indexOf(targetTurnId);
    if (targetIndex <= 0) {
      return null;
    }
    return _historicalTurnOrder[targetIndex - 1];
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
  ///
  /// [modelConfig] 为本回合发送时的模型配置快照，供终态 footer 展示。
  String startPendingLiveTurn({AgentTurnModelConfig? modelConfig}) {
    // 用户已开始真实对话，移除初始 Ready 占位文案。
    _dismissWelcomeMessage();
    final pendingTurnId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    _pendingTurnGroupId = pendingTurnId;
    currentTurnGroupId = pendingTurnId;
    final startedAt = DateTime.now();
    _turnStateFor(
      pendingTurnId,
      isStandby: false,
      isHistorical: false,
    ).updateMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: startedAt,
      modelConfig: modelConfig,
    );
    _setActivity(AgentTurnActivityPhase.starting, turnStartedAt: startedAt);
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
    _planApprovalRequests.clear();
    _timelineEntries.clear();
    _timelineEntryTurnIds.clear();
    _turnIdsByTimelineEntryId.clear();
    _historicalTurnOrder.clear();
    _liveTurnOrder.clear();
    _turnGroups.clear();
    _liveTurnNotifier.value = null;
    _messageIndexesByProviderId.clear();
    _reasoningBuffersByItemId.clear();
    _expandedToolCallIds.clear();
    _expandedPlanMessageIds.clear();
    _expandedCommandGroupIds.clear();
    _expandedFileEditItemIds.clear();
    currentTurnGroupId = null;
    _pendingTurnGroupId = null;
    _visibleHistoryStartIndex = 0;
    _threadTokenUsage = null;
    _clearActivity();
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

    // Codex 历史：tokenUsage.total 是会话累计，注册时转成 turn 增量。
    // Grok 历史：tokenUsage 已是本回合绝对用量，直接挂到 turn，并累加会话总量。
    AgentTokenUsage? previousCumulative;
    String? runningTurnId;
    for (final turn in history.turns) {
      final isRunningTurn = turn.status == AgentHistoryTurnStatus.running;
      final usage = turn.tokenUsage;
      final AgentTokenUsage? turnDelta;
      if (usage != null && usage.hasCumulativeBreakdown) {
        if (turn.tokenUsageIsSessionCumulative) {
          turnDelta = usage.deltaFrom(previousCumulative);
          previousCumulative = usage;
          _threadTokenUsage = usage;
        } else {
          turnDelta = usage;
          previousCumulative = previousCumulative == null
              ? usage
              : previousCumulative.addCumulative(usage);
          _threadTokenUsage = previousCumulative;
        }
      } else {
        turnDelta = usage;
      }
      _registerHistoryTurn(turn, asLive: isRunningTurn, tokenUsage: turnDelta);
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
                localImagePaths: entry.localImagePaths,
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
    final existingIndex = _messages.indexWhere((item) => item.id == message.id);
    if (existingIndex != -1) {
      _messages[existingIndex] = message;
    } else {
      _messages.add(message);
    }
    return appendTimelineEntry(AgentMessageTimelineEntry(message: message));
  }

  /// 插入系统/警告类历史事件卡片（模型改道、弃用提示等）。
  String addHistoryEvent(AgentHistoryEventEntry event) {
    return appendTimelineEntry(AgentHistoryEventTimelineEntry(event: event));
  }

  /// 追加时间线条目，并打上当前 turn 分组 id。
  String appendTimelineEntry(AgentTimelineEntry entry) {
    // 任意真实内容进入时间线后，不再保留 Ready 占位。
    if (!_isWelcomeTimelineEntry(entry)) {
      _dismissWelcomeMessage();
    }
    // 同 id 条目已存在时替换，避免 Windows 时钟精度不足导致重复 key。
    final existingIndex = _timelineEntries.indexWhere(
      (item) => item.id == entry.id,
    );
    if (existingIndex != -1) {
      _timelineEntries[existingIndex] = entry;
      final turnId = _timelineEntryTurnIds[existingIndex];
      _turnIdsByTimelineEntryId[entry.id] = turnId;
      _turnGroups[turnId]?.replaceEntry(entry);
      return turnId;
    }
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

  String addPlanApprovalRequest(AgentPlanApprovalRequest request) {
    _planApprovalRequests.add(request);
    return appendTimelineEntry(
      AgentPlanApprovalTimelineEntry(request: request),
    );
  }

  /// 插入或更新回合级聚合 diff。
  ///
  /// 同一 `turnId` 只保留一条；空 diff 时移除已有条目。
  void upsertTurnDiff(AgentTurnDiffEvent event) {
    final entryId = 'turn-diff-${event.turnId}';
    final trimmed = event.diff.trim();
    if (trimmed.isEmpty) {
      _removeTimelineEntryById(entryId);
      return;
    }

    final entry = AgentTurnDiffTimelineEntry(
      turnId: event.turnId,
      sessionId: event.sessionId,
      diff: event.diff,
      raw: event.raw,
    );
    final index = _timelineEntries.indexWhere((item) => item.id == entryId);
    if (index != -1) {
      _timelineEntries[index] = entry;
      final turnId = _timelineEntryTurnIds[index];
      _turnGroups[turnId]?.replaceEntry(entry);
      return;
    }

    // 优先挂到通知指定的 turn 分组；若不存在则落到当前活跃分组。
    final previousCurrent = currentTurnGroupId;
    if (_turnGroups.containsKey(event.turnId)) {
      currentTurnGroupId = event.turnId;
    }
    appendTimelineEntry(entry);
    currentTurnGroupId = previousCurrent;
  }

  void _removeTimelineEntryById(String entryId) {
    final index = _timelineEntries.indexWhere((item) => item.id == entryId);
    if (index == -1) {
      return;
    }
    final entry = _timelineEntries[index];
    final turnId = _timelineEntryTurnIds[index];
    _timelineEntries.removeAt(index);
    _timelineEntryTurnIds.removeAt(index);
    _turnIdsByTimelineEntryId.remove(entry.id);
    _turnGroups[turnId]?.removeEntry(entry.id);
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

  void removePlanApprovalRequest(String requestId) {
    _planApprovalRequests.removeWhere((item) => item.id == requestId);
    var index = 0;
    while (index < _timelineEntries.length) {
      final entry = _timelineEntries[index];
      if (entry is AgentPlanApprovalTimelineEntry &&
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
  /// `item/plan/delta` 会带上 `type: plan`，首次创建时自动展开计划卡。
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
      if (kind == AgentConversationMessageKind.plan && event.delta.isNotEmpty) {
        _expandedPlanMessageIds.add(event.messageId);
      }
      _noteRespondingActivity(event.role);
      return;
    }
    final existing = _messages[existingIndex];
    final wasEmptyPlan =
        existing.isPlan &&
        existing.text.trim().isEmpty &&
        event.delta.isNotEmpty;
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
    if (wasEmptyPlan ||
        (kind == AgentConversationMessageKind.plan &&
            !existing.isPlan &&
            event.delta.isNotEmpty)) {
      _expandedPlanMessageIds.add(event.messageId);
    }
    _noteRespondingActivity(event.role);
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
    // item/completed 携带完整 reasoning 正文时，用其重置缓冲，避免后续
    // 迟到的 delta 基于过期片段继续拼接。
    if (toolCall.kind == AgentToolKind.think) {
      final content = toolCall.content ?? '';
      if (content.isNotEmpty) {
        _reasoningBuffersByItemId[toolCall.id] = _ReasoningStreamBuffers(
          summary: StringBuffer(content),
          text: StringBuffer(),
          hasSummary: true,
        );
      }
    }

    final index = _toolCalls.indexWhere((item) => item.id == toolCall.id);
    if (index == -1) {
      final stamped = _stampNewToolCall(toolCall);
      _toolCalls.add(stamped);
      appendTimelineEntry(AgentToolTimelineEntry(toolCall: stamped));
      // MCP 进度先于 item/started 到达时，有内容则自动展开便于观察。
      if (_isToolProgressAppend(stamped) &&
          stamped.content != null &&
          stamped.content!.isNotEmpty) {
        _expandedToolCallIds.add(stamped.id);
      }
      _noteToolActivity(stamped);
      return;
    }

    final existing = _toolCalls[index];
    final merged = _mergeToolCallUpdate(existing, toolCall);
    _toolCalls[index] = merged;
    replaceTimelineTool(merged);
    // 进度消息到达时展开卡片，便于观察 MCP 工具执行过程。
    if (_isToolProgressAppend(toolCall) &&
        merged.content != null &&
        merged.content!.isNotEmpty) {
      _expandedToolCallIds.add(toolCall.id);
    }
    _noteToolActivity(merged);
  }

  /// 合并同 id 工具卡更新：进度追加 content，空 content 不冲掉已有正文。
  ///
  /// [startedAt] 只写一次；进入终态时冻结 [duration]。
  AgentToolCall _mergeToolCallUpdate(
    AgentToolCall existing,
    AgentToolCall incoming,
  ) {
    final progressAppend = _isToolProgressAppend(incoming);
    final incomingContent = incoming.content;
    final existingContent = existing.content;

    final String? content;
    if (progressAppend) {
      content = _appendToolProgressContent(existingContent, incomingContent);
    } else if ((incomingContent == null || incomingContent.isEmpty) &&
        existingContent != null &&
        existingContent.isNotEmpty) {
      // item/started 或空完成态不要冲掉已聚合的进度 / reasoning delta。
      content = existingContent;
    } else {
      content = incomingContent;
    }

    // 后续 tool_call_update 常省略 title，mapper 可能填成 call- id 或泛化文案；
    // 不要冲掉已有更具体的标题。
    final keepExistingTitle =
        progressAppend ||
        (isNonInformativeAgentToolCallTitle(
              incoming.title,
              toolCallId: incoming.id,
            ) &&
            !isNonInformativeAgentToolCallTitle(
              existing.title,
              toolCallId: existing.id,
            ));
    // 状态型 update 通常也会省略 kind；保留首次/详情更新已经确定的具体类型。
    final keepExistingKind =
        incoming.kind == AgentToolKind.other &&
        existing.kind != AgentToolKind.other;
    final kind = keepExistingKind ? existing.kind : incoming.kind;
    final startedAt =
        existing.startedAt ??
        incoming.startedAt ??
        (incoming.isActiveStatus || existing.isActiveStatus
            ? DateTime.now()
            : null);

    var completedAt = existing.completedAt ?? incoming.completedAt;
    var duration = existing.duration ?? incoming.duration;
    final status = incoming.status;
    final isTerminal =
        status == AgentToolStatus.completed ||
        status == AgentToolStatus.failed ||
        status == AgentToolStatus.cancelled;
    if (isTerminal && duration == null && startedAt != null) {
      completedAt ??= DateTime.now();
      duration = completedAt.difference(startedAt);
      if (duration.isNegative) {
        duration = Duration.zero;
      }
    }

    return AgentToolCall(
      id: incoming.id,
      title: keepExistingTitle ? existing.title : incoming.title,
      kind: kind,
      status: status,
      content: content,
      locations: incoming.locations.isNotEmpty
          ? incoming.locations
          : existing.locations,
      sessionId: incoming.sessionId ?? existing.sessionId,
      turnId: incoming.turnId ?? existing.turnId,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      rawInput: incoming.rawInput.isNotEmpty
          ? incoming.rawInput
          : existing.rawInput,
      rawOutput: incoming.rawOutput.isNotEmpty
          ? incoming.rawOutput
          : existing.rawOutput,
      raw: incoming.raw.isNotEmpty ? incoming.raw : existing.raw,
    );
  }

  /// 首次出现的工具项：活跃态补本地 [startedAt]；终态可直接冻结 duration。
  AgentToolCall _stampNewToolCall(AgentToolCall toolCall) {
    final now = DateTime.now();
    final startedAt =
        toolCall.startedAt ?? (toolCall.isActiveStatus ? now : null);
    if (toolCall.isTerminalStatus &&
        toolCall.duration == null &&
        startedAt != null) {
      final completedAt = toolCall.completedAt ?? now;
      return toolCall.copyWith(
        startedAt: startedAt,
        completedAt: completedAt,
        duration: completedAt.difference(startedAt),
      );
    }
    if (startedAt == null || toolCall.startedAt != null) {
      return toolCall;
    }
    return toolCall.copyWith(startedAt: startedAt);
  }

  /// MCP `item/mcpToolCall/progress` 等进度通知：content 按行追加。
  bool _isToolProgressAppend(AgentToolCall toolCall) {
    return toolCall.raw['_progressAppend'] == true;
  }

  String? _appendToolProgressContent(String? existing, String? incoming) {
    if (incoming == null || incoming.isEmpty) {
      return existing;
    }
    if (existing == null || existing.isEmpty) {
      return incoming;
    }
    // 去重：同一进度消息重复下发时不追加。
    if (existing == incoming ||
        existing.endsWith('\n$incoming') ||
        existing.endsWith(incoming)) {
      return existing;
    }
    return '$existing\n$incoming';
  }

  /// 聚合 reasoning 流式增量到「思考」工具卡片。
  ///
  /// 优先展示摘要流（`summaryText`）；若本 item 尚未收到摘要，则回退到
  /// 原始推理文本（`text`）。`summaryPart` 仅在已有摘要内容时插入分段换行。
  /// 首次出现时自动展开卡片，便于实时观看思考过程。
  void appendReasoningDelta(AgentReasoningDeltaEvent event) {
    final existingIndex = _toolCalls.indexWhere(
      (item) => item.id == event.itemId,
    );
    final existing = existingIndex == -1 ? null : _toolCalls[existingIndex];
    final buffers = _reasoningBuffersFor(event.itemId, existing: existing);
    final previousDisplay = buffers.displayText;

    switch (event.kind) {
      case AgentReasoningDeltaKind.text:
        if (event.delta.isEmpty) {
          return;
        }
        buffers.text.write(event.delta);
      case AgentReasoningDeltaKind.summaryText:
        if (event.delta.isEmpty) {
          return;
        }
        buffers.hasSummary = true;
        buffers.summary.write(event.delta);
      case AgentReasoningDeltaKind.summaryPart:
        buffers.hasSummary = true;
        if (buffers.summary.isNotEmpty &&
            !buffers.summary.toString().endsWith('\n\n')) {
          buffers.summary.write('\n\n');
        }
    }

    final displayText = buffers.displayText;
    if (displayText == previousDisplay && existing != null) {
      return;
    }

    final now = DateTime.now();
    final isCompleted = existing?.status == AgentToolStatus.completed;
    final startedAt = existing?.startedAt ?? now;
    final toolCall = AgentToolCall(
      id: event.itemId,
      title: existing?.title ?? '思考',
      kind: AgentToolKind.think,
      status: isCompleted
          ? AgentToolStatus.completed
          : AgentToolStatus.inProgress,
      content: displayText.isEmpty ? null : displayText,
      locations: existing?.locations ?? const <String>[],
      sessionId: event.sessionId ?? existing?.sessionId,
      turnId: event.turnId ?? existing?.turnId,
      startedAt: startedAt,
      completedAt: existing?.completedAt,
      duration: existing?.duration,
      rawInput: existing?.rawInput ?? const <String, Object?>{},
      rawOutput: existing?.rawOutput ?? const <String, Object?>{},
      raw: event.raw.isEmpty
          ? (existing?.raw ?? const <String, Object?>{})
          : event.raw,
    );

    if (existingIndex == -1) {
      _toolCalls.add(toolCall);
      appendTimelineEntry(AgentToolTimelineEntry(toolCall: toolCall));
      // 流式思考首次出现时自动展开，完成后仍可由用户折叠。
      if (displayText.isNotEmpty) {
        _expandedToolCallIds.add(event.itemId);
      }
      _noteToolActivity(toolCall);
      return;
    }

    _toolCalls[existingIndex] = toolCall;
    replaceTimelineTool(toolCall);
    if (displayText.isNotEmpty && previousDisplay.isEmpty) {
      _expandedToolCallIds.add(event.itemId);
    }
    _noteToolActivity(toolCall);
  }

  /// 读取或初始化某个 reasoning item 的文本缓冲。
  _ReasoningStreamBuffers _reasoningBuffersFor(
    String itemId, {
    AgentToolCall? existing,
  }) {
    final cached = _reasoningBuffersByItemId[itemId];
    if (cached != null) {
      return cached;
    }

    // item/started|completed 可能先于 delta 到达；用已有 content 作为摘要种子，
    // 避免后续 summary delta 覆盖掉 completed 已写入的全文。
    final seed = existing?.content ?? '';
    final buffers = _ReasoningStreamBuffers(
      summary: StringBuffer(seed),
      text: StringBuffer(),
      hasSummary: seed.isNotEmpty,
    );
    _reasoningBuffersByItemId[itemId] = buffers;
    return buffers;
  }

  /// turn 真正启动时，把 sendMessage 建立的临时分组重命名为真实 turn id，
  /// 并记录运行状态与起始时间。后续条目都会归到该分组。
  ///
  /// [modelConfig] 可选；若 pending 分组已在 [startPendingLiveTurn] 写入配置则保留。
  void beginLiveTurnGroup(AgentTurn turn, {AgentTurnModelConfig? modelConfig}) {
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
    final startedAt = turnState.startedAt ?? DateTime.now();
    turnState.updateMetadata(
      status: AgentHistoryTurnStatus.running,
      startedAt: startedAt,
      completedAt: turnState.completedAt,
      duration: turnState.duration,
      tokenUsage: turnState.tokenUsage,
      modelConfig: modelConfig ?? turnState.modelConfig,
    );
    // 若尚未进入思考/工具/回复，保持或进入 starting。
    if (!_currentActivity.isActive ||
        _currentActivity.phase == AgentTurnActivityPhase.starting) {
      _setActivity(
        AgentTurnActivityPhase.starting,
        turnStartedAt: startedAt,
        forceSegmentRestart: false,
      );
    } else {
      _setActivity(
        _currentActivity.phase,
        label: _currentActivity.label,
        primaryToolId: _currentActivity.primaryToolId,
        turnStartedAt: startedAt,
        forceSegmentRestart: false,
      );
    }
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
      _clearActivity();
      return;
    }
    final oldHistoryLength = _historicalTurnOrder.length;
    final oldDefaultStartIndex = _defaultVisibleHistoryStartIndexForLength(
      oldHistoryLength,
    );
    final historyExpanded = _visibleHistoryStartIndex < oldDefaultStartIndex;
    final previousVisibleCount = oldHistoryLength - _visibleHistoryStartIndex;
    final completedAt = DateTime.now();
    // 优先 provider 上报耗时（如 Grok apiDurationMs），其次已冻结值，最后本地估算。
    final resolvedDuration =
        duration ??
        turnState.duration ??
        (turnState.startedAt == null
            ? null
            : completedAt.difference(turnState.startedAt!));
    turnState.updateMetadata(
      status: status,
      startedAt: turnState.startedAt,
      completedAt: completedAt,
      duration: resolvedDuration,
      tokenUsage: turnState.tokenUsage,
      modelConfig: turnState.modelConfig,
    );
    _freezeOpenToolDurations(completedAt);
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
    _clearActivity();
  }

  /// 用 provider 上报的 token 用量更新会话总量与对应回合增量。
  ///
  /// Codex（[AgentTokenUsageEvent.isSessionCumulative] == true）：`total` 是
  /// 整个会话累计，直接写入 [_threadTokenUsage]；turn 上保存相对上一 turn
  /// 累计的差值。
  ///
  /// Grok（`isSessionCumulative == false`）：上报值即本回合绝对用量，直接
  /// 写入 turn，并累加到会话总量。
  ///
  /// 优先按事件中的 turnId 定位分组；缺失时回退到当前运行回合。
  /// 若目标 turn 已进历史区，原地更新元数据，不再把它 demote 回 live。
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
    final existing = _turnGroups[turnId];
    final AgentConversationTurnState turnState;
    if (existing != null) {
      // 已存在（含已完成历史 turn）：只改元数据，保持 historical/live 归属。
      turnState = existing;
    } else {
      turnState = _turnStateFor(turnId, isStandby: false, isHistorical: false);
    }

    final AgentTokenUsage turnDelta;
    if (event.isSessionCumulative) {
      final previousCumulative = _previousTurnCumulativeUsage(turnId);
      turnDelta = event.tokenUsage.deltaFrom(previousCumulative);
      _threadTokenUsage = event.tokenUsage;
    } else {
      // 本回合绝对用量：覆盖写入，避免同 turn 多次上报时差分错误。
      turnDelta = event.tokenUsage;
      final previousCumulative = _previousTurnCumulativeUsage(turnId);
      _threadTokenUsage = previousCumulative == null
          ? event.tokenUsage
          : previousCumulative.addCumulative(event.tokenUsage);
    }
    turnState.updateMetadata(
      status: turnState.status,
      startedAt: turnState.startedAt,
      completedAt: turnState.completedAt,
      duration: turnState.duration,
      tokenUsage: turnDelta,
      modelConfig: turnState.modelConfig,
    );
  }

  bool isHistoryTurnId(String turnId) {
    return turnId == standbyTurnId || _historicalTurnOrder.contains(turnId);
  }

  bool isLiveTurnId(String turnId) {
    return _liveTurnOrder.contains(turnId) || currentTurnGroupId == turnId;
  }

  void _noteRespondingActivity(AgentMessageRole role) {
    if (role != AgentMessageRole.agent || !isTurnRunning) {
      return;
    }
    // 工具进行中时保持 tool 主相位，避免流式回复抢占命令计时展示。
    if (_currentActivity.phase == AgentTurnActivityPhase.toolRunning) {
      final toolId = _currentActivity.primaryToolId;
      if (toolId != null) {
        for (final tool in _toolCalls) {
          if (tool.id == toolId && tool.isActiveStatus) {
            return;
          }
        }
      }
    }
    _setActivity(AgentTurnActivityPhase.responding);
  }

  void _noteToolActivity(AgentToolCall toolCall) {
    if (!isTurnRunning) {
      return;
    }
    if (toolCall.kind == AgentToolKind.think) {
      if (toolCall.isActiveStatus || toolCall.duration == null) {
        _setActivity(
          AgentTurnActivityPhase.thinking,
          primaryToolId: toolCall.id,
        );
      } else {
        _fallbackActivityAfterToolSettled(toolCall.id);
      }
      return;
    }
    if (toolCall.isActiveStatus) {
      final title = toolCall.displayTitle.trim();
      _setActivity(
        AgentTurnActivityPhase.toolRunning,
        label: title.isEmpty ? null : title,
        primaryToolId: toolCall.id,
      );
      return;
    }
    _fallbackActivityAfterToolSettled(toolCall.id);
  }

  /// 主工具结束后回退到其他活跃工具 / 思考 / 启动中。
  void _fallbackActivityAfterToolSettled(String settledToolId) {
    if (!isTurnRunning) {
      _clearActivity();
      return;
    }
    AgentToolCall? activeTool;
    AgentToolCall? activeThink;
    for (final tool in _toolCalls.reversed) {
      if (!tool.isActiveStatus) {
        continue;
      }
      if (tool.id == settledToolId) {
        continue;
      }
      if (tool.kind == AgentToolKind.think) {
        activeThink ??= tool;
      } else {
        activeTool ??= tool;
      }
      if (activeTool != null) {
        break;
      }
    }
    if (activeTool != null) {
      final title = activeTool.title.trim();
      _setActivity(
        AgentTurnActivityPhase.toolRunning,
        label: title.isEmpty ? null : title,
        primaryToolId: activeTool.id,
      );
      return;
    }
    if (activeThink != null) {
      _setActivity(
        AgentTurnActivityPhase.thinking,
        primaryToolId: activeThink.id,
      );
      return;
    }
    if (_currentActivity.phase == AgentTurnActivityPhase.responding) {
      return;
    }
    _setActivity(AgentTurnActivityPhase.starting);
  }

  void _setActivity(
    AgentTurnActivityPhase phase, {
    String? label,
    String? primaryToolId,
    DateTime? turnStartedAt,
    bool forceSegmentRestart = false,
  }) {
    final resolvedTurnStartedAt =
        turnStartedAt ?? currentTurnStartedAt ?? _currentActivity.turnStartedAt;
    final samePhase = _currentActivity.phase == phase;
    final sameTool = _currentActivity.primaryToolId == primaryToolId;
    final sameLabel = _currentActivity.label == label;
    if (samePhase &&
        sameTool &&
        sameLabel &&
        !forceSegmentRestart &&
        _currentActivity.isActive) {
      // 仅补齐 turnStartedAt。
      if (_currentActivity.turnStartedAt == null &&
          resolvedTurnStartedAt != null) {
        _currentActivity = AgentTurnActivitySnapshot(
          phase: phase,
          label: label,
          segmentStartedAt: _currentActivity.segmentStartedAt,
          turnStartedAt: resolvedTurnStartedAt,
          primaryToolId: primaryToolId,
        );
        _activityDirty = true;
      }
      return;
    }
    final now = DateTime.now();
    final keepSegmentStart =
        samePhase &&
        sameTool &&
        !forceSegmentRestart &&
        _currentActivity.segmentStartedAt != null;
    _currentActivity = AgentTurnActivitySnapshot(
      phase: phase,
      label: label,
      segmentStartedAt: keepSegmentStart
          ? _currentActivity.segmentStartedAt
          : now,
      turnStartedAt: resolvedTurnStartedAt,
      primaryToolId: primaryToolId,
    );
    _activityDirty = true;
  }

  void _clearActivity() {
    if (_currentActivity.phase == AgentTurnActivityPhase.idle &&
        !_activityDirty) {
      return;
    }
    _currentActivity = AgentTurnActivitySnapshot.idle;
    _activityDirty = true;
  }

  /// turn 结束时冻结尚未写 duration 的工具项。
  void _freezeOpenToolDurations(DateTime completedAt) {
    for (var index = 0; index < _toolCalls.length; index += 1) {
      final tool = _toolCalls[index];
      if (tool.duration != null || tool.startedAt == null) {
        continue;
      }
      final duration = completedAt.difference(tool.startedAt!);
      final frozen = tool.copyWith(
        completedAt: tool.completedAt ?? completedAt,
        duration: duration.isNegative ? Duration.zero : duration,
      );
      _toolCalls[index] = frozen;
      replaceTimelineTool(frozen);
    }
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

  /// 会话已有实质内容时移除 Ready 占位，避免与真实消息并存。
  void _dismissWelcomeMessage() {
    final messageIndex = _messages.indexWhere(
      (message) => message.id == welcomeMessage.id,
    );
    if (messageIndex == -1) {
      return;
    }
    _messages.removeAt(messageIndex);
    _removeTimelineEntryById('message-${welcomeMessage.id}');
  }

  bool _isWelcomeTimelineEntry(AgentTimelineEntry entry) {
    return entry is AgentMessageTimelineEntry &&
        entry.message.id == welcomeMessage.id;
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

  void _registerHistoryTurn(
    AgentHistoryTurn turn, {
    required bool asLive,
    AgentTokenUsage? tokenUsage,
  }) {
    _turnStateFor(
      turn.id,
      isStandby: false,
      isHistorical: !asLive,
    ).updateMetadata(
      status: turn.status,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      duration: turn.duration,
      tokenUsage: tokenUsage ?? turn.tokenUsage,
      modelConfig: AgentTurnModelConfig.fromHistoryTurn(turn),
    );
  }

  /// 计算 [turnId] 之前所有 turn 的累计用量，作为本 turn 差分的基线。
  AgentTokenUsage? _previousTurnCumulativeUsage(String turnId) {
    AgentTokenUsage? cumulative;
    for (final orderedTurnId in _orderedTurnIds()) {
      if (orderedTurnId == turnId) {
        break;
      }
      final usage = _turnGroups[orderedTurnId]?.tokenUsage;
      if (usage == null || !usage.hasCumulativeBreakdown) {
        continue;
      }
      cumulative = cumulative == null ? usage : cumulative.addCumulative(usage);
    }
    return cumulative;
  }

  /// 历史 turn 在前、live turn 在后的稳定顺序。
  Iterable<String> _orderedTurnIds() sync* {
    yield* _historicalTurnOrder;
    yield* _liveTurnOrder;
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
    this.localImagePaths = const <String>[],
    this.raw = const <String, Object?>{},
  });

  final String id;
  final AgentMessageRole role;
  final String text;
  final AgentConversationMessageKind kind;
  final AgentMessagePhase? phase;
  final AgentMessageStatus? status;
  final Duration? duration;

  /// 本条消息附带的本地图片路径（发送时预览 / 历史回填）。
  final List<String> localImagePaths;
  final Map<String, Object?> raw;

  bool get isPlan => kind == AgentConversationMessageKind.plan;

  /// 是否为 Agent 完成汇总（Codex `phase=final_answer` → [AgentMessagePhase.response]）。
  bool get isFinalAnswer {
    return role == AgentMessageRole.agent &&
        phase == AgentMessagePhase.response &&
        !isPlan;
  }

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
    List<String>? localImagePaths,
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
      localImagePaths: localImagePaths ?? this.localImagePaths,
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

/// 时间线独立计划审批条目。
class AgentPlanApprovalTimelineEntry extends AgentTimelineEntry {
  AgentPlanApprovalTimelineEntry({required this.request})
    : super(id: 'plan-approval-${request.id}');

  final AgentPlanApprovalRequest request;
}

/// 时间线历史事件条目。
class AgentHistoryEventTimelineEntry extends AgentTimelineEntry {
  AgentHistoryEventTimelineEntry({required this.event})
    : super(id: 'history-event-${event.id}');

  final AgentHistoryEventEntry event;
}

/// 时间线回合级聚合 diff 条目。
///
/// 由 `turn/diff/updated` 驱动；UI 层解析为文件编辑组复用 diff 渲染。
class AgentTurnDiffTimelineEntry extends AgentTimelineEntry {
  AgentTurnDiffTimelineEntry({
    required this.turnId,
    required this.diff,
    this.sessionId,
    this.raw = const <String, Object?>{},
  }) : super(id: 'turn-diff-$turnId');

  /// 所属回合 id。
  final String turnId;

  /// 所属会话 id。
  final String? sessionId;

  /// 最新聚合 unified diff。
  final String diff;

  /// 原始通知 payload。
  final Map<String, Object?> raw;
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
    this.modelConfig,
  });

  final String id;
  final List<AgentTimelineEntry> entries;
  final bool isStandby;
  final AgentHistoryTurnStatus? status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final AgentTokenUsage? tokenUsage;

  /// 本回合使用的模型 / 思考程度 / Fast 配置（若有）。
  final AgentTurnModelConfig? modelConfig;
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
  AgentTurnModelConfig? _modelConfig;
  bool _dirty = false;

  List<AgentTimelineEntry> get entries => UnmodifiableListView(_entries);

  AgentHistoryTurnStatus? get status => _status;

  DateTime? get startedAt => _startedAt;

  DateTime? get completedAt => _completedAt;

  Duration? get duration => _duration;

  AgentTokenUsage? get tokenUsage => _tokenUsage;

  AgentTurnModelConfig? get modelConfig => _modelConfig;

  bool get isRunning => _status == AgentHistoryTurnStatus.running;

  void appendEntry(AgentTimelineEntry entry) {
    final existingIndex = _entries.indexWhere((item) => item.id == entry.id);
    if (existingIndex != -1) {
      _entries[existingIndex] = entry;
    } else {
      _entries.add(entry);
    }
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
    AgentTurnModelConfig? modelConfig,
  }) {
    _status = status;
    _startedAt = startedAt;
    _completedAt = completedAt;
    _duration = duration;
    _tokenUsage = tokenUsage;
    _modelConfig = modelConfig;
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
      modelConfig: _modelConfig,
    );
  }
}

/// Reasoning 流式双缓冲：摘要优先，原文兜底。
class _ReasoningStreamBuffers {
  _ReasoningStreamBuffers({
    required this.summary,
    required this.text,
    required this.hasSummary,
  });

  final StringBuffer summary;
  final StringBuffer text;
  bool hasSummary;

  /// 有摘要时只展示摘要；否则展示原始推理文本。
  String get displayText {
    if (hasSummary && summary.isNotEmpty) {
      return summary.toString();
    }
    return text.toString();
  }
}
