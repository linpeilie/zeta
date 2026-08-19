/// Shows already-localized desktop notifications.
// A port intentionally groups this capability behind an injectable interface.
// ignore: one_member_abstracts
abstract interface class DesktopNotificationApi {
  /// Shows a notification. This package performs no localization.
  Future<void> show({
    required String title,
    required String body,
    String? tag,
  });
}

/// Controls platform attention indicators such as Dock or taskbar badges.
abstract interface class DesktopAttentionApi {
  /// Sets the unread badge count. Implementations clamp negative values to 0.
  Future<void> setBadgeCount(int count);

  /// Requests non-critical user attention.
  Future<void> requestUserAttention();
}
