import 'dart:collection';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:meta/meta.dart';

/// Claude Code identity 状态失效原因。
enum ClaudeCodeIdentityInvalidationReason {
  /// The `newTurn` value.
  newTurn,

  /// The `cancel` value.
  cancel,

  /// The `peerClosed` value.
  peerClosed,

  /// The `connectionEpochChanged` value.
  connectionEpochChanged,

  /// The `sessionSwitched` value.
  sessionSwitched,

  /// The `dispose` value.
  dispose,
}

/// 参与 first-terminal-wins 的终态来源。
enum ClaudeCodeTerminalSource {
  /// A terminal stream-JSON result frame.
  resultFrame,

  /// A host interrupt request.
  interrupt,

  /// A host cancellation request.
  cancel,

  /// A provider runtime error.
  providerError,
}

/// 终态竞争结果。
enum ClaudeCodeTerminalDisposition {
  /// The `accepted` value.
  accepted,

  /// The `duplicate` value.
  duplicate,

  /// The `conflicting` value.
  conflicting,

  /// The `missingScope` value.
  missingScope,
}

/// identity reducer 的只读诊断快照（仅计数器，G7）。
final class ClaudeCodeStreamIdentityDiagnostics {
  /// Creates a [ClaudeCodeStreamIdentityDiagnostics].
  const ClaudeCodeStreamIdentityDiagnostics({
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

  /// The `syntheticEntryIdCreated` value.
  final int syntheticEntryIdCreated;

  /// The `duplicateRawEventDropped` value.
  final int duplicateRawEventDropped;

  /// The `lateContentDropped` value.
  final int lateContentDropped;

  /// The `lateEventDropped` value.
  final int lateEventDropped;

  /// The `missingTurnScopeDropped` value.
  final int missingTurnScopeDropped;

  /// The `identityCollisionDetected` value.
  final int identityCollisionDetected;

  /// The `terminalAccepted` value.
  final int terminalAccepted;

  /// The `duplicateTerminalIgnored` value.
  final int duplicateTerminalIgnored;

  /// The `conflictingTerminalIgnored` value.
  final int conflictingTerminalIgnored;

  @override
  String toString() =>
      'ClaudeCodeStreamIdentityDiagnostics('
      'synthetic=$syntheticEntryIdCreated, '
      'dupRaw=$duplicateRawEventDropped, '
      'lateContent=$lateContentDropped, '
      'lateEvent=$lateEventDropped, '
      'missingScope=$missingTurnScopeDropped, '
      'collision=$identityCollisionDetected, '
      'terminalOk=$terminalAccepted, '
      'dupTerminal=$duplicateTerminalIgnored, '
      'conflictTerminal=$conflictingTerminalIgnored)';
}

/// 已解析到当前 turn generation 的规范化条目身份。
final class ClaudeCodeResolvedEntryIdentity {
  /// Creates a [ClaudeCodeResolvedEntryIdentity].
  const ClaudeCodeResolvedEntryIdentity({
    required this.entryId,
    required this.sessionId,
    required this.turnId,
    required this.generation,
  });

  /// The `entryId` value.
  final String entryId;

  /// The `sessionId` value.
  final String sessionId;

  /// The `turnId` value.
  final String turnId;

  /// The `generation` value.
  final int generation;
}

/// 已解析到当前 turn generation 的元数据身份。
final class ClaudeCodeResolvedTurnIdentity {
  /// Creates a [ClaudeCodeResolvedTurnIdentity].
  const ClaudeCodeResolvedTurnIdentity({
    required this.sessionId,
    required this.turnId,
    required this.generation,
  });

  /// The `sessionId` value.
  final String sessionId;

  /// The `turnId` value.
  final String turnId;

  /// The `generation` value.
  final int generation;
}

/// 工具更新的 identity 解析结果。
final class ClaudeCodeResolvedToolIdentity
    extends ClaudeCodeResolvedTurnIdentity {
  /// Creates a [ClaudeCodeResolvedToolIdentity].
  const ClaudeCodeResolvedToolIdentity({
    required super.sessionId,
    required super.turnId,
    required super.generation,
    required this.isNewTool,
  });

  /// The `isNewTool` value.
  final bool isNewTool;
}

/// first-terminal-wins 的解析结果。
final class ClaudeCodeTerminalResolution
    extends ClaudeCodeResolvedTurnIdentity {
  /// Creates a [ClaudeCodeTerminalResolution].
  const ClaudeCodeTerminalResolution({
    required super.sessionId,
    required super.turnId,
    required super.generation,
    required this.disposition,
    required this.status,
  });

  /// The `disposition` value.
  final ClaudeCodeTerminalDisposition disposition;

  /// The `status` value.
  final AgentHistoryTurnStatus status;

  /// The `accepted` value.
  bool get accepted => disposition == ClaudeCodeTerminalDisposition.accepted;
}

/// 供单测读取的 turn identity 快照（toString 不含 source id 原文，G7）。
final class ClaudeCodeTurnIdentitySnapshot {
  /// Creates a [ClaudeCodeTurnIdentitySnapshot].
  const ClaudeCodeTurnIdentitySnapshot({
    required this.generation,
    required this.messageSegmentOrdinal,
    required this.reasoningPhaseOrdinal,
    required this.sourceMessageEntryCount,
    required this.seenToolCallCount,
    required this.recentRawEventCount,
    required this.terminal,
  });

  /// The `generation` value.
  final int generation;

  /// The `messageSegmentOrdinal` value.
  final int messageSegmentOrdinal;

  /// The `reasoningPhaseOrdinal` value.
  final int reasoningPhaseOrdinal;

  /// 已绑定 source message 的条数（不暴露 source id 原文）。
  final int sourceMessageEntryCount;

  /// The `seenToolCallCount` value.
  final int seenToolCallCount;

  /// The `recentRawEventCount` value.
  final int recentRawEventCount;

  /// The `terminal` value.
  final bool terminal;

  @override
  String toString() =>
      'ClaudeCodeTurnIdentitySnapshot('
      'generation=$generation, '
      'messageOrdinal=$messageSegmentOrdinal, '
      'reasoningOrdinal=$reasoningPhaseOrdinal, '
      'sourceMessageCount=$sourceMessageEntryCount, '
      'toolCount=$seenToolCallCount, '
      'recentRaw=$recentRawEventCount, '
      'terminal=$terminal)';
}

/// Claude Code live/history 流的 Provider-local identity reducer。
///
/// 只保存 identity、边界、去重和终态；不读取或记录正文 / token / raw payload。
/// live 与 history 必须使用独立实例（G3）。
final class ClaudeCodeStreamIdentity {
  /// Creates a [ClaudeCodeStreamIdentity].
  ClaudeCodeStreamIdentity({
    this.maxRecentRawEvents = 512,
    String Function(String value)? identityToken,
  }) : assert(maxRecentRawEvents > 0, 'maxRecentRawEvents must be positive'),
       _identityToken = identityToken ?? _defaultIdentityToken;

  /// The `maxRecentRawEvents` value.
  final int maxRecentRawEvents;
  final String Function(String value) _identityToken;

  final Map<_SessionScopeKey, int> _generations = <_SessionScopeKey, int>{};
  final Map<_SessionScopeKey, _ClaudeCodeTurnState> _activeTurns =
      <_SessionScopeKey, _ClaudeCodeTurnState>{};
  final Map<_TurnLookupKey, _ClaudeCodeTurnState> _turnsById =
      <_TurnLookupKey, _ClaudeCodeTurnState>{};
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
  ClaudeCodeStreamIdentityDiagnostics get diagnostics =>
      ClaudeCodeStreamIdentityDiagnostics(
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
      throw StateError('ClaudeCodeStreamIdentity has been disposed');
    }
    final previousRuntime = _currentRuntimeScope;
    if (previousRuntime != null && previousRuntime != runtimeScope) {
      invalidateRuntime(
        runtimeScope: previousRuntime,
        reason: ClaudeCodeIdentityInvalidationReason.connectionEpochChanged,
      );
    }
    _currentRuntimeScope = runtimeScope;

    final sessionKey = _SessionScopeKey(runtimeScope, sessionId);
    final previous = _activeTurns.remove(sessionKey);
    if (previous != null) {
      _invalidateState(previous, ClaudeCodeIdentityInvalidationReason.newTurn);
    }

    // 同 turnId 复用：旧 tombstone 仍占用 _turnsById，新 generation 须防 entryId 碰撞。
    final lookupKey = _TurnLookupKey(runtimeScope, sessionId, turnId);
    final existingById = _turnsById[lookupKey];
    if (existingById != null) {
      _identityCollisionDetected += 1;
    }

    final generation = (_generations[sessionKey] ?? 0) + 1;
    _generations[sessionKey] = generation;
    final state = _ClaudeCodeTurnState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
      generation: generation,
    );
    _activeTurns[sessionKey] = state;
    _turnsById[lookupKey] = state;
    return generation;
  }

