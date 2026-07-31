import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';

/// 流式 UI 刷新的最小间隔，用于约束发布频率。
///
/// 帧级 writer 背压见 [AgentConversationUiSignals] 的 stream in-flight 门闩。
const Duration kAgentStreamFlushInterval = Duration(milliseconds: 16);

/// Agent 面板的分区刷新信号与流式节流器。
///
/// 它把 UI 刷新拆成 header/history/composer/pending interaction/
/// live turn/auto scroll 等分区信号，避免流式输出时整页频繁重建。
///
/// ## 流式刷新背压
///
/// - **dirty 合并**：多次 [scheduleStreamFlush] 只合并标志位。
/// - **min interval**：[kAgentStreamFlushInterval]。
/// - **stream in-flight**（Phase 2）：仅 **timer 驱动的纯流式 flush**
///   在上一帧未结束时再 defer 一拍；[flushStreamChangesNow] 关键路径
///   **永不**被门闩阻塞。
class AgentConversationUiSignals {
  AgentConversationUiSignals({
    required this._timeline,
    required this._onLegacyNotify,
    required this._isDisposed,
    this._scheduleAfterFrame,
  });

  final AgentConversationTimelineStore _timeline;
  final VoidCallback _onLegacyNotify;
  final bool Function() _isDisposed;

  /// 测试可注入：替代 post-frame 调度（stream in-flight 释放）。
  final void Function(VoidCallback onFrame)? _scheduleAfterFrame;

  final ValueNotifier<int> _historyVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _headerVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _composerVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _pendingInteractionVersionNotifier =
      ValueNotifier<int>(0);
  final ValueNotifier<int> _expansionVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _autoScrollTickNotifier = ValueNotifier<int>(0);

  Timer? _streamFlushTimer;
  bool _streamNeedsLiveFlush = false;
  bool _streamNeedsHeaderFlush = false;
  bool _streamNeedsComposerFlush = false;
  bool _streamNeedsAutoScroll = false;
  bool _streamNeedsExpansionFlush = false;

  /// 上一拍纯流式 publish 后、帧/事件循环结束前为 true。
  bool _streamPublishInFlight = false;

  /// 诊断：因 stream in-flight 而再 defer 的 timer flush 次数。
  int debugSkippedInFlightStreamFlushCount = 0;

  int get autoScrollTick => _autoScrollTickNotifier.value;

  int get historyVersion => _historyVersionNotifier.value;

  int get headerVersion => _headerVersionNotifier.value;

  int get composerVersion => _composerVersionNotifier.value;

  /// 待处理权限、提问或计划审批列表的变更版本。
  int get pendingInteractionVersion => _pendingInteractionVersionNotifier.value;

  int get expansionVersion => _expansionVersionNotifier.value;

  ValueListenable<int> get historyVersionListenable => _historyVersionNotifier;

  ValueListenable<int> get headerVersionListenable => _headerVersionNotifier;

  ValueListenable<int> get composerVersionListenable =>
      _composerVersionNotifier;

  /// 只在待处理交互变更时通知 Dock，避免跟随流式正文频繁重建。
  ValueListenable<int> get pendingInteractionVersionListenable =>
      _pendingInteractionVersionNotifier;

  ValueListenable<int> get expansionVersionListenable =>
      _expansionVersionNotifier;

  ValueListenable<int> get autoScrollTickListenable => _autoScrollTickNotifier;

