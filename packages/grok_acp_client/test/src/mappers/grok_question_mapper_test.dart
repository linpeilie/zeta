import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/mappers/grok_question_mapper.dart';
import 'package:test/test.dart';

void main() {
  const mapper = GrokQuestionMapper();

  group('GrokQuestionMapper', () {
    test('recognizes ask_user_question method prefixes', () {
      expect(
        GrokQuestionMapper.isAskUserQuestionMethod('_x.ai/ask_user_question'),
        isTrue,
      );
      expect(
        GrokQuestionMapper.isAskUserQuestionMethod('x.ai/ask_user_question'),
        isTrue,
      );
      expect(
        GrokQuestionMapper.isAskUserQuestionMethod(
          'session/request_permission',
        ),
        isFalse,
      );
    });

    test('maps questions without ids using question text as keys', () {
      final mapped = mapper.mapRequest(
        requestId: 42,
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'call-q-1',
          'questions': <Object?>[
            <String, Object?>{
              'question': 'Which path?',
              'options': <Object?>[
                <String, Object?>{
                  'label': 'ACP bridge',
                  'description': 'Reuse Grok ACP',
                },
                <String, Object?>{'label': 'Native stream-json'},
              ],
            },
            <String, Object?>{
              'question': 'Scope?',
              'multiSelect': true,
              'options': <Object?>[
                <String, Object?>{'label': 'MVP'},
                <String, Object?>{'label': 'Full'},
              ],
            },
          ],
        },
        runningTurnId: 'turn-1',
      );

      expect(mapped.pending.id, 'call-q-1');
      expect(mapped.pending.requestId, 42);
      expect(mapped.pending.sessionId, 'sess-1');
      expect(mapped.event.request.turnId, 'turn-1');
      expect(mapped.event.request.questions, hasLength(2));

      final first = mapped.event.request.questions.first;
      expect(first.questionId, 'Which path?');
      expect(first.optionItems.map((o) => o.id), <String>[
        'ACP bridge',
        'Native stream-json',
      ]);
      expect(first.allowMultiple, isFalse);
      expect(first.isOther, isTrue);

      final second = mapped.event.request.questions.last;
      expect(second.questionId, 'Scope?');
      expect(second.allowMultiple, isTrue);
    });

    test('encodes accepted answers with StringOrVec shape', () {
      final mapped = mapper.mapRequest(
        requestId: 1,
        params: <String, Object?>{
          'sessionId': 'sess-1',
          'toolCallId': 'call-1',
          'questions': <Object?>[
            <String, Object?>{
              'question': 'Which path?',
              'options': <Object?>[
                <String, Object?>{'label': 'ACP'},
              ],
            },
            <String, Object?>{
              'question': 'Scope?',
              'multiSelect': true,
              'options': <Object?>[
                <String, Object?>{'label': 'MVP'},
                <String, Object?>{'label': 'Full'},
              ],
            },
          ],
        },
      );

      final result = mapper.response(
        AgentQuestionResponse(
          requestId: mapped.pending.id,
          answers: <String, List<String>>{
            'Which path?': <String>['ACP'],
            'Scope?': <String>['MVP', 'Full'],
          },
        ),
        pending: mapped.pending,
      ) as Map<String, Object?>;

      expect(result['type'], 'accepted');
      final answers = result['answers']! as Map<String, Object?>;
      expect(answers['Which path?'], 'ACP');
      expect(answers['Scope?'], <String>['MVP', 'Full']);
      expect(result['partial_answers'], isA<Map<String, Object?>>());
    });

    test('encodes empty answers as skip_interview', () {
      const pending = GrokPendingQuestion(
        id: 'call-1',
        requestId: 9,
        questions: <AgentUserInputQaPair>[],
      );

      expect(
        mapper.response(
          AgentQuestionResponse(requestId: 'call-1'),
          pending: pending,
        ),
        <String, Object?>{'type': 'skip_interview'},
      );
    });
  });
}
