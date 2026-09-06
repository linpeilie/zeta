import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';

import '../../../testing/agent_provider_stub_base.dart';

void main() {
  test(
    'each save reports its own result when an older failure is followed by success',
    () async {
      final firstSave = Completer<void>();
      var count = 0;
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {
          if (++count == 1) await firstSave.future;
        },
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);
      final first = controller.selectReasoningEffort('low');
      final second = controller.selectReasoningEffort('medium');
      firstSave.completeError(StateError('older save failed'));
      expect(
        await first,
        isA<AgentCommandFailed>().having(
          (v) => v.kind,
          'kind',
          AgentCommandFailureKind.requestFailed,
        ),
      );
      expect(await second, isA<AgentCommandSucceeded>());
      expect(controller.selectedReasoningEffort, 'medium');
      expect(controller.saveError, isNull);
      expect(count, 2);
    },
  );

  test(
    'generation reset supersedes its waiter; disposal settles new waiter without waiting for IO',
    () async {
      final gate = Completer<void>();
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) => gate.future,
      );
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);
      final old = controller.selectModel('gpt-5.4-mini');
      controller.resetForProvider(_configuredProvider());
      expect(
        await old,
        isA<AgentCommandIgnored>().having(
          (v) => v.reason,
          'reason',
          AgentCommandIgnoreReason.superseded,
        ),
      );
      controller.handleModelList(_modelList);
      final next = controller.selectModel('gpt-5.4-mini');
      controller.dispose();
      expect(
        await next,
        isA<AgentCommandFailed>().having(
          (v) => v.kind,
          'kind',
          AgentCommandFailureKind.staleTarget,
        ),
      );
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'retry after disposal rejects without creating another save waiter',
    () async {
      var saves = 0;
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {
          saves++;
          throw StateError('save failed');
        },
      );
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);
      expect(
        await controller.selectReasoningEffort('low'),
        isA<AgentCommandFailed>(),
      );
      controller.dispose();
      expect(
        await controller.retryFailedSelection(),
        isA<AgentCommandFailed>().having(
          (value) => value.kind,
          'kind',
          AgentCommandFailureKind.staleTarget,
        ),
      );
      expect(saves, 1);
    },
  );

  group('AgentConversationModelSelectionController', () {
    test('reconciles invalid config selection to provider defaults', () async {
      final persistedSelections = <AgentModelSelection>[];
      final controller = AgentConversationModelSelectionController(
        persistSelection: (selection, _) async {
          persistedSelections.add(selection);
        },
      );
      addTearDown(controller.dispose);

      controller.seedFromConfig(
        defaultCodexAgentProviderConfig.copyWith(
          selectedModel: 'missing-model',
          selectedReasoningEffort: 'xhigh',
          selectedServiceTier: 'priority',
        ),
      );
      controller.handleModelList(_modelList);
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedModelId, 'gpt-5.5');
      expect(controller.selectedReasoningEffort, 'medium');
      expect(controller.selectedServiceTierId, 'priority');
      expect(controller.selectionNotice, contains('missing-model'));
      expect(persistedSelections, hasLength(1));
      expect(persistedSelections.single.modelId, 'gpt-5.5');
      expect(persistedSelections.single.reasoningEffort, 'medium');
      expect(persistedSelections.single.serviceTierId, 'priority');

      controller.clearTransientState();
      expect(controller.selectionNotice, isNull);
    });

    test('selectModel updates provider runtime state and persists', () async {
      final persistedSelections = <AgentModelSelection>[];
      final provider = _FakeAgentProvider();
      final controller = AgentConversationModelSelectionController(
        persistSelection: (selection, _) async {
          persistedSelections.add(selection);
        },
      );
      addTearDown(controller.dispose);

      controller.bindRuntime(provider);
      controller.handleModelList(_modelList);
      await Future<void>.delayed(Duration.zero);
      persistedSelections.clear();

      await controller.selectModel('gpt-5.4-mini');

      expect(controller.selectedModelId, 'gpt-5.4-mini');
      expect(controller.selectedReasoningEffort, 'low');
      expect(controller.selectedServiceTierId, isNull);
      expect(provider.runtimeSelection?.modelId, 'gpt-5.4-mini');
      expect(provider.runtimeSelection?.reasoningEffort, 'low');
      expect(persistedSelections, hasLength(1));
      expect(persistedSelections.single.modelId, 'gpt-5.4-mini');
    });

    test(
      'does not migrate provider-level selection into a preference',
      () async {
        var saveCount = 0;
        final controller = AgentConversationModelSelectionController(
          persistSelection: (_, _) async {
            saveCount += 1;
          },
          clock: () => _now,
        );
        addTearDown(controller.dispose);

        controller.seedFromConfig(
          defaultCodexAgentProviderConfig.copyWith(
            selectedModel: 'gpt-5.5',
            selectedReasoningEffort: 'medium',
            selectedServiceTier: 'priority',
          ),
        );
        controller.handleModelList(_modelList);
        await Future<void>.delayed(Duration.zero);

        expect(saveCount, 0);
        expect(controller.preferences['gpt-5.5']?.serviceTierId, 'priority');
      },
    );

    test('restores each model last valid preference when switching', () async {
      final persistedPreferences = <Map<String, AgentModelPreference>>[];
      final controller = AgentConversationModelSelectionController(
        persistSelection: (selection, preferences) async {
          persistedPreferences.add(preferences);
        },
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);

      await controller.selectModel('gpt-5.4-mini');
      await controller.selectFastEnabled(true);
      await controller.selectModel('gpt-5.5');
      await controller.selectModel('gpt-5.4-mini');

      expect(controller.selectedReasoningEffort, 'low');
      expect(controller.selectedServiceTierId, 'priority');
      expect(controller.selectedFastEnabled, isTrue);
      expect(persistedPreferences.last['gpt-5.4-mini']?.fastEnabled, isTrue);
    });

    test('requires explicit atomic resolution for xhigh and Fast', () async {
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {},
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);
      await controller.selectModel('gpt-reasoner');
      await controller.selectReasoningEffort('xhigh');

      final fastAccepted = await controller.selectFastEnabled(true);

      expect(
        fastAccepted,
        isA<AgentCommandIgnored>().having(
          (value) => value.reason,
          'reason',
          AgentCommandIgnoreReason.requiresConfirmation,
        ),
      );
      expect(controller.selectedReasoningEffort, 'xhigh');
      expect(controller.selectedFastEnabled, isFalse);
      expect(
        controller.compatibilityConflict?.actionLabel,
        '切换到 high 并开启 Fast',
      );

      expect(
        await controller.resolveCompatibilityConflict(),
        isA<AgentCommandSucceeded>(),
      );
      expect(controller.selectedReasoningEffort, 'high');
      expect(controller.selectedFastEnabled, isTrue);

      final xhighAccepted = await controller.selectReasoningEffort('xhigh');
      expect(
        xhighAccepted,
        isA<AgentCommandIgnored>().having(
          (value) => value.reason,
          'reason',
          AgentCommandIgnoreReason.requiresConfirmation,
        ),
      );
      expect(controller.selectedReasoningEffort, 'high');
      expect(
        controller.compatibilityConflict?.actionLabel,
        '关闭 Fast 并切换到 xhigh',
      );

      expect(
        await controller.resolveCompatibilityConflict(),
        isA<AgentCommandSucceeded>(),
      );
      expect(controller.selectedReasoningEffort, 'xhigh');
      expect(controller.selectedFastEnabled, isFalse);
    });

    test('rolls back a failed save and retries the full snapshot', () async {
      var shouldFail = true;
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {
          if (shouldFail) {
            throw const FileSystemException('disk full');
          }
        },
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);

      expect(
        await controller.selectModel('gpt-5.4-mini'),
        isA<AgentCommandFailed>().having(
          (value) => value.kind,
          'kind',
          AgentCommandFailureKind.requestFailed,
        ),
      );
      expect(controller.selectedModelId, 'gpt-5.5');
      expect(controller.saveError, isNotNull);

      shouldFail = false;
      expect(
        await controller.retryFailedSelection(),
        isA<AgentCommandSucceeded>(),
      );
      expect(controller.selectedModelId, 'gpt-5.4-mini');
      expect(controller.saveError, isNull);
    });

    test(
      'coalesces rapid changes and persists the latest snapshot last',
      () async {
        final firstSave = Completer<void>();
        final persisted = <AgentModelSelection>[];
        final controller = AgentConversationModelSelectionController(
          persistSelection: (selection, _) async {
            persisted.add(selection);
            if (persisted.length == 1) {
              await firstSave.future;
            }
          },
          clock: () => _now,
        );
        addTearDown(controller.dispose);
        controller.seedFromConfig(_configuredProvider());
        controller.handleModelList(_modelList);

        final low = controller.selectReasoningEffort('low');
        final medium = controller.selectReasoningEffort('medium');
        final fast = controller.selectFastEnabled(true);
        firstSave.complete();

        expect(await low, isA<AgentCommandSucceeded>());
        expect(
          await medium,
          isA<AgentCommandIgnored>().having(
            (value) => value.reason,
            'reason',
            AgentCommandIgnoreReason.superseded,
          ),
        );
        expect(await fast, isA<AgentCommandSucceeded>());
        expect(persisted, hasLength(2));
        expect(persisted.last.reasoningEffort, 'medium');
        expect(persisted.last.serviceTierId, 'priority');
      },
    );

    test('selecting the current model does not persist again', () async {
      var saveCount = 0;
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {
          saveCount += 1;
        },
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);

      expect(
        await controller.selectModel('gpt-5.5'),
        isA<AgentCommandIgnored>().having(
          (value) => value.reason,
          'reason',
          AgentCommandIgnoreReason.unchanged,
        ),
      );
      expect(saveCount, 0);
    });

    test('rejects a disabled model without changing or persisting', () async {
      var saveCount = 0;
      final controller = AgentConversationModelSelectionController(
        persistSelection: (_, _) async {
          saveCount += 1;
        },
        clock: () => _now,
      );
      addTearDown(controller.dispose);
      controller.seedFromConfig(_configuredProvider());
      controller.handleModelList(_modelList);

      expect(
        await controller.selectModel('gpt-legacy'),
        isA<AgentCommandIgnored>().having(
          (value) => value.reason,
          'reason',
          AgentCommandIgnoreReason.notAllowed,
        ),
      );
      expect(controller.selectedModelId, 'gpt-5.5');
      expect(saveCount, 0);
    });
  });
}

