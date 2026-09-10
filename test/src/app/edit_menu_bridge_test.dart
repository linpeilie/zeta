import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/edit_menu_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zeta/edit_menu');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('copy method invokes the registered Flutter handler', () async {
    final bridge = EditMenuBridge();
    var copies = 0;
    bridge.setCopyHandler(() => copies += 1);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('copy')),
          (_) {},
        );

    expect(copies, 1);
  });
}
