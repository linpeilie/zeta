import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentConversationModeId', () {
    test('normalizes known mode ids', () {
      final defaultMode = AgentConversationModeId.fromRaw(' DEFAULT ');
      final planMode = AgentConversationModeId.fromRaw('Plan');

      expect(defaultMode, AgentConversationModeId.defaultMode);
      expect(defaultMode.rawValue, 'default');
      expect(defaultMode.kind, AgentConversationModeKind.defaultMode);
      expect(planMode, AgentConversationModeId.plan);
      expect(planMode.rawValue, 'plan');
      expect(planMode.kind, AgentConversationModeKind.plan);
    });

    test('preserves the normalized raw value of unknown modes', () {
      final mode = AgentConversationModeId.fromRaw('  Review  ');

      expect(mode.rawValue, 'review');
      expect(mode.kind, AgentConversationModeKind.unknown);
      expect(mode.toString(), 'review');
    });

    test('provides a tolerant parser for external values', () {
      expect(
        AgentConversationModeId.tryFromRaw(' PLAN '),
        AgentConversationModeId.plan,
      );
      expect(AgentConversationModeId.tryFromRaw(null), isNull);
      expect(AgentConversationModeId.tryFromRaw(1), isNull);
      expect(AgentConversationModeId.tryFromRaw('  '), isNull);
    });

    test('rejects empty ids in the strict parser', () {
      expect(() => AgentConversationModeId.fromRaw('  '), throwsArgumentError);
    });

    test('uses normalized ids for equality and hash codes', () {
      final first = AgentConversationModeId.fromRaw(' CUSTOM ');
      final second = AgentConversationModeId.fromRaw('custom');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('AgentConversationModeCatalog', () {
    test('exposes a defensive unmodifiable preset snapshot', () {
      const defaultPreset = AgentConversationModePreset(
        id: AgentConversationModeId.defaultMode,
        displayName: 'Default',
      );
      final source = <AgentConversationModePreset>[defaultPreset];

      final catalog = AgentConversationModeCatalog(presets: source);
      source.add(
        const AgentConversationModePreset(
          id: AgentConversationModeId.plan,
          displayName: 'Plan',
          suggestedReasoningEffort: 'medium',
        ),
      );

      expect(catalog.presets, <AgentConversationModePreset>[defaultPreset]);
      expect(() => catalog.presets.add(defaultPreset), throwsUnsupportedError);
    });
  });

  group('AgentConversationModeSelection', () {
    test('normalizes the effective model and optional effort', () {
      final selection = AgentConversationModeSelection(
        modeId: AgentConversationModeId.plan,
        effectiveModelId: '  gpt-test  ',
        effectiveReasoningEffort: '  medium  ',
      );

      expect(selection.effectiveModelId, 'gpt-test');
      expect(selection.effectiveReasoningEffort, 'medium');
    });

    test('normalizes a blank optional effort to null', () {
      final selection = AgentConversationModeSelection(
        modeId: AgentConversationModeId.defaultMode,
        effectiveModelId: 'gpt-test',
        effectiveReasoningEffort: '  ',
      );

      expect(selection.effectiveReasoningEffort, isNull);
    });

    test('rejects an empty effective model', () {
      expect(
        () => AgentConversationModeSelection(
          modeId: AgentConversationModeId.plan,
          effectiveModelId: '  ',
        ),
        throwsArgumentError,
      );
    });
  });

  test('AgentTurnConfiguration keeps the frozen mode selection', () {
    final selection = AgentConversationModeSelection(
      modeId: AgentConversationModeId.plan,
      effectiveModelId: 'gpt-test',
      effectiveReasoningEffort: 'medium',
    );

    final configuration = AgentTurnConfiguration(conversationMode: selection);

    expect(configuration.conversationMode, same(selection));
    expect(const AgentTurnConfiguration().conversationMode, isNull);
  });
}
