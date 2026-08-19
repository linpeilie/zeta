import 'dart:async';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  late _ConfigStore configStore;
  late _ModelCacheStore modelCache;
  late _Runtime runtime;
  late _Capabilities capabilities;
  late _BundleFactory factory;
  late AgentProviderRepository repository;

  setUp(() {
    configStore = _ConfigStore(<AgentProviderConfig>[
      AgentProviderConfig.defaultCodex,
    ]);
    modelCache = _ModelCacheStore();
    runtime = _Runtime();
    capabilities = _Capabilities();
    factory = _BundleFactory(() => _bundle(runtime, capabilities));
  });

  tearDown(() async {
    try {
      await repository.close();
    } on Object {
      // Tests exercising initialization and disposal failures assert the error.
    }
  });

  AgentProviderRepository createRepository({
    DateTime Function()? clock,
    Duration freshFor = const Duration(hours: 1),
    Duration maxStaleFor = const Duration(days: 7),
    Map<AgentProviderKind, AgentProviderBundleFactory>? factories,
  }) {
    return repository = AgentProviderRepository(
      configStore: configStore,
      modelCatalogCache: modelCache,
      bundleFactories:
          factories ??
          <AgentProviderKind, AgentProviderBundleFactory>{
            AgentProviderKind.codexAppServer: factory,
          },
      logger: loggerFor('agent-provider-repository-test'),
      modelCatalogFreshFor: freshFor,
      modelCatalogMaxStaleFor: maxStaleFor,
      clock: clock,
    );
  }

  group('configuration', () {
    test('snapshot is immutable, comparable, and supports lookup', () {
      final configs = <AgentProviderConfig>[AgentProviderConfig.defaultCodex];
      final snapshot = ProviderConfigSnapshot(configs: configs, revision: 4);
      final same = ProviderConfigSnapshot(configs: configs, revision: 4);
      configs.clear();

      expect(snapshot, same);
      expect(snapshot.configs, hasLength(1));
      expect(snapshot.providerById(defaultAgentProviderId), isNotNull);
      expect(snapshot.providerById('missing'), isNull);
      expect(snapshot.configs.clear, throwsUnsupportedError);
      expect(ProviderConfigSnapshot.empty.revision, 0);
    });

    test('ready loads and publishes the first snapshot', () async {
      final changes = <ProviderConfigSnapshot>[];
      createRepository().configChanges.listen(changes.add);

      await repository.ready;

      expect(repository.configSnapshot.revision, 1);
      expect(repository.configSnapshot.configs, configStore.configs);
      expect(changes, <ProviderConfigSnapshot>[repository.configSnapshot]);
    });

    test('clean install supplies Codex and Grok without writing', () async {
      configStore.configs = <AgentProviderConfig>[];
      createRepository(
        factories: <AgentProviderKind, AgentProviderBundleFactory>{
          AgentProviderKind.codexAppServer: factory,
          AgentProviderKind.acp: factory,
        },
      );

      await repository.ready;

      expect(
        repository.configSnapshot.configs.map((config) => config.id),
        <String>[defaultAgentProviderId, grokAgentProviderId],
      );
      expect(configStore.writes, isEmpty);
    });

    test('bundleFor rejects calls before ready', () async {
      configStore.readCompleter = Completer<List<AgentProviderConfig>>();
      createRepository();

      expect(
        () => repository.bundleFor(defaultAgentProviderId),
        failsWith(
          AgentProviderFailureCode.unavailable,
          'repository_not_ready',
        ),
      );
      configStore.readCompleter!.complete(configStore.configs);
      await repository.ready;
    });

    test('initialization translates decode failures', () async {
      const error = AgentConfigDecodeException(
        document: AgentConfigDocumentKind.providerConfig,
        reason: AgentConfigDecodeReason.invalidShape,
      );
      configStore.readError = error;
      createRepository();

      await expectLater(
        repository.ready,
        failsWith(
          AgentProviderFailureCode.invalidConfiguration,
          'initialize_failed',
          operation: AgentProviderRepositoryOperation.initialize,
          cause: error,
        ),
      );
    });

    test('duplicate and blank ids are translated', () async {
      for (final configs in <List<AgentProviderConfig>>[
        <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultCodex,
        ],
        <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex.copyWith(id: ' '),
        ],
      ]) {
        configStore.configs = configs;
        createRepository();
        await expectLater(
          repository.ready,
          failsWith(AgentProviderFailureCode.invalidConfiguration, null),
        );
        await expectLater(repository.close(), throwsA(isA<Exception>()));
      }
    });
  });

  group('bundle and lifecycle', () {
    test('creates one global bundle per provider', () async {
      createRepository();
      await repository.ready;

      final first = repository.bundleFor(defaultAgentProviderId);
      final second = repository.bundleFor(' codex ');

      expect(first, same(second));
      expect(factory.createdWith, <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
      ]);
    });

    test('rejects unknown, disabled, and missing-factory providers', () async {
      createRepository(
        factories: <AgentProviderKind, AgentProviderBundleFactory>{},
      );
      await repository.ready;
      expect(
        () => repository.bundleFor('missing'),
        failsWith(
          AgentProviderFailureCode.invalidConfiguration,
          'provider_unknown',
        ),
      );
      expect(
        () => repository.bundleFor(defaultAgentProviderId),
        failsWith(
          AgentProviderFailureCode.invalidConfiguration,
          'bundle_factory_missing',
        ),
      );

      await repository.close();
      configStore.configs = <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex.copyWith(enabled: false),
      ];
      createRepository();
      await repository.ready;
      expect(
        () => repository.bundleFor(defaultAgentProviderId),
        failsWith(AgentProviderFailureCode.unavailable, 'provider_disabled'),
      );
    });

    test('factory failures retain cause but render safely', () async {
      final error = StateError('factory secret');
      factory.error = error;
      createRepository();
      await repository.ready;

      late AgentProviderRepositoryException translated;
      try {
        repository.bundleFor(defaultAgentProviderId);
        fail('bundleFor should throw');
      } on AgentProviderRepositoryException catch (caught) {
        translated = caught;
      }

      expect(translated.cause, same(error));
      expect(translated.stackTrace, isNotNull);
      expect(translated.toString(), contains('resolveBundle, unknown'));
      expect(translated.toString(), isNot(contains('secret')));
    });

    test('close disposes once, is idempotent, and rejects reuse', () async {
      createRepository();
      await repository.ready;
      repository.bundleFor(defaultAgentProviderId);

      await repository.close();
      await repository.close();

      expect(runtime.disposeCalls, 1);
      expect(
        () => repository.bundleFor(defaultAgentProviderId),
        failsWith(AgentProviderFailureCode.unavailable, 'repository_closed'),
      );
    });

    test('close translates disposal failure', () async {
      runtime.disposeError = StateError('dispose failed');
      createRepository();
      await repository.ready;
      repository.bundleFor(defaultAgentProviderId);

      await expectLater(
        repository.close(),
        failsWith(
          AgentProviderFailureCode.unknown,
          'close_failed',
          operation: AgentProviderRepositoryOperation.close,
        ),
      );
    });
  });

  group('catalog capabilities', () {
    test('loads all catalogs and applies explicit permission', () async {
      createRepository();
      await repository.ready;
      const selection = AgentPermissionSelection(optionId: 'safe');

      expect(
        await repository.conversationModes(defaultAgentProviderId),
        same(capabilities.modes),
      );
      expect(
        await repository.skills('codex', cwds: <String>['workspace']),
        same(capabilities.skillsCatalog),
      );
      expect(
        await repository.permissionOptions('codex'),
        same(capabilities.permissionCatalog),
      );
      expect(
        await repository.applyPermissionSelection('codex', selection),
        same(capabilities.permissionResult),
      );
      expect(runtime.initializeCalls, 1);
      expect(capabilities.receivedCwds, <String>['workspace']);
      expect(capabilities.receivedSelection, selection);
      expect(capabilities.cwdsWereImmutable, isTrue);
    });

    test('absent optional ports become typed failures', () async {
      factory.builder = () => _bundle(runtime, null);
      createRepository();
      await repository.ready;

      await expectLater(
        repository.conversationModes('codex'),
        failsWith(
          AgentProviderFailureCode.unavailable,
          'conversation_modes_unsupported',
        ),
      );
      await expectLater(
        repository.skills('codex'),
        failsWith(AgentProviderFailureCode.unavailable, 'skills_unsupported'),
      );
      await expectLater(
        repository.permissionOptions('codex'),
        failsWith(
          AgentProviderFailureCode.unavailable,
          'permission_policy_unsupported',
        ),
      );
      await expectLater(
        repository.applyPermissionSelection(
          'codex',
          const AgentPermissionSelection(optionId: 'safe'),
        ),
        failsWith(
          AgentProviderFailureCode.unavailable,
          'permission_policy_unsupported',
        ),
      );
    });

    test('runtime initialization is single-flight and retryable', () async {
      final gate = Completer<void>();
      runtime.initializeCompleter = gate;
      createRepository();
      await repository.ready;

      final first = repository.conversationModes('codex');
      final second = repository.skills('codex');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.initializeCalls, 1);
      gate.complete();
      await Future.wait<Object>(<Future<Object>>[first, second]);

      await repository.close();
      runtime = _Runtime()..initializeError = StateError('initialize failed');
      factory.builder = () => _bundle(runtime, capabilities);
      createRepository();
      await repository.ready;
      await expectLater(
        repository.conversationModes('codex'),
        failsWith(
          AgentProviderFailureCode.unknown,
          'initializeRuntime_failed',
          operation: AgentProviderRepositoryOperation.initializeRuntime,
        ),
      );
      runtime.initializeError = null;
      await repository.conversationModes('codex');
      expect(runtime.initializeCalls, 2);
    });

    test(
      'asynchronous runtime failure clears the single-flight entry',
      () async {
        final gate = Completer<void>();
        runtime.initializeCompleter = gate;
        createRepository();
        await repository.ready;

        final operation = repository.conversationModes('codex');
        await Future<void>.delayed(Duration.zero);
        gate.completeError(StateError('asynchronous initialize failure'));
        await expectLater(
          operation,
          failsWith(
            AgentProviderFailureCode.unknown,
            'initializeRuntime_failed',
          ),
        );

        runtime.initializeCompleter = null;
        await repository.conversationModes('codex');
        expect(runtime.initializeCalls, 2);
      },
    );

    test('capability errors preserve timeout and unknown causes', () async {
      createRepository();
      await repository.ready;
      capabilities.modeError = TimeoutException('slow');
      await expectLater(
        repository.conversationModes('codex'),
        failsWith(
          AgentProviderFailureCode.timeout,
          'conversationModes_failed',
        ),
      );

      final error = StateError('failed');
      capabilities.skillsError = error;
      await expectLater(
        repository.skills('codex'),
        failsWith(
          AgentProviderFailureCode.unknown,
          'skills_failed',
          cause: error,
        ),
      );
    });

    test('retains catalogs and reloads skills after invalidation', () async {
      createRepository();
      await repository.ready;
      final modes = await repository.conversationModes('codex');
      final permissions = await repository.permissionOptions('codex');
      final skills = await repository.skills('codex', cwds: <String>['repo']);

      capabilities
        ..modeError = StateError('mode offline')
        ..permissionOptionsError = StateError('permission offline');
      expect(await repository.conversationModes('codex'), same(modes));
      expect(await repository.permissionOptions('codex'), same(permissions));

      capabilities.skillsChangedController.add(null);
      expect(
        await repository.skills('codex', cwds: <String>['repo']),
        same(skills),
      );
      expect(capabilities.skillsForceReloadValues, <bool>[false, true]);

      capabilities.skillsChangedController.addError(
        StateError('watch failed'),
        StackTrace.current,
      );
      capabilities.skillsError = StateError('skill offline');
      expect(
        await repository.skills('codex', cwds: <String>['repo']),
        same(skills),
      );
      expect(capabilities.skillsForceReloadValues, <bool>[false, true, true]);
    });
  });

  group('model catalog', () {
    test('refreshes, caches, and force refreshes', () async {
      final first = modelList('first');
      final second = modelList('second');
      capabilities.modelResults.addAll(<AgentModelList>[first, second]);
      createRepository();
      await repository.ready;

      expect(await repository.modelCatalog('codex'), same(first));
      expect(await repository.modelCatalog('codex'), same(first));
      expect(
        await repository.modelCatalog('codex', forceRefresh: true),
        same(second),
      );
      expect(capabilities.modelCalls, 2);
      expect(capabilities.forceRefreshValues, everyElement(isTrue));
      expect(runtime.initializeCalls, 1);
      expect(modelCache.saves, hasLength(2));
      expect(modelCache.saves.last.single.source, 'codexAppServer');
      expect(modelCache.saves.last.single.configFingerprint, hasLength(8));
    });

    test('uses the newest visible persisted cache snapshot', () async {
      final now = DateTime.utc(2026, 8, 20, 12);
      capabilities.modelResults.add(modelList('seed'));
      createRepository(clock: () => now);
      await repository.ready;
      await repository.modelCatalog('codex');
      final saved = modelCache.saves.single.single;
      await repository.close();

      modelCache = _ModelCacheStore()
        ..loaded = <AgentModelCatalogSnapshot>[
          AgentModelCatalogSnapshot(
            providerId: saved.providerId,
            configFingerprint: saved.configFingerprint,
            includeHidden: false,
            models: modelList('older'),
            fetchedAt: now.subtract(const Duration(minutes: 20)),
            source: 'older',
          ),
          saved,
          AgentModelCatalogSnapshot(
            providerId: saved.providerId,
            configFingerprint: saved.configFingerprint,
            includeHidden: true,
            models: modelList('hidden'),
            fetchedAt: now.add(const Duration(minutes: 1)),
            source: 'hidden',
          ),
        ];
      capabilities = _Capabilities();
      factory
        ..createdWith.clear()
        ..builder = () => _bundle(runtime, capabilities);
      createRepository(clock: () => now.add(const Duration(minutes: 10)));
      await repository.ready;

      expect(await repository.modelCatalog('codex'), same(saved.models));
      expect(factory.createdWith, isEmpty);
    });

    test('returns stale cache on error but rejects expired cache', () async {
      final now = DateTime.utc(2026, 8, 20, 12);
      capabilities.modelResults.add(modelList('seed'));
      createRepository(clock: () => now);
      await repository.ready;
      final seed = await repository.modelCatalog('codex');
      final saved = modelCache.saves.single.single;
      await repository.close();

      capabilities = _Capabilities()..modelError = StateError('offline');
      factory.builder = () => _bundle(runtime, capabilities);
      modelCache = _ModelCacheStore()
        ..loaded = <AgentModelCatalogSnapshot>[saved];
      createRepository(clock: () => now.add(const Duration(hours: 2)));
      await repository.ready;
      expect(await repository.modelCatalog('codex'), same(seed));

      await repository.close();
      modelCache = _ModelCacheStore()
        ..loaded = <AgentModelCatalogSnapshot>[saved];
      createRepository(clock: () => now.add(const Duration(days: 8)));
      await repository.ready;
      await expectLater(
        repository.modelCatalog('codex'),
        failsWith(AgentProviderFailureCode.unknown, 'modelCatalog_failed'),
      );
    });

    test('empty refresh never writes and preserves stale data', () async {
      capabilities.modelResults.add(emptyModelList());
      createRepository();
      await repository.ready;
      expect((await repository.modelCatalog('codex')).models, isEmpty);
      expect(modelCache.saves, isEmpty);

      capabilities.modelResults.add(modelList('good'));
      final good = await repository.modelCatalog('codex', forceRefresh: true);
      capabilities.modelResults.add(emptyModelList());
      expect(
        await repository.modelCatalog('codex', forceRefresh: true),
        same(good),
      );
      expect(modelCache.saves, hasLength(1));
    });

    test('cache failures are best effort', () async {
      modelCache
        ..loadError = StateError('corrupt')
        ..saveError = StateError('disk full');
      capabilities.modelResults.add(modelList('live'));
      createRepository();
      await repository.ready;

      expect((await repository.modelCatalog('codex')).models.single.id, 'live');
      expect(modelCache.loadCalls, 1);
      expect(modelCache.saveCalls, 1);
    });

    test('refresh is single-flight and absent port is typed', () async {
      final gate = Completer<AgentModelList>();
      capabilities.modelCompleter = gate;
      createRepository();
      await repository.ready;
      final first = repository.modelCatalog('codex');
      final second = repository.modelCatalog('codex');
      await Future<void>.delayed(Duration.zero);
      expect(capabilities.modelCalls, 1);
      final result = modelList('shared');
      gate.complete(result);
      expect(await first, same(result));
      expect(await second, same(result));

      await repository.close();
      factory.builder = () => _bundle(runtime, null);
      createRepository();
      await repository.ready;
      await expectLater(
        repository.modelCatalog('codex'),
        failsWith(
          AgentProviderFailureCode.unavailable,
          'model_catalog_unsupported',
        ),
      );
    });

    test(
      'concurrent callers wait for the single persisted-cache read',
      () async {
        final now = DateTime.utc(2026, 8, 20, 12);
        capabilities.modelResults.add(modelList('seed'));
        createRepository(clock: () => now);
        await repository.ready;
        await repository.modelCatalog('codex');
        final saved = modelCache.saves.single.single;
        await repository.close();

        final loadGate = Completer<List<AgentModelCatalogSnapshot>>();
        modelCache = _ModelCacheStore()..loadCompleter = loadGate;
        factory.createdWith.clear();
        createRepository(clock: () => now.add(const Duration(minutes: 10)));
        await repository.ready;
        final first = repository.modelCatalog('codex');
        final second = repository.modelCatalog('codex');
        await Future<void>.delayed(Duration.zero);
        expect(modelCache.loadCalls, 1);
        expect(factory.createdWith, isEmpty);

        loadGate.complete(<AgentModelCatalogSnapshot>[saved]);
        expect(await first, same(saved.models));
        expect(await second, same(saved.models));
        expect(factory.createdWith, isEmpty);
      },
    );

    test('serializes full-cache writes across providers', () async {
      configStore.configs = <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
        AgentProviderConfig.defaultGrok,
      ];
      capabilities.modelResults.addAll(<AgentModelList>[
        modelList('codex-model'),
        modelList('grok-model'),
      ]);
      final saveGate = Completer<void>();
      modelCache.saveCompleters.add(saveGate);
      createRepository(
        factories: <AgentProviderKind, AgentProviderBundleFactory>{
          AgentProviderKind.codexAppServer: factory,
          AgentProviderKind.acp: factory,
        },
      );
      await repository.ready;

      final codex = repository.modelCatalog('codex');
      final grok = repository.modelCatalog('grok');
      await Future<void>.delayed(Duration.zero);
      expect(modelCache.saveCalls, 1);
      saveGate.complete();
      await Future.wait<AgentModelList>(<Future<AgentModelList>>[codex, grok]);

      expect(modelCache.saveCalls, 2);
      expect(modelCache.saves.first, hasLength(1));
      expect(modelCache.saves.last, hasLength(2));
    });
  });

  group('explicit model persistence', () {
    test('writes, publishes, and updates an existing runtime', () async {
      createRepository();
      await repository.ready;
      repository.bundleFor('codex');
      final changes = <ProviderConfigSnapshot>[];
      repository.configChanges.listen(changes.add);
      const selection = AgentModelSelection(
        modelId: 'gpt-5.6',
        reasoningEffort: 'high',
        serviceTierId: 'priority',
      );

      await repository.persistDefaultModel(' codex ', selection);

      expect(configStore.writes, hasLength(1));
      final updated = repository.configSnapshot.providerById('codex')!;
      expect(updated.selectedModel, 'gpt-5.6');
      expect(updated.selectedReasoningEffort, 'high');
      expect(updated.selectedServiceTier, 'priority');
      expect(changes.single.revision, 2);
      expect(runtime.selections, <AgentModelSelection>[selection]);
    });

    test('serializes writes and retains state on failure', () async {
      final firstWrite = Completer<void>();
      configStore.writeCompleters.add(firstWrite);
      createRepository();
      await repository.ready;
      final first = repository.persistDefaultModel(
        'codex',
        const AgentModelSelection(modelId: 'first'),
      );
      final second = repository.persistDefaultModel(
        'codex',
        const AgentModelSelection(modelId: 'second'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(configStore.writes, hasLength(1));
      firstWrite.complete();
      await Future.wait<void>(<Future<void>>[first, second]);
      expect(configStore.writes, hasLength(2));
      expect(
        repository.configSnapshot.providerById('codex')!.selectedModel,
        'second',
      );

      configStore.writeError = StateError('write failed');
      await expectLater(
        repository.persistDefaultModel(
          'codex',
          const AgentModelSelection(modelId: 'lost'),
        ),
        failsWith(
          AgentProviderFailureCode.unknown,
          'persistDefaultModel_failed',
        ),
      );
      expect(
        repository.configSnapshot.providerById('codex')!.selectedModel,
        'second',
      );
    });

    test(
      'translates a synchronous runtime update failure after persistence',
      () async {
        runtime.updateError = StateError('runtime update failed');
        createRepository();
        await repository.ready;
        repository.bundleFor('codex');

        await expectLater(
          repository.persistDefaultModel(
            'codex',
            const AgentModelSelection(modelId: 'persisted'),
          ),
          failsWith(
            AgentProviderFailureCode.unknown,
            'persistDefaultModel_failed',
          ),
        );
        expect(configStore.writes, hasLength(1));
        expect(
          repository.configSnapshot.providerById('codex')!.selectedModel,
          'persisted',
        );
      },
    );
  });
}

Matcher failsWith(
  AgentProviderFailureCode code,
  String? diagnosticCode, {
  AgentProviderRepositoryOperation? operation,
  Object? cause,
}) => throwsA(
  isA<AgentProviderRepositoryException>()
      .having((error) => error.failure.code, 'code', code)
      .having(
        (error) => error.failure.diagnosticCode,
        'diagnosticCode',
        diagnosticCode ?? anything,
      )
      .having(
        (error) => error.operation,
        'operation',
        operation ?? anything,
      )
      .having((error) => error.cause, 'cause', cause ?? anything),
);

AgentModelList modelList(String id) => AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(id: id, model: id, displayName: id),
  ],
);