  /// 为正文 block 解析稳定的 message segment entryId。
  ///
  /// 同 [sourceMessageId] 且当前 segment 未关闭 → 同一 entryId；
  /// tool / reasoning 打断后 → 新 segment。
  ///
  /// 字符级 partial 与整帧 text 必须走同一 API，以产出同一 entryId（B2）。
  ClaudeCodeResolvedEntryIdentity? resolveMessage({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? sourceMessageId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
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

    state
      ..closeMessage()
      ..messageSegmentOrdinal += 1;
    final entryId = _createEntryId(
      state: state,
      entryKind: 'message',
      sourceId: sourceMessageId,
      ordinal: state.messageSegmentOrdinal,
    );
    state
      ..currentMessageEntryId = entryId
      ..currentMessageSourceId = sourceMessageId;
    if (sourceMessageId != null) {
      state.sourceMessageEntryIds
          .putIfAbsent(sourceMessageId, () => <String>[])
          .add(entryId);
    }
    return _entryIdentity(state, entryId);
  }

  /// 为连续 thinking block 解析 phase entryId。
  ///
  /// 同 [sourceItemId] 且 phase 未关闭 → 同一 entryId；
  /// text / tool_use 打断后再次 thinking → **新** phase entryId。
  /// eventId 只参与去重，不参与 phase 分段。
  ClaudeCodeResolvedEntryIdentity? resolveReasoning({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? sourceItemId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
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

    state
      ..closeReasoning()
      ..reasoningPhaseOrdinal += 1;
    final entryId = _createEntryId(
      state: state,
      entryKind: 'reasoning',
      sourceId: sourceItemId,
      ordinal: state.reasoningPhaseOrdinal,
    );
    state
      ..currentReasoningEntryId = entryId
      ..currentReasoningSourceId = sourceItemId;
    return _entryIdentity(state, entryId);
  }

  /// 解析 tool start/update；首见 tool id 时关闭当前可见 message/reasoning phase。
  ///
  /// 终态后仍允许**已知** tool 收尾（tool_result 迟到）；未知 tool 丢弃。
  ClaudeCodeResolvedToolIdentity? resolveTool({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String toolCallId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
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
    return ClaudeCodeResolvedToolIdentity(
      sessionId: state.sessionId,
      turnId: state.turnId,
      generation: state.generation,
      isNewTool: !known,
    );
  }

  /// 显式关闭当前 turn 的可见 message / reasoning phase（叙事边界）。
  ///
  /// 返回 false 表示 scope 缺失或已 terminal。
  bool closeVisiblePhases({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
    );
    if (state == null || state.terminal) {
      return false;
    }
    state.closeVisiblePhases();
    return true;
  }

  /// 接受 usage 等非叙事 update；terminal 后仍允许幂等 metadata。
  ClaudeCodeResolvedTurnIdentity? resolveMetadata({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required String? eventId,
    required String eventKind,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
    );
    if (state == null || !_acceptRawEvent(state, eventKind, eventId)) {
      return null;
    }
    return _turnIdentity(state);
  }

  /// 以 first-terminal-wins 完成 turn。
  ClaudeCodeTerminalResolution completeTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required AgentHistoryTurnStatus status,
    required ClaudeCodeTerminalSource source,
    String? eventId,
    String eventKind = 'result',
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
    );
    if (state == null) {
      return ClaudeCodeTerminalResolution(
        sessionId: sessionId,
        turnId: runningTurnId ?? '',
        generation: 0,
        disposition: ClaudeCodeTerminalDisposition.missingScope,
        status: status,
      );
    }
    if (!_acceptRawEvent(state, eventKind, eventId)) {
      _duplicateTerminalIgnored += 1;
      return ClaudeCodeTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: ClaudeCodeTerminalDisposition.duplicate,
        status: state.terminalStatus ?? status,
      );
    }

    if (!state.terminal) {
      state
        ..terminal = true
        ..terminalStatus = status
        ..terminalSource = source
        ..closeVisiblePhases();
      _activeTurns.remove(_SessionScopeKey(runtimeScope, sessionId));
      _terminalAccepted += 1;
      return ClaudeCodeTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: ClaudeCodeTerminalDisposition.accepted,
        status: status,
      );
    }

