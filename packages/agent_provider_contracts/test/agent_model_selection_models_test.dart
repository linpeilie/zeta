import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('orderedReasoningEffortsForDisplay', () {
    test('orders known efforts from low to high for left-to-right UI', () {
      final ordered = orderedReasoningEffortsForDisplay(
        <AgentModelReasoningEffort>[
          const AgentModelReasoningEffort(effort: 'high'),
          const AgentModelReasoningEffort(effort: 'low'),
          const AgentModelReasoningEffort(effort: 'xhigh'),
          const AgentModelReasoningEffort(effort: 'medium'),
        ],
      );

      expect(ordered.map((item) => item.effort).toList(), <String>[
        'low',
        'medium',
        'high',
        'xhigh',
      ]);
    });

    test('keeps unknown efforts after known ones with stable order', () {
      final ordered = orderedReasoningEffortsForDisplay(
        <AgentModelReasoningEffort>[
          const AgentModelReasoningEffort(effort: 'custom-b'),
          const AgentModelReasoningEffort(effort: 'high'),
          const AgentModelReasoningEffort(effort: 'custom-a'),
          const AgentModelReasoningEffort(effort: 'low'),
        ],
      );

      expect(ordered.map((item) => item.effort).toList(), <String>[
        'low',
        'high',
        'custom-b',
        'custom-a',
      ]);
    });

    test('returns immutable snapshots for short lists', () {
      final single = <AgentModelReasoningEffort>[
        const AgentModelReasoningEffort(effort: 'high'),
      ];
      final ordered = orderedReasoningEffortsForDisplay(single);
      expect(ordered, orderedEquals(single));
      expect(identical(ordered, single), isFalse);
      expect(
        () => ordered.add(const AgentModelReasoningEffort(effort: 'low')),
        throwsUnsupportedError,
      );
      expect(orderedReasoningEffortsForDisplay(const []), isEmpty);
    });
  });
}
