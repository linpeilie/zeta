import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_state.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

const _runtimeIdentity = AgentProviderRuntimeIdentity(
  providerId: 'test-provider',
  generation: 1,
);

void main() {
  group('AgentConversationPermissionSelectionController', () {
    test(
      'seeds optionId as default preference without provider kind branch',
      () {
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        controller.seedFromConfig('auto');

        expect(controller.selectedOptionId, 'auto');
        expect(controller.defaultOptionId, 'auto');
        expect(controller.effectiveSelection?.optionId, 'auto');
      },
    );

    test('selectOption applies via port and persists normalized id', () async {
      String? persisted;
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
          AgentPermissionOption(id: 'always-approve', label: 'Always approve'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (id) async => persisted = id,
      );
      controller.bind(
        port: port,
        persistedOptionId: 'ask',
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();

      await controller.selectOption(
        const AgentPermissionOption(
          id: 'always-approve',
          label: 'Always approve',
        ),
      );

      expect(persisted, 'always-approve');
      expect(controller.selectedOptionId, 'always-approve');
      expect(controller.defaultOptionId, 'always-approve');
      expect(port.applyCalls, 1);
      expect(port.lastApplied?.optionId, 'always-approve');
    });

    test('refreshOptions ignores stale catalog after rebinding port', () async {
      final slow = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'slow', label: 'Slow'),
        ],
        listDelay: const Duration(milliseconds: 40),
      );
      final fast = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'fast', label: 'Fast'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );

      controller.bind(
        port: slow,
        persistedOptionId: null,
        runtimeIdentity: _runtimeIdentity,
      );
      final slowRefresh = controller.refreshOptions();
      controller.bind(
        port: fast,
        persistedOptionId: null,
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();
      await slowRefresh;

      expect(controller.options.map((o) => o.id), <String>['fast']);
      expect(controller.options.map((o) => o.id), isNot(contains('slow')));
    });

    test('apply failure rolls back effective selection', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
        ],
        applyError: StateError('apply failed'),
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(
        port: port,
        persistedOptionId: 'ask',
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();

      await controller.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(controller.selectedOptionId, 'ask');
      expect(controller.takeLastError(), isNotNull);
    });

    test(
      'thread settings update the binding effective without changing default',
      () async {
        final port = _FakePermissionPort(
          options: const <AgentPermissionOption>[
            AgentPermissionOption(id: ':workspace', label: 'Workspace write'),
            AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
          ],
        );
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {
            fail('settings must not persist global default');
          },
        );
        controller.bind(
          port: port,
          persistedOptionId: ':workspace',
          runtimeIdentity: _runtimeIdentity,
        );
        controller.bindThread('thread-a');
        await controller.refreshOptions();

        await controller.applyThreadSettings(
          threadId: 'thread-a',
          permissionSelection: const AgentPermissionSelection(
            optionId: 'team-safe',
          ),
        );

        expect(controller.selectedOptionId, 'team-safe');
        expect(controller.defaultOptionId, ':workspace');
        // 服务端回写默认不同步 port。
        expect(port.applyCalls, 0);

        controller.bindThread('thread-b');
        expect(controller.selectedOptionId, ':workspace');

        controller.bindThread('thread-a');
        expect(
          controller.selectedOptionId,
          ':workspace',
          reason: 'single Binding state must not cache a detached thread',
        );
      },
    );

    test('thread settings for another Binding are ignored', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: ':workspace', label: 'Workspace write'),
          AgentPermissionOption(id: ':read-only', label: 'Read only'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {
          fail('settings must not persist global default');
        },
      );
      controller.bind(
        port: port,
        persistedOptionId: ':workspace',
        runtimeIdentity: _runtimeIdentity,
      );
      controller.bindThread('thread-b');
      await controller.refreshOptions();

      await controller.applyThreadSettings(
        threadId: 'thread-a',
        permissionSelection: const AgentPermissionSelection(
          optionId: ':read-only',
        ),
      );

      expect(controller.selectedOptionId, ':workspace');
      expect(controller.defaultOptionId, ':workspace');
      expect(port.applyCalls, 0);
      expect(controller.state.sessionEffective, isNull);
      expect(
        controller.stateSource,
        AgentPermissionStateSource.providerDefault,
      );
    });

    test('runtime scope stays inside the owning Binding', () async {
      final firstPort = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
        ],
        applyScope: AgentPermissionApplyScope.runtime,
      );
      final secondPort = _FakePermissionPort(
        options: firstPort.options,
        applyScope: AgentPermissionApplyScope.runtime,
      );
      final first = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      final second = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      first.bind(
        port: firstPort,
        persistedOptionId: 'ask',
        runtimeIdentity: _runtimeIdentity,
      );
      first.bindThread('t1');
      second.bind(
        port: secondPort,
        persistedOptionId: 'ask',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: 'test',
          generation: 2,
        ),
      );
      second.bindThread('t2');
      await Future.wait(<Future<void>>[
        first.refreshOptions(),
        second.refreshOptions(),
      ]);

      await first.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(first.defaultOptionId, 'auto');
      expect(first.selectedOptionId, 'auto');
      expect(first.stateSource, AgentPermissionStateSource.runtimeSelection);
      expect(second.defaultOptionId, 'ask');
      expect(second.selectedOptionId, 'ask');
    });

    test('nextSession scope exposes compact hint', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
        ],
        applyScope: AgentPermissionApplyScope.nextSession,
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(
        port: port,
        persistedOptionId: 'ask',
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();
      await controller.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(controller.lastApplyScope, AgentPermissionApplyScope.nextSession);
      expect(controller.applyScopeHint, '下次会话生效');
    });

    test(
      'persistence failure keeps applied state and exposes retry without reapply',
      () async {
        var persistCalls = 0;
        final port = _FakePermissionPort(
          options: const <AgentPermissionOption>[
            AgentPermissionOption(id: 'ask', label: 'Ask'),
            AgentPermissionOption(id: 'auto', label: 'Auto'),
          ],
          applyScope: AgentPermissionApplyScope.runtime,
        );
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (optionId) async {
            persistCalls += 1;
            if (persistCalls == 1) {
              throw StateError('disk unavailable');
            }
          },
        );
        controller.bind(
          port: port,
          persistedOptionId: 'ask',
          runtimeIdentity: _runtimeIdentity,
        );
        controller.bindThread('thread-a');

        await controller.selectOption(
          const AgentPermissionOption(id: 'auto', label: 'Auto'),
        );

        expect(controller.selectedOptionId, 'auto');
        expect(controller.defaultOptionId, 'auto');
        expect(controller.canRetryPersistence, isTrue);
        expect(controller.lastError, contains('已应用'));
        expect(port.applyCalls, 1);

        expect(await controller.retryPersistOptionId(), isTrue);
        expect(controller.canRetryPersistence, isFalse);
        expect(controller.lastError, isNull);
        expect(persistCalls, 2);
        expect(
          port.applyCalls,
          1,
          reason: 'retry must not apply provider twice',
        );
      },
    );

    test(
      'applyEffectiveSelection commits normalizedSelection and runtime scope',
      () async {
        final port = _FakePermissionPort(
          options: const <AgentPermissionOption>[
            AgentPermissionOption(id: 'ask', label: 'Ask'),
            AgentPermissionOption(id: 'default', label: 'Default'),
          ],
          normalizeSelection: (selection) {
            final raw = selection.optionId;
            return AgentPermissionApplyResult(
              normalizedSelection: AgentPermissionSelection(
                optionId: raw == 'default' ? 'ask' : raw,
              ),
              scope: AgentPermissionApplyScope.runtime,
              warning: 'normalized',
            );
          },
        );
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        controller.bind(
          port: port,
          persistedOptionId: 'auto',
          runtimeIdentity: _runtimeIdentity,
        );
        controller.bindThread('t1');

        await controller.applyEffectiveSelection(
          const AgentPermissionSelection(optionId: 'default'),
        );

        expect(controller.selectedOptionId, 'ask');
        expect(controller.lastApplyScope, AgentPermissionApplyScope.runtime);
        expect(controller.lastApplyWarning, 'normalized');
        expect(
          controller.defaultOptionId,
          'auto',
          reason: 'runtime selection must not rewrite provider preference',
        );
      },
    );

    test('refreshOptions keeps catalog when port throws transiently', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(
        port: port,
        persistedOptionId: null,
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();
      expect(controller.options.map((o) => o.id), <String>['team-safe']);

      port.listError = TimeoutException('list timed out');
      await controller.refreshOptions();
      expect(controller.options.map((o) => o.id), <String>['team-safe']);
      expect(controller.lastError, contains('list timed out'));
    });

    test(
      'request snapshot keeps catalog default distinct from provider default',
      () async {
        final port = _FakePermissionPort(
          options: const <AgentPermissionOption>[
            AgentPermissionOption(id: 'catalog-safe', label: 'Catalog safe'),
          ],
        );
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        controller.bind(
          port: port,
          persistedOptionId: null,
          runtimeIdentity: _runtimeIdentity,
        );
        await controller.refreshOptions();

        final catalogSnapshot = controller.snapshotForRequest();
        expect(controller.defaultOptionId, isNull);
        expect(controller.selectedOptionId, 'catalog-safe');
        expect(catalogSnapshot.selection?.optionId, 'catalog-safe');
        expect(
          catalogSnapshot.source,
          AgentPermissionRequestSource.catalogDefault,
        );

        controller.seedFromConfig('provider-safe');
        final providerSnapshot = controller.snapshotForRequest();
        expect(providerSnapshot.selection?.optionId, 'provider-safe');
        expect(
          providerSnapshot.source,
          AgentPermissionRequestSource.providerDefault,
        );
      },
    );

    test(
      'request snapshot uses addressed thread effective before defaults',
      () async {
        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        controller.bind(
          port: null,
          persistedOptionId: 'provider-safe',
          runtimeIdentity: _runtimeIdentity,
        );
        await controller.applyThreadSettings(
          threadId: 'thread-a',
          permissionSelection: const AgentPermissionSelection(
            optionId: 'thread-safe',
          ),
        );

        final threadSnapshot = controller.snapshotForRequest(
          threadId: 'thread-a',
        );
        final otherSnapshot = controller.snapshotForRequest(
          threadId: 'thread-b',
        );

        expect(threadSnapshot.selection?.optionId, 'thread-safe');
        expect(
          threadSnapshot.source,
          AgentPermissionRequestSource.threadEffective,
        );
        expect(otherSnapshot.selection?.optionId, 'provider-safe');
        expect(
          otherSnapshot.source,
          AgentPermissionRequestSource.providerDefault,
        );
      },
    );

    test('displayLabel uses catalog label without parsing id shape', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(
        port: port,
        persistedOptionId: 'team-safe',
        runtimeIdentity: _runtimeIdentity,
      );
      await controller.refreshOptions();

      expect(controller.displayLabel, 'Team safe');
    });

    test('custom team-safe option id is preserved as opaque preference', () {
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.seedFromConfig('team-safe');
      expect(controller.selectedOptionId, 'team-safe');
      expect(controller.defaultOptionId, 'team-safe');
    });

    test('rapid runtime rebind drops an old generation apply result', () async {
      final delayedResult = Completer<AgentPermissionApplyResult>();
      final oldPort = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'old-runtime', label: 'Old runtime'),
        ],
        applyCompleter: delayedResult,
      );
      final newPort = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'new-runtime', label: 'New runtime'),
        ],
      );
      final persisted = <String>[];
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (optionId) async => persisted.add(optionId),
      );
      addTearDown(controller.dispose);
      controller.bind(
        port: oldPort,
        persistedOptionId: 'old-default',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: 'shared-provider',
          generation: 1,
        ),
      );
      controller.bindThread('thread-a');

      final pending = controller.selectOption(oldPort.options.single);
      expect(oldPort.applyCalls, 1);
      controller.bind(
        port: newPort,
        persistedOptionId: 'new-default',
        runtimeIdentity: const AgentProviderRuntimeIdentity(
          providerId: 'shared-provider',
          generation: 2,
        ),
      );
      delayedResult.complete(
        const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(
            optionId: 'old-runtime',
          ),
          scope: AgentPermissionApplyScope.currentSession,
        ),
      );
      await pending;

      expect(controller.runtimeIdentity?.generation, 2);
      expect(
        controller.selectedOptionId,
        'old-default',
        reason: 'an opened Binding keeps its logical provider default snapshot',
      );
      expect(controller.state.sessionEffective, isNull);
      expect(persisted, isEmpty);
    });

    test('dispose drops a delayed permission apply completion', () async {
      final delayedResult = Completer<AgentPermissionApplyResult>();
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'late', label: 'Late'),
        ],
        applyCompleter: delayedResult,
      );
      var persistCalls = 0;
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async => persistCalls += 1,
      );
      controller.bind(
        port: port,
        persistedOptionId: 'safe',
        runtimeIdentity: _runtimeIdentity,
      );

      final pending = controller.selectOption(port.options.single);
      expect(port.applyCalls, 1);
      controller.dispose();
      delayedResult.complete(
        const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'late'),
          scope: AgentPermissionApplyScope.runtime,
        ),
      );
      await pending;

      expect(persistCalls, 0);
    });

    test('dispose blocks further catalog writes', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
        ],
        listDelay: const Duration(milliseconds: 30),
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(
        port: port,
        persistedOptionId: null,
        runtimeIdentity: _runtimeIdentity,
      );
      final refresh = controller.refreshOptions();
      controller.dispose();
      await refresh;
      expect(controller.options, isEmpty);
    });
  });
}

