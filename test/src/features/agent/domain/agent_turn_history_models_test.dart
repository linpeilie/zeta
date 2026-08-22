import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentHistoryMessageEntry identity contract', () {
    test('keeps existing constructors compatible through defaults', () {
      const entry = AgentHistoryMessageEntry(
        id: 'entry-1',
        role: AgentMessageRole.agent,
        text: 'hello',
      );

      expect(entry.kind, AgentMessageKind.regular);
      expect(entry.sourceMessageId, isNull);
    });

    test('constructs explicit plan and source identity metadata', () {
      const entry = AgentHistoryMessageEntry(
        id: 'entry-1',
        sourceMessageId: 'provider-message-1',
        kind: AgentMessageKind.plan,
        role: AgentMessageRole.agent,
        text: '# Plan',
      );

      expect(entry.id, 'entry-1');
      expect(entry.sourceMessageId, 'provider-message-1');
      expect(entry.kind, AgentMessageKind.plan);
    });
  });

  group('AgentTokenUsage display getters', () {
    test('returns null for missing values and keeps sub-1k values raw', () {
      const usage = AgentTokenUsage(inputTokens: 999);
      const empty = AgentTokenUsage();

      expect(usage.displayInputTokens, '999');
      expect(usage.displayCachedInputTokens, isNull);
      expect(empty.displayTotalTokens, isNull);
      expect(empty.displayModelContextWindow, isNull);
    });

    test('formats each token field with compact units', () {
      const usage = AgentTokenUsage(
        inputTokens: 1200,
        cachedInputTokens: 2000000,
        outputTokens: 3000000000,
        totalTokens: 4000000000000,
        lastInputTokens: 5000000000000000,
        lastCachedInputTokens: 6000000000000000000,
        lastOutputTokens: 7000000000000000,
        lastTotalTokens: 8000000000000000000,
        modelContextWindow: 1500,
      );

      expect(usage.displayInputTokens, '1.2k');
      expect(usage.displayCachedInputTokens, '2m');
      expect(usage.displayOutputTokens, '3g');
      expect(usage.displayTotalTokens, '4t');
      expect(usage.displayLastInputTokens, '5p');
      expect(usage.displayLastCachedInputTokens, '6e');
      expect(usage.displayLastOutputTokens, '7p');
      expect(usage.displayLastTotalTokens, '8e');
      expect(usage.displayModelContextWindow, '1.5k');
    });

    test('promotes rounded boundary values to the next suffix', () {
      const usage = AgentTokenUsage(
        totalTokens: 999950,
        lastTotalTokens: 999950000,
      );

      expect(usage.displayTotalTokens, '1m');
      expect(usage.displayLastTotalTokens, '1g');
    });

    test('deltaFrom subtracts previous cumulative and keeps last* fields', () {
      const previous = AgentTokenUsage(
        inputTokens: 2000,
        cachedInputTokens: 500,
        outputTokens: 330,
        totalTokens: 2250,
      );
      const current = AgentTokenUsage(
        inputTokens: 3000,
        cachedInputTokens: 700,
        outputTokens: 680,
        totalTokens: 3550,
        lastInputTokens: 920,
        lastCachedInputTokens: 180,
        lastOutputTokens: 320,
        lastTotalTokens: 1240,
        modelContextWindow: 2000,
      );

      final delta = current.deltaFrom(previous);
      expect(delta.inputTokens, 1000);
      expect(delta.cachedInputTokens, 200);
      expect(delta.outputTokens, 350);
      expect(delta.totalTokens, 1300);
      expect(delta.lastInputTokens, 920);
      expect(delta.lastCachedInputTokens, 180);
      expect(delta.lastOutputTokens, 320);
      expect(delta.lastTotalTokens, 1240);
      expect(delta.modelContextWindow, 2000);

      final firstTurn = current.deltaFrom(null);
      expect(firstTurn.totalTokens, 3550);
      expect(firstTurn.inputTokens, 3000);
    });

    test('addCumulative sums breakdown fields', () {
      const left = AgentTokenUsage(
        inputTokens: 2000,
        cachedInputTokens: 500,
        outputTokens: 330,
        totalTokens: 2250,
      );
      const right = AgentTokenUsage(
        inputTokens: 1000,
        cachedInputTokens: 200,
        outputTokens: 350,
        totalTokens: 1300,
        modelContextWindow: 2000,
      );

      final sum = left.addCumulative(right);
      expect(sum.inputTokens, 3000);
      expect(sum.cachedInputTokens, 700);
      expect(sum.outputTokens, 680);
      expect(sum.totalTokens, 3550);
      expect(sum.modelContextWindow, 2000);
    });
  });

  group('AgentTurnModelConfig', () {
    test('uses only Provider-normalized model config', () {
      const turn = AgentHistoryTurn(
        id: 'turn-1',
        modelId: 'gpt-5.5',
        reasoningEffort: AgentHistoryReasoningEffort.explicit('high'),
        serviceTierId: 'priority',
        explicitFast: true,
        raw: <String, Object?>{
          'turnContext': <String, Object?>{
            'model': 'ignored-model',
            'serviceTier': 'ignored-tier',
            'fast': false,
          },
        },
      );

      final config = AgentTurnModelConfig.fromHistoryTurn(turn);
      expect(config, isNotNull);
      expect(config!.modelId, 'gpt-5.5');
      expect(config.reasoningEffort, 'high');
      expect(config.fastEnabled, isTrue);
    });

    test('ignores every raw model config alias', () {
      const turn = AgentHistoryTurn(
        id: 'turn-typed-effort',
        modelId: 'claude-opus-5',
        reasoningEffort: AgentHistoryReasoningEffort.explicit('xhigh'),
        explicitFast: false,
        raw: <String, Object?>{
          'turnContext': <String, Object?>{
            'model': 'raw-model',
            'effort': 'low',
            'serviceTier': 'priority',
            'fast': true,
          },
        },
      );

      final config = AgentTurnModelConfig.fromHistoryTurn(turn);

      expect(config?.reasoningEffort, 'xhigh');
      expect(config?.modelId, 'claude-opus-5');
      expect(config?.fastEnabled, isFalse);
    });

    test('keeps unknown and explicit provider default distinct', () {
      const unknown = AgentHistoryTurn(id: 'turn-unknown', modelId: 'gpt-5.5');
      const providerDefault = AgentHistoryTurn(
        id: 'turn-default',
        modelId: 'gpt-5.5',
        reasoningEffort: AgentHistoryReasoningEffort.providerDefault(),
      );

      expect(unknown.reasoningEffort.isKnown, isFalse);
      expect(providerDefault.reasoningEffort.isKnown, isTrue);
      expect(providerDefault.reasoningEffort.value, isNull);
      expect(
        AgentTurnModelConfig.fromHistoryTurn(providerDefault)?.reasoningEffort,
        isNull,
      );
    });

    test('returns null when only raw model config exists', () {
      const turn = AgentHistoryTurn(
        id: 'turn-empty',
        raw: <String, Object?>{
          'modelId': 'raw-model',
          'reasoning_effort': 'high',
          'service_tier_id': 'priority',
          'fast_enabled': true,
        },
      );
      expect(AgentTurnModelConfig.fromHistoryTurn(turn), isNull);
    });

    test('shows raw reasoning effort values for footer', () {
      expect(agentReasoningEffortFooterLabel('high'), 'high');
      expect(agentReasoningEffortFooterLabel('xhigh'), 'xhigh');
      expect(agentReasoningEffortFooterLabel(null), isNull);
      expect(agentReasoningEffortFooterLabel('  custom  '), 'custom');
      expect(agentReasoningEffortFooterLabel('   '), isNull);
    });
  });

  group('Agent history collaboration mode', () {
    test('returns the latest typed mode while skipping missing turns', () {
      final unknownMode = AgentConversationModeId.fromRaw('future-mode');
      final snapshot = AgentThreadHistorySnapshot(
        threadId: 'thread-1',
        turns: <AgentHistoryTurn>[
          const AgentHistoryTurn(
            id: 'turn-plan',
            collaborationMode: AgentConversationModeId.plan,
          ),
          const AgentHistoryTurn(id: 'turn-missing'),
          AgentHistoryTurn(id: 'turn-future', collaborationMode: unknownMode),
          const AgentHistoryTurn(id: 'turn-latest-missing'),
        ],
        currentTurn: const AgentHistoryTurn(id: 'turn-latest-missing'),
      );

      expect(snapshot.latestCollaborationMode, unknownMode);
      expect(
        snapshot.latestCollaborationMode?.kind,
        AgentConversationModeKind.unknown,
      );
    });
  });
}
