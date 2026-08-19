// Protocol fixtures remain readable as single-line wire examples.
// ignore_for_file: lines_longer_than_80_chars

import 'package:grok_acp_client/src/acp/acp_session_update_decoder.dart';
import 'package:test/test.dart';

void main() {
  group('AcpSessionUpdateDecoder', () {
    const decoder = AcpSessionUpdateDecoder();

    test('decodes user message chunks from a full notification envelope', () {
      final decoded = decoder.decode(<String, Object?>{
        'method': 'session/update',
        'params': <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': 'user_message_chunk',
            'messageId': 'source-user-1',
            'content': <String, Object?>{'type': 'text', 'text': 'hello'},
            '_meta': <String, Object?>{
              'promptId': 'prompt-1',
              'hideFromScrollback': true,
            },
            'futureField': true,
          },
          '_meta': <String, Object?>{'eventId': 'event-1'},
        },
      });

      expect(decoded, isA<AcpUserMessageChunk>());
      final chunk = decoded as AcpUserMessageChunk;
      expect(chunk.sessionId, 'session-1');
      expect(chunk.sourceMessageId, 'source-user-1');
      expect(chunk.promptId, 'prompt-1');
      expect(chunk.eventId, 'event-1');
      expect(chunk.hideFromScrollback, isTrue);
      expect(chunk.raw['futureField'], isTrue);
    });

    test('keeps ordinary user message chunks visible by default', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'user_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'hello'},
        },
      }) as AcpUserMessageChunk;

      expect(decoded.hideFromScrollback, isFalse);
    });

    test('decodes agent chunks without synthesizing an identity', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'delta'},
          '_meta': <String, Object?>{
            'promptId': 'prompt-1',
            'eventId': 'event-1',
          },
        },
      });

      expect(decoded, isA<AcpAgentMessageChunk>());
      final chunk = decoded as AcpAgentMessageChunk;
      expect(chunk.sourceMessageId, isNull);
      expect(chunk.promptId, 'prompt-1');
      expect(chunk.eventId, 'event-1');
      expect(chunk.raw, isNot(contains('entryId')));
      expect(chunk.raw, isNot(contains('messageId')));
    });

    test('decodes thought chunks with an optional source item id', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'agent_thought_chunk',
          'itemId': 'source-reasoning-1',
          'content': <String, Object?>{'type': 'text', 'text': 'thought'},
        },
      });

      expect(decoded, isA<AcpAgentThoughtChunk>());
      final chunk = decoded as AcpAgentThoughtChunk;
      expect(chunk.sourceItemId, 'source-reasoning-1');
      expect(chunk.content, isA<Map<String, Object?>>());
    });

    test('decodes tool starts and updates into the same typed shape', () {
      AcpToolCallUpdate decodeTool(String kind) {
        return decoder.decode(<String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{
            'sessionUpdate': kind,
            'toolCallId': 'tool-1',
            'title': 'Read file',
            'kind': 'read',
            'status': 'completed',
            'content': <Object?>['result'],
            'locations': <Object?>[
              <String, Object?>{'path': '/repo/file.dart'},
              '/repo/other.dart',
            ],
            'rawInput': <String, Object?>{'path': '/repo/file.dart'},
            'rawOutput': <String, Object?>{'ok': true},
          },
        }) as AcpToolCallUpdate;
      }

      final started = decodeTool('tool_call');
      final updated = decodeTool('tool_call_update');

      expect(started.isUpdate, isFalse);
      expect(updated.isUpdate, isTrue);
      expect(updated.toolCallId, 'tool-1');
      expect(updated.toolKind, 'read');
      expect(updated.status, 'completed');
      expect(updated.locations, <String>[
        '/repo/file.dart',
        '/repo/other.dart',
      ]);
      expect(updated.rawInput['path'], '/repo/file.dart');
      expect(updated.rawOutput['ok'], isTrue);
    });

    test('decodes plan entries and ignores malformed entries', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'plan',
          'entries': <Object?>[
            <String, Object?>{
              'content': 'Step one',
              'status': 'pending',
              'priority': 'high',
            },
            <String, Object?>{'status': 'missing-content'},
            'damaged',
          ],
        },
      });

      expect(decoded, isA<AcpPlanUpdate>());
      final plan = decoded as AcpPlanUpdate;
      expect(plan.entries, hasLength(1));
      expect(plan.entries.single.content, 'Step one');
      expect(plan.entries.single.status, 'pending');
      expect(plan.entries.single.priority, 'high');
    });

    test('decodes current_mode_update with camelCase mode id', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        },
      });

      expect(decoded, isA<AcpCurrentModeUpdate>());
      final mode = decoded as AcpCurrentModeUpdate;
      expect(mode.modeId, 'plan');
    });

    test('decodes current_mode_update with snake_case mode id fallback', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'current_mode_id': 'default',
        },
      });

      expect(decoded, isA<AcpCurrentModeUpdate>());
      final mode = decoded as AcpCurrentModeUpdate;
      expect(mode.modeId, 'default');
    });

    test('decodes session_info_update with title', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'session_info_update',
          'title': 'Realtime Session Grok retry_state Event Adaptation',
          'modelId': 'grok-4.5',
        },
      });

      expect(decoded, isA<AcpSessionInfoUpdate>());
      final info = decoded as AcpSessionInfoUpdate;
      expect(info.sessionId, 'session-1');
      expect(info.title, 'Realtime Session Grok retry_state Event Adaptation');
      expect(info.modelId, 'grok-4.5');
    });

    test('decodes session_summary_generated with session_summary', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'session_summary_generated',
          'session_summary':
              'Realtime Session Grok retry_state Event Adaptation',
        },
      });

      expect(decoded, isA<AcpSessionSummaryGenerated>());
      final summary = decoded as AcpSessionSummaryGenerated;
      expect(summary.sessionId, 'session-1');
      expect(
        summary.sessionSummary,
        'Realtime Session Grok retry_state Event Adaptation',
      );
    });

    test('decodes retry_state transport diagnostics', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'retry_state',
          'type': 'retrying',
          'attempt': 1,
          'max_retries': 15,
          'reason': 'reqwest error stream: Transport error: error decoding response body',
          '_meta': <String, Object?>{'eventId': 'event-retry-1'},
        },
      });

      expect(decoded, isA<AcpRetryStateUpdate>());
      final retry = decoded as AcpRetryStateUpdate;
      expect(retry.sessionId, 'session-1');
      expect(retry.type, 'retrying');
      expect(retry.attempt, 1);
      expect(retry.maxRetries, 15);
      expect(retry.attempts, isNull);
      expect(retry.isRateLimited, isFalse);
      expect(retry.reason, contains('Transport error'));
      expect(retry.eventId, 'event-retry-1');
    });

    test('decodes exhausted retry_state with rate limit flag', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'retry_state',
          'type': 'exhausted',
          'attempts': 2,
          'is_rate_limited': true,
          'reason': 'API error (status 429 Too Many Requests)',
        },
      });

      expect(decoded, isA<AcpRetryStateUpdate>());
      final retry = decoded as AcpRetryStateUpdate;
      expect(retry.type, 'exhausted');
      expect(retry.attempts, 2);
      expect(retry.isRateLimited, isTrue);
    });

    test('rejects current_mode_update without a mode id', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{'sessionUpdate': 'current_mode_update'},
      });

      expect(decoded, isA<AcpUnknownUpdate>());
      final unknown = decoded as AcpUnknownUpdate;
      expect(unknown.diagnostic, 'missing_mode_id');
    });

    test('decodes usage updates with tolerant numeric fields', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'usage_update',
          'used': '2048',
          'model_context_window': 8192,
        },
      });

      expect(decoded, isA<AcpUsageUpdate>());
      final usage = decoded as AcpUsageUpdate;
      expect(usage.used, 2048);
      expect(usage.modelContextWindow, 8192);
    });

    test('decodes turn completion and typed usage', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': 'prompt-1',
          'stop_reason': 'end_turn',
          'usage': <String, Object?>{
            'inputTokens': 10,
            'outputTokens': 5,
            'totalTokens': 15,
            'cachedReadTokens': 2,
            'reasoningTokens': 3,
            'modelContextWindow': 4096,
            'apiDurationMs': 120,
          },
        },
      });

      expect(decoded, isA<AcpTurnCompletedUpdate>());
      final completed = decoded as AcpTurnCompletedUpdate;
      expect(completed.promptId, 'prompt-1');
      expect(completed.stopReason, 'end_turn');
      expect(completed.usage?.inputTokens, 10);
      expect(completed.usage?.outputTokens, 5);
      expect(completed.usage?.totalTokens, 15);
      expect(completed.usage?.cachedReadTokens, 2);
      expect(completed.usage?.reasoningTokens, 3);
      expect(completed.usage?.modelContextWindow, 4096);
      expect(completed.usage?.apiDurationMs, 120);
    });

    test('returns a typed unknown for future update kinds', () {
      final decoded = decoder.decode(<String, Object?>{
        'sessionId': 'session-1',
        'update': <String, Object?>{
          'sessionUpdate': 'future_update',
          'futureField': <String, Object?>{'value': 1},
        },
      });

      expect(decoded, isA<AcpUnknownUpdate>());
      final unknown = decoded as AcpUnknownUpdate;
      expect(unknown.kind, 'future_update');
      expect(unknown.diagnostic, 'unknown_kind');
      expect(unknown.raw['futureField'], isNotNull);
    });

    test('returns typed unknown results for damaged input', () {
      final values = <Object?>[
        null,
        'not-an-object',
        const <String, Object?>{},
        const <String, Object?>{'update': 'not-an-object'},
        const <String, Object?>{
          'sessionId': 'session-1',
          'update': <String, Object?>{'sessionUpdate': 'agent_message_chunk'},
        },
        const <String, Object?>{
          'update': <String, Object?>{
            'sessionUpdate': 'usage_update',
            'used': 1,
          },
        },
      ];

      final decoded = values.map(decoder.decode).toList(growable: false);

      expect(decoded, everyElement(isA<AcpUnknownUpdate>()));
      expect(
        decoded.map((update) => (update as AcpUnknownUpdate).diagnostic),
        containsAll(<String>[
          'params_not_object',
          'update_not_object',
          'missing_content',
          'missing_session_id',
        ]),
      );
    });
  });
}