AgentModelList emptyModelList() =>
    AgentModelList(models: const <AgentModelInfo>[]);

AgentProviderBundle _bundle(_Runtime runtime, _Capabilities? capabilities) =>
    AgentProviderBundle(
      runtime: runtime,
      conversation: _Conversation(),
      modelCatalog: capabilities,
      conversationModes: capabilities,
      skills: capabilities,
      permissionPolicy: capabilities,
    );

final class _ConfigStore implements ProviderConfigStore {
  _ConfigStore(this.configs);
  List<AgentProviderConfig> configs;
  final List<List<AgentProviderConfig>> writes = <List<AgentProviderConfig>>[];
  final List<Completer<void>> writeCompleters = <Completer<void>>[];
  Completer<List<AgentProviderConfig>>? readCompleter;
  Object? readError;
  Object? writeError;

  @override
  Future<List<AgentProviderConfig>> read() async {
    if (readError case final error?) _throwTestError(error);
    return readCompleter?.future ?? configs;
  }

  @override
  Future<void> write(List<AgentProviderConfig> configs) async {
    writes.add(List<AgentProviderConfig>.unmodifiable(configs));
    if (writeError case final error?) _throwTestError(error);
    if (writeCompleters.isNotEmpty) await writeCompleters.removeAt(0).future;
  }
}

