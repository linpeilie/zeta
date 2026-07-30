import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('orderedReasoningEffortsForDisplay', () {
    test('orders known efforts from low to high for left-to-right UI', () {
      final ordered =
          orderedReasoningEffortsForDisplay(const <AgentModelReasoningEffort>[
            AgentModelReasoningEffort(effort: 'high'),
            AgentModelReasoningEffort(effort: 'low'),
            AgentModelReasoningEffort(effort: 'xhigh'),
            AgentModelReasoningEffort(effort: 'medium'),
          ]);

      expect(ordered.map((item) => item.effort).toList(), <String>[
        'low',
        'medium',
        'high',
        'xhigh',
      ]);
    });

    test('keeps unknown efforts after known ones with stable order', () {
      final ordered =
          orderedReasoningEffortsForDisplay(const <AgentModelReasoningEffort>[
            AgentModelReasoningEffort(effort: 'custom-b'),
            AgentModelReasoningEffort(effort: 'high'),
            AgentModelReasoningEffort(effort: 'custom-a'),
            AgentModelReasoningEffort(effort: 'low'),
          ]);

      expect(ordered.map((item) => item.effort).toList(), <String>[
        'low',
        'high',
        'custom-b',
        'custom-a',
      ]);
    });

    test('returns short lists unchanged', () {
      const single = <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'high'),
      ];
      expect(
        identical(orderedReasoningEffortsForDisplay(single), single),
        isTrue,
      );
      expect(orderedReasoningEffortsForDisplay(const []), isEmpty);
    });
  });
}
