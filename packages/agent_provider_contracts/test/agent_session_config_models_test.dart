import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AgentSessionConfigOption', () {
    test('decodes select options while preserving stable values', () {
      final option = AgentSessionConfigOption.tryDecode(<String, Object?>{
        'id': 'mode',
        'name': 'Mode',
        'description': 'Agent operating mode',
        'category': 'mode',
        'type': 'select',
        'currentValue': 'agent',
        'options': <Object?>[
          <String, Object?>{
            'value': 'agent',
            'name': 'Agent',
            'description': 'Use tools autonomously',
          },
          <String, Object?>{'value': 'ask', 'name': 'Ask'},
        ],
      });

      expect(option, isNotNull);
      expect(option!.kind, AgentSessionConfigOptionKind.select);
      expect(option.category, 'mode');
      expect(option.currentValue, 'agent');
      expect(option.values.map((value) => value.id), <Object>['agent', 'ask']);
      expect(option.values.first.label, 'Agent');
    });

    test('rejects damaged options without blocking other config', () {
      expect(AgentSessionConfigOption.tryDecode(null), isNull);
      expect(
        AgentSessionConfigOption.tryDecode(<String, Object?>{'id': 'mode'}),
        isNull,
      );
    });
  });

  test('structured question options keep ids and multi-select semantics', () {
    final question = AgentUserInputQaPair(
      questionId: 'scope',
      question: 'Select scopes',
      allowMultiple: true,
      optionItems: <AgentUserInputOption>[
        const AgentUserInputOption(id: 'source', label: 'Source code'),
        const AgentUserInputOption(id: 'tests', label: 'Tests'),
      ],
    );

    expect(question.allowMultiple, isTrue);
    expect(question.resolvedOptions.first.id, 'source');
    expect(question.resolvedOptions.first.label, 'Source code');
  });

  test('legacy question labels remain valid stable option ids', () {
    final question = AgentUserInputQaPair(
      questionId: 'legacy',
      question: 'Choose one',
      options: <String>['A', 'B'],
    );

    expect(question.resolvedOptions.map((option) => option.id), <String>[
      'A',
      'B',
    ]);
  });
}
