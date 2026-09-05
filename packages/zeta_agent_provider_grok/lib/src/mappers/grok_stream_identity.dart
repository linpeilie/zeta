import 'dart:collection';

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Grok 时间线中会关闭当前正文与 reasoning 的可见叙事边界。
enum GrokNarrativeBoundaryKind {
  plan,
  permission,
  userQuestion,
  planApproval,
  warningOrSystem,
}

/// Grok identity 状态失效原因。
enum GrokIdentityInvalidationReason {
  newTurn,
  cancel,
  promptError,
  peerClosed,
  connectionEpochChanged,
  sessionSwitched,
  dispose,
}

/// 参与 first-terminal-wins 的终态来源。
enum GrokTerminalSource {
  standardNotification,
  xaiNotification,
  promptRpc,
  cancel,
  promptError,
}

/// 终态竞争结果。
enum GrokTerminalDisposition { accepted, duplicate, conflicting, missingScope }

/// Grok identity reducer 的只读诊断快照。
final class GrokStreamIdentityDiagnostics {
  const GrokStreamIdentityDiagnostics({
    required this.syntheticEntryIdCreated,
    required this.duplicateRawEventDropped,
    required this.lateContentDropped,
    required this.lateEventDropped,
    required this.missingTurnScopeDropped,
    required this.identityCollisionDetected,
    required this.terminalAccepted,
    required this.duplicateTerminalIgnored,
    required this.conflictingTerminalIgnored,
  });

  final int syntheticEntryIdCreated;
  final int duplicateRawEventDropped;
  final int lateContentDropped;
  final int lateEventDropped;
  final int missingTurnScopeDropped;
  final int identityCollisionDetected;
  final int terminalAccepted;
  final int duplicateTerminalIgnored;
  final int conflictingTerminalIgnored;
}

/// 一个已解析到当前 turn generation 的规范化条目身份。
final class GrokResolvedEntryIdentity {
  const GrokResolvedEntryIdentity({
    required this.entryId,
    required this.sessionId,
    required this.turnId,
    required this.generation,
  });

  final String entryId;
  final String sessionId;
  final String turnId;
  final int generation;
}

/// 一个已解析到当前 turn generation 的元数据身份。
final class GrokResolvedTurnIdentity {
  const GrokResolvedTurnIdentity({
    required this.sessionId,
    required this.turnId,
    required this.generation,
  });

  final String sessionId;
  final String turnId;
  final int generation;
}

/// 工具更新的 identity 解析结果。
final class GrokResolvedToolIdentity extends GrokResolvedTurnIdentity {
  const GrokResolvedToolIdentity({
    required super.sessionId,
    required super.turnId,
    required super.generation,
    required this.isNewTool,
  });

  final bool isNewTool;
}

/// first-terminal-wins 的解析结果。
final class GrokTerminalResolution extends GrokResolvedTurnIdentity {
  const GrokTerminalResolution({
    required super.sessionId,
    required super.turnId,
    required super.generation,
    required this.disposition,
    required this.status,
  });

  final GrokTerminalDisposition disposition;
  final AgentHistoryTurnStatus status;

  bool get accepted => disposition == GrokTerminalDisposition.accepted;
}

/// 供单测和脱敏诊断读取的 turn identity 快照。
final class GrokTurnIdentitySnapshot {
  const GrokTurnIdentitySnapshot({
    required this.generation,
    required this.messageSegmentOrdinal,
    required this.reasoningPhaseOrdinal,
    required this.sourceMessageEntryIds,
    required this.seenToolCallIds,
    required this.recentRawEventCount,
    required this.terminal,
  });

  final int generation;
  final int messageSegmentOrdinal;
  final int reasoningPhaseOrdinal;
  final Map<String, List<String>> sourceMessageEntryIds;
  final Set<String> seenToolCallIds;
  final int recentRawEventCount;
  final bool terminal;
}

/// Grok live 流的 Provider-local identity reducer。
///
/// reducer 只保存 identity、边界、去重和终态状态，不读取或记录正文。所有可见
/// message/reasoning 在进入 application 层前都必须先取得这里生成的最终 entryId。
final class GrokStreamIdentity {
  GrokStreamIdentity({this.maxRecentRawEvents = 512})
    : assert(maxRecentRawEvents > 0);