class _FakePermissionPort implements AgentPermissionPolicyPort {
  _FakePermissionPort({
    required this.options,
    this.listDelay,
    this.applyError,
    this.applyScope = AgentPermissionApplyScope.runtime,
    this.normalizeSelection,
    this.applyCompleter,
  });

  final List<AgentPermissionOption> options;
  final Duration? listDelay;
  final Object? applyError;
  final AgentPermissionApplyScope applyScope;
  final AgentPermissionApplyResult Function(AgentPermissionSelection selection)?
  normalizeSelection;
  final Completer<AgentPermissionApplyResult>? applyCompleter;

  Object? listError;
  int listCalls = 0;
  int applyCalls = 0;
  AgentPermissionSelection? lastApplied;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    listCalls += 1;
    final delay = listDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    final error = listError;
    if (error != null) {
      throw error;
    }
    return AgentPermissionCatalog(
      options: options,
      defaultOptionId: options.isEmpty ? '' : options.first.id,
    );
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    applyCalls += 1;
    lastApplied = selection;
    final error = applyError;
    if (error != null) {
      throw error;
    }
    final completer = applyCompleter;
    if (completer != null) {
      return completer.future;
    }
    final normalize = normalizeSelection;
    if (normalize != null) {
      return normalize(selection);
    }
    return AgentPermissionApplyResult(
      normalizedSelection: selection,
      scope: applyScope,
    );
  }
}
