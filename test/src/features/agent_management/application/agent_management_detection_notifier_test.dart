import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_agent_view.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_port.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_detection_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_home_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_dependencies.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';

void main() {
  test(
    'initializing callers share the exact future and only one execution',
    () async {
      final h = _Harness(initializing: true);
      final first = h.owner.ensureDetected();
      expect(h.owner.ensureDetected(), same(first));
      expect(h.owner.refreshDetection(), same(first));
      expect(h.runner.initializationCalls, 1);
      expect(h.port.calls, 0);
      h.runner.initialized.complete();
      await _flush();
      expect(h.port.calls, 1);
      h.succeed('a', '1');
      h.succeed('b', '2');
      h.port.done.complete();
      expect((await first).status, DetectionRunStatus.succeeded);
      expect(h.port.calls, 1);
    },
  );

  test(
    'partial never commits, A success and B failure retain per-provider confirmed evidence',
    () async {
      final h = _Harness(cached: true);
      final request = h.owner.ensureDetected();
      await _flush();
      h.port.emit(DetectionProviderStarted('a'));
      h.port.emit(
        const DetectionProviderProgress(
          'a',
          AgentDetectionProgress(completed: 1, total: 3, message: 'progress'),
          AgentDetectionPartial(currentVersion: 'partial'),
        ),
      );
      expect(h.home.installedProviders.map((v) => v.version), [
        'old-a',
        'old-b',
      ]);
      expect(h.owner.agent.currentVersion, 'old-a');
      h.succeed('a', 'new-a');
      h.fail('b');
      h.port.done.complete();
      expect((await request).status, DetectionRunStatus.partialFailure);
      expect(h.home.installedProviders.map((v) => v.version), [
        'new-a',
        'old-b',
      ]);
      expect(h.home.showingStaleData, isTrue);
      expect(
        h.owner.current.detection.confirmedByProviderId['b']!.freshness,
        DetectionFreshness.stale,
      );
      expect(h.owner.current.detection.pendingPartialByProviderId, isEmpty);
      expect(h.home.detectionFailure?.agentId, 'b');
      expect(h.owner.operationError, isNull);
    },
  );

  test(
    'all failed on first attempt stays unknown and remount ensure never retries',
    () async {
      final h = _Harness();
      final request = h.owner.ensureDetected();
      await _flush();
      h.fail('a');
      h.fail('b');
      h.port.done.complete();
      expect((await request).status, DetectionRunStatus.failed);
      expect(h.home.hasConfirmedData, isFalse);
      expect(h.home.installedProviders, isEmpty);
      expect(h.owner.agent.installationState, AgentInstallationState.unknown);
      final subscription = h.container.listen(
        agentManagementHomeProvider,
        (_, _) {},
      );
      subscription.close();
      await h.owner.ensureDetected();
      expect(h.port.calls, 1);
      final next = h.owner.refreshDetection();
      await _flush();
      expect(h.port.calls, 2);
      h.succeed('a', '1');
      h.succeed('b', '1');
      h.port.done.complete();
      await next;
    },
  );

  test(
    'confirmed not installed removes row and settings/runtime beat stale detection',
    () async {
      final h = _Harness(cached: true);
      final request = h.owner.refreshDetection();
      await _flush();
      h.owner.runtimeFactsReplaced(
        AgentManagementRuntimeFacts([
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: 'a',
            lifecycle: AgentConversationRuntimeLifecyclePhase.attached,
            activeTurn: true,
          ),
          AgentManagementRuntimeFact(
            observationKey: Object(),
            providerId: 'b',
            runtimeIdentity: const AgentProviderRuntimeIdentity(
              providerId: 'b',
              generation: 1,
            ),
            lifecycle: AgentConversationRuntimeLifecyclePhase.attached,
            connected: true,
          ),
        ]),
      );
      h.owner.providerSettingsChanged(
        AgentProviderSettings(
          providers: [
            for (final id in ['a', 'b'])
              AgentProviderConfig(
                id: id,
                displayName: id,
                kind: const AgentProviderTypeId('test'),
                command: id,
                enabled: false,
              ),
          ],
        ),
      );
      h.succeed('a', '2');
      expect(h.owner.agent.enabled, isFalse);
      expect(h.owner.agent.runtimeState, AgentRuntimeState.running);
      expect(
        h.home.installedProviders.first.status,
        HomeProviderStatus.running,
      );
      h.port.emit(const DetectionProviderStarted('b'));
      h.port.emit(
        DetectionProviderSucceeded(
          'b',
          AgentDetectionDetails(
            installationState: AgentInstallationState.notInstalled,
          ),
        ),
      );
      h.port.done.complete();
      await request;
      expect(h.home.installedProviders.map((v) => v.id), ['a']);
      expect(
        h.owner.current.runtimeByProviderId['b']!.connectedRuntimeCount,
        1,
      );
    },
  );

  test(
    'cancel settles now, preserves A, retains active slot until physical completion',
    () async {
      final h = _Harness(cached: true);
      final first = h.owner.ensureDetected();
      await _flush();
      h.succeed('a', 'new-a');
      h.port.emit(const DetectionProviderStarted('b'));
      h.owner.cancelDetection();
      expect((await first).status, DetectionRunStatus.canceled);
      expect(h.owner.refreshDetection(), same(first));
      expect(h.port.calls, 1);
      expect(
        h.port.emit(
          DetectionProviderSucceeded(
            'b',
            AgentDetectionDetails(currentVersion: 'late'),
          ),
        ),
        isFalse,
      );
      expect(h.home.installedProviders.map((v) => v.version), [
        'new-a',
        'old-b',
      ]);
      h.port.done.complete();
      await _flush();
      await h.owner.ensureDetected();
      expect(h.port.calls, 1);
      final second = h.owner.refreshDetection();
      await _flush();
      expect(h.port.calls, 2);
      h.succeed('a', '3');
      h.succeed('b', '3');
      h.port.done.complete();
      await second;
    },
  );

  test(
    'stop settles closed and drains physical work; old callbacks cannot reach new owner',
    () async {
      final h = _Harness();
      final request = h.owner.ensureDetected();
      await _flush();
      final oldEmit = h.port.emit;
      h.owner.stopAcceptingCommandsAndSettleWaiters();
      expect((await request).status, DetectionRunStatus.closed);
      var drained = false;
      final drain = h.owner.drainExecutions().then((_) => drained = true);
      await _flush();
      expect(drained, isFalse);
      final other = _Harness();
      expect(
        oldEmit(
          DetectionProviderSucceeded(
            'a',
            AgentDetectionDetails(currentVersion: 'late'),
          ),
        ),
        isFalse,
      );
      expect(other.home.hasConfirmedData, isFalse);
      h.port.done.complete();
      await drain;
      expect(
        (await h.owner.refreshDetection()).status,
        DetectionRunStatus.closed,
      );
    },
  );

  test(
    'initialization failure becomes a safe failure and does not strand or automatically retry',
    () async {
      final h = _Harness(initializing: true);
      final request = h.owner.ensureDetected();
      h.runner.initialized.completeError(
        StateError('token=secret /private/path'),
      );
      expect((await request).status, DetectionRunStatus.failed);
      expect(h.home.detectionFailure?.message, isNull);
      await h.owner.ensureDetected();
      expect(h.runner.initializationCalls, 1);
      expect(h.port.calls, 0);
    },
  );

  test(
    'synchronous observer reentry joins reserved run before any effect',
    () async {
      final h = _Harness();
      Future<AgentManagementDetectionRunResult>? joined;
      final sub = h.container.listen(agentManagementSliceProvider, (_, value) {
        if (value.detection.phase == ManagementDetectionPhase.initializing) {
          joined = h.owner.refreshDetection();
        }
      });
      final first = h.owner.ensureDetected();
      expect(joined, same(first));
      await _flush();
      h.succeed('a', '1');
      h.succeed('b', '1');
      h.port.done.complete();
      await first;
      sub.close();
      expect(h.port.calls, 1);
    },
  );

  test(
    'observer failure after state publication cannot reject committed result or strand caller',
    () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final h = _Harness(observers: [_ThrowingObserver()]);
        final request = h.owner.ensureDetected();
        await _flush();
        expect(h.port.emit(const DetectionProviderStarted('a')), isTrue);
        expect(
          h.port.emit(
            DetectionProviderSucceeded(
              'a',
              AgentDetectionDetails(
                installationState: AgentInstallationState.installed,
                currentVersion: 'accepted',
              ),
            ),
          ),
          isTrue,
        );
        h.succeed('b', 'accepted');
        h.port.done.complete();
        expect((await request).status, DetectionRunStatus.succeeded);
        expect(h.owner.agent.currentVersion, 'accepted');
      }, (error, _) => errors.add(error));
      expect(errors, isNotEmpty);
    },
  );

  test(
    'catalog replacement cancels generation and rejects same-id old result',
    () async {
      final h = _Harness(cached: true);
      final request = h.owner.ensureDetected();
      await _flush();
      h.owner.replaceDetectionCatalog(1, {'a': _definition('a')});
      expect((await request).status, DetectionRunStatus.canceled);
      expect(
        h.port.emit(
          DetectionProviderSucceeded(
            'a',
            AgentDetectionDetails(currentVersion: 'old-generation'),
          ),
        ),
        isFalse,
      );
      expect(h.owner.refreshDetection(), same(request));
      expect(h.home.hasConfirmedData, isFalse);
      h.port.done.complete();
      await _flush();
      final next = h.owner.refreshDetection();
      await _flush();
      expect(h.port.generation, 1);
      h.succeed('a', 'current');
      h.port.done.complete();
      await next;
      expect(h.home.installedProviders.single.version, 'current');
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
AgentManagementDisplayDefinition _definition(String id) =>
    AgentManagementDisplayDefinition(
      id: id,
      displayName: id,
      vendor: 'test',
      commandName: id,
      protocol: 'test',
      transport: 'test',
      configFormat: 'test',
    );

final class _Harness {
  _Harness({
    bool cached = false,
    bool initializing = false,
    List<ProviderObserver> observers = const [],
  }) {
    runner = _Runner(port, initializing);
    container = ProviderContainer(
      observers: observers,
      overrides: [
        agentManagementSliceDependenciesProvider.overrideWithValue(
          AgentManagementSliceDependencies(
            initialState: AgentManagementSliceState(
              definitionsByProviderId: {
                for (final id in ['a', 'b']) id: _definition(id),
              },
              orderedAgentIds: ['a', 'b'],
              selectedAgentId: 'a',
              capabilitiesByAgentId: {},
              initialized: !initializing,
              detection: AgentManagementDetectionState(
                confirmedByProviderId: {
                  if (cached)
                    for (final id in ['a', 'b'])
                      id: AgentDetectionConfirmedRecord(
                        details: AgentDetectionDetails(
                          installationState: AgentInstallationState.installed,
                          currentVersion: 'old-$id',
                        ),
                        freshness: DetectionFreshness.restoredCache,
                      ),
                },
              ),
            ),
            configurationNotLoadedMessage: '',
            accountDataEnrichmentEnabledFor: (_) => false,
          ),
        ),
        agentManagementRunnerFactoryProvider.overrideWithValue((sink) {
          runner.sink = sink;
          return runner;
        }),
      ],
    );
    owner = container.read(agentManagementSliceProvider.notifier);
    addTearDown(() async {
      owner.stopAcceptingCommandsAndSettleWaiters();
      if (!runner.initialized.isCompleted) runner.initialized.complete();
      if (!port.done.isCompleted) port.done.complete();
      await owner.drainExecutions();
      container.dispose();
    });
  }
  final port = _Port();
  late final _Runner runner;
  late final ProviderContainer container;
  late final AgentManagementSliceNotifier owner;
  AgentManagementHomeState get home => selectManagementHome(owner.current);
  void succeed(String id, String version) {
    port.emit(DetectionProviderStarted(id));
    port.emit(
      DetectionProviderSucceeded(
        id,
        AgentDetectionDetails(
          installationState: AgentInstallationState.installed,
          currentVersion: version,
        ),
      ),
    );
  }

  void fail(String id) {
    port.emit(DetectionProviderStarted(id));
    port.emit(
      DetectionProviderFailed(
        id,
        AgentManagementFailure(
          kind: AgentManagementFailureKind.detection,
          operationId: owner.current.detection.operationId!,
          agentId: id,
        ),
      ),
    );
  }
}

final class _Port implements AgentManagementDetectionPort {
  int calls = 0;
  int generation = 0;
  Completer<void> done = Completer<void>();
  late bool Function(AgentManagementDetectionEvent) emit;
  @override
  Future<void> detect({
    required OperationId operationId,
    required List<String> providerIds,
    required int catalogGeneration,
    required AgentManagementCancellation cancellation,
    required bool Function(AgentManagementDetectionEvent) emit,
  }) {
    calls++;
    generation = catalogGeneration;
    this.emit = emit;
    done = Completer<void>();
    return done.future;
  }
}

final class _Runner implements AgentManagementSliceEffectRunner {
  _Runner(this.port, this.waitForInit);
  final _Port port;
  final bool waitForInit;
  final initialized = Completer<void>();
  int initializationCalls = 0;
  late AgentManagementResultSink sink;
  @override
  Future<void> run(AgentManagementSliceEffect effect) async {
    if (effect is ManagementInitializeEffect) {
      initializationCalls++;
      try {
        if (waitForInit) await initialized.future;
        sink.initializationSucceeded(
          effect.operationId,
          sink.current.providerSettings,
          {},
        );
      } catch (e, st) {
        sink.initializationFailed(effect.operationId, e, st);
      }
    } else if (effect is DetectAgentsEffect) {
      await port.detect(
        operationId: effect.operationId,
        providerIds: effect.providerIds,
        catalogGeneration: effect.catalogGeneration,
        cancellation: effect.cancellation,
        emit: (event) => sink.acceptDetectionResult(
          effect.operationId,
          effect.ownerGeneration,
          effect.catalogGeneration,
          event,
        ),
      );
    } else {
      throw StateError('Unexpected effect');
    }
  }

  @override
  String? validateConfiguration(String agentId, String content) => null;
}

final class _ThrowingObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (context.provider == agentManagementSliceProvider) {
      throw StateError('observer failure');
    }
  }
}
