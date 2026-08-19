import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:zeta/app/platform/desktop_notification_adapter.dart';

/// Production facade over `flutter_local_notifications`.
final class FlutterLocalNotificationsFacade
    implements DesktopNotificationPluginFacade {
  /// Creates a facade around an injected plugin instance.
  FlutterLocalNotificationsFacade(
    this._plugin, {
    required this.linuxActionName,
  });

  final FlutterLocalNotificationsPlugin _plugin;

  /// Already-localized Linux default action name.
  final String linuxActionName;

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: InitializationSettings(
        macOS: const DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: linuxActionName,
        ),
        windows: const WindowsInitializationSettings(
          appName: 'Zeta',
          appUserModelId: 'io.github.linpeilie.zeta',
          guid: '9b5bb3b5-a44b-4f52-8a51-7991b7ab2831',
        ),
      ),
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      macOS: DarwinNotificationDetails(presentSound: true),
      linux: LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
      ),
      windows: WindowsNotificationDetails(
        duration: WindowsNotificationDuration.short,
      ),
    ),
  );
}
