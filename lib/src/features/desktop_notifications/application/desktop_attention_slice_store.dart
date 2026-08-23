import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_intent.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_reducer.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

abstract interface class DesktopAttentionSliceEffectRunner {
  Future<void> run(DesktopAttentionSliceEffect effect);
}

/// Desktop Attention 的唯一状态 owner。
final class DesktopAttentionSliceStore {
  DesktopAttentionSliceStore({
    required this._effectRunner,
    DesktopAttentionSliceState? initialState,
  }) : _state = initialState ?? DesktopAttentionSliceState();

  final DesktopAttentionSliceEffectRunner _effectRunner;
  final List<void Function()> _listeners = <void Function()>[];
  DesktopAttentionSliceState _state;
  bool _closed = false;

  DesktopAttentionSliceState get state => _state;
  int get unreadCount => _state.unreadCount;
  bool get isClosed => _closed;

  void addListener(void Function() listener) {
    if (!_closed && !_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<void> dispatch(DesktopAttentionSliceIntent intent) async {
    if (_closed) {
      return;
    }
    final before = _state;
    final transition = desktopAttentionSliceReduce(before, intent);
    if (!identical(transition.state, before) && transition.state != before) {
      _state = transition.state;
      for (final listener in List<void Function()>.of(_listeners)) {
        listener();
      }
    }
    for (final effect in transition.effects) {
      if (_closed) {
        return;
      }
      await _effectRunner.run(effect);
    }
  }

  Future<void> initialized(AgentNotificationSettings settings) =>
      dispatch(DesktopAttentionInitialized(settings));

  Future<void> settingsChanged(AgentNotificationSettings settings) =>
      dispatch(DesktopAttentionSettingsChanged(settings));

  Future<void> updateVisibility(DesktopAttentionVisibility visibility) =>
      dispatch(DesktopAttentionVisibilityChanged(visibility));

  Future<void> handleAttention(AgentWorkspaceAttention attention) =>
      dispatch(DesktopAttentionReceived(attention));

  Future<void> markThreadRead(String providerId, String threadId) =>
      dispatch(DesktopAttentionThreadRead(providerId, threadId));

  Future<void> removeIdentity(String identity) =>
      dispatch(DesktopAttentionIdentityRemoved(identity));

  Future<void> handleActivation(String? payload) {
    final normalized = payload?.trim();
    if (normalized == null || normalized.isEmpty) {
      return Future<void>.value();
    }
    return dispatch(DesktopAttentionNotificationActivated(normalized));
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _listeners.clear();
  }
}
