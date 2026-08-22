import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('ClaudeCodeQuestionAdapter', () {
    test('maps sampled AskUserQuestion shape to an independent question', () {
      final adapter = ClaudeCodeQuestionAdapter();

      final result = adapter.handleControlRequest(
        _questionFrame(
          requestId: 'req-question-1',
          questions: <Object?>[
            <String, Object?>{
              'question': 'Choose a repair direction',
              'header': 'Repair',
              'multiSelect': false,
              'options': <Object?>[
                <String, Object?>{
                  'label': 'Static fallback',
                  'description': 'Use a versioned model table',
                },
                <String, Object?>{
                  'label': 'Keep hidden',
                  'description': 'Explain why the value is unavailable',
                },
                <String, Object?>{
                  'label': 'No change',
                  'description': 'Only report the cause',
                },
              ],
            },
          ],
        ),
        sessionId: 'session-question-1',
        turnId: 'turn-question-1',
      );

      expect(result.handled, isTrue);
      expect(result.responseFrame, isNull);
      expect(adapter.pendingCount, 1);
      final event = result.events.single as AgentQuestionRequestedEvent;
      expect(event.request.id, 'req-question-1');
      expect(event.request.sessionId, 'session-question-1');
      expect(event.request.turnId, 'turn-question-1');
      final question = event.request.questions.single;
      expect(question.questionId, 'Choose a repair direction');
      expect(question.header, 'Repair');
      expect(question.allowMultiple, isFalse);
      expect(question.isOther, isTrue);
      expect(question.optionItems.map((option) => option.label), <String>[
        'Static fallback',
        'Keep hidden',
        'No change',
      ]);
      expect(
        question.optionItems.first.description,
        'Use a versioned model table',
      );
      expect(
        event.request.raw.toPrettyJson(),
        allOf(<Matcher>[
          contains('"tool_use_id": "toolu-req-question-1"'),
          contains('"source": "claude_code.can_use_tool"'),
        ]),
      );
    });

    test('encodes single and multi answers into updatedInput', () {
      final adapter = ClaudeCodeQuestionAdapter();
      adapter.handleControlRequest(
        _questionFrame(
          requestId: 'req-answers',
          questions: <Object?>[
            <String, Object?>{
              'question': 'Choose one',
              'header': 'Single',
              'multiSelect': false,
              'options': <Object?>[
                <String, Object?>{'label': 'Alpha'},
                <String, Object?>{'label': 'Beta'},
              ],
            },
            <String, Object?>{
              'question': 'Choose several',
              'header': 'Multiple',
              'multiSelect': true,
              'options': <Object?>[
                <String, Object?>{'label': 'Tests'},
                <String, Object?>{'label': 'Docs'},
              ],
            },
          ],
        ),
        sessionId: 'session-answers',
        turnId: 'turn-answers',
      );

      final resolved = adapter.resolveResponse(
        const AgentQuestionResponse(
          requestId: 'req-answers',
          answers: <String, List<String>>{
            'Choose one': <String>['Beta'],
            'Choose several': <String>['Tests', 'Docs'],
          },
        ),
      );

      expect(resolved, isNotNull);
      expect(adapter.pendingCount, 0);
      final envelope =
          resolved!.responseFrame['response'] as Map<String, Object?>;
      expect(envelope['request_id'], 'req-answers');
      final body = envelope['response'] as Map<String, Object?>;
      expect(body['behavior'], 'allow');
      final updatedInput = body['updatedInput'] as Map<String, Object?>;
      expect(updatedInput['questions'], isA<List>());
      expect(updatedInput['answers'], <String, String>{
        'Choose one': 'Beta',
        'Choose several': 'Tests, Docs',
      });
    });

    test('empty answers explicitly encode Skip', () {
      final adapter = ClaudeCodeQuestionAdapter();
      adapter.handleControlRequest(
        _questionFrame(
          requestId: 'req-skip',
          questions: <Object?>[
            <String, Object?>{
              'question': 'Optional question',
              'header': 'Optional',
              'multiSelect': false,
              'options': <Object?>[
                <String, Object?>{'label': 'Continue'},
              ],
            },
          ],
        ),
      );

      final resolved = adapter.resolveResponse(
        const AgentQuestionResponse(requestId: 'req-skip'),
      );

      final envelope =
          resolved!.responseFrame['response'] as Map<String, Object?>;
      final body = envelope['response'] as Map<String, Object?>;
      final updatedInput = body['updatedInput'] as Map<String, Object?>;
      expect(updatedInput['answers'], isEmpty);
    });

    test('turn completion only clears questions owned by that turn', () {
      final adapter = ClaudeCodeQuestionAdapter();
      adapter.handleControlRequest(
        _questionFrame(
          requestId: 'req-completed',
          questions: <Object?>[
            <String, Object?>{
              'question': 'First question',
              'header': 'First',
              'multiSelect': false,
              'options': <Object?>[
                <String, Object?>{'label': 'Continue'},
              ],
            },
          ],
        ),
        sessionId: 'session-completed',
        turnId: 'turn-completed',
      );
      adapter.handleControlRequest(
        _questionFrame(
          requestId: 'req-active',
          questions: <Object?>[
            <String, Object?>{
              'question': 'Second question',
              'header': 'Second',
              'multiSelect': false,
              'options': <Object?>[
                <String, Object?>{'label': 'Continue'},
              ],
            },
          ],
        ),
        sessionId: 'session-active',
        turnId: 'turn-active',
      );

      final completed = adapter.completeTurn(
        sessionId: 'session-completed',
        turnId: 'turn-completed',
      );

      expect(completed.map((item) => item.requestId), <String>[
        'req-completed',
      ]);
      expect(adapter.pendingCount, 1);
      expect(
        adapter.resolveResponse(
          const AgentQuestionResponse(requestId: 'req-completed'),
        ),
        isNull,
      );
      expect(
        adapter.resolveResponse(
          const AgentQuestionResponse(requestId: 'req-active'),
        ),
        isNotNull,
      );
    });

    test(
      'does not consume permissions and fail-closes malformed questions',
      () {
        final adapter = ClaudeCodeQuestionAdapter();

        final permission = adapter.handleControlRequest(<String, Object?>{
          'type': 'control_request',
          'request_id': 'req-bash',
          'request': <String, Object?>{
            'subtype': 'can_use_tool',
            'tool_use_id': 'toolu-bash',
            'tool_name': 'Bash',
            'input': <String, Object?>{'command': 'echo sentinel'},
          },
        });
        final malformed = adapter.handleControlRequest(
          _questionFrame(requestId: 'req-malformed', questions: const []),
        );

        expect(permission.handled, isFalse);
        expect(malformed.handled, isTrue);
        expect(malformed.events, isEmpty);
        final envelope =
            malformed.responseFrame!['response'] as Map<String, Object?>;
        expect(envelope['subtype'], 'error');
        expect(envelope['request_id'], 'req-malformed');
        expect(adapter.pendingCount, 0);
      },
    );
  });
}

Map<String, Object?> _questionFrame({
  required String requestId,
  required List<Object?> questions,
}) {
  return <String, Object?>{
    'type': 'control_request',
    'request_id': requestId,
    'request': <String, Object?>{
      'subtype': 'can_use_tool',
      'tool_use_id': 'toolu-$requestId',
      'tool_name': claudeCodeAskUserQuestionToolName,
      'input': <String, Object?>{'questions': questions},
    },
  };
}
