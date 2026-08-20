import 'dart:async';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:app_ui/app_ui.dart';
import 'package:bloc/bloc.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:settings_client/settings_client.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/app/platform/platform.dart';
import 'package:zeta/bootstrap.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta_storage/zeta_storage.dart';

import 'helpers/helpers.dart';

void main() {
  group('bootstrap', () {
    testWidgets('freezes supported locale dependencies before app creation', (
      tester,
    ) async {
      final apps = <Widget>[];
      late Locale frozenLocale;

      await tester.runAsync(() async {
        await bootstrap(
          (dependencies, composition) {
            frozenLocale = dependencies.locale;
            expect(
              dependencies.desktopNotificationCopyResolver.linuxActionName,
              '打开 Zeta',
            );
            return const SizedBox();
          },
          platformLocale: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
          ),
          appRunner: apps.add,
          compose: _stubComposition,
        );
      });

      expect(
        frozenLocale,
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        ),
      );
      expect(apps, hasLength(1));
    });

    testWidgets('uses the platform locale and accepts an async builder', (
      tester,
    ) async {
      final apps = <Widget>[];

      await tester.runAsync(() async {
        await bootstrap(
          (dependencies, composition) async {
            expect(dependencies.locale.languageCode, isNotEmpty);
            return const SizedBox();
          },
          appRunner: apps.add,
          compose: _stubComposition,
        );
      });

      expect(apps, hasLength(1));
    });

    testWidgets('passes the composed repositories to the builder', (
      tester,
    ) async {
      late ZetaComposition observed;

      await tester.runAsync(() async {
        await bootstrap(
          (dependencies, composition) {
            observed = composition;
            return const SizedBox();
          },
          platformLocale: const Locale('en'),
          appRunner: (_) {},
          compose: _stubComposition,
        );
        expect(observed.repositories, isNotNull);
        await observed.close();
      });
    });

    test('observer forwards changes and errors', () async {
      final previousObserver = Bloc.observer;
      const observer = AppBlocObserver();
      final cubit = ObservedCubit();
      final error = StateError('expected');
      Bloc.observer = observer;
      addTearDown(() {
        Bloc.observer = previousObserver;
      });

      observer
        ..onChange(cubit, const Change<int>(currentState: 0, nextState: 1))
        ..onError(cubit, error, StackTrace.empty);

      expect(Bloc.observer, isA<AppBlocObserver>());
      await cubit.close();
    });

    testWidgets('bootstrap error handler accepts Flutter errors', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await bootstrap(
          (_, _) => const SizedBox(),
          platformLocale: const Locale('en'),
          appRunner: (_) {},
          compose: _stubComposition,
        );
      });

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: FlutterError('expected'),
          stack: StackTrace.empty,
        ),
      );
    });
  });

  group('composeZeta', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('zeta_composition');
    });

    tearDown(() async {
      await home.delete(recursive: true);
    });

    Future<ZetaComposition> compose({Map<String, String>? environment}) {
      return composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: environment ?? <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(),
        codexProcessStarter: _unreachableProcessStarter,
        claudeProcessStarter: _unreachableProcessStarter,
        grokProcessStarter: _unreachableProcessStarter,
      );
    }

    test('creates the Zeta data directories and every repository', () async {
      final composition = await compose();
      addTearDown(composition.close);

      expect(Directory('${home.path}/.zeta/config').existsSync(), isTrue);
      expect(Directory('${home.path}/.zeta/logs').existsSync(), isTrue);

      final repositories = composition.repositories;
      expect(repositories.workspaceRepository, isNotNull);
      expect(repositories.projectSessionRepository, isNotNull);
      expect(repositories.desktopPlatformRepository, isNotNull);
      expect(repositories.settingsRepository, isNotNull);
      expect(repositories.agentProviderRepository, isNotNull);
      expect(repositories.agentConversationRepository, isNotNull);
      expect(repositories.agentManagementRepository, isNotNull);
      expect(repositories.usageStatisticsRepository, isNotNull);
      expect(repositories.desktopNotificationsRepository, isNotNull);
    });

    test(
      'registers a management client for every built-in definition',
      () async {
        final composition = await compose();
        addTearDown(composition.close);

        final definitions = composition
            .repositories
            .agentManagementRepository
            .definitions
            .map((definition) => definition.providerId)
            .toSet();
        expect(definitions, isNotEmpty);

        for (final providerId in definitions) {
          await expectLater(
            composition.repositories.agentManagementRepository
                .readConfiguration(
                  providerId,
                ),
            completes,
          );
        }
      },
    );

    test(
      'exposes clean-install providers through the session catalogs',
      () async {
        final composition = await compose();
        addTearDown(composition.close);

        final snapshot =
            composition.repositories.agentProviderRepository.configSnapshot;
        expect(snapshot.revision, greaterThan(0));
        expect(
          snapshot.configs.map((config) => config.id),
          containsAll(<String>[defaultAgentProviderId, grokAgentProviderId]),
        );
      },
    );

    test('shows the primary window before the first frame', () async {
      final windowManager = _FakeWindowManagerFacade();
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(windowManager: windowManager),
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.light,
      );
      addTearDown(composition.close);

      expect(windowManager.calls, <String>[
        'ensureInitialized',
        'prepare',
        'setPreventClose(true)',
        'show',
        'focus',
      ]);
      final configuration = windowManager.preparedWith!;
      expect(configuration.title, 'Zeta');
      expect(configuration.size, const WindowSize(width: 1280, height: 800));
      expect(
        configuration.minimumSize,
        const WindowSize(width: 900, height: 560),
      );
      expect(configuration.center, isTrue);
      expect(
        configuration.backgroundColorArgb,
        AppColors.light.frame.toARGB32(),
      );
    });

    test('paints the launch frame with the persisted dark theme', () async {
      final paths = ZetaDataPaths.fromHomeDirectory(
        home.path,
        isWindows: Platform.isWindows,
      );
      await paths.ensureDirectories();
      await FileAppearanceSettingsStore(
        storage: AtomicSettingsDocumentStorage.fromFile(paths.appearanceFile),
      ).save(
        const AppearanceSettingsResponse(
          themeMode: AppearanceThemeModeResponse.dark,
        ),
      );

      final windowManager = _FakeWindowManagerFacade();
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: paths,
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(windowManager: windowManager),
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.light,
      );
      addTearDown(composition.close);

      expect(
        windowManager.preparedWith!.backgroundColorArgb,
        AppColors.dark.frame.toARGB32(),
      );
    });

    test('paints the launch frame with the persisted light theme', () async {
      final paths = ZetaDataPaths.fromHomeDirectory(
        home.path,
        isWindows: Platform.isWindows,
      );
      await paths.ensureDirectories();
      await FileAppearanceSettingsStore(
        storage: AtomicSettingsDocumentStorage.fromFile(paths.appearanceFile),
      ).save(
        const AppearanceSettingsResponse(
          themeMode: AppearanceThemeModeResponse.light,
        ),
      );

      final windowManager = _FakeWindowManagerFacade();
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: paths,
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(windowManager: windowManager),
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.dark,
      );
      addTearDown(composition.close);

      expect(
        windowManager.preparedWith!.backgroundColorArgb,
        AppColors.light.frame.toARGB32(),
      );
    });

    test(
      'falls back to the system brightness for unreadable settings',
      () async {
        final paths = ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        );
        await paths.ensureDirectories();
        await paths.appearanceFile.writeAsString('{ not json');

        final windowManager = _FakeWindowManagerFacade();
        final composition = await composeZeta(
          _dependencies(),
          dataPaths: paths,
          environment: <String, String>{'HOME': home.path},
          isWindows: false,
          facades: _fakeFacades(windowManager: windowManager),
          bundleFactories: _workingFactories(),
          platformBrightness: Brightness.dark,
        );
        addTearDown(() async {
          try {
            await composition.close();
          } on Object {
            // The corrupted settings document also fails on close.
          }
        });

        expect(
          windowManager.preparedWith!.backgroundColorArgb,
          AppColors.dark.frame.toARGB32(),
        );
      },
    );

    test('installs the native menu with the frozen locale copy', () async {
      final menuChannel = _FakeMethodChannelFacade();
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(menuChannel: menuChannel),
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.light,
      );
      addTearDown(composition.close);

      final configure = menuChannel.calls.singleWhere(
        (call) => call.method == 'configure',
      );
      expect(configure.arguments, <String, Object?>{
        'version': MethodChannelMenuCommandAdapter.schemaVersion,
        'fileMenuLabel': 'File',
        'openProjectLabel': 'Open Project',
      });
    });

    test('releases the composition before the window really closes', () async {
      final windowManager = _FakeWindowManagerFacade();
      addTearDown(windowManager.lifecycleEvents.close);
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(windowManager: windowManager),
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.light,
      );

      windowManager.calls.clear();
      windowManager.lifecycleEvents.add(WindowLifecycleEvent.closeRequested);
      await _settleUntil(() => windowManager.calls.contains('close'));

      expect(windowManager.calls, <String>[
        'setPreventClose(false)',
        'close',
      ]);
      expect(
        () => composition.repositories.agentProviderRepository.bundleFor(
          defaultAgentProviderId,
        ),
        throwsA(isA<AgentProviderRepositoryException>()),
        reason: 'Repositories must be closed before the window closes.',
      );

      // A second request must not run shutdown again.
      windowManager.calls.clear();
      windowManager.lifecycleEvents.add(WindowLifecycleEvent.closeRequested);
      await _settleUntil(() => false);
      expect(windowManager.calls, isEmpty);
    });

    test('closes the window even when shutdown fails', () async {
      final runtime = _MockRuntimePort();
      when(runtime.initialize).thenAnswer((_) async {});
      when(runtime.dispose).thenThrow(StateError('dispose failed'));
      when(() => runtime.runtimeInfo).thenReturn(null);

      final windowManager = _FakeWindowManagerFacade();
      addTearDown(windowManager.lifecycleEvents.close);
      await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(windowManager: windowManager),
        bundleFactories: _workingFactories(
          codex: _StubBundleFactory(_bundleWith(runtime: runtime)),
        ),
        platformBrightness: Brightness.light,
      );

      windowManager.calls.clear();
      windowManager.lifecycleEvents.add(WindowLifecycleEvent.closeRequested);
      await _settleUntil(() => windowManager.calls.contains('close'));

      expect(windowManager.calls, <String>[
        'setPreventClose(false)',
        'close',
      ]);
    });

    test('closes every owned resource once', () async {
      final composition = await compose();

      await composition.close();
      await composition.close();
    });

    test(
      'falls back to bare directory names without a home directory',
      () async {
        final composition = await compose(
          environment: const <String, String>{},
        );
        addTearDown(composition.close);

        expect(composition.repositories.usageStatisticsRepository, isNotNull);
      },
    );

    test('resolves data paths from the environment when absent', () async {
      final composition = await composeZeta(
        _dependencies(),
        environment: <String, String>{
          'HOME': home.path,
          'USERPROFILE': home.path,
        },
        isWindows: Platform.isWindows,
        facades: _fakeFacades(),
        bundleFactories: _workingFactories(),
      );
      addTearDown(composition.close);

      expect(Directory('${home.path}/.zeta').existsSync(), isTrue);
    });

    test('reads the host environment when no override is given', () async {
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        facades: _fakeFacades(),
        bundleFactories: _workingFactories(),
      );
      addTearDown(composition.close);

      expect(composition.repositories.agentManagementRepository, isNotNull);
    });

    test('joins vendor paths under a home ending in a separator', () async {
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: const <String, String>{'HOME': '/home/zeta/'},
        isWindows: false,
        facades: _fakeFacades(),
        bundleFactories: _workingFactories(),
      );
      addTearDown(composition.close);

      expect(composition.repositories.usageStatisticsRepository, isNotNull);
    });

    test('drives the real plugin facades when none are injected', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const windowChannel = MethodChannel('window_manager');
      const screenChannel = MethodChannel(
        'dev.leanflutter.plugins/screen_retriever',
      );
      addTearDown(() {
        messenger
          ..setMockMethodCallHandler(windowChannel, null)
          ..setMockMethodCallHandler(screenChannel, null);
      });
      messenger
        ..setMockMethodCallHandler(windowChannel, (call) async {
          if (call.method.startsWith('is')) {
            return false;
          }
          if (call.method.startsWith('get')) {
            return <String, double>{
              'x': 0,
              'y': 0,
              'width': 1280,
              'height': 800,
            };
          }
          return null;
        })
        ..setMockMethodCallHandler(screenChannel, (call) async {
          const display = <String, Object?>{
            'id': 'primary',
            'name': 'primary',
            'size': <String, double>{'width': 1920, 'height': 1080},
            'visiblePosition': <String, double>{'dx': 0, 'dy': 0},
            'visibleSize': <String, double>{'width': 1920, 'height': 1080},
            'scaleFactor': 1.0,
          };
          if (call.method == 'getAllDisplays') {
            return <String, Object?>{
              'displays': <Map<String, Object?>>[display],
            };
          }
          if (call.method == 'getCursorScreenPoint') {
            return <String, double>{'dx': 0, 'dy': 0};
          }
          return display;
        });

      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        bundleFactories: _workingFactories(),
        platformBrightness: Brightness.light,
      );
      addTearDown(composition.close);

      expect(composition.repositories.desktopPlatformRepository, isNotNull);
    });

    test('skips providers whose bundle cannot be resolved', () async {
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(),
        bundleFactories: _workingFactories(
          codex: _StubBundleFactory.failing(
            Exception('no codex bundle'),
          ),
        ),
      );
      addTearDown(composition.close);

      expect(composition.repositories.projectSessionRepository, isNotNull);
    });

    test('close rethrows the first shutdown failure', () async {
      final runtime = _MockRuntimePort();
      when(runtime.initialize).thenAnswer((_) async {});
      when(runtime.dispose).thenThrow(StateError('dispose failed'));
      when(
        () => runtime.capabilities,
      ).thenReturn(CodexStaticCapabilities.value);
      when(
        () => runtime.events,
      ).thenAnswer((_) => const Stream<AgentEvent>.empty());

      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        facades: _fakeFacades(),
        bundleFactories: _workingFactories(
          codex: _StubBundleFactory(_bundleWith(runtime: runtime)),
        ),
      );

      await expectLater(composition.close, throwsA(isA<Object>()));
    });

    test('prefers the vendor home overrides', () async {
      final composition = await compose(
        environment: <String, String>{
          'HOME': home.path,
          'CODEX_HOME': '${home.path}/codex-override',
          'CLAUDE_HOME': '${home.path}/claude-override',
          'GROK_HOME': '${home.path}/grok-override',
        },
      );
      addTearDown(composition.close);

      expect(composition.repositories.usageStatisticsRepository, isNotNull);
    });
  });
  group('productionPlatformFacades', () {
    test('binds every plugin seam the composition root needs', () {
      final facades = productionPlatformFacades(_dependencies());

      expect(facades.fileSelector, isA<FlutterFileSelectorFacade>());
      expect(facades.pasteboard, isA<FlutterPasteboardFacade>());
      expect(facades.fileManager, isA<IoSystemFileManagerFacade>());
      expect(facades.windowManager, isA<FlutterWindowManagerFacade>());
      expect(facades.macOsWindow, isA<MacOsWindowManipulatorFacade>());
      expect(facades.notifications, isA<FlutterLocalNotificationsFacade>());
      expect(facades.menuChannel, isA<FlutterMethodChannelFacade>());
      expect(facades.fontChannel, isA<FlutterMethodChannelFacade>());
      expect(facades.attentionChannel, isA<FlutterMethodChannelFacade>());
      addTearDown(facades.windowManager.dispose);
    });
  });

  group('probeAgentProtocol', () {
    test('binds composition factories to the management probe seam', () async {
      final runtime = _MockRuntimePort();
      when(runtime.initialize).thenAnswer((_) async {});
      when(runtime.dispose).thenAnswer((_) async {});
      when(() => runtime.runtimeInfo).thenReturn(null);

      final probe = agentProtocolProbeFor(
        <AgentProviderKind, AgentProviderBundleFactory>{
          AgentProviderKind.codexAppServer: _StubBundleFactory(
            _bundleWith(runtime: runtime),
          ),
        },
      );
      final response = await probe(AgentProviderConfig.defaultCodex);

      expect(response.success, isTrue);
    });

    test('fails closed when no factory serves the provider kind', () async {
      final response = await probeAgentProtocol(
        AgentProviderConfig.defaultCodex,
        const <AgentProviderKind, AgentProviderBundleFactory>{},
      );

      expect(response.success, isFalse);
      expect(response.accountValid, isFalse);
      expect(response.failureCode, 'bundle-factory-missing');
      expect(response.models, isEmpty);
    });

    test('returns the model catalog and runtime identity', () async {
      final runtime = _MockRuntimePort();
      final catalog = _MockModelCatalogPort();
      final model = AgentModelInfo(
        id: 'gpt-5',
        model: 'gpt-5',
        displayName: 'GPT-5',
      );
      when(runtime.initialize).thenAnswer((_) async {});
      when(runtime.dispose).thenAnswer((_) async {});
      when(() => runtime.runtimeInfo).thenReturn(
        const AgentRuntimeInfo(
          runtimeId: 'runtime-1',
          connectionEpoch: 1,
          protocolName: 'codex-app-server',
          protocolVersion: '0.144.5',
          compatibilityStatus: AgentRuntimeCompatibilityStatus.supported,
          cliVersion: '1.2.3',
        ),
      );
      when(
        () => catalog.listModels(
          limit: any(named: 'limit'),
          includeHidden: any(named: 'includeHidden'),
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer(
        (_) async => AgentModelList(models: <AgentModelInfo>[model]),
      );

      final response = await probeAgentProtocol(
        AgentProviderConfig.defaultCodex,
        <AgentProviderKind, AgentProviderBundleFactory>{
          AgentProviderKind.codexAppServer: _StubBundleFactory(
            _bundleWith(runtime: runtime, modelCatalog: catalog),
          ),
        },
      );

      expect(response.success, isTrue);
      expect(response.accountValid, isTrue);
      expect(response.models, <AgentModelInfo>[model]);
      expect(response.protocolVersion, '0.144.5');
      expect(response.agentName, 'codex-app-server');
      expect(response.agentVersion, '1.2.3');
      verify(runtime.dispose).called(1);
    });

    test('reports success without models when no catalog exists', () async {
      final runtime = _MockRuntimePort();
      when(runtime.initialize).thenAnswer((_) async {});
      when(runtime.dispose).thenAnswer((_) async {});
      when(() => runtime.runtimeInfo).thenReturn(null);

      final response = await probeAgentProtocol(
        AgentProviderConfig.defaultGrok,
        <AgentProviderKind, AgentProviderBundleFactory>{
          AgentProviderKind.acp: _StubBundleFactory(
            _bundleWith(runtime: runtime),
          ),
        },
      );

      expect(response.success, isTrue);
      expect(response.models, isEmpty);
      expect(response.protocolVersion, isNull);
      expect(response.agentName, isNull);
      expect(response.agentVersion, isNull);
    });

    test('propagates handshake failures without masking them', () async {
      final runtime = _MockRuntimePort();
      when(runtime.initialize).thenThrow(StateError('handshake failed'));
      when(runtime.dispose).thenThrow(StateError('dispose failed'));

      await expectLater(
        probeAgentProtocol(
          AgentProviderConfig.defaultCodex,
          <AgentProviderKind, AgentProviderBundleFactory>{
            AgentProviderKind.codexAppServer: _StubBundleFactory(
              _bundleWith(runtime: runtime),
            ),
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'handshake failed',
          ),
        ),
      );
      verify(runtime.dispose).called(1);
    });
  });
}

Future<ZetaComposition> _stubComposition(AppDependencies dependencies) async {
  final home = await Directory.systemTemp.createTemp('zeta_bootstrap');
  final composition = await composeZeta(
    dependencies,
    dataPaths: ZetaDataPaths.fromHomeDirectory(
      home.path,
      isWindows: Platform.isWindows,
    ),
    environment: <String, String>{'HOME': home.path},
    isWindows: false,
    facades: _fakeFacades(),
    codexProcessStarter: _unreachableProcessStarter,
    claudeProcessStarter: _unreachableProcessStarter,
    grokProcessStarter: _unreachableProcessStarter,
  );
  addTearDown(() async {
    await composition.close();
    await home.delete(recursive: true);
  });
  return composition;
}

/// Yields the event loop until [done] holds, so shutdown assertions never
/// depend on a fixed number of turns.
Future<void> _settleUntil(bool Function() done) async {
  for (var turn = 0; turn < 500 && !done(); turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppDependencies _dependencies() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  return AppDependencies(
    locale: const Locale('en'),
    failureMessages: FailureMessages(l10n),
    desktopNotificationCopyResolver: DesktopNotificationCopyResolver(l10n),
    desktopChromeCopyResolver: DesktopChromeCopyResolver(l10n),
  );
}

ZetaPlatformFacades _fakeFacades({
  _FakeWindowManagerFacade? windowManager,
  _FakeMethodChannelFacade? menuChannel,
}) {
  return ZetaPlatformFacades(
    fileSelector: _FakeFileSelectorFacade(),
    pasteboard: _FakePasteboardFacade(),
    fileManager: _FakeSystemFileManagerFacade(),
    windowManager: windowManager ?? _FakeWindowManagerFacade(),
    macOsWindow: _FakeMacOsWindowFacade(),
    notifications: _FakeNotificationPluginFacade(),
    menuChannel: menuChannel ?? _FakeMethodChannelFacade(),
    fontChannel: _FakeMethodChannelFacade(),
    attentionChannel: _FakeMethodChannelFacade(),
  );
}

Future<Process> _unreachableProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  throw StateError('Composition must not start a Provider process.');
}

class _FakeFileSelectorFacade implements FileSelectorFacade {
  @override
  Future<String?> getDirectoryPath({String? initialDirectory}) async => null;

  @override
  Future<List<String>> openFiles({
    required List<FileTypeFilter> acceptedTypes,
  }) async => const <String>[];
}

class _FakePasteboardFacade implements PasteboardFacade {
  @override
  Future<List<String>> readFiles() async => const <String>[];

  @override
  Future<Uint8List?> readImage() async => null;

  @override
  Future<String?> readText() async => null;

  @override
  Future<void> writeText(String text) async {}
}

class _FakeSystemFileManagerFacade implements SystemFileManagerFacade {
  @override
  Future<bool> directoryExists(String path) async => false;

  @override
  String get operatingSystem => 'linux';

  @override
  Future<void> startDetached(String executable, List<String> arguments) async {}
}

class _FakeWindowManagerFacade implements WindowManagerFacade {
  final List<String> calls = <String>[];
  final StreamController<WindowLifecycleEvent> lifecycleEvents =
      StreamController<WindowLifecycleEvent>.broadcast();
  WindowBootstrapConfiguration? preparedWith;

  @override
  Future<void> close() async {
    calls.add('close');
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureInitialized() async {
    calls.add('ensureInitialized');
  }

  @override
  Future<void> setPreventClose({required bool preventClose}) async {
    calls.add('setPreventClose($preventClose)');
  }

  @override
  Future<void> focus() async {
    calls.add('focus');
  }

  @override
  Future<bool> isMaximized() async => false;

  @override
  Stream<WindowLifecycleEvent> get lifecycle => lifecycleEvents.stream;

  @override
  Future<void> maximize() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> prepare(WindowBootstrapConfiguration configuration) async {
    calls.add('prepare');
    preparedWith = configuration;
  }

  @override
  Future<void> show() async {
    calls.add('show');
  }

  @override
  Future<void> unmaximize() async {}
}

class _FakeMacOsWindowFacade implements MacOsWindowFacade {
  @override
  Future<void> configureTitleBar() async {}

  @override
  Future<void> initialize() async {}
}

class _FakeNotificationPluginFacade implements DesktopNotificationPluginFacade {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}
}

class _FakeMethodChannelFacade implements PlatformMethodChannelFacade {
  final List<({String method, Object? arguments})> calls =
      <({String method, Object? arguments})>[];

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    calls.add((method: method, arguments: arguments));
    return null;
  }

  @override
  void setMethodCallHandler(PlatformMethodCallHandler? handler) {}
}

