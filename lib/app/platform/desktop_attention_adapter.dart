import 'package:desktop_platform_api/desktop_platform_api.dart';

import 'package:zeta/app/platform/method_channel_facade.dart';

/// Method-channel implementation of [DesktopAttentionApi].
final class MethodChannelDesktopAttentionAdapter
    implements DesktopAttentionApi {
  /// Creates an adapter with an injected channel facade.
  const MethodChannelDesktopAttentionAdapter(this._channel);

  /// Native channel name.
  static const channelName = 'zeta/desktop_attention';

  final PlatformMethodChannelFacade _channel;

  @override
  Future<void> requestUserAttention() =>
      _channel.invokeMethod<void>('requestAttention');

  @override
  Future<void> setBadgeCount(int count) =>
      _channel.invokeMethod<void>('setUnreadCount', <String, Object?>{
        'count': count < 0 ? 0 : count,
      });
}
