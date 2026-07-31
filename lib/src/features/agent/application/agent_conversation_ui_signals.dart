import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

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
  });

  /// 已接受并交给 frame scheduler 的普通更新请求数。
  final int scheduledStreamFlushCount;

  /// 已进入立即刷新路径的请求数。
  final int immediateFlushCount;

  /// 未单独发布、而是合并进已有 frame 批次或立即刷新中的请求数。
  final int mergedRequestCount;

  /// 携带至少一个有效 region/effect 并实际执行的 publish 次数。
  final int actualPublishCount;

  /// 旧兼容通知回调的调用次数。
  final int legacyNotifyCount;
}

/// Agent 面板的分区刷新信号发布器。
///
/// 它消费类型化 region/effect 请求，并发布 header/history/composer/
/// pending interaction/live turn 等分区信号，避免流式输出时整页频繁重建。
///
/// 本类只拥有 listenable 与 legacy notify 兼容边界；请求合并和 Flutter frame
/// 调度由 presentation 层的 `AgentUiUpdateScheduler` 负责。
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
  final ValueNotifier<int> _pendingInteractionVersionNotifier =
      ValueNotifier<int>(0);
  final ValueNotifier<int> _expansionVersionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _autoScrollTickNotifier = ValueNotifier<int>(0);

  AgentUiUpdateRequest? _debugLastAcceptedRequest;

  int _actualPublishCount = 0;
  int _legacyNotifyCount = 0;

  /// 当前发布端累计诊断快照。
  ///
  /// 调度相关字段由 ViewModel 与 `AgentUiUpdateScheduler` 的诊断合并后对外暴露；
  /// 直接读取本发布端时这些字段为零。
  AgentConversationUiSignalsDiagnostics get diagnostics =>
      AgentConversationUiSignalsDiagnostics(
        scheduledStreamFlushCount: 0,
        immediateFlushCount: 0,
        mergedRequestCount: 0,
        actualPublishCount: _actualPublishCount,
        legacyNotifyCount: _legacyNotifyCount,
      );

  /// 最近一次实际发布的无 payload 请求，仅用于测试事件映射。
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

  /// 应用由 presentation scheduler 决定好发布时机的类型化 UI 更新请求。
  ///
  /// 此方法不再二次调度，也不合并请求；除 scheduler 回调与本类单元测试外，
  /// 调用方不应绕过 `AgentUiUpdatePort` 直接调用。
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

  void dispose() {
    _historyVersionNotifier.dispose();
    _headerVersionNotifier.dispose();
    _composerVersionNotifier.dispose();
    _pendingInteractionVersionNotifier.dispose();
    _expansionVersionNotifier.dispose();
    _autoScrollTickNotifier.dispose();
  }
}