Map<AgentProviderKind, AgentProviderBundleFactory> _workingFactories({
  AgentProviderBundleFactory? codex,
}) {
  return <AgentProviderKind, AgentProviderBundleFactory>{
    AgentProviderKind.codexAppServer:
        codex ?? _StubBundleFactory(_bundleWith()),
    AgentProviderKind.claudeCode: _StubBundleFactory(_bundleWith()),
    AgentProviderKind.acp: _StubBundleFactory(_bundleWith()),
  };
}

AgentProviderBundle _bundleWith({
  AgentRuntimePort? runtime,
  AgentModelCatalogPort? modelCatalog,
}) {
  final port = runtime ?? _defaultRuntime();
  return AgentProviderBundle(
    runtime: port,
    conversation: _MockConversationPort(),
    threadCatalog: _MockThreadCatalogPort(),
    modelCatalog: modelCatalog,
    usageQuota: _MockUsageQuotaProvider(),
  );
}

AgentRuntimePort _defaultRuntime() {
  final runtime = _MockRuntimePort();
  when(runtime.initialize).thenAnswer((_) async {});
  when(runtime.dispose).thenAnswer((_) async {});
  when(() => runtime.runtimeInfo).thenReturn(null);
  when(() => runtime.events).thenAnswer(
    (_) => const Stream<AgentEvent>.empty(),
  );
  return runtime;
}

class _StubBundleFactory implements AgentProviderBundleFactory {
  _StubBundleFactory(this._bundle) : _error = null;

  _StubBundleFactory.failing(Exception error) : _bundle = null, _error = error;

  final AgentProviderBundle? _bundle;
  final Exception? _error;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    final error = _error;
    if (error != null) {
      throw error;
    }
    return _bundle!;
  }
}

class _MockRuntimePort extends Mock implements AgentRuntimePort {}

class _MockConversationPort extends Mock implements AgentConversationPort {}

class _MockThreadCatalogPort extends Mock implements AgentThreadCatalogPort {}

class _MockModelCatalogPort extends Mock implements AgentModelCatalogPort {}

class _MockUsageQuotaProvider extends Mock implements AgentUsageQuotaProvider {}
