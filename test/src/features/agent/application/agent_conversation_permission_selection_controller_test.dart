import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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
      controller.bind(port: port, persistedOptionId: 'ask');
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

      controller.bind(port: slow, persistedOptionId: null);
      final slowRefresh = controller.refreshOptions();
      controller.bind(port: fast, persistedOptionId: null);
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
      controller.bind(port: port, persistedOptionId: 'ask');
      await controller.refreshOptions();

      await controller.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(controller.selectedOptionId, 'ask');
      expect(controller.takeLastError(), isNotNull);
    });

    test(
      'thread settings update effective only without changing default',
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
        controller.bind(port: port, persistedOptionId: ':workspace');
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
        expect(controller.selectedOptionId, 'team-safe');
      },
    );

    test(
      'thread settings for other thread only cache without touching current UI',
      () async {
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
        controller.bind(port: port, persistedOptionId: ':workspace');
        controller.bindThread('thread-b');
        await controller.refreshOptions();

        await controller.applyThreadSettings(
          threadId: 'thread-a',
          permissionSelection: const AgentPermissionSelection(
            optionId: ':read-only',
          ),
        );

        expect(controller.selectedOptionId, ':workspace');
        controller.bindThread('thread-a');
        expect(controller.selectedOptionId, ':read-only');
      },
    );

    test('runtime scope syncs all thread effectives and default', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
        ],
        applyScope: AgentPermissionApplyScope.runtime,
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(port: port, persistedOptionId: 'ask');
      controller.bindThread('t1');
      await controller.applyEffectiveSelection(
        const AgentPermissionSelection(optionId: 'ask'),
        syncPort: false,
      );
      controller.bindThread('t2');
      await controller.applyEffectiveSelection(
        const AgentPermissionSelection(optionId: 'ask'),
        syncPort: false,
      );
      controller.bindThread('t1');
      await controller.refreshOptions();

      await controller.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(controller.defaultOptionId, 'auto');
      expect(controller.selectedOptionId, 'auto');
      controller.bindThread('t2');
      expect(controller.selectedOptionId, 'auto');
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
      controller.bind(port: port, persistedOptionId: 'ask');
      await controller.refreshOptions();
      await controller.selectOption(
        const AgentPermissionOption(id: 'auto', label: 'Auto'),
      );

      expect(controller.lastApplyScope, AgentPermissionApplyScope.nextSession);
      expect(controller.applyScopeHint, '下次会话生效');
    });

    test('displayLabel uses catalog label without parsing id shape', () async {
      final port = _FakePermissionPort(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
        ],
      );
      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      controller.bind(port: port, persistedOptionId: 'team-safe');
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
      controller.bind(port: port, persistedOptionId: null);
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
  });

  final List<AgentPermissionOption> options;
  final Duration? listDelay;
  final Object? applyError;
  final AgentPermissionApplyScope applyScope;

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
    return AgentPermissionApplyResult(
      normalizedSelection: selection,
      scope: applyScope,
    );
  }
}
