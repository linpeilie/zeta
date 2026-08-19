import 'dart:async';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/app/platform/desktop_attention_adapter.dart';
import 'package:zeta/app/platform/desktop_notification_adapter.dart';
import 'package:zeta/app/platform/file_selector_adapter.dart';
import 'package:zeta/app/platform/menu_command_adapter.dart';
import 'package:zeta/app/platform/method_channel_facade.dart';
import 'package:zeta/app/platform/pasteboard_clipboard_adapter.dart';
import 'package:zeta/app/platform/system_file_manager_adapter.dart';
import 'package:zeta/app/platform/system_font_catalog_adapter.dart';
import 'package:zeta/app/platform/window_command_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterMethodChannelFacade', () {
    const methodChannel = MethodChannel('zeta/test_platform_facade');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      methodChannel.setMethodCallHandler(null);
    });

    test('forwards outgoing and incoming method calls', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        expect(call.method, 'outgoing');
        expect(call.arguments, <String, Object?>{'value': 1});
        return 'response';
      });
      final facade = FlutterMethodChannelFacade(methodChannel);
      final incoming = Completer<PlatformMethodCall>();
      facade.setMethodCallHandler((call) async {
        incoming.complete(call);
        return 'handled';
      });

      expect(
        await facade.invokeMethod<String>(
          'outgoing',
          <String, Object?>{'value': 1},
        ),
        'response',
      );
      final reply = Completer<ByteData?>();
      await messenger.handlePlatformMessage(
        methodChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('incoming', 2),
        ),
        reply.complete,
      );
      expect((await incoming.future).method, 'incoming');
      expect((await incoming.future).arguments, 2);
      expect(
        const StandardMethodCodec().decodeEnvelope((await reply.future)!),
        'handled',
      );

      facade.setMethodCallHandler(null);
    });
  });

  group('method-channel adapters', () {
    test('font adapter sanitizes, deduplicates, sorts, and freezes', () async {
      final channel = _FakeMethodChannel()
        ..response = <Object?>[
          _font('second', 'Zulu'),
          _font('FIRST', 'alpha'),
          _font('first', 'duplicate'),
          <String, Object?>{'invalid': true},
        ];
      final adapter = MethodChannelSystemFontCatalogAdapter(channel);

      final families = await adapter.listFontFamilies(localeName: 'zh_CN');

      expect(families.map((family) => family.displayName), ['alpha', 'Zulu']);
      expect(channel.calls.single.method, 'listFontFamilies');
      expect(channel.calls.single.arguments, <String, Object?>{
        'locale': 'zh_CN',
      });
      expect(() => families.add(families.first), throwsUnsupportedError);
    });

    test('font adapter handles null and rejects a non-list response', () async {
      final channel = _FakeMethodChannel();
      final adapter = MethodChannelSystemFontCatalogAdapter(channel);

      expect(await adapter.listFontFamilies(localeName: 'en'), isEmpty);
      channel.response = 'invalid';
      await expectLater(
        adapter.listFontFamilies(localeName: 'en'),
        throwsFormatException,
      );
    });

    test('attention adapter clamps badge and requests attention', () async {
      final channel = _FakeMethodChannel();
      final adapter = MethodChannelDesktopAttentionAdapter(channel);

      await adapter.setBadgeCount(-2);
      await adapter.setBadgeCount(3);
      await adapter.requestUserAttention();

      expect(channel.calls, [
        const _Invocation('setUnreadCount', <String, Object?>{'count': 0}),
        const _Invocation('setUnreadCount', <String, Object?>{'count': 3}),
        const _Invocation('requestAttention', null),
      ]);
    });

    test('menu adapter configures, emits commands, and closes', () async {
      final channel = _FakeMethodChannel()..response = true;
      final adapter = MethodChannelMenuCommandAdapter(channel);
      final emitted = expectLater(
        adapter.commands,
        emitsInOrder(<Object>[MenuCommand.openProject, emitsDone]),
      );

      expect(
        await adapter.configure(
          const MenuConfiguration(
            fileMenuLabel: 'File',
            openProjectLabel: 'Open Project',
          ),
        ),
        isTrue,
      );
      await channel.handler!(const PlatformMethodCall('unknown', null));
      await channel.handler!(const PlatformMethodCall('openProject', null));
      await adapter.setMenuEnabled(commandId: 'openProject', enabled: false);
      await adapter.close();
      await emitted;

      expect(channel.calls, [
        const _Invocation('configure', <String, Object?>{
          'version': 1,
          'fileMenuLabel': 'File',
          'openProjectLabel': 'Open Project',
        }),
        const _Invocation('setEnabled', <String, Object?>{
          'commandId': 'openProject',
          'enabled': false,
        }),
      ]);
      expect(channel.handler, isNull);
    });

    test(
      'menu adapter fails closed for plugin errors and false values',
      () async {
        final channel = _FakeMethodChannel()..response = false;
        final adapter = MethodChannelMenuCommandAdapter(channel);
        const configuration = MenuConfiguration(
          fileMenuLabel: 'File',
          openProjectLabel: 'Open Project',
        );

        expect(await adapter.configure(configuration), isFalse);
        channel.error = MissingPluginException();
        expect(await adapter.configure(configuration), isFalse);
        await adapter.setMenuEnabled(commandId: 'openProject', enabled: true);
        channel.error = PlatformException(code: 'invalid');
        expect(await adapter.configure(configuration), isFalse);
        channel.error = null;
        await adapter.close();
      },
    );
  });

  group('plugin facade adapters', () {
    test(
      'shared platform values retain value equality in the app boundary',
      () {
        final fileMenuLabel = String.fromCharCodes(<int>[70, 105, 108, 101]);
        final openProjectLabel = String.fromCharCodes(<int>[
          79,
          112,
          101,
          110,
          32,
          80,
          114,
          111,
          106,
          101,
          99,
          116,
        ]);
        final width = double.parse('10');
        final height = double.parse('20');
        expect(
          FileTypeFilter(label: 'Images', extensions: const ['png']),
          FileTypeFilter(label: 'Images', extensions: const ['png']),
        );
        expect(
          MenuConfiguration(
            fileMenuLabel: fileMenuLabel,
            openProjectLabel: openProjectLabel,
          ),
          MenuConfiguration(
            fileMenuLabel: fileMenuLabel,
            openProjectLabel: openProjectLabel,
          ),
        );
        expect(
          SystemFontFamily(
            id: 'id',
            familyName: 'Family',
            displayName: 'Display',
            aliases: const ['Alias'],
            isMonospace: true,
          ),
          SystemFontFamily(
            id: 'id',
            familyName: 'Family',
            displayName: 'Display',
            aliases: const ['Alias'],
            isMonospace: true,
          ),
        );
        expect(
          WindowSize(width: width, height: height),
          WindowSize(width: width, height: height),
        );
        expect(
          WindowBootstrapConfiguration(
            size: WindowSize(width: width, height: height),
            minimumSize: WindowSize(
              width: width / 10,
              height: height / 10,
            ),
            title: 'Zeta',
          ),
          WindowBootstrapConfiguration(
            size: WindowSize(width: width, height: height),
            minimumSize: WindowSize(
              width: width / 10,
              height: height / 10,
            ),
            title: 'Zeta',
          ),
        );
      },
    );

    test(
      'notification adapter initializes once and uses stable tag IDs',
      () async {
        final facade = _FakeNotificationFacade();
        final adapter = FlutterDesktopNotificationAdapter(facade);

        await adapter.show(title: 'One', body: 'Body', tag: 'project');
        await adapter.show(title: 'Two', body: 'Body', tag: 'project');
        await adapter.show(title: 'Three', body: 'Body');
        await adapter.show(title: 'Four', body: 'Body', tag: '');

        expect(facade.initializeCalls, 1);
        expect(facade.shows[0].id, facade.shows[1].id);
        expect(facade.shows[0].id, greaterThan(0));
        expect(facade.shows[2].id, 0);
        expect(facade.shows[3].id, 0);
      },
    );

    test('notification adapter retries initialization after failure', () async {
      final facade = _FakeNotificationFacade()..failInitialization = true;
      final adapter = FlutterDesktopNotificationAdapter(facade);

      await expectLater(
        adapter.show(title: 'Title', body: 'Body'),
        throwsStateError,
      );
      facade.failInitialization = false;
      await adapter.show(title: 'Title', body: 'Body');

      expect(facade.initializeCalls, 2);
      expect(facade.shows, hasLength(1));
    });

    test('file selector adapter forwards filters and freezes paths', () async {
      final facade = _FakeFileSelectorFacade();
      final adapter = FileSelectorAdapter(facade);
      final filter = FileTypeFilter(label: 'Images', extensions: const ['png']);

      final paths = await adapter.pickFiles(acceptedTypes: [filter]);

      expect(paths, ['a.png', 'b.png']);
      expect(facade.acceptedTypes, [filter]);
      expect(() => paths.add('c.png'), throwsUnsupportedError);
      expect(
        await adapter.pickDirectory(initialDirectory: r'C:\work'),
        'selected',
      );
      expect(facade.initialDirectory, r'C:\work');
    });

    test(
      'clipboard adapter forwards text and defensively copies data',
      () async {
        final facade = _FakePasteboardFacade();
        final adapter = PasteboardClipboardAdapter(facade);

        await adapter.writeText('copy');
        expect(await adapter.readText(), 'text');
        final image = await adapter.readImage();
        final files = await adapter.readFilePaths();
        facade.image![0] = 9;
        facade.files.add('mutated');

        expect(facade.writtenText, 'copy');
        expect(image, Uint8List.fromList([1, 2]));
        expect(files, ['a.png']);
        expect(() => files.add('blocked'), throwsUnsupportedError);
        facade.image = null;
        expect(await adapter.readImage(), isNull);
      },
    );

    test(
      'window adapter preserves bootstrap order and both toggle paths',
      () async {
        final manager = _FakeWindowManagerFacade();
        final mac = _FakeMacOsWindowFacade(manager.calls);
        final adapter = WindowCommandAdapter(manager, mac);
        const configuration = WindowBootstrapConfiguration(
          size: WindowSize(width: 1280, height: 800),
          minimumSize: WindowSize(width: 900, height: 560),
          title: 'Zeta',
        );

        await adapter.initialize(configuration);
        manager.maximized = false;
        await adapter.toggleMaximize();
        manager.maximized = true;
        await adapter.toggleMaximize();
        await adapter.minimize();
        await adapter.close();
        final lifecycle = expectLater(
          adapter.lifecycle,
          emits(WindowLifecycleEvent.focused),
        );
        manager.controller.add(WindowLifecycleEvent.focused);
        await lifecycle;
        await adapter.dispose();

        expect(manager.configuration, configuration);
        expect(manager.calls, [
          'ensureInitialized',
          'macInitialize',
          'prepare',
          'macConfigureTitleBar',
          'show',
          'focus',
          'isMaximized',
          'maximize',
          'isMaximized',
          'unmaximize',
          'minimize',
          'close',
          'dispose',
        ]);
      },
    );

    test(
      'system file manager selects commands and rejects missing paths',
      () async {
        final facade = _FakeSystemFileManagerFacade('windows');
        final adapter = SystemFileManagerAdapter(facade);

        await adapter.openDirectory(r'C:\project');
        expect(facade.launch, const _Launch('explorer.exe', [r'C:\project']));
        facade.operatingSystemValue = 'macos';
        await adapter.openDirectory('/project');
        expect(facade.launch, const _Launch('open', ['/project']));
        facade.operatingSystemValue = 'linux';
        await adapter.openDirectory('/project');
        expect(facade.launch, const _Launch('xdg-open', ['/project']));
        facade.exists = false;
        await expectLater(
          adapter.openDirectory('/missing'),
          throwsArgumentError,
        );
      },
    );
  });
}