final DateTime _now = DateTime.utc(2026, 7, 15, 8);

AgentProviderConfig _configuredProvider() {
  return defaultCodexAgentProviderConfig.copyWith(
    selectedModel: 'gpt-5.5',
    selectedReasoningEffort: 'medium',
    modelPreferences: <String, AgentModelPreference>{
      'gpt-5.5': AgentModelPreference(
        modelId: 'gpt-5.5',
        reasoningEffort: 'medium',
        fastEnabled: false,
        serviceTierId: null,
        updatedAt: _now,
      ),
    },
  );
}

const AgentModelList _modelList = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'gpt-5.5',
      model: 'gpt-5.5',
      displayName: 'GPT-5.5',
      isDefault: true,
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'medium'),
      ],
      defaultReasoningEffort: 'medium',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
      defaultServiceTier: 'priority',
    ),
    AgentModelInfo(
      id: 'gpt-5.4-mini',
      model: 'gpt-5.4-mini',
      displayName: 'GPT-5.4-Mini',
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
      ],
      defaultReasoningEffort: 'low',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-reasoner',
      model: 'gpt-reasoner',
      displayName: 'GPT-Reasoner',
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'medium'),
        AgentModelReasoningEffort(effort: 'high'),
        AgentModelReasoningEffort(effort: 'xhigh'),
      ],
      defaultReasoningEffort: 'medium',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-legacy',
      model: 'gpt-legacy',
      displayName: 'GPT-Legacy',
      enabled: false,
      unavailableReason: '当前账号没有访问权限',
    ),
  ],
);

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentRuntimePort, AgentConversationPort {
  AgentModelSelection? runtimeSelection;

  @override
  AgentProviderConfig get config => defaultCodexAgentProviderConfig;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {}

  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    return _modelList;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    runtimeSelection = selection;
  }

  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    return const AgentThreadHistorySnapshot(
      threadId: 'thread-1',
      turns: <AgentHistoryTurn>[],
    );
  }

  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return const AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    return const AgentTurn(id: 'turn-1', sessionId: 'thread-1');
  }

  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {}
}