  void publish({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool pendingInteraction = false,
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    if (!history &&
        !syncLiveTurn &&
        !header &&
        !composer &&
        !pendingInteraction &&
        !expansion &&
        !liveTurn &&
        !autoScroll) {
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
    if (pendingInteraction) {
      _pendingInteractionVersionNotifier.value += 1;
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
    bool composer = false,
    bool autoScroll = false,
    bool expansion = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    _streamNeedsLiveFlush = true;
    _streamNeedsHeaderFlush = _streamNeedsHeaderFlush || header;
    _streamNeedsComposerFlush = _streamNeedsComposerFlush || composer;
    _streamNeedsAutoScroll = _streamNeedsAutoScroll || autoScroll;
    _streamNeedsExpansionFlush = _streamNeedsExpansionFlush || expansion;
    // 单例 timer：同一窗口内多次 schedule 只合并标志。
    _streamFlushTimer ??= Timer(
      kAgentStreamFlushInterval,
      flushPendingStreamChangesNow,
    );
  }

  /// Timer 驱动的纯流式 flush；受 stream in-flight 门闩约束。
  void flushPendingStreamChangesNow() {
    if (_isDisposed()) {
      return;
    }
    // 关键标志不应走 timer 路径长期滞留；若已有 composer 等，改立即 force。
    final hasCriticalScheduled = _streamNeedsComposerFlush;
    if (hasCriticalScheduled) {
      flushStreamChangesNow();
      return;
    }

    if (_streamPublishInFlight) {
      // 保留 dirty 标志并延后一拍，等待当前发布完成。
      debugSkippedInFlightStreamFlushCount += 1;
      _streamFlushTimer = Timer(
        kAgentStreamFlushInterval,
        flushPendingStreamChangesNow,
      );
      return;
    }

    _streamFlushTimer = null;
    final live = _streamNeedsLiveFlush;
    final header = _streamNeedsHeaderFlush;
    final autoScroll = _streamNeedsAutoScroll;
    final expansion = _streamNeedsExpansionFlush;
    _streamNeedsLiveFlush = false;
    _streamNeedsHeaderFlush = false;
    _streamNeedsComposerFlush = false;
    _streamNeedsAutoScroll = false;
    _streamNeedsExpansionFlush = false;

    if (!live && !header && !autoScroll && !expansion) {
      return;
    }

    publish(
      header: header,
      expansion: expansion,
      liveTurn: live,
      autoScroll: autoScroll,
    );
    _armStreamPublishInFlight();
  }

  /// 关键路径立即发布；**永不**被 stream in-flight 阻塞。
  ///
  /// 会取消 timer 并吸收已调度的 stream 标志。
  void flushStreamChangesNow({
    bool history = false,
    bool syncLiveTurn = false,
    bool header = false,
    bool composer = false,
    bool pendingInteraction = false,
    bool expansion = false,
    bool liveTurn = false,
    bool autoScroll = false,
  }) {
    if (_isDisposed()) {
      return;
    }
    final scheduledLiveFlush = _streamNeedsLiveFlush;
    final scheduledHeaderFlush = _streamNeedsHeaderFlush;
    final scheduledComposerFlush = _streamNeedsComposerFlush;
    final scheduledAutoScroll = _streamNeedsAutoScroll;
    final scheduledExpansionFlush = _streamNeedsExpansionFlush;
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _streamNeedsLiveFlush = false;
    _streamNeedsHeaderFlush = false;
    _streamNeedsComposerFlush = false;
    _streamNeedsAutoScroll = false;
    _streamNeedsExpansionFlush = false;
    publish(
      history: history,
      syncLiveTurn: syncLiveTurn,
      header: header || scheduledHeaderFlush,
      composer: composer || scheduledComposerFlush,
      pendingInteraction: pendingInteraction,
      expansion: expansion || scheduledExpansionFlush,
      liveTurn: liveTurn || scheduledLiveFlush,
      autoScroll: autoScroll || scheduledAutoScroll,
    );
    // 关键路径不占用 stream in-flight 门闩，避免阻塞后续 cadence。
  }

  void dispose() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _historyVersionNotifier.dispose();
    _headerVersionNotifier.dispose();
    _composerVersionNotifier.dispose();
    _pendingInteractionVersionNotifier.dispose();
    _expansionVersionNotifier.dispose();
    _autoScrollTickNotifier.dispose();
  }

  void _armStreamPublishInFlight() {
    if (_streamPublishInFlight) {
      return;
    }
    _streamPublishInFlight = true;
    var completed = false;
    void release() {
      if (completed) {
        return;
      }
      completed = true;
      _streamPublishInFlight = false;
    }

    final injected = _scheduleAfterFrame;
    if (injected != null) {
      injected(release);
      return;
    }

    try {
      final scheduler = SchedulerBinding.instance;
      scheduler.addPostFrameCallback((_) => release());
      scheduler.ensureVisualUpdate();
      // 单测无 pump 时兜底释放，避免门闩永久卡住。
      Timer(Duration.zero, release);
    } catch (_) {
      scheduleMicrotask(release);
    }
  }
}