Map<String, Object?> _font(String id, String displayName) => <String, Object?>{
  'id': id,
  'familyName': displayName,
  'displayName': displayName,
  'aliases': <Object?>[displayName],
  'monospace': false,
};

@immutable
final class _Invocation {
  const _Invocation(this.method, this.arguments);

  final String method;
  final Object? arguments;

  @override
  bool operator ==(Object other) =>
      other is _Invocation &&
      other.method == method &&
      _deepEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(method, arguments);

  @override
  String toString() => '$method($arguments)';
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _deepEquals(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _deepEquals(left[index], right[index]));
  }
  return left == right;
}

final class _FakeMethodChannel implements PlatformMethodChannelFacade {
  final List<_Invocation> calls = <_Invocation>[];
  Object? response;
  Object? error;
  PlatformMethodCallHandler? handler;

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    calls.add(_Invocation(method, arguments));
    final currentError = error;
    if (currentError case final Error error) {
      throw error;
    }
    if (currentError case final Exception exception) {
      throw exception;
    }
    if (currentError != null) {
      throw StateError('Unsupported fake error: $currentError');
    }
    return response as T?;
  }

  @override
  void setMethodCallHandler(PlatformMethodCallHandler? handler) {
    this.handler = handler;
  }
}

final class _NotificationShow {
  const _NotificationShow(this.id, this.title, this.body);
  final int id;
  final String title;
  final String body;
}

