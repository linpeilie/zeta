import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_history_models.dart';

void main() {
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
  });
}
