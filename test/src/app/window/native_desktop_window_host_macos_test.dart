import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/window/zeta_window_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS 启动保留窗口事件代理并继续配置标题栏', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const windowChannel = MethodChannel('window_manager');
    const appearanceChannel = MethodChannel(
      'macos_window_utils/window_manipulator',
    );
    const screenChannel = MethodChannel(
      'dev.leanflutter.plugins/screen_retriever',
    );
    final appearanceCalls = <MethodCall>[];
    final focused = Completer<void>();
    final initialListeners = windowManager.listeners;
    addTearDown(() {
      messenger.setMockMethodCallHandler(windowChannel, null);
      messenger.setMockMethodCallHandler(appearanceChannel, null);
      messenger.setMockMethodCallHandler(screenChannel, null);
      for (final listener in windowManager.listeners) {
        if (!initialListeners.contains(listener)) {
          windowManager.removeListener(listener);
        }
      }
    });
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      return switch (call.method) {
        'isFullScreen' || 'isMaximized' || 'isMinimized' => false,
        'getBounds' => <String, double>{
          'x': 0,
          'y': 0,
          'width': 1280,
          'height': 800,
        },
        'focus' => focused.complete(),
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(appearanceChannel, (call) async {
      appearanceCalls.add(call);
      return true;
    });
    const display = <String, Object>{
      'id': 'test-display',
      'size': <String, double>{'width': 1440, 'height': 900},
      'visiblePosition': <String, double>{'dx': 0, 'dy': 0},
    };
    messenger.setMockMethodCallHandler(screenChannel, (call) async {
      return switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => <String, Object>{
          'displays': <Object>[display],
        },
        'getCursorScreenPoint' => <String, double>{'dx': 10, 'dy': 10},
        _ => throw StateError('Unexpected screen method: ${call.method}'),
      };
    });

    await windowManager.ensureInitialized();
    await NativeDesktopWindowHost().prepareDesktopWindow();
    // window_manager 的 ready 回调为 void，等待其中的异步标题栏配置完成。
    await focused.future;

    expect(
      appearanceCalls
          .singleWhere((call) => call.method == 'initialize')
          .arguments,
      <String, Object>{'enableWindowDelegate': false},
      reason:
          'macos_window_utils 会覆盖 NSWindow.delegate；必须由 window_manager '
          '独占，才能收到后台通知依赖的 blur/minimize 事件。',
    );
    expect(
      appearanceCalls.map((call) => call.method),
      containsAllInOrder(<String>[
        'initialize',
        'enableFullSizeContentView',
        'hideTitle',
        'makeTitlebarTransparent',
      ]),
    );
  }, skip: !Platform.isMacOS);
}
