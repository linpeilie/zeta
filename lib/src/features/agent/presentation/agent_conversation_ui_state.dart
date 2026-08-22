import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Typed UI state 发布端的累计只读诊断。
///
/// 仅包含调度与发布次数，不包含消息正文、Provider payload 或用户数据。
@immutable
final class AgentConversationUiStateDiagnostics {
  const AgentConversationUiStateDiagnostics({required this.publishCount});

  final int publishCount;
}

/// 将类型化 UI 更新请求发布到结构值 listenable 与一次性 effect stream。
///
/// effect stream 是无 replay 的瞬时通道，只用于当前挂载的活动 AgentPane；
/// 历史与 live turn 数据仍由 TimelineStore 保存。
final class AgentConversationUiStateStore {
  factory AgentConversationUiStateStore({
    required AgentConversationTimelineStore timeline,
    required AgentHeaderState Function() buildHeaderState,
    required AgentComposerState Function() buildComposerState,
    required AgentPendingInteractionState Function()
    buildPendingInteractionState,
    required AgentExpansionState Function() buildExpansionState,
    required AgentConversationHistoryState Function() buildHistoryState,
    required bool Function() isDisposed,
  }) {
    return AgentConversationUiStateStore._(
      timeline: timeline,
      buildHeaderState: buildHeaderState,
      buildComposerState: buildComposerState,
      buildPendingInteractionState: buildPendingInteractionState,
      buildExpansionState: buildExpansionState,
      buildHistoryState: buildHistoryState,
      isDisposed: isDisposed,
    );
  }

  AgentConversationUiStateStore._({
    required this._timeline,
    required this._buildHeaderState,
    required this._buildComposerState,
    required this._buildPendingInteractionState,
    required this._buildExpansionState,
    required this._buildHistoryState,
    required this._isDisposed,
  }) {
    _header = ValueNotifier<AgentHeaderState>(_buildHeaderState());
    _composer = ValueNotifier<AgentComposerState>(_buildComposerState());
    _pendingInteractions = ValueNotifier<AgentPendingInteractionState>(
      _buildPendingInteractionState(),
    );
    _expansion = ValueNotifier<AgentExpansionState>(_buildExpansionState());
    _history = ValueNotifier<AgentConversationHistoryState>(
      _buildHistoryState(),
    );
  }

  final AgentConversationTimelineStore _timeline;
  final AgentHeaderState Function() _buildHeaderState;
  final AgentComposerState Function() _buildComposerState;
  final AgentPendingInteractionState Function() _buildPendingInteractionState;
  final AgentExpansionState Function() _buildExpansionState;
  final AgentConversationHistoryState Function() _buildHistoryState;
  final bool Function() _isDisposed;

  late final ValueNotifier<AgentHeaderState> _header;
  late final ValueNotifier<AgentComposerState> _composer;
  late final ValueNotifier<AgentPendingInteractionState> _pendingInteractions;
  late final ValueNotifier<AgentExpansionState> _expansion;
  late final ValueNotifier<AgentConversationHistoryState> _history;
  final StreamController<AgentUiEffect> _effectController =
      StreamController<AgentUiEffect>.broadcast(sync: true);

  AgentUiUpdateRequest? _debugLastAcceptedRequest;
  int _publishCount = 0;
  bool _closed = false;

  ValueListenable<AgentHeaderState> get header => _header;

  ValueListenable<AgentComposerState> get composer => _composer;

  ValueListenable<AgentPendingInteractionState> get pendingInteractions =>
      _pendingInteractions;

  ValueListenable<AgentExpansionState> get expansion => _expansion;

  ValueListenable<AgentConversationHistoryState> get history => _history;

  /// 无 replay 的一次性 UI effect。
  Stream<AgentUiEffect> get effects => _effectController.stream;

  AgentConversationUiStateDiagnostics get diagnostics =>
      AgentConversationUiStateDiagnostics(publishCount: _publishCount);

  @visibleForTesting
  AgentUiUpdateRequest? get debugLastAcceptedRequest =>
      _debugLastAcceptedRequest;

  void publish(AgentUiUpdateRequest request) {
    if (_closed || _isDisposed() || request.isEmpty) {
      return;
    }
    _debugLastAcceptedRequest = request;
    _publishCount += 1;

    if (request.regions.contains(AgentUiRegion.liveTurnBinding)) {
      _timeline.syncLiveTurnBinding();
    }
    if (request.regions.contains(AgentUiRegion.history)) {
      _publishIfChanged(_history, _buildHistoryState());
    }
    if (request.regions.contains(AgentUiRegion.header)) {
      _publishIfChanged(_header, _buildHeaderState());
    }
    if (request.regions.contains(AgentUiRegion.composer)) {
      _publishIfChanged(_composer, _buildComposerState());
    }
    if (request.regions.contains(AgentUiRegion.pendingInteraction)) {
      _publishIfChanged(_pendingInteractions, _buildPendingInteractionState());
    }
    if (request.regions.contains(AgentUiRegion.expansion)) {
      _publishIfChanged(_expansion, _buildExpansionState());
    }
    if (request.regions.contains(AgentUiRegion.liveTurn)) {
      _timeline.liveTurnState?.markDirty();
      _timeline.liveTurnState?.flushNow();
    }
    for (final effect in request.effects) {
      _effectController.add(effect);
    }
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _header.dispose();
    _composer.dispose();
    _pendingInteractions.dispose();
    _expansion.dispose();
    _history.dispose();
    unawaited(_effectController.close());
  }
}

void _publishIfChanged<T>(ValueNotifier<T> notifier, T next) {
  if (notifier.value != next) {
    notifier.value = next;
  }
}
