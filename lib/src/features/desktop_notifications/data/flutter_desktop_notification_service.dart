import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';

/// 基于 flutter_local_notifications 的三桌面平台系统通知实现。
final class FlutterDesktopNotificationService
    implements DesktopNotificationService {
  FlutterDesktopNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.linuxActionName = '打开 Zeta',
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final String linuxActionName;

  @override
  Future<String?> initialize({
    required DesktopNotificationActivation onActivate,
  }) async {
    await _plugin.initialize(
      settings: InitializationSettings(
        macOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: linuxActionName),
        windows: const WindowsInitializationSettings(
          appName: 'Zeta',
          appUserModelId: 'io.github.linpeilie.zeta',
          guid: '9b5bb3b5-a44b-4f52-8a51-7991b7ab2831',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        onActivate(response.payload);
      },
    );
    if (Platform.isLinux) {
      return null;
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp ?? false
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool?> requestPermissions() async {
    if (!Platform.isMacOS) {
      return true;
    }
    return _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> show(DesktopNotificationRequest request) {
    return _plugin.show(
      id: request.id,
      title: request.title,
      body: request.body,
      payload: request.payload,
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

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  void dispose() {}
}
