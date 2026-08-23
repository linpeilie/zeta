import 'dart:convert';

/// 系统通知 payload 的白名单定位信息。
final class DesktopNotificationPayload {
  const DesktopNotificationPayload({
    required this.providerId,
    required this.threadId,
    this.identity,
  });

  final String providerId;
  final String threadId;
  final String? identity;
}

abstract final class DesktopNotificationPayloadCodec {
  static const int version = 1;

  static String encode(DesktopNotificationPayload payload) {
    return jsonEncode(<String, Object?>{
      'version': version,
      'providerId': payload.providerId,
      'threadId': payload.threadId,
      'identity': payload.identity,
    });
  }

  static DesktopNotificationPayload? tryDecode(String payload) {
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map || raw['version'] != version) {
        return null;
      }
      final providerId = raw['providerId'];
      final threadId = raw['threadId'];
      final identity = raw['identity'];
      if (providerId is! String ||
          providerId.trim().isEmpty ||
          threadId is! String ||
          threadId.trim().isEmpty ||
          (identity != null && identity is! String)) {
        return null;
      }
      return DesktopNotificationPayload(
        providerId: providerId,
        threadId: threadId,
        identity: identity as String?,
      );
    } on FormatException {
      return null;
    }
  }
}
