import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  test('visibleOutputTokens subtracts reasoning without going negative', () {
    expect(AgentTokenUsage.visibleOutputTokens(301, 63), 238);
    expect(AgentTokenUsage.visibleOutputTokens(10, 20), 0);
    expect(AgentTokenUsage.visibleOutputTokens(null, null), isNull);
  });

  test('deltaFrom and addCumulative preserve reasoning independently', () {
    const baseline = AgentTokenUsage(
      inputTokens: 100,
      cachedInputTokens: 20,
      outputTokens: 30,
      reasoningOutputTokens: 10,
      totalTokens: 140,
    );
    const current = AgentTokenUsage(
      inputTokens: 180,
      cachedInputTokens: 50,
      outputTokens: 55,
      reasoningOutputTokens: 25,
      totalTokens: 260,
      lastReasoningOutputTokens: 15,
    );

    final delta = current.deltaFrom(baseline);
    final combined = baseline.addCumulative(delta);

    expect(delta.outputTokens, 25);
    expect(delta.reasoningOutputTokens, 15);
    expect(delta.lastReasoningOutputTokens, 15);
    expect(combined.reasoningOutputTokens, 25);
    expect(combined.outputTokens, 55);
  });

  test(
    'displayExclusiveTotalTokens subtracts cached input without negatives',
    () {
      const usage = AgentTokenUsage(cachedInputTokens: 200, totalTokens: 1300);
      expect(usage.displayExclusiveTotalTokens, '1.1k');

      const cachedHeavier = AgentTokenUsage(
        cachedInputTokens: 800,
        totalTokens: 500,
      );
      expect(cachedHeavier.displayExclusiveTotalTokens, '0');

      const noTotal = AgentTokenUsage(totalTokens: null);
      expect(noTotal.displayExclusiveTotalTokens, isNull);
    },
  );

  test('displayLastExclusiveTotalTokens uses the latest request snapshot', () {
    const usage = AgentTokenUsage(
      totalTokens: 100000,
      cachedInputTokens: 90000,
      lastTotalTokens: 1300,
      lastCachedInputTokens: 200,
    );

    expect(usage.displayLastExclusiveTotalTokens, '1.1k');
  });
}