final class _ModelCacheStore implements AgentModelCatalogCacheStore {
  List<AgentModelCatalogSnapshot> loaded = <AgentModelCatalogSnapshot>[];
  final List<List<AgentModelCatalogSnapshot>> saves =
      <List<AgentModelCatalogSnapshot>>[];
  Object? loadError;
  Object? saveError;
  Completer<List<AgentModelCatalogSnapshot>>? loadCompleter;
  final List<Completer<void>> saveCompleters = <Completer<void>>[];
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async {
    loadCalls += 1;
    if (loadError case final error?) _throwTestError(error);
    return loadCompleter?.future ?? loaded;
  }

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    saveCalls += 1;
    if (saveError case final error?) _throwTestError(error);
    saves.add(List<AgentModelCatalogSnapshot>.unmodifiable(snapshots));
    if (saveCompleters.isNotEmpty) {
      await saveCompleters.removeAt(0).future;
    }
  }
}

final class _BundleFactory implements AgentProviderBundleFactory {
  _BundleFactory(this.builder);
  AgentProviderBundle Function() builder;
  final List<AgentProviderConfig> createdWith = <AgentProviderConfig>[];
  Object? error;

  @override
  AgentProviderBundle createBundle(AgentProviderConfig config) {
    createdWith.add(config);
    if (error case final value?) _throwTestError(value);
    return builder();
  }
}

