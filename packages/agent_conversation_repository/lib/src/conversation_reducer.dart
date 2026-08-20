// Package-internal reducer API shared with the repository library.
// ignore_for_file: public_member_api_docs

import 'package:agent_conversation_repository/src/conversation_models.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';

enum ConversationReductionScope { live, history, replay }

/// Deterministic reducer instance dedicated to exactly one reduction scope.
final class ConversationReducer {
  ConversationReducer(this.scope);

  final ConversationReductionScope scope;
  final Map<String, _MutableTurn> _turns = <String, _MutableTurn>{};
  final List<String> _turnOrder = <String>[];
  final Map<String, AgentPermissionRequest> pendingPermissions =
      <String, AgentPermissionRequest>{};
  final Map<String, AgentQuestionRequest> pendingQuestions =
      <String, AgentQuestionRequest>{};
  final Map<String, AgentPlanApprovalRequest> pendingPlanApprovals =
      <String, AgentPlanApprovalRequest>{};
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId =
      <String, AgentAutoApprovalReviewEvent>{};
  final Map<String, AgentTokenUsage?> _cumulativeBaselineByTurn =
      <String, AgentTokenUsage?>{};
  AgentTokenUsage? _lastCumulativeUsage;
  int _localId = 0;

  AgentSession? session;
  AgentTurn? activeTurn;
  AgentProviderStatus providerStatus = const AgentProviderStatus.idle();
  AgentThreadRuntimeStatus threadStatus = AgentThreadRuntimeStatus.unknown;
  String? threadName;
  String? threadPreview;
  bool isArchived = false;
  bool waitingOnApproval = false;
  bool waitingOnUserInput = false;
  List<AgentSessionConfigOption> sessionConfigOptions =
      const <AgentSessionConfigOption>[];
  AgentConversationModeId? conversationMode;
  AgentModelList? modelList;
  AgentConversationFailure? failure;

  bool hasTurn(String turnId) => _turns.containsKey(turnId);

  List<ConversationTurnSnapshot> get turns => <ConversationTurnSnapshot>[
    for (final id in _turnOrder) _turns[id]!.snapshot(),
  ];

  void loadHistory(Iterable<AgentHistoryTurn> turns) {
    for (final history in turns) {
      final turn = _turn(history.id)
        ..status = history.status
        ..startedAt = history.startedAt
        ..completedAt = history.completedAt
        ..duration = history.duration
        ..tokenUsage = history.tokenUsage
        ..modelContextWindow = history.modelContextWindow;
      for (final entry in history.entries) {
        turn.upsert(_historyEntry(history.id, entry));
      }
    }
  }

  void beginLocalTurn(AgentTurn turn, {String? message, String? messageId}) {
    activeTurn = turn;
    final mutable = _turn(turn.id)..status = AgentHistoryTurnStatus.running;
    if (message != null && message.isNotEmpty) {
      mutable.upsert(
        ConversationMessageEntry(
          id: messageId ?? 'local-user-${++_localId}',
          turnId: turn.id,
          role: AgentMessageRole.user,
          text: message,
          status: AgentMessageStatus.completed,
        ),
      );
    }
  }

  bool resolvePermission(String requestId) => _resolvePending(
    pendingPermissions,
    requestId,
    ConversationEntryKind.permission,
  );

  bool resolveQuestion(String requestId) => _resolvePending(
    pendingQuestions,
    requestId,
    ConversationEntryKind.question,
  );

  bool resolvePlanApproval(String requestId) => _resolvePending(
    pendingPlanApprovals,
    requestId,
    ConversationEntryKind.planApproval,
  );

  bool _resolvePending<T>(
    Map<String, T> pending,
    String requestId,
    ConversationEntryKind kind,
  ) {
    if (pending.remove(requestId) == null) {
      return false;
    }
    for (final turn in _turns.values) {
      final entry = turn.entries[requestId];
      if (entry is ConversationPendingEntry && entry.kind == kind) {
        turn.entries[requestId] = entry.markResolved();
        return true;
      }
    }
    return true;
  }

