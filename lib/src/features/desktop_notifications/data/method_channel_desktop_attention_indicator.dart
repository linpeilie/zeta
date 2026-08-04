import 'package:flutter/services.dart';

import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';

/// 调用各桌面 Runner 的任务栏、Dock 或 urgency 能力。
final class MethodChannelDesktopAttentionIndicator
    implements DesktopAttentionIndicator {
  MethodChannelDesktopAttentionIndicator({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('zeta/desktop_attention');

  final MethodChannel _channel;

  @override
  Future<void> setUnreadCount(int count) {
    return _channel.invokeMethod<void>('setUnreadCount', <String, Object?>{
      'count': count < 0 ? 0 : count,
    });
  }

  @override
  Future<void> requestAttention() {
    return _channel.invokeMethod<void>('requestAttention');
  }
}
