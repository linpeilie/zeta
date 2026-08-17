import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/menu_action_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zeta/menu');
  late List<MethodCall> calls;
  late Object? configureResult;

  setUp(() {
    calls = <MethodCall>[];
    configureResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'configure') {
            if (configureResult is Exception) {
              throw configureResult! as Exception;
            }
            return configureResult;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('configure sends versioned labels and treats true as success', () async {
    final bridge = MenuActionBridge();

    final ok = await bridge.configure(
      fileMenuLabel: '文件',
      openProjectLabel: '打开项目',
    );

    expect(ok, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'configure');
    expect(calls.single.arguments, <String, Object?>{
      'version': MenuActionBridge.schemaVersion,
      'fileMenuLabel': '文件',
      'openProjectLabel': '打开项目',
    });
  });

  test('configure is idempotent and fail-closed on unknown version', () async {
    final bridge = MenuActionBridge();

    expect(
      await bridge.configure(
        fileMenuLabel: 'File',
        openProjectLabel: 'Open Project',
      ),
      isTrue,
    );
    expect(
      await bridge.configure(fileMenuLabel: '文件', openProjectLabel: '打开项目'),
      isTrue,
    );
    expect(calls, hasLength(2));

    configureResult = PlatformException(code: 'unsupported_version');
    expect(
      await bridge.configure(
        fileMenuLabel: 'File',
        openProjectLabel: 'Open Project',
      ),
      isFalse,
    );
  });

  test('openProject still invokes the same Flutter callback', () async {
    final bridge = MenuActionBridge();
    var opened = 0;
    bridge.setOpenProject(() => opened += 1);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('openProject')),
          (_) {},
        );

    expect(opened, 1);
  });
}
