import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

/// 流式 UI 刷新的最小间隔，用于约束发布频率。
///
/// 帧级 writer 背压见 [AgentConversationUiSignals] 的 stream in-flight 门闩。
const Duration kAgentStreamFlushInterval = Duration(milliseconds: 16);

/// [AgentConversationUiSignals] 的累计只读诊断快照。
///
/// 快照只包含调度与发布次数，不包含消息正文、Provider payload 或任何用户数据。
@immutable
final class AgentConversationUiSignalsDiagnostics {
  const AgentConversationUiSignalsDiagnostics({
    required this.scheduledStreamFlushCount,
    required this.immediateFlushCount,
    required this.mergedRequestCount,
    required this.actualPublishCount,
    required this.legacyNotifyCount,
    required this.skippedInFlightStreamFlushCount,
  });

  /// 已接受的 [AgentConversationUiSignals.scheduleStreamFlush] 请求数。
  final int scheduledStreamFlushCount;

  /// 已进入立即刷新路径的次数，包含 timer 将关键请求升级为立即刷新的情况。
  final int immediateFlushCount;

  /// 未单独发布、而是合并进已有普通批次或立即刷新中的请求数。
  final int mergedRequestCount;

  /// 携带至少一个有效 region/effect 并实际执行的 publish 次数。
  final int actualPublishCount;

  /// 旧兼容通知回调的调用次数。
  final int legacyNotifyCount;

  /// 因上一拍纯流式 publish 尚未释放而延后的 timer flush 次数。
  final int skippedInFlightStreamFlushCount;
}

