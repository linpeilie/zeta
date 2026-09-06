import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_details_catalog.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/app/agent_management_slice/contributed_agent_management_detection_adapter.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import '../../testing/agent_management_test_container.dart';

void main() {
  test(
    'initialization reads current settings after the cached load future resolves',
    () async {
      final h = _Harness();
      h.settings.loadResult = h.settings.settings;
      h.settings.replace(
        _config('a').copyWith(
          enabled: false,
          extra: {
            'cliPath': '/current/a',
            'detectedCurrentVersion': 'current-cache',
          },
        ),
      );
      final container = managementAppTestContainer(
        AgentManagementCompositionInputs(
          repositories: h.repos,
          definitions: h.definitions,
          providerSettings: h.settings,
          textCatalog: const FallbackAgentManagementTextCatalog(),
        ),
      );
      addTearDown(() => closeManagementTestContainer(container));
      final owner = container.read(agentManagementSliceProvider.notifier);
      await owner.initialize();
      expect(owner.agent.enabled, isFalse);
      expect(owner.agent.currentVersion, 'current-cache');
      expect(owner.current.providerSettings, same(h.settings.settings));
    },
  );

  test(
    'A failure does not prevent B success; cache failure is independent warning',
    () async {
      final h = _Harness();
      h.repos['a']!.failure = StateError('secret /home/private');
      h.settings.failWrites = true;
      await h.run();
      expect(
        h.events.whereType<DetectionProviderFailed>().single.providerId,
        'a',
      );
      expect(
        h.events.whereType<DetectionProviderSucceeded>().single.providerId,
        'b',
      );
      expect(
        h.events.whereType<DetectionCacheWriteWarning>().single.providerId,
        'b',
      );
      expect(
        h.events.whereType<DetectionProviderFailed>().single.failure.message,
        isNull,
      );
    },
  );

  test(
    'detect completion merges whitelist into latest settings without losing user edits',
    () async {
      final h = _Harness();
      final gate = Completer<void>();
      h.repos['a']!.gate = gate;
      final request = h.run();
      await _flush();
      final latest = _config('a').copyWith(
        enabled: false,
        command: 'new-command',
        arguments: ['new-argument'],
        extra: {'permissionOptionId': 'conservative', 'unrelated': 'retained'},
      );
      h.settings.replace(latest);
      gate.complete();
      await request;
      final written = h.settings.writes.first;
      expect(written.command, latest.command);
      expect(written.arguments, latest.arguments);
      expect(written.enabled, isFalse);
      expect(written.extra['permissionOptionId'], 'conservative');
      expect(written.extra['unrelated'], 'retained');
      expect(written.extra['detectedCurrentVersion'], 'new-a');
      expect(h.settings.restarts, everyElement(isFalse));
    },
  );

  test(
    'confirmed not installed clears stale install cache without replacing user command',
    () async {
      final h = _Harness();
      h.settings.replace(_config('a').copyWith(extra: {'cliPath': '/old/a'}));
      h.repos['a']!.notInstalled = true;
      await h.run();
      expect(h.settings.writes.first.extra.containsKey('cliPath'), isFalse);
      expect(h.settings.writes.first.command, 'a');
      expect(
        h.events
            .whereType<DetectionProviderSucceeded>()
            .first
            .details
            .installationState,
        AgentInstallationState.notInstalled,
      );
    },
  );

  test(
    'cancel during repository await drops late result and prevents any write or resource',
    () async {
      final h = _Harness();
      final gate = Completer<void>();
      h.repos['a']!.gate = gate;
      final request = expectLater(
        h.run(),
        throwsA(isA<AgentManagementDetectionCanceled>()),
      );
      await _flush();
      h.cancel.canceled = true;
      gate.complete();
      await request;
      expect(h.events.whereType<DetectionProviderSucceeded>(), isEmpty);
      expect(h.settings.writes, isEmpty);
      expect(h.catalog.resourceCount, 0);
      expect(h.repos['b']!.calls, 0);
    },
  );

  for (final throwing in [false, true]) {
    test(
      'staged handle is visible before receipt and discarded on ${throwing ? 'throw' : 'rejection'}',
      () async {
        final h = _Harness();
        AgentManagementDetailsHandle? staged;
        h.accept = (event) {
          if (event is DetectionProviderSucceeded) {
            staged = event.details.detailsHandle;
            expect(h.catalog.display(staged).available, isTrue);
            expect(h.catalog.display(staged).executableLocationLabel, '…/a');
            if (throwing) throw StateError('observer before commit');
            return false;
          }
          return true;
        };
        await expectLater(
          h.run(),
          throwsA(
            throwing
                ? isA<StateError>()
                : isA<AgentManagementDetectionCanceled>(),
          ),
        );
        expect(h.catalog.display(staged).available, isFalse);
        expect(h.catalog.resourceCount, 0);
        expect(h.settings.writes, isEmpty);
      },
    );
  }

  test(
    'catalog generation mismatch and same-id replacement fail closed',
    () async {
      final h = _Harness();
      await expectLater(
        h.run(generation: 1),
        throwsA(isA<AgentManagementDetectionCanceled>()),
      );
      expect(h.repos['a']!.calls, 0);
      h.repos['a']!.replacement = _definition('a');
      await h.run();
      expect(
        h.events.whereType<DetectionProviderFailed>().single.providerId,
        'a',
      );
      expect(h.settings.writes.map((v) => v.id), ['b']);
    },
  );

  test(
    'cancel synchronously after accepted success prevents not-yet-started write',
    () async {
      final h = _Harness();
      h.accept = (event) {
        if (event is DetectionProviderSucceeded) h.cancel.canceled = true;
        return true;
      };
      await expectLater(
        h.run(),
        throwsA(isA<AgentManagementDetectionCanceled>()),
      );
      expect(h.events.whereType<DetectionProviderSucceeded>().length, 1);
      expect(h.settings.writes, isEmpty);
      expect(h.catalog.resourceCount, 1);
    },
  );

  test(
    'details slots replace independently, copy stays inside catalog, closed handles fail',
    () async {
      final copied = <String>[];
      final opened = <String>[];
      final catalog = AppAgentManagementDetailsCatalog(
        copy: (s) async => copied.add(s),
        openDirectory: (s) async => opened.add(s),
      );
      final first = catalog.stage(
        executable: '/private/agent',
        diagnostic: 'token=secret /private/file',
      )!;
      catalog.confirm('a', AgentManagementDetailsKind.detection, first);
      final check = catalog.stage(diagnostic: 'authorization: secret')!;
      catalog.confirm(
        'a',
        AgentManagementDetailsKind.explicitConnectionCheck,
        check,
      );
      expect(
        catalog.display(first).diagnosticDescription,
        isNot(contains('secret')),
      );
      expect(
        catalog.display(first).diagnosticDescription,
        isNot(contains('/private')),
      );
      await catalog.copyExecutableLocation(first);
      await catalog.openExecutableDirectory(first);
      expect(copied, ['/private/agent']);
      expect(opened, ['/private']);
      final replacement = catalog.stage(executable: '/other/agent')!;
      catalog.confirm('a', AgentManagementDetailsKind.detection, replacement);
      expect(catalog.display(first).available, isFalse);
      expect(catalog.display(check).available, isTrue);
      expect(catalog.resourceCount, 2);
      final unknown = AgentManagementDetailsHandle();
      expect(catalog.display(unknown).available, isFalse);
      await expectLater(
        catalog.copyExecutableLocation(unknown),
        throwsUnsupportedError,
      );
      catalog.close();
      expect(catalog.resourceCount, 0);
      expect(catalog.display(check).available, isFalse);
      await expectLater(
        catalog.copyExecutableLocation(replacement),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'process configuration change rejects a connection result still in flight',
    () async {
      final h = _Harness();
      final container = managementAppTestContainer(
        AgentManagementCompositionInputs(
          repositories: h.repos,
          definitions: h.definitions,
          providerSettings: h.settings,
          textCatalog: const FallbackAgentManagementTextCatalog(),
        ),
      );
      final owner = container.read(agentManagementSliceProvider.notifier);
      addTearDown(() => closeManagementTestContainer(container));
      await owner.initialize();
      final gate = Completer<void>();
      h.repos['a']!.connectionGate = gate;
      final request = owner.testConnection();
      h.settings.replace(_config('a').copyWith(environment: {'MODE': 'new'}));
      gate.complete();
      expect(await request, isNull);
      expect(owner.current.confirmedConnectionChecksByProviderId, isEmpty);
    },
  );

  test(
    'explicit checks override diagnostics, preserve detection models on empty, clear after process config edit',
    () async {
      final h = _Harness();
      final container = managementAppTestContainer(
        AgentManagementCompositionInputs(
          repositories: h.repos,
          definitions: h.definitions,
          providerSettings: h.settings,
          textCatalog: const FallbackAgentManagementTextCatalog(),
        ),
      );
      final owner = container.read(agentManagementSliceProvider.notifier);
      addTearDown(() => closeManagementTestContainer(container));
      await owner.refreshDetection();
      expect(owner.agent.models.single.id, 'detected');
      final original = owner.current.detection.confirmedByProviderId['a'];
      await owner.testConnection();
      expect(owner.agent.connectionTest!.success, isTrue);
      expect(owner.agent.models.single.id, 'detected');
      expect(
        owner.current.detection.confirmedByProviderId['a'],
        same(original),
      );
      h.repos['a']!.connectionModels = const [
        AgentModelInfo(
          id: 'explicit',
          model: 'explicit',
          displayName: 'explicit',
        ),
      ];
      await owner.testConnection();
      expect(owner.agent.models.single.id, 'explicit');
      h.settings.replace(_config('a').copyWith(command: 'updated'));
      expect(owner.current.confirmedConnectionChecksByProviderId, isEmpty);
      expect(owner.agent.models.single.id, 'detected');
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
AgentDefinition _definition(String id) => AgentDefinition(
  id: id,
  displayName: id,
  vendor: 'test',
  commandName: id,
  protocol: 'test',
  transport: 'test',
  configFormat: 'test',
  defaultConfigRelativePath: '',
  npmPackage: '',
);
AgentProviderConfig _config(String id) => AgentProviderConfig(
  id: id,
  kind: const AgentProviderTypeId('test'),
  displayName: id,
  command: id,
);

final class _Harness {
  _Harness() {
    repos = {for (final e in definitions.entries) e.key: _Repository(e.value)};
    adapter = ContributedAgentManagementDetectionAdapter(
      repositories: repos,
      definitions: definitions,
      settings: settings,
      details: catalog,
      textCatalog: const FallbackAgentManagementTextCatalog(),
      configFor: (s, r) => s.providers.firstWhere((p) => p.id == r.agentId),
    );
    addTearDown(catalog.close);
  }
  final definitions = {
    for (final id in ['a', 'b']) id: _definition(id),
  };
  late final Map<String, _Repository> repos;
  final settings = _Settings();
  final cancel = _Cancellation();
  final catalog = AppAgentManagementDetailsCatalog();
  final events = <AgentManagementDetectionEvent>[];
  bool Function(AgentManagementDetectionEvent)? accept;
  late final ContributedAgentManagementDetectionAdapter adapter;
  Future<void> run({int generation = 0}) => adapter.detect(
    operationId: OperationIdGenerator(scope: 'test').next(),
    providerIds: ['a', 'b'],
    catalogGeneration: generation,
    cancellation: cancel,
    emit: (e) {
      events.add(e);
      return accept?.call(e) ?? true;
    },
  );
}

final class _Cancellation implements AgentManagementCancellation {
  bool canceled = false;
  @override
  bool get isCanceled => canceled;
  @override
  void throwIfCanceled() {
    if (canceled) throw const AgentManagementDetectionCanceled();
  }
}

final class _Repository implements AgentCliManagementRepository {
  _Repository(this.definition);
  final AgentDefinition definition;
  AgentDefinition? replacement;
  Completer<void>? gate;
  Object? failure;
  bool notInstalled = false;
  int calls = 0;
  Completer<void>? connectionGate;
  List<AgentModelInfo> connectionModels = const [];
  @override
  String get agentId => definition.id;
  @override
  String get configPath => '/private/config';
  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    calls++;
    await gate?.future;
    if (failure case final error?) throw error;
    final agent =
        ManagedAgent.forDefinition(
          definition: replacement ?? definition,
          enabled: enabled,
        ).copyWith(
          installationState: notInstalled
              ? AgentInstallationState.notInstalled
              : AgentInstallationState.installed,
          currentVersion: 'new-$agentId',
          executablePath: notInstalled ? null : '/private/$agentId',
          models: const [
            AgentModelInfo(
              id: 'detected',
              model: 'detected',
              displayName: 'detected',
            ),
          ],
        );
    onProgress?.call(
      const AgentDetectionProgress(
        completed: 1,
        total: 1,
        message: 'token=secret /private/a',
      ),
      agent,
    );
    return agent;
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    await connectionGate?.future;
    return (
      AgentConnectionTestResult(
        success: true,
        testedAt: DateTime(2026),
        elapsed: Duration.zero,
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
      ),
      connectionModels,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Settings implements AgentProviderSettingsPort {
  @override
  AgentProviderSettings settings = AgentProviderSettings(
    providers: [_config('a'), _config('b')],
  );
  final writes = <AgentProviderConfig>[];
  final restarts = <bool>[];
  final listeners = <void Function()>[];
  bool failWrites = false;
  AgentProviderSettings? loadResult;
  void replace(AgentProviderConfig p) {
    settings = settings.copyWith(
      providers: [
        for (final old in settings.providers)
          if (old.id == p.id) p else old,
      ],
    );
    for (final f in List.of(listeners)) {
      f();
    }
  }

  @override
  Future<void> updateProviderConfig(
    AgentProviderConfig updated, {
    bool restartProvider = false,
  }) async {
    if (failWrites) throw StateError('private failure');
    writes.add(updated);
    restarts.add(restartProvider);
    replace(updated);
  }

  @override
  Future<AgentProviderSettings> loadSettings() async => loadResult ?? settings;
  @override
  bool isProviderEnabled(String id) =>
      settings.providers.firstWhere((p) => p.id == id).enabled;
  @override
  void Function() subscribe(void Function() listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
