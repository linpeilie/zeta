import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_intent.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Desktop Attention 的纯同步 reducer。
Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>
desktopAttentionSliceReduce(
  DesktopAttentionSliceState state,
  DesktopAttentionSliceIntent intent,
) {
  return switch (intent) {
    DesktopAttentionInitialized(:final settings) => _settingsChanged(
      state,
      settings,
      initialized: true,
      requestPermissions: settings.enabled,
    ),
    DesktopAttentionSettingsChanged(:final settings) => _settingsChanged(
      state,
      settings,
      requestPermissions: !state.settings.enabled && settings.enabled,
    ),
    DesktopAttentionVisibilityChanged(:final visibility) => _visibilityChanged(
      state,
      visibility,
    ),
    DesktopAttentionReceived(:final attention) => _attentionReceived(
      state,
      attention,
    ),
    DesktopAttentionThreadRead(:final providerId, :final threadId) =>
      _removeWhere(
        state,
        (unread) =>
            unread.attention.providerId == providerId &&
            unread.attention.threadId == threadId,
      ),
    DesktopAttentionIdentityRemoved(:final identity) => _removeWhere(
      state,
      (unread) => unread.attention.identity == identity,
    ),
    DesktopAttentionNotificationActivated(:final payload) =>
      Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>(
        state,
        <DesktopAttentionSliceEffect>[
          DesktopAttentionActivateNotificationEffect(payload),
        ],
      ),
  };
}

Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>
_settingsChanged(
  DesktopAttentionSliceState state,
  AgentNotificationSettings settings, {
  bool initialized = false,
  bool requestPermissions = false,
}) {
  final retained = <String, DesktopUnreadAttention>{};
  final removedIds = <int>[];
  for (final entry in state.unreadByIdentity.entries) {
    if (_isEnabled(entry.value.attention.signal.kind, settings)) {
      retained[entry.key] = entry.value;
    } else {
      removedIds.add(entry.value.notificationId);
    }
  }
  final next = state.copyWith(
    initialized: initialized || state.initialized,
    settings: settings,
    unreadByIdentity: retained,
  );
  final effects = <DesktopAttentionSliceEffect>[
    if (requestPermissions) const DesktopAttentionRequestPermissionsEffect(),
    if (removedIds.isNotEmpty)
      DesktopAttentionCancelNotificationsEffect(removedIds),
    if (removedIds.isNotEmpty)
      DesktopAttentionSyncIndicatorEffect(unreadCount: retained.length),
  ];
  return Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>(
    next,
    effects,
  );
}

Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>
_visibilityChanged(
  DesktopAttentionSliceState state,
  DesktopAttentionVisibility visibility,
) {
  final next = state.copyWith(visibility: visibility);
  if (!visibility.windowFocused ||
      !visibility.agentCanvasVisible ||
      visibility.providerId == null ||
      visibility.threadId == null) {
    return Transition<
      DesktopAttentionSliceState,
      DesktopAttentionSliceEffect
    >.stateOnly(next);
  }
  return _removeWhere(
    next,
    (unread) =>
        unread.attention.providerId == visibility.providerId &&
        unread.attention.threadId == visibility.threadId,
  );
}

Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>
_attentionReceived(
  DesktopAttentionSliceState state,
  AgentWorkspaceAttention attention,
) {
  if (attention.signal.phase == AgentAttentionPhase.resolved) {
    return _removeWhere(
      state,
      (unread) => unread.attention.identity == attention.identity,
    );
  }
  if (!_isEnabled(attention.signal.kind, state.settings) ||
      state.visibility.shows(attention) ||
      state.unreadByIdentity.containsKey(attention.identity)) {
    return Transition<
      DesktopAttentionSliceState,
      DesktopAttentionSliceEffect
    >.none(state);
  }

  final notificationId = state.nextNotificationId + 1;
  final unread = DesktopUnreadAttention(
    attention: attention,
    notificationId: notificationId,
  );
  final unreadByIdentity = <String, DesktopUnreadAttention>{
    ...state.unreadByIdentity,
    attention.identity: unread,
  };
  final wasEmpty = state.unreadByIdentity.isEmpty;
  return Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>(
    state.copyWith(
      unreadByIdentity: unreadByIdentity,
      nextNotificationId: notificationId,
    ),
    <DesktopAttentionSliceEffect>[
      DesktopAttentionSyncIndicatorEffect(
        unreadCount: unreadByIdentity.length,
        requestAttention: wasEmpty,
      ),
      DesktopAttentionShowNotificationEffect(unread),
    ],
  );
}

Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>
_removeWhere(
  DesktopAttentionSliceState state,
  bool Function(DesktopUnreadAttention unread) predicate,
) {
  final retained = <String, DesktopUnreadAttention>{};
  final removedIds = <int>[];
  for (final entry in state.unreadByIdentity.entries) {
    if (predicate(entry.value)) {
      removedIds.add(entry.value.notificationId);
    } else {
      retained[entry.key] = entry.value;
    }
  }
  if (removedIds.isEmpty) {
    return Transition<
      DesktopAttentionSliceState,
      DesktopAttentionSliceEffect
    >.none(state);
  }
  return Transition<DesktopAttentionSliceState, DesktopAttentionSliceEffect>(
    state.copyWith(unreadByIdentity: retained),
    <DesktopAttentionSliceEffect>[
      DesktopAttentionCancelNotificationsEffect(removedIds),
      DesktopAttentionSyncIndicatorEffect(unreadCount: retained.length),
    ],
  );
}

bool _isEnabled(AgentAttentionKind kind, AgentNotificationSettings settings) {
  if (!settings.enabled) {
    return false;
  }
  return switch (kind) {
    AgentAttentionKind.turnCompleted ||
    AgentAttentionKind.turnFailed ||
    AgentAttentionKind.turnInterrupted => settings.turnTerminalEnabled,
    AgentAttentionKind.permissionRequired ||
    AgentAttentionKind.questionRequired ||
    AgentAttentionKind.planApprovalRequired ||
    AgentAttentionKind.planExecutionRequired => settings.actionRequiredEnabled,
  };
}