  void reduce(AgentEvent event) {
    if (event is AgentStatusEvent) {
      providerStatus = event.status;
    } else if (event is AgentSessionStartedEvent) {
      session = event.session;
    } else if (event is AgentThreadStatusChangedEvent) {
      threadStatus = event.status;
      waitingOnApproval = event.waitingOnApproval;
      waitingOnUserInput = event.waitingOnUserInput;
    } else if (event is AgentThreadNameUpdatedEvent) {
      threadName = event.threadName;
    } else if (event is AgentThreadPreviewUpdatedEvent) {
      threadPreview = event.preview;
    } else if (event is AgentThreadArchivedEvent) {
      isArchived = true;
    } else if (event is AgentThreadUnarchivedEvent) {
      isArchived = false;
    } else if (event is AgentThreadDeletedEvent ||
        event is AgentThreadClosedEvent) {
      threadStatus = AgentThreadRuntimeStatus.unknown;
      activeTurn = null;
    } else if (event is AgentThreadCompactedEvent) {
      _addSystem(
        event.turnId,
        ConversationSystemSignal.threadCompacted,
      );
    } else if (event is AgentThreadSettingsUpdatedEvent) {
      conversationMode = event.collaborationMode?.modeId;
    } else if (event is AgentAutoApprovalReviewEvent) {
      autoReviewsByTurnId[event.turnId] = event;
    } else if (event is AgentTurnStartedEvent) {
      activeTurn = event.turn;
      _turn(event.turn.id)
        ..status = AgentHistoryTurnStatus.running
        ..startedAt = event.startedAt;
    } else if (event is AgentTurnCompletedEvent) {
      final turn = _turn(event.turnId)
        ..status = event.status
        ..completedAt = event.completedAt
        ..duration = event.duration;
      if (activeTurn?.id == turn.id) {
        activeTurn = null;
      }
    } else if (event is AgentTokenUsageEvent) {
      final turnId = event.turnId ?? activeTurn?.id;
      if (turnId != null) {
        final turn = _turn(turnId);
        if (event.isSessionCumulative) {
          final baseline = _cumulativeBaselineByTurn.putIfAbsent(
            turnId,
            () => _lastCumulativeUsage,
          );
          turn.tokenUsage = event.tokenUsage.deltaFrom(baseline);
          _lastCumulativeUsage = event.tokenUsage;
        } else {
          turn.tokenUsage = event.tokenUsage;
        }
      }
    } else if (event is AgentContextWindowUsageEvent) {
      final turnId = event.turnId ?? activeTurn?.id;
      if (turnId != null) {
        final turn = _turn(turnId)..contextWindowUsedTokens = event.usedTokens;
        turn.modelContextWindow =
            event.modelContextWindow ?? turn.modelContextWindow;
      }
    } else if (event is AgentMessageDeltaEvent) {
      _appendMessage(event);
    } else if (event is AgentReasoningDeltaEvent) {
      _appendReasoning(event);
    } else if (event is AgentMessageUpdatedEvent) {
      _updateMessage(event);
    } else if (event is AgentPlanUpdatedEvent) {
      _turnFor(event.turnId).upsert(
        ConversationValueEntry(
          id: 'plan:${event.turnId ?? activeTurn?.id ?? "standby"}',
          turnId: event.turnId ?? activeTurn?.id,
          kind: ConversationEntryKind.plan,
          value: event.entries,
        ),
      );
    } else if (event is AgentSessionConfigUpdatedEvent) {
      sessionConfigOptions = event.options;
    } else if (event is AgentConversationModeUpdatedEvent) {
      conversationMode = event.modeId;
    } else if (event is AgentPlanApprovalRequestedEvent) {
      final request = event.request;
      pendingPlanApprovals[request.id] = request;
      _turnFor(request.turnId).upsert(
        ConversationPendingEntry(
          id: request.id,
          turnId: request.turnId,
          kind: ConversationEntryKind.planApproval,
          request: request,
        ),
      );
    } else if (event is AgentPlanApprovalResolvedEvent) {
      resolvePlanApproval(event.requestId);
    } else if (event is AgentTurnFileChangesEvent) {
      _turn(event.turnId).upsert(
        ConversationFileChangesEntry(
          id: 'file-changes:${event.turnId}',
          turnId: event.turnId,
          snapshot: event.snapshot,
        ),
      );
    } else if (event is AgentToolCallEvent) {
      final call = event.toolCall;
      _turnFor(call.turnId).upsert(
        ConversationToolEntry(
          id: call.id,
          turnId: call.turnId ?? activeTurn?.id,
          toolCall: call,
        ),
      );
    } else if (event is AgentPermissionRequestedEvent) {
      final request = event.request;
      pendingPermissions[request.id] = request;
      _turnFor(request.turnId).upsert(
        ConversationPendingEntry(
          id: request.id,
          turnId: request.turnId,
          kind: ConversationEntryKind.permission,
          request: request,
        ),
      );
    } else if (event is AgentPermissionResolvedEvent) {
      resolvePermission(event.requestId);
    } else if (event is AgentQuestionRequestedEvent) {
      final request = event.request;
      pendingQuestions[request.id] = request;
      _turnFor(request.turnId).upsert(
        ConversationPendingEntry(
          id: request.id,
          turnId: request.turnId,
          kind: ConversationEntryKind.question,
          request: request,
        ),
      );
    } else if (event is AgentQuestionResolvedEvent) {
      resolveQuestion(event.requestId);
    } else if (event is AgentSystemItemEvent) {
      _turnFor(event.turnId).upsert(
        ConversationHistoryEntry(
          id: event.entry.id,
          turnId: event.turnId ?? activeTurn?.id,
          entry: event.entry,
        ),
      );
    } else if (event is AgentModelReroutedEvent ||
        event is AgentDeprecationNoticeEvent ||
        event is AgentErrorEvent) {
      final signal = event is AgentModelReroutedEvent
          ? ConversationSystemSignal.modelRerouted
          : event is AgentDeprecationNoticeEvent
          ? ConversationSystemSignal.deprecationNotice
          : ConversationSystemSignal.providerError;
      _addSystem(_eventTurnId(event), signal);
      if (event is AgentErrorEvent) {
        failure = const AgentConversationFailure(
          AgentConversationFailureCode.providerOperationFailed,
        );
      }
    } else if (event is AgentModelListEvent) {
      modelList = event.models;
    }
  }