final class _Runtime implements AgentRuntimePort {
  int initializeCalls = 0;
  int disposeCalls = 0;
  Completer<void>? initializeCompleter;
  Object? initializeError;
  Object? disposeError;
  Object? updateError;
  final List<AgentModelSelection> selections = <AgentModelSelection>[];

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.unsupported;
  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;
  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();
  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.stopped;
  @override
  AgentRuntimeInfo? get runtimeInfo => null;
  @override
  AgentRuntimeScope? get runtimeScope => null;

  @override
  Future<void> initialize() {
    initializeCalls += 1;
    if (initializeError case final error?) _throwTestError(error);
    return initializeCompleter?.future ?? Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (disposeError case final error?) _throwTestError(error);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    if (updateError case final error?) _throwTestError(error);
    selections.add(selection);
  }
}

final class _Capabilities
    implements
        AgentModelCatalogPort,
        AgentConversationModeCatalogPort,
        AgentSkillsPort,
        AgentPermissionPolicyPort {
  final modes = AgentConversationModeCatalog(
    presets: const <AgentConversationModePreset>[],
  );
  final skillsCatalog = AgentSkillsCatalog(
    entries: const <AgentSkillsCatalogEntry>[],
  );
  final permissionCatalog = AgentPermissionCatalog(
    options: const <AgentPermissionOption>[],
    defaultOptionId: 'safe',
  );
  final permissionResult = const AgentPermissionApplyResult(
    normalizedSelection: AgentPermissionSelection(optionId: 'safe'),
    scope: AgentPermissionApplyScope.nextSession,
  );
  final List<AgentModelList> modelResults = <AgentModelList>[];
  final List<bool> forceRefreshValues = <bool>[];
  final List<String> receivedCwds = <String>[];
  final List<bool> skillsForceReloadValues = <bool>[];
  final StreamController<void> skillsChangedController =
      StreamController<void>.broadcast(sync: true);
  Object? modelError;
  Object? modeError;
  Object? skillsError;
  Object? permissionOptionsError;
  Completer<AgentModelList>? modelCompleter;
  AgentPermissionSelection? receivedSelection;
  bool cwdsWereImmutable = false;
  int modelCalls = 0;

  @override
  Stream<void> get skillsChanged => skillsChangedController.stream;

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    modelCalls += 1;
    forceRefreshValues.add(forceRefresh);
    if (modelError case final error?) _throwTestError(error);
    if (modelCompleter case final completer?) return completer.future;
    return modelResults.removeAt(0);
  }

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    if (modeError case final error?) _throwTestError(error);
    return modes;
  }

  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) async {
    skillsForceReloadValues.add(forceReload);
    if (skillsError case final error?) _throwTestError(error);
    receivedCwds
      ..clear()
      ..addAll(cwds);
    expect(() => cwds.add('mutation'), throwsUnsupportedError);
    cwdsWereImmutable = true;
    return skillsCatalog;
  }

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    if (permissionOptionsError case final error?) _throwTestError(error);
    return permissionCatalog;
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    receivedSelection = selection;
    return permissionResult;
  }
}

final class _Conversation extends Mock implements AgentConversationPort {}

Never _throwTestError(Object error) {
  if (error is Error) {
    throw error;
  }
  if (error is Exception) {
    throw error;
  }
  throw StateError('Invalid test error');
}