final class _FakeNotificationFacade implements DesktopNotificationPluginFacade {
  int initializeCalls = 0;
  bool failInitialization = false;
  final List<_NotificationShow> shows = <_NotificationShow>[];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (failInitialization) {
      throw StateError('failed');
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shows.add(_NotificationShow(id, title, body));
  }
}

final class _FakeFileSelectorFacade implements FileSelectorFacade {
  List<FileTypeFilter>? acceptedTypes;
  String? initialDirectory;

  @override
  Future<String?> getDirectoryPath({String? initialDirectory}) async {
    this.initialDirectory = initialDirectory;
    return 'selected';
  }

  @override
  Future<List<String>> openFiles({
    required List<FileTypeFilter> acceptedTypes,
  }) async {
    this.acceptedTypes = acceptedTypes;
    return <String>['a.png', 'b.png'];
  }
}

final class _FakePasteboardFacade implements PasteboardFacade {
  Uint8List? image = Uint8List.fromList([1, 2]);
  final List<String> files = <String>['a.png'];
  String? writtenText;

  @override
  Future<List<String>> readFiles() async => files;

  @override
  Future<Uint8List?> readImage() async => image;

  @override
  Future<String?> readText() async => 'text';

  @override
  Future<void> writeText(String text) async {
    writtenText = text;
  }
}