  void _appendMessage(AgentMessageDeltaEvent event) {
    final turn = _turnFor(event.turnId);
    final previous = turn.entries[event.messageId];
    final text = previous is ConversationMessageEntry
        ? '${previous.text}${event.delta}'
        : event.delta;
    turn.upsert(
      ConversationMessageEntry(
        id: event.messageId,
        turnId: event.turnId ?? activeTurn?.id,
        role: event.role,
        text: text,
        sourceMessageId:
            event.sourceMessageId ??
            (previous is ConversationMessageEntry
                ? previous.sourceMessageId
                : null),
        messageKind: event.kind,
        phase: event.phase,
        status: event.status ?? AgentMessageStatus.streaming,
        duration: event.duration,
      ),
    );
  }

  void _updateMessage(AgentMessageUpdatedEvent event) {
    final turn = _turnFor(event.turnId);
    final previous = turn.entries[event.messageId];
    final previousMessage = previous is ConversationMessageEntry
        ? previous
        : null;
    turn.upsert(
      ConversationMessageEntry(
        id: event.messageId,
        turnId: event.turnId ?? activeTurn?.id,
        role: event.role ?? previousMessage?.role ?? AgentMessageRole.agent,
        text: event.text ?? previousMessage?.text ?? '',
        sourceMessageId:
            event.sourceMessageId ?? previousMessage?.sourceMessageId,
        messageKind: event.kind,
        phase: event.phase ?? previousMessage?.phase,
        status: event.status ?? previousMessage?.status,
        duration: event.duration ?? previousMessage?.duration,
      ),
    );
  }

  void _appendReasoning(AgentReasoningDeltaEvent event) {
    final turn = _turnFor(event.turnId);
    final previous = turn.entries[event.itemId];
    final previousText = previous is ConversationReasoningEntry
        ? previous.text
        : '';
    turn.upsert(
      ConversationReasoningEntry(
        id: event.itemId,
        turnId: event.turnId ?? activeTurn?.id,
        text: '$previousText${event.delta}',
        reasoningKind: event.kind,
        sourceItemId:
            event.sourceItemId ??
            (previous is ConversationReasoningEntry
                ? previous.sourceItemId
                : null),
      ),
    );
  }

  void _addSystem(String? turnId, Object value) {
    _turnFor(turnId).upsert(
      ConversationValueEntry(
        id: 'system-${++_localId}',
        turnId: turnId ?? activeTurn?.id,
        kind: ConversationEntryKind.system,
        value: value,
      ),
    );
  }

  _MutableTurn _turnFor(String? turnId) {
    final resolved = turnId ?? activeTurn?.id ?? '<standby>';
    return _turn(resolved);
  }

  _MutableTurn _turn(String id) {
    return _turns.putIfAbsent(id, () {
      _turnOrder.add(id);
      return _MutableTurn(id);
    });
  }
}

String? _eventTurnId(AgentEvent event) {
  return switch (event) {
    AgentModelReroutedEvent() => event.turnId,
    AgentErrorEvent() => event.turnId,
    _ => null,
  };
}

ConversationTimelineEntry _historyEntry(
  String turnId,
  AgentHistoryEntry entry,
) {
  return switch (entry) {
    AgentHistoryMessageEntry() => ConversationMessageEntry(
      id: entry.id,
      turnId: turnId,
      role: entry.role,
      text: entry.text,
      sourceMessageId: entry.sourceMessageId,
      messageKind: entry.kind,
      phase: entry.phase,
      status: entry.status,
      duration: entry.duration,
    ),
    AgentHistoryToolEntry() => ConversationToolEntry(
      id: entry.id,
      turnId: turnId,
      toolCall: entry.toolCall,
    ),
    _ => ConversationHistoryEntry(
      id: entry.id,
      turnId: turnId,
      entry: entry,
    ),
  };
}

final class _MutableTurn {
  _MutableTurn(this.id);

  final String id;
  final Map<String, ConversationTimelineEntry> entries =
      <String, ConversationTimelineEntry>{};
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.unknown;
  DateTime? startedAt;
  DateTime? completedAt;
  Duration? duration;
  AgentTokenUsage? tokenUsage;
  int? contextWindowUsedTokens;
  int? modelContextWindow;

  void upsert(ConversationTimelineEntry entry) {
    entries[entry.id] = entry;
  }

  ConversationTurnSnapshot snapshot() => ConversationTurnSnapshot(
    id: id,
    entries: entries.values.toList(growable: false),
    status: status,
    startedAt: startedAt,
    completedAt: completedAt,
    duration: duration,
    tokenUsage: tokenUsage,
    contextWindowUsedTokens: contextWindowUsedTokens,
    modelContextWindow: modelContextWindow,
  );
}
