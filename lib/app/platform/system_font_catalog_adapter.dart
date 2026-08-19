import 'dart:collection';

import 'package:desktop_platform_api/desktop_platform_api.dart';

import 'package:zeta/app/platform/method_channel_facade.dart';

/// Method-channel implementation of [SystemFontCatalogApi].
final class MethodChannelSystemFontCatalogAdapter
    implements SystemFontCatalogApi {
  /// Creates an adapter with an injected channel facade.
  const MethodChannelSystemFontCatalogAdapter(this._channel);

  /// Native channel name.
  static const channelName = 'zeta/system_fonts';

  final PlatformMethodChannelFacade _channel;

  @override
  Future<List<SystemFontFamily>> listFontFamilies({
    required String localeName,
  }) async {
    final raw = await _channel.invokeMethod<Object?>(
      'listFontFamilies',
      <String, Object?>{'locale': localeName},
    );
    if (raw == null) {
      return const <SystemFontFamily>[];
    }
    if (raw is! List<Object?>) {
      throw const FormatException('System font response must be a list.');
    }
    final unique = <String, SystemFontFamily>{};
    for (final value in raw) {
      final family = SystemFontFamily.tryDecode(value);
      if (family != null) {
        unique.putIfAbsent(family.id.toLowerCase(), () => family);
      }
    }
    final families = unique.values.toList(growable: false)
      ..sort(
        (left, right) => left.displayName.toLowerCase().compareTo(
          right.displayName.toLowerCase(),
        ),
      );
    return UnmodifiableListView<SystemFontFamily>(families);
  }
}
