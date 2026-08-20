import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:bloc/bloc.dart';
import 'package:codex_app_server_client/codex_app_server_client.dart';
import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

    test('builds production platform facades when none are injected', () async {
      final composition = await composeZeta(
        _dependencies(),
        dataPaths: ZetaDataPaths.fromHomeDirectory(
          home.path,
          isWindows: Platform.isWindows,
        ),
        environment: <String, String>{'HOME': home.path},
        isWindows: false,
        bundleFactories: _workingFactories(),
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

AppDependencies _dependencies() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  return AppDependencies(
    locale: const Locale('en'),
    failureMessages: FailureMessages(l10n),
    desktopNotificationCopyResolver: DesktopNotificationCopyResolver(l10n),
  );
}

ZetaPlatformFacades _fakeFacades() {
  return ZetaPlatformFacades(
    fileSelector: _FakeFileSelectorFacade(),
    pasteboard: _FakePasteboardFacade(),
    fileManager: _FakeSystemFileManagerFacade(),
    windowManager: _FakeWindowManagerFacade(),
    macOsWindow: _FakeMacOsWindowFacade(),
    notifications: _FakeNotificationPluginFacade(),
    menuChannel: _FakeMethodChannelFacade(),
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
  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> focus() async {}

  @override
  Future<bool> isMaximized() async => false;

  @override
  Stream<WindowLifecycleEvent> get lifecycle =>
      const Stream<WindowLifecycleEvent>.empty();

  @override
  Future<void> maximize() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> prepare(WindowBootstrapConfiguration configuration) async {}

  @override
  Future<void> show() async {}

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
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async => null;

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
