import 'dart:io';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zeta/app/platform/flutter_file_selector_facade.dart';
import 'package:zeta/app/platform/flutter_local_notifications_facade.dart';
import 'package:zeta/app/platform/flutter_pasteboard_facade.dart';
import 'package:zeta/app/platform/flutter_window_manager_facade.dart';
import 'package:zeta/app/platform/io_system_file_manager_facade.dart';
import 'package:zeta/app/platform/macos_window_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_FakeWindowListener());
    registerFallbackValue(const WindowOptions());
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
  });

  test('file selector facade maps neutral filters and plugin files', () async {
    List<XTypeGroup>? capturedGroups;
    String? capturedDirectory;
    final facade = FlutterFileSelectorFacade(
      openFiles: ({acceptedTypeGroups = const <XTypeGroup>[]}) async {
        capturedGroups = acceptedTypeGroups;
        return <XFile>[XFile('/tmp/image.png')];
      },
      getDirectoryPath: ({initialDirectory}) async {
        capturedDirectory = initialDirectory;
        return '/tmp';
      },
    );
    final filter = FileTypeFilter(
      label: 'Images',
      extensions: const ['png'],
      mimeTypes: const ['image/png'],
      uniformTypeIdentifiers: const ['public.png'],
    );

    expect(await facade.openFiles(acceptedTypes: [filter]), ['/tmp/image.png']);
    expect(capturedGroups!.single.label, 'Images');
    expect(capturedGroups!.single.extensions, ['png']);
    expect(capturedGroups!.single.mimeTypes, ['image/png']);
    expect(capturedGroups!.single.uniformTypeIdentifiers, ['public.png']);
    expect(await facade.getDirectoryPath(initialDirectory: '/start'), '/tmp');
    expect(capturedDirectory, '/start');

    expect(FlutterFileSelectorFacade(), isNotNull);
  });

  test('pasteboard facade invokes injected plugin entrypoints', () async {
    String? written;
    final facade = FlutterPasteboardFacade(
      readFiles: () async => <String>['file'],
      readImage: () async => Uint8List.fromList([1]),
      readText: () async => 'text',
      writeText: (text) async => written = text,
    );

    expect(await facade.readFiles(), ['file']);
    expect(await facade.readImage(), Uint8List.fromList([1]));
    expect(await facade.readText(), 'text');
    await facade.writeText('copy');
    expect(written, 'copy');
    expect(FlutterPasteboardFacade(), isNotNull);
  });

  test(
    'pasteboard facade default entrypoints reach platform channels',
    () async {
      const pasteboardChannel = MethodChannel('pasteboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final temporaryImage = File(
        '${Directory.systemTemp.path}/zeta-pasteboard-coverage-image',
      )..writeAsBytesSync(<int>[3, 4]);
      messenger
        ..setMockMethodCallHandler(pasteboardChannel, (call) async {
          return switch (call.method) {
            'files' => <String>['native-file'],
            'image' =>
              Platform.isWindows
                  ? temporaryImage.path
                  : Uint8List.fromList(<int>[3, 4]),
            _ => null,
          };
        })
        ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': 'native-text'};
          }
          return null;
        });
      try {
        final facade = FlutterPasteboardFacade();
        expect(await facade.readFiles(), ['native-file']);
        expect(await facade.readImage(), Uint8List.fromList(<int>[3, 4]));
        expect(await facade.readText(), 'native-text');
        await facade.writeText('native-copy');
      } finally {
        messenger
          ..setMockMethodCallHandler(pasteboardChannel, null)
          ..setMockMethodCallHandler(SystemChannels.platform, null);
        if (temporaryImage.existsSync()) {
          temporaryImage.deleteSync();
        }
      }
    },
  );

  test('local notification facade configures and invokes the plugin', () async {
    final plugin = _MockNotificationsPlugin();
    when(
      () => plugin.initialize(settings: any(named: 'settings')),
    ).thenAnswer((_) async => true);
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).thenAnswer((_) async {});
    final facade = FlutterLocalNotificationsFacade(
      plugin,
      linuxActionName: 'Open',
    );

    await facade.initialize();
    await facade.show(id: 7, title: 'Title', body: 'Body');

    final initialization =
        verify(
              () => plugin.initialize(settings: captureAny(named: 'settings')),
            ).captured.single
            as InitializationSettings;
    expect(initialization.macOS, isNotNull);
    expect(initialization.linux, isNotNull);
    expect(initialization.windows, isNotNull);
    verify(
      () => plugin.show(
        id: 7,
        title: 'Title',
        body: 'Body',
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
  });

  test('window manager facade maps options, commands, and lifecycle', () async {
    final manager = _MockWindowManager();
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);
    when(manager.ensureInitialized).thenAnswer((_) async {});
    when(() => manager.waitUntilReadyToShow(any())).thenAnswer((_) async {});
    when(manager.show).thenAnswer((_) async {});
    when(manager.focus).thenAnswer((_) async {});
    when(manager.isMaximized).thenAnswer((_) async => true);
    when(manager.maximize).thenAnswer((_) async {});
    when(manager.unmaximize).thenAnswer((_) async {});
    when(manager.minimize).thenAnswer((_) async {});
    when(manager.close).thenAnswer((_) async {});
    final facade = FlutterWindowManagerFacade(manager);
    final events = <WindowLifecycleEvent>[];
    final subscription = facade.lifecycle.listen(events.add);

    await facade.ensureInitialized();
    await facade.prepare(
      const WindowBootstrapConfiguration(
        size: WindowSize(width: 1280, height: 800),
        minimumSize: WindowSize(width: 900, height: 560),
        title: 'Zeta',
        backgroundColorArgb: 0xFF010203,
      ),
    );
    await facade.prepare(
      const WindowBootstrapConfiguration(
        size: WindowSize(width: 10, height: 20),
        minimumSize: WindowSize(width: 1, height: 2),
        title: 'No color',
        center: false,
      ),
    );
    await facade.show();
    await facade.focus();
    expect(await facade.isMaximized(), isTrue);
    await facade.maximize();
    await facade.unmaximize();
    await facade.minimize();
    await facade.close();
    facade
      ..onWindowFocus()
      ..onWindowBlur()
      ..onWindowMinimize()
      ..onWindowRestore()
      ..onWindowMaximize()
      ..onWindowUnmaximize()
      ..onWindowClose();
    await Future<void>.delayed(Duration.zero);

    expect(events, WindowLifecycleEvent.values);
    final options = verify(
      () => manager.waitUntilReadyToShow(captureAny()),
    ).captured.cast<WindowOptions>();
    expect(options.first.title, 'Zeta');
    expect(options.first.backgroundColor, isNotNull);
    expect(options.last.center, isFalse);
    expect(options.last.backgroundColor, isNull);

    await subscription.cancel();
    await facade.dispose();
    facade.onWindowFocus();
    verify(() => manager.removeListener(facade)).called(1);
  });

  test('macOS facade supports no-op and injected enabled paths', () async {
    final calls = <String>[];
    final enabled = MacOsWindowManipulatorFacade(
      enabled: true,
      initialize: () async => calls.add('initialize'),
      enableFullSizeContentView: () async => calls.add('fullSize'),
      hideTitle: () async => calls.add('hideTitle'),
      makeTitlebarTransparent: () async => calls.add('transparent'),
    );
    await enabled.initialize();
    await enabled.configureTitleBar();
    expect(calls, ['initialize', 'fullSize', 'hideTitle', 'transparent']);

    final disabled = MacOsWindowManipulatorFacade(enabled: false);
    await disabled.initialize();
    await disabled.configureTitleBar();
  });

  test('macOS facade default entrypoints reach the plugin channel', () async {
    const channel = MethodChannel('macos_window_utils/window_manipulator');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    try {
      final facade = MacOsWindowManipulatorFacade(enabled: true);
      await facade.initialize();
      await facade.configureTitleBar();
      expect(methods, [
        'initialize',
        'enableFullSizeContentView',
        'hideTitle',
        'makeTitlebarTransparent',
      ]);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'IO file manager facade supports injected and default IO paths',
    () async {
      String? executable;
      List<String>? arguments;
      final injected = IoSystemFileManagerFacade(
        operatingSystem: 'test',
        directoryExists: (path) => path == 'exists',
        startDetached: (command, commandArguments) async {
          executable = command;
          arguments = commandArguments;
        },
      );
      expect(injected.operatingSystem, 'test');
      expect(await injected.directoryExists('exists'), isTrue);
      await injected.startDetached('command', <String>['argument']);
      expect(executable, 'command');
      expect(arguments, ['argument']);

      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'zeta-platform-facade-',
      );
      try {
        final production = IoSystemFileManagerFacade();
        expect(production.operatingSystem, Platform.operatingSystem);
        expect(
          await production.directoryExists(temporaryDirectory.path),
          isTrue,
        );
        if (Platform.isWindows) {
          await production.startDetached('cmd.exe', <String>[
            '/c',
            'exit',
            '0',
          ]);
        } else {
          await production.startDetached('/usr/bin/true', const <String>[]);
        }
      } finally {
        await temporaryDirectory.delete();
      }
    },
  );
}

final class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

final class _MockWindowManager extends Mock implements WindowManager {}

final class _FakeWindowListener extends Fake with WindowListener {}