  final int maxRecentRawEvents;

  final Map<_SessionScopeKey, int> _generations = <_SessionScopeKey, int>{};
  final Map<_SessionScopeKey, _GrokTurnState> _activeTurns =
      <_SessionScopeKey, _GrokTurnState>{};
  final Map<_TurnLookupKey, _GrokTurnState> _turnsById =
      <_TurnLookupKey, _GrokTurnState>{};
  final Map<_TurnLookupKey, _GrokTurnState> _turnsByPromptId =
      <_TurnLookupKey, _GrokTurnState>{};
  final Set<String> _issuedEntryIds = <String>{};

  AgentRuntimeScope? _currentRuntimeScope;
  bool _disposed = false;

  int _syntheticEntryIdCreated = 0;
  int _duplicateRawEventDropped = 0;
  int _lateContentDropped = 0;
  int _lateEventDropped = 0;
  int _missingTurnScopeDropped = 0;
  int _identityCollisionDetected = 0;
  int _terminalAccepted = 0;
  int _duplicateTerminalIgnored = 0;
  int _conflictingTerminalIgnored = 0;

  /// 当前累计诊断；不包含正文、raw payload 或未脱敏 source id。
  GrokStreamIdentityDiagnostics get diagnostics =>
      GrokStreamIdentityDiagnostics(
        syntheticEntryIdCreated: _syntheticEntryIdCreated,
        duplicateRawEventDropped: _duplicateRawEventDropped,
        lateContentDropped: _lateContentDropped,
        lateEventDropped: _lateEventDropped,
        missingTurnScopeDropped: _missingTurnScopeDropped,
        identityCollisionDetected: _identityCollisionDetected,
        terminalAccepted: _terminalAccepted,
        duplicateTerminalIgnored: _duplicateTerminalIgnored,
        conflictingTerminalIgnored: _conflictingTerminalIgnored,
      );

  /// 为 session 开启新 turn generation，并使同 session 的旧 active state 失效。
  int beginTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    if (_disposed) {
      throw StateError('GrokStreamIdentity has been disposed');
    }
    final previousRuntime = _currentRuntimeScope;
    if (previousRuntime != null && previousRuntime != runtimeScope) {
      invalidateRuntime(
        runtimeScope: previousRuntime,
        reason: GrokIdentityInvalidationReason.connectionEpochChanged,
      );
    }
    _currentRuntimeScope = runtimeScope;