    if (state.terminalStatus == status) {
      _duplicateTerminalIgnored += 1;
      return ClaudeCodeTerminalResolution(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
        disposition: ClaudeCodeTerminalDisposition.duplicate,
        status: state.terminalStatus!,
      );
    }
    _conflictingTerminalIgnored += 1;
    return ClaudeCodeTerminalResolution(
      sessionId: state.sessionId,
      turnId: state.turnId,
      generation: state.generation,
      disposition: ClaudeCodeTerminalDisposition.conflicting,
      status: state.terminalStatus ?? status,
    );
  }

  /// 使指定 turn state 失效；保留 tombstone 以识别后续迟到事件。
  void invalidateTurn({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
    required ClaudeCodeIdentityInvalidationReason reason,
  }) {
    final state = _resolveState(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      runningTurnId: runningTurnId,
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
    required ClaudeCodeIdentityInvalidationReason reason,
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
    required ClaudeCodeIdentityInvalidationReason reason,
  }) {
    for (final state in _turnsById.values.toSet()) {
      if (state.runtimeScope == runtimeScope && state.sessionId == sessionId) {
        _invalidateState(state, reason);
      }
    }
    _activeTurns.remove(_SessionScopeKey(runtimeScope, sessionId));
  }

  /// 返回指定 turn 的只读状态快照。
  ClaudeCodeTurnIdentitySnapshot? snapshot({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String turnId,
  }) {
    final state = _turnsById[_TurnLookupKey(runtimeScope, sessionId, turnId)];
    if (state == null) {
      return null;
    }
    return ClaudeCodeTurnIdentitySnapshot(
      generation: state.generation,
      messageSegmentOrdinal: state.messageSegmentOrdinal,
      reasoningPhaseOrdinal: state.reasoningPhaseOrdinal,
      sourceMessageEntryCount: state.sourceMessageEntryIds.length,
      seenToolCallCount: state.seenToolCallIds.length,
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
        reason: ClaudeCodeIdentityInvalidationReason.dispose,
      );
    }
    _disposed = true;
    _activeTurns.clear();
    _turnsById.clear();
    _generations.clear();
  }

  _ClaudeCodeTurnState? _resolveState({
    required AgentRuntimeScope runtimeScope,
    required String sessionId,
    required String? runningTurnId,
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
    if (byTurnId != null) {
      if (byTurnId.invalidatedBy != null) {
        if (recordMissing) {
          _missingTurnScopeDropped += 1;
        }
        return null;
      }
      return byTurnId;
    }

    final active = _activeTurns[_SessionScopeKey(runtimeScope, sessionId)];
    // A non-null running turn id has already been resolved through _turnsById.
    // The active-session lookup is only the protocol fallback for frames that
    // omit the running turn id.
    if (active != null && runningTurnId == null) {
      return active;
    }
    if (recordMissing) {
      _missingTurnScopeDropped += 1;
    }
    return null;
  }

  bool _acceptRawEvent(
    _ClaudeCodeTurnState state,
    String kind,
    String? eventId,
  ) {
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
    required _ClaudeCodeTurnState state,
    required String entryKind,
    required String? sourceId,
    required int ordinal,
  }) {
    if (sourceId == null) {
      _syntheticEntryIdCreated += 1;
    }
    // entryId 用 hash 绑定 source，避免把 source id 原文嵌进 entryId 后经
    // diagnostics/snapshot 泄漏（G7）；碰撞时追加 generation 后缀。
    final sourceToken = sourceId == null
        ? 'anon'
        : 's${_identityToken(sourceId)}';
    final base =
        'cc:${_identityToken(state.sessionId)}:'
        '${_identityToken(state.turnId)}:'
        '$entryKind:$sourceToken:$ordinal';
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

  static String _defaultIdentityToken(String value) =>
      value.hashCode.toUnsigned(32).toRadixString(16);

  void _invalidateState(
    _ClaudeCodeTurnState state,
    ClaudeCodeIdentityInvalidationReason reason,
  ) {
    state
      ..invalidatedBy = reason
      ..terminal = true
      ..closeVisiblePhases();
  }

  ClaudeCodeResolvedEntryIdentity _entryIdentity(
    _ClaudeCodeTurnState state,
    String entryId,
  ) => ClaudeCodeResolvedEntryIdentity(
    entryId: entryId,
    sessionId: state.sessionId,
    turnId: state.turnId,
    generation: state.generation,
  );

  ClaudeCodeResolvedTurnIdentity _turnIdentity(_ClaudeCodeTurnState state) =>
      ClaudeCodeResolvedTurnIdentity(
        sessionId: state.sessionId,
        turnId: state.turnId,
        generation: state.generation,
      );
}

final class _ClaudeCodeTurnState {
  _ClaudeCodeTurnState({
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
  ClaudeCodeTerminalSource? terminalSource;
  ClaudeCodeIdentityInvalidationReason? invalidatedBy;

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

@immutable
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

@immutable
final class _TurnLookupKey {
  const _TurnLookupKey(this.runtimeScope, this.sessionId, this.turnId);

  final AgentRuntimeScope runtimeScope;
  final String sessionId;
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is _TurnLookupKey &&
      other.runtimeScope == runtimeScope &&
      other.sessionId == sessionId &&
      other.turnId == turnId;

  @override
  int get hashCode => Object.hash(runtimeScope, sessionId, turnId);
}
