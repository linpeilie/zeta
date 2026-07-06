import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationModelSelectionController', () {
    test('reconciles invalid config selection to provider defaults', () async {
      final persistedSelections = <AgentModelSelection>[];
      final controller = AgentConversationModelSelectionController(
        persistSelection: (selection) async {
          persistedSelections.add(selection);
        },
      );

      controller.seedFromConfig(
        AgentProviderConfig.defaultCodex.copyWith(
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
      expect(persistedSelections, hasLength(1));
      expect(persistedSelections.single.modelId, 'gpt-5.5');
      expect(persistedSelections.single.reasoningEffort, 'medium');
      expect(persistedSelections.single.serviceTierId, 'priority');
    });

    test('selectModel updates provider runtime state and persists', () async {
      final persistedSelections = <AgentModelSelection>[];
      final provider = _FakeAgentProvider();
      final controller = AgentConversationModelSelectionController(
        persistSelection: (selection) async {
          persistedSelections.add(selection);
        },
      );

      controller.bindProvider(provider);
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
  });
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
    ),
  ],
);

class _FakeAgentProvider implements AgentProvider {
  AgentModelSelection? runtimeSelection;

  @override
  AgentProviderConfig get config => AgentProviderConfig.defaultCodex;

  @override
  Stream<AgentEvent> get events => const Stream<AgentEvent>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return _modelList;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    runtimeSelection = selection;
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  }) async {
    return const AgentThreadHistorySnapshot(
      threadId: 'thread-1',
      turns: <AgentHistoryTurn>[],
    );
  }

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
    return const AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {
    return const AgentTurn(id: 'turn-1', sessionId: 'thread-1');
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {}
}