final class _FakeWindowManagerFacade implements WindowManagerFacade {
  final StreamController<WindowLifecycleEvent> controller =
      StreamController<WindowLifecycleEvent>.broadcast();
  final List<String> calls = <String>[];
  bool maximized = false;
  WindowBootstrapConfiguration? configuration;

  @override
  Stream<WindowLifecycleEvent> get lifecycle => controller.stream;

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await controller.close();
  }

  @override
  Future<void> ensureInitialized() async => calls.add('ensureInitialized');

  @override
  Future<void> focus() async => calls.add('focus');

  @override
  Future<bool> isMaximized() async {
    calls.add('isMaximized');
    return maximized;
  }

  @override
  Future<void> maximize() async => calls.add('maximize');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> prepare(WindowBootstrapConfiguration configuration) async {
    calls.add('prepare');
    this.configuration = configuration;
  }

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');
}

final class _FakeMacOsWindowFacade implements MacOsWindowFacade {
  _FakeMacOsWindowFacade(this.calls);
  final List<String> calls;

  @override
  Future<void> configureTitleBar() async => calls.add('macConfigureTitleBar');

  @override
  Future<void> initialize() async => calls.add('macInitialize');
}

@immutable
final class _Launch {
  const _Launch(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) =>
      other is _Launch &&
      other.executable == executable &&
      _deepEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(executable, arguments);
}

final class _FakeSystemFileManagerFacade implements SystemFileManagerFacade {
  _FakeSystemFileManagerFacade(this.operatingSystemValue);
  String operatingSystemValue;
  bool exists = true;
  _Launch? launch;

  @override
  String get operatingSystem => operatingSystemValue;

  @override
  Future<bool> directoryExists(String path) async => exists;

  @override
  Future<void> startDetached(
    String executable,
    List<String> arguments,
  ) async {
    launch = _Launch(executable, arguments);
  }
}