    final sessionKey = _SessionScopeKey(runtimeScope, sessionId);
    final previous = _activeTurns.remove(sessionKey);
    if (previous != null) {
      _invalidateState(previous, GrokIdentityInvalidationReason.newTurn);
    }
    final generation = (_generations[sessionKey] ?? 0) + 1;
    _generations[sessionKey] = generation;
    final state = _GrokTurnState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      generation: generation,
    );
    _activeTurns[sessionKey] = state;
    _turnsById[_TurnLookupKey(runtimeScope, sessionId, turnId)] = state;
    return generation;
  }

  /// 为正文 chunk 解析稳定的 message segment entryId。
  GrokResolvedEntryIdentity? resolveMessage({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required String? sourceMessageId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }
    if (state.terminal) {
      _lateContentDropped += 1;
      return null;
    }

    state.closeReasoning();
    final currentId = state.currentMessageEntryId;
    if (currentId != null && state.currentMessageSourceId == sourceMessageId) {
      return _entryIdentity(state, currentId);
    }

    state.closeMessage();
    state.messageSegmentOrdinal += 1;
    final entryId = _createEntryId(
      state: state,
      entryKind: 'message',
      sourceId: sourceMessageId,
      ordinal: state.messageSegmentOrdinal,
    );
    state.currentMessageEntryId = entryId;
    state.currentMessageSourceId = sourceMessageId;
    if (sourceMessageId != null) {
      state.sourceMessageEntryIds
          .putIfAbsent(sourceMessageId, () => <String>[])
          .add(entryId);
    }
    return _entryIdentity(state, entryId);
  }

  /// 为连续 reasoning chunk 解析 phase entryId；eventId 不参与 phase 分段。
  GrokResolvedEntryIdentity? resolveReasoning({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required String? sourceItemId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }
    if (state.terminal) {
      _lateContentDropped += 1;
      return null;
    }

    state.closeMessage();
    final currentId = state.currentReasoningEntryId;
    if (currentId != null && state.currentReasoningSourceId == sourceItemId) {
      return _entryIdentity(state, currentId);
    }

    state.closeReasoning();
    state.reasoningPhaseOrdinal += 1;
    final entryId = _createEntryId(
      state: state,
      entryKind: 'reasoning',
      sourceId: sourceItemId,
      ordinal: state.reasoningPhaseOrdinal,
    );
    state.currentReasoningEntryId = entryId;
    state.currentReasoningSourceId = sourceItemId;
    return _entryIdentity(state, entryId);
  }

  /// 解析 tool start/update；只有首次见到的 toolCallId 会关闭当前可见 phase。
  GrokResolvedToolIdentity? resolveTool({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required String toolCallId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }

    final known = state.seenToolCallIds.contains(toolCallId);
    if (state.terminal && !known) {
      _lateEventDropped += 1;
      return null;
    }
    if (!known) {
      state.seenToolCallIds.add(toolCallId);
      state.closeVisiblePhases();
    }
    return GrokResolvedToolIdentity(
      sessionId: state.sessionId,
      turnId: state.turnId,
      generation: state.generation,
      isNewTool: !known,
    );
  }

  /// 接受 plan 等可见 boundary update；terminal 后不再创建新可见条目。
  GrokResolvedTurnIdentity? resolveVisibleBoundaryUpdate({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }
    if (state.terminal) {
      _lateEventDropped += 1;
      return null;
    }
    state.closeVisiblePhases();
    return _turnIdentity(state);
  }

  /// 接受 usage 等非叙事 update；terminal 后仍允许幂等 metadata 更新。
  GrokResolvedTurnIdentity? resolveMetadata({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }
    return _turnIdentity(state);
  }

  /// 记录 provider server request 或实际进入时间线的 warning/system boundary。
  bool noteBoundary({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required GrokNarrativeBoundaryKind kind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null) {
      return false;
    }
    if (state.terminal) {
      _lateEventDropped += 1;
      return false;
    }
    state.closeVisiblePhases();
    return true;
  }

  /// 以 first-terminal-wins 完成 turn。
  GrokTerminalResolution completeTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required AgentHistoryTurnStatus status,
    required GrokTerminalSource source,
    String? eventId,
    String eventKind = 'turn_completed',
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
    );
    if (state == null) {
      return GrokTerminalResolution(
        sessionId: sessionId,
        turnId: runningTurnId ?? promptId ?? '',
        generation: 0,
        disposition: GrokTerminalDisposition.missingScope,
        status: status,
      );
    }
    if (!_acceptRawEvent(state, eventKind, eventId)) {
      _duplicateTerminalIgnored += 1;
      return GrokTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: GrokTerminalDisposition.duplicate,
        status: state.terminalStatus ?? status,
      );
    }

    if (!state.terminal) {
      state.terminal = true;
      state.terminalStatus = status;
      state.terminalSource = source;
      state.closeVisiblePhases();
      _activeTurns.remove(_SessionScopeKey(runtimeScope, sessionId));
      _terminalAccepted += 1;
      return GrokTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: GrokTerminalDisposition.accepted,
        status: status,
      );
    }

    if (state.terminalStatus == status) {
      _duplicateTerminalIgnored += 1;
      return GrokTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: GrokTerminalDisposition.duplicate,
        status: state.terminalStatus!,
      );
    }
    _conflictingTerminalIgnored += 1;
    return GrokTerminalResolution(
      sessionId: state.sessionId,
      turnId: state.turnId,
      generation: state.generation,
      disposition: GrokTerminalDisposition.conflicting,
      status: state.terminalStatus ?? status,
    );
  }

  /// 使指定 turn state 失效；保留 tombstone 以识别后续迟到事件。
  void invalidateTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    required GrokIdentityInvalidationReason reason,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
      promptId: promptId,
      recordMissing: false,
    );
    if (state != null) {
      _invalidateState(state, reason);
      _activeTurns.remove(_SessionScopeKey(runtimeScope, sessionId));
    }
  }

  /// 使一个 connection epoch 下的所有 turn state 失效。
  void invalidateRuntime({
    required AgentRuntimeScope runtimeScope,
    required GrokIdentityInvalidationReason reason,
  }) {
    for (final state in _turnsById.values.toSet()) {
      if (state.runtimeScope == runtimeScope) {
        _invalidateState(state, reason);
      }
    }
    _activeTurns.removeWhere((key, _) => key.runtimeScope == runtimeScope);
    if (_currentRuntimeScope == runtimeScope) {
      _currentRuntimeScope = null;
    }
  }

  /// 使指定 session 的全部 generation 失效。
  void invalidateSession({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required GrokIdentityInvalidationReason reason,
  }) {
    for (final state in _turnsById.values.toSet()) {
      if (state.runtimeScope == runtimeScope && state.sessionId == sessionId) {
        _invalidateState(state, reason);
      }
    }
    _activeTurns.remove(_SessionScopeKey(runtimeScope, sessionId));
  }

  /// 返回指定 turn 的只读状态快照。
  GrokTurnIdentitySnapshot? snapshot({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    final state = _turnsById[_TurnLookupKey(runtimeScope, sessionId, turnId)];
    if (state == null) {
      return null;
    }
    return GrokTurnIdentitySnapshot(
      generation: state.generation,
      messageSegmentOrdinal: state.messageSegmentOrdinal,
      reasoningPhaseOrdinal: state.reasoningPhaseOrdinal,
      sourceMessageEntryIds: Map<String, List<String>>.unmodifiable(
        state.sourceMessageEntryIds.map(
          (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
        ),
      ),
      seenToolCallIds: Set<String>.unmodifiable(state.seenToolCallIds),
      recentRawEventCount: state.recentRawEventKeys.length,
      terminal: state.terminal,
    );
  }

  /// 释放全部 mutable identity state。
  void dispose() {
    if (_disposed) {
      return;
    }
    final runtimeScope = _currentRuntimeScope;
    if (runtimeScope != null) {
      invalidateRuntime(
        runtimeScope: runtimeScope,
        reason: GrokIdentityInvalidationReason.dispose,
      );
    }
    _disposed = true;
    _activeTurns.clear();
    _turnsById.clear();
    _turnsByPromptId.clear();
    _generations.clear();
  }

  _GrokTurnState? _resolveState({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? promptId,
    bool recordMissing = true,
  }) {
    if (_disposed || _currentRuntimeScope != runtimeScope) {
      if (recordMissing) {
        _missingTurnScopeDropped += 1;
      }
      return null;
    }

    final byTurnId = runningTurnId == null
        ? null
        : _turnsById[_TurnLookupKey(runtimeScope, sessionId, runningTurnId)];
    final byPromptId = promptId == null
        ? null
        : _turnsByPromptId[_TurnLookupKey(runtimeScope, sessionId, promptId)];
    if (byTurnId != null && byPromptId != null && byTurnId != byPromptId) {
      _identityCollisionDetected += 1;
      if (recordMissing) {
        _missingTurnScopeDropped += 1;
      }
      return null;
    }

    final state = byTurnId ?? byPromptId;
    if (state != null) {
      if (promptId != null) {
        _bindPromptAlias(state, promptId);
      }
      return state;
    }

    final active = _activeTurns[_SessionScopeKey(runtimeScope, sessionId)];
    if (active != null && runningTurnId == active.turnId) {
      if (promptId != null) {
        _bindPromptAlias(active, promptId);
      }
      return active;
    }
    if (recordMissing) {
      _missingTurnScopeDropped += 1;
    }
    return null;
  }

  void _bindPromptAlias(_GrokTurnState state, String promptId) {
    final key = _TurnLookupKey(state.runtimeScope, state.sessionId, promptId);
    final existing = _turnsByPromptId[key];
    if (existing != null && existing != state) {
      _identityCollisionDetected += 1;
      return;
    }
    _turnsByPromptId[key] = state;
  }

  bool _acceptRawEvent(_GrokTurnState state, String kind, String? eventId) {
    if (eventId == null || eventId.isEmpty) {
      return true;
    }
    final key = '$kind\u0000$eventId';
    if (!state.recentRawEventKeys.add(key)) {
      _duplicateRawEventDropped += 1;
      return false;
    }
    if (state.recentRawEventKeys.length > maxRecentRawEvents) {
      state.recentRawEventKeys.remove(state.recentRawEventKeys.first);
    }
    return true;
  }

  String _createEntryId({
    required _GrokTurnState state,
    required String entryKind,
    required String? sourceId,
    required int ordinal,
  }) {
    if (sourceId == null) {
      _syntheticEntryIdCreated += 1;
    }
    final encodedSession = Uri.encodeComponent(state.sessionId);
    final encodedTurn = Uri.encodeComponent(state.turnId);
    final encodedSource = Uri.encodeComponent(sourceId ?? 'anon');
    final base =
        'acp:grok:$encodedSession:$encodedTurn:$entryKind:$encodedSource:$ordinal';
    if (_issuedEntryIds.add(base)) {
      return base;
    }

    _identityCollisionDetected += 1;
    var suffix = state.generation;
    var candidate = '$base:g$suffix';
    while (!_issuedEntryIds.add(candidate)) {
      suffix += 1;
      candidate = '$base:g$suffix';
    }
    return candidate;
  }

  void _invalidateState(
    _GrokTurnState state,
    GrokIdentityInvalidationReason reason,
  ) {
    state.invalidatedBy = reason;
    state.terminal = true;
    state.closeVisiblePhases();
  }

  GrokResolvedEntryIdentity _entryIdentity(
    _GrokTurnState state,
    String entryId,
  ) => GrokResolvedEntryIdentity(
    entryId: entryId,
    sessionId: state.sessionId,
    turnId: state.turnId,
    generation: state.generation,
  );

  GrokResolvedTurnIdentity _turnIdentity(_GrokTurnState state) =>
      GrokResolvedTurnIdentity(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
      );
}

final class _GrokTurnState {
  _GrokTurnState({
    required this.runtimeScope,
    required this.sessionId,
    required this.turnId,
    required this.generation,
  });

  final AgentRuntimeScope runtimeScope;
  final String sessionId;
  final String turnId;
  final int generation;

  int messageSegmentOrdinal = 0;
  int reasoningPhaseOrdinal = 0;
  String? currentMessageEntryId;
  String? currentMessageSourceId;
  String? currentReasoningEntryId;
  String? currentReasoningSourceId;
  final Map<String, List<String>> sourceMessageEntryIds =
      <String, List<String>>{};
  final Set<String> seenToolCallIds = <String>{};
  final LinkedHashSet<String> recentRawEventKeys = LinkedHashSet<String>();

  bool terminal = false;
  AgentHistoryTurnStatus? terminalStatus;
  GrokTerminalSource? terminalSource;
  GrokIdentityInvalidationReason? invalidatedBy;

  void closeMessage() {
    currentMessageEntryId = null;
    currentMessageSourceId = null;
  }

  void closeReasoning() {
    currentReasoningEntryId = null;
    currentReasoningSourceId = null;
  }

  void closeVisiblePhases() {
    closeMessage();
    closeReasoning();
  }
}

final class _SessionScopeKey {
  const _SessionScopeKey(this.runtimeScope, this.sessionId);

  final AgentRuntimeScope runtimeScope;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is _SessionScopeKey &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId);
}

final class _TurnLookupKey {
  const _TurnLookupKey(this.runtimeScope, this.sessionId, this.turnOrPromptId);

  final AgentRuntimeScope runtimeScope;
  final String sessionId;
  final String turnOrPromptId;

  @override
  bool operator ==(Object other) =>
      other is _TurnLookupKey &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId &&
      other.turnOrPromptId == turnOrPromptId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId, turnOrPromptId);
}
