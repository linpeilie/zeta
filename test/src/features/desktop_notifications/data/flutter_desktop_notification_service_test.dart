import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/desktop_notifications/data/flutter_desktop_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows identity uses the bundled logo beside the executable',
    () async {
      final plugin = _RecordingNotificationPlugin();
      final service = FlutterDesktopNotificationService(plugin: plugin);

      await service.initialize(onActivate: (_) {});

      final windows = plugin.settings!.windows!;
      expect(windows.appUserModelId, 'io.github.linpeilie.zeta');
      final icon = File(windows.iconPath!);
      expect(icon.isAbsolute, isTrue);
      final bundle = File(Platform.resolvedExecutable).parent.uri;
      expect(
        icon.uri,
        bundle.resolve('data/flutter_assets/assets/branding/zeta_logo.png'),
      );

      // Verify Flutter actually packages a decodable raster logo at that key.
      final bytes = await rootBundle.load('assets/branding/zeta_logo.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 256);
      expect(frame.image.height, 256);
      frame.image.dispose();
      codec.dispose();
    },
  );
}

class _RecordingNotificationPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  InitializationSettings? settings;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    this.settings = settings;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
}