/// Agent 面板的分区刷新信号与流式节流器。
///
/// 它消费类型化 region/effect 请求，并发布 header/history/composer/
/// pending interaction/live turn 等分区信号，避免流式输出时整页频繁重建。
///
/// ## 流式刷新背压
///
/// - **dirty 合并**：多次 [scheduleStreamFlush] 合并 region 与 effect。
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
  AgentUiUpdateRequest _pendingStreamRequest = AgentUiUpdateRequest.none;
  AgentUiUpdateRequest? _debugLastAcceptedRequest;

  /// 上一拍纯流式 publish 后、帧/事件循环结束前为 true。
  bool _streamPublishInFlight = false;

  int _scheduledStreamFlushCount = 0;
  int _immediateFlushCount = 0;
  int _mergedRequestCount = 0;
  int _actualPublishCount = 0;
  int _legacyNotifyCount = 0;
  int _skippedInFlightStreamFlushCount = 0;

  /// 当前累计诊断快照。
  AgentConversationUiSignalsDiagnostics get diagnostics =>
      AgentConversationUiSignalsDiagnostics(
        scheduledStreamFlushCount: _scheduledStreamFlushCount,
        immediateFlushCount: _immediateFlushCount,
        mergedRequestCount: _mergedRequestCount,
        actualPublishCount: _actualPublishCount,
        legacyNotifyCount: _legacyNotifyCount,
        skippedInFlightStreamFlushCount: _skippedInFlightStreamFlushCount,
      );

  /// 兼容既有测试诊断入口；新测试优先读取 [diagnostics]。
  int get debugSkippedInFlightStreamFlushCount =>
      _skippedInFlightStreamFlushCount;

  /// 最近一次被入口接受或合并后的无 payload 请求，仅用于测试事件映射。
  @visibleForTesting
  AgentUiUpdateRequest? get debugLastAcceptedRequest =>
      _debugLastAcceptedRequest;

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

  /// 在当前同步发布边界应用一个类型化 UI 更新请求。
  ///
  /// [AgentUiUpdateRequest.urgency] 描述请求抵达该边界之前的调度意图；
  /// 此方法不再二次调度，以保持既有同步发布行为。
  void publish(AgentUiUpdateRequest request) {
    if (_isDisposed()) {
      return;
    }
    if (request.isEmpty) {
      return;
    }
    _debugLastAcceptedRequest = request;
    _actualPublishCount += 1;
    if (request.regions.contains(AgentUiRegion.liveTurnBinding)) {
      _timeline.syncLiveTurnBinding();
    }
    if (request.regions.contains(AgentUiRegion.history)) {
      _historyVersionNotifier.value += 1;
    }
    if (request.regions.contains(AgentUiRegion.header)) {
      _headerVersionNotifier.value += 1;
    }
    if (request.regions.contains(AgentUiRegion.composer)) {
      _composerVersionNotifier.value += 1;
    }
    if (request.regions.contains(AgentUiRegion.pendingInteraction)) {
      _pendingInteractionVersionNotifier.value += 1;
    }
    if (request.regions.contains(AgentUiRegion.expansion)) {
      _expansionVersionNotifier.value += 1;
    }
    if (request.regions.contains(AgentUiRegion.liveTurn)) {
      _timeline.liveTurnState?.markDirty();
      _timeline.liveTurnState?.flushNow();
    }
    for (final effect in request.effects) {
      if (effect is AgentRequestAutoScroll) {
        // Widget 暂时仍订阅旧 tick；类型化 effect 在此兼容边界被消费一次。
        _autoScrollTickNotifier.value += 1;
      }
    }
    _legacyNotifyCount += 1;
    _onLegacyNotify();
  }

  /// 将 next-frame 请求合并进既有 16 ms 流式刷新窗口。
  void scheduleStreamFlush(AgentUiUpdateRequest request) {
    assert(
      request.urgency == AgentUiUpdateUrgency.nextFrame,
      'scheduleStreamFlush 只接受 nextFrame 请求。',
    );
    if (_isDisposed()) {
      return;
    }
    if (request.isEmpty) {
      return;
    }
    _scheduledStreamFlushCount += 1;
    if (_hasPendingStreamChanges) {
      _mergedRequestCount += 1;
    }
    _pendingStreamRequest = _pendingStreamRequest.mergedWith(request);
    _debugLastAcceptedRequest = _pendingStreamRequest;
    // 单例 timer：同一窗口内多次 schedule 只合并类型化请求。
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
    // 关键 region 不应走 timer 路径长期滞留；若已有 composer，改立即 force。
    final hasCriticalScheduled = _pendingStreamRequest.regions.contains(
      AgentUiRegion.composer,
    );
    if (hasCriticalScheduled) {
      flushStreamChangesNow(
        AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
      );
      return;
    }

    if (_streamPublishInFlight) {
      // 保留 dirty 标志并延后一拍，等待当前发布完成。
      _skippedInFlightStreamFlushCount += 1;
      _streamFlushTimer = Timer(
        kAgentStreamFlushInterval,
        flushPendingStreamChangesNow,
      );
      return;
    }

    _streamFlushTimer = null;
    final request = _takePendingStreamRequest();
    if (request.isEmpty) {
      return;
    }

    publish(request);
    _armStreamPublishInFlight();
  }

  /// 关键路径立即发布；**永不**被 stream in-flight 阻塞。
  ///
  /// 会取消 timer 并吸收已调度的 stream 请求。
  void flushStreamChangesNow(AgentUiUpdateRequest request) {
    assert(
      request.urgency == AgentUiUpdateUrgency.immediate,
      'flushStreamChangesNow 只接受 immediate 请求。',
    );
    if (_isDisposed()) {
      return;
    }
    _immediateFlushCount += 1;
    if (_hasPendingStreamChanges) {
      _mergedRequestCount += 1;
    }
    final mergedRequest = _pendingStreamRequest.mergedWith(request);
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamRequest = AgentUiUpdateRequest.none;
    publish(mergedRequest);
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

  AgentUiUpdateRequest _takePendingStreamRequest() {
    final request = _pendingStreamRequest;
    _pendingStreamRequest = AgentUiUpdateRequest.none;
    return request;
  }

  bool get _hasPendingStreamChanges => !_pendingStreamRequest.isEmpty;
}
