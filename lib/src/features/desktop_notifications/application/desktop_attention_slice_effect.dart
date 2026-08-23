import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';

/// Desktop Attention reducer 产出的副作用描述。
sealed class DesktopAttentionSliceEffect {
  const DesktopAttentionSliceEffect();
}

final class DesktopAttentionRequestPermissionsEffect
    extends DesktopAttentionSliceEffect {
  const DesktopAttentionRequestPermissionsEffect();
}

final class DesktopAttentionShowNotificationEffect
    extends DesktopAttentionSliceEffect {
  const DesktopAttentionShowNotificationEffect(this.unread);

  final DesktopUnreadAttention unread;
}

final class DesktopAttentionCancelNotificationsEffect
    extends DesktopAttentionSliceEffect {
  DesktopAttentionCancelNotificationsEffect(Iterable<int> notificationIds)
    : notificationIds = List<int>.unmodifiable(notificationIds);

  final List<int> notificationIds;
}

final class DesktopAttentionSyncIndicatorEffect
    extends DesktopAttentionSliceEffect {
  const DesktopAttentionSyncIndicatorEffect({
    required this.unreadCount,
    this.requestAttention = false,
  });

  final int unreadCount;
  final bool requestAttention;
}

final class DesktopAttentionActivateNotificationEffect
    extends DesktopAttentionSliceEffect {
  const DesktopAttentionActivateNotificationEffect(this.payload);

  final String payload;
}
