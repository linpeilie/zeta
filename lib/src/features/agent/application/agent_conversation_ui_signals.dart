import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';

/// Agent 面板的分区刷新信号与流式节流器。
///
/// 它把 UI 刷新拆成 header/history/composer/live turn/auto scroll 五类信号，
/// 避免流式输出时整页频繁重建。
class AgentConversationUiSignals {
  AgentConversationUiSignals({
    required this._timeline,
    required this._onLegacyNotify,
    required this._isDisposed,
  });

  final AgentConversationTimelineStore _timeline;
  final VoidCallback _onLegacyNotify;
  final bool Function() _isDisposed;

  final ValueNotifier<int> _historyVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _headerVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _composerVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _expansionVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _autoScrollTickNotifier = ValueNotifier<int>(0);

  Timer? _streamFlushTimer;
  bool _streamNeedsLiveFlush = false;
  bool _streamNeedsHeaderFlush = false;
  bool _streamNeedsAutoScroll = false;
  bool _streamNeedsExpansionFlush = false;

  int get autoScrollTick => _autoScrollTickNotifier.value;

  int get historyVersion => _historyVersionNotifier.value;

  int get headerVersion => _headerVersionNotifier.value;

  int get composerVersion => _composerVersionNotifier.value;

  int get expansionVersion => _expansionVersionNotifier.value;

  ValueListenable<int> get historyVersionListenable => _historyVersionNotifier;

  ValueListenable<int> get headerVersionListenable => _headerVersionNotifier;

  ValueListenable<int> get composerVersionListenable =>
      _composerVersionNotifier;

  ValueListenable<int> get expansionVersionListenable =>
      _expansionVersionNotifier;

  ValueListenable<int> get autoScrollTickListenable => _autoScrollTickNotifier;

  void publish({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    if (syncLiveTurn) {
      _timeline.syncLiveTurnBinding();
    }
    if (history) {
      _historyVersionNotifier.value += 1;
    }
    if (header) {
      _headerVersionNotifier.value += 1;
    }
    if (composer) {
      _composerVersionNotifier.value += 1;
    }
    if (expansion) {
      _expansionVersionNotifier.value += 1;
    }
    if (liveTurn) {
      _timeline.liveTurnState?.markDirty();
      _timeline.liveTurnState?.flushNow();
    }
    if (autoScroll) {
      _autoScrollTickNotifier.value += 1;
    }
    _onLegacyNotify();
  }

  void scheduleStreamFlush({
    bool header = false,
    bool autoScroll = false,
    bool expansion = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    _streamNeedsLiveFlush = true;
    _streamNeedsHeaderFlush = _streamNeedsHeaderFlush || header;
    _streamNeedsAutoScroll = _streamNeedsAutoScroll || autoScroll;
    _streamNeedsExpansionFlush = _streamNeedsExpansionFlush || expansion;
    _streamFlushTimer ??= Timer(
      const Duration(milliseconds: 16),
      flushPendingStreamChangesNow,
    );
  }

  void flushPendingStreamChangesNow() {
    flushStreamChangesNow();
  }

  void flushStreamChangesNow({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    final scheduledLiveFlush = _streamNeedsLiveFlush;
    final scheduledHeaderFlush = _streamNeedsHeaderFlush;
    final scheduledAutoScroll = _streamNeedsAutoScroll;
    final scheduledExpansionFlush = _streamNeedsExpansionFlush;
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _streamNeedsLiveFlush = false;
    _streamNeedsHeaderFlush = false;
    _streamNeedsAutoScroll = false;
    _streamNeedsExpansionFlush = false;
    publish(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header || scheduledHeaderFlush,
      composer: composer,
      expansion: expansion || scheduledExpansionFlush,
      liveTurn: liveTurn || scheduledLiveFlush,
      autoScroll: autoScroll || scheduledAutoScroll,
    );
  }

  void dispose() {
    _streamFlushTimer?.cancel();
    _historyVersionNotifier.dispose();
    _headerVersionNotifier.dispose();
    _composerVersionNotifier.dispose();
    _expansionVersionNotifier.dispose();
    _autoScrollTickNotifier.dispose();
  }
}
