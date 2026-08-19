import 'package:desktop_platform_api/desktop_platform_api.dart';

/// Injectable facade for the desktop notification plugin.
abstract interface class DesktopNotificationPluginFacade {
  /// Initializes the desktop plugin and requests required permissions.
  Future<void> initialize();

  /// Shows a platform notification.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

/// Implements [DesktopNotificationApi] through an injected plugin facade.
final class FlutterDesktopNotificationAdapter
    implements DesktopNotificationApi {
  /// Creates an adapter.
  FlutterDesktopNotificationAdapter(this._facade);

  final DesktopNotificationPluginFacade _facade;
  Future<void>? _initialization;

  @override
  Future<void> show({
    required String title,
    required String body,
    String? tag,
  }) async {
    try {
      await (_initialization ??= _facade.initialize());
    } on Object {
      _initialization = null;
      rethrow;
    }
    await _facade.show(
      id: _stableNotificationId(tag),
      title: title,
      body: body,
    );
  }
}

int _stableNotificationId(String? tag) {
  if (tag == null || tag.isEmpty) {
    return 0;
  }
  var hash = 0x811C9DC5;
  for (final unit in tag.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}
