import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_acp_notification_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../../testing/fixture_reader.dart';

void main() {
  const runtimeScope = AgentRuntimeScope(
    runtimeId: 'grok-runtime-test',
    connectionEpoch: 1,
  );
  const sessionId = 'session-1';
  const turnId = 'turn-1';
  const promptId = 'prompt-1';

  late GrokAcpNotificationMapper mapper;

  setUp(() {
    mapper = GrokAcpNotificationMapper();
    mapper.beginTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );
  });

  tearDown(() {
    mapper.dispose();
  });

  group('GrokSessionUpdateMapper normalized identity', () {
    test('G1 text chunks share one message entryId', () {
      // Arrange / Act
      final first = _mapText(mapper, text: 'a', eventId: 'event-1');
      final second = _mapText(mapper, text: 'b', eventId: 'event-2');

      // Assert
      expect(first.messageId, second.messageId);
      expect('${first.delta}${second.delta}', 'ab');
      expect(mapper.diagnostics.syntheticEntryIdCreated, 1);
    });

    test('G2 text, new tool, text emits Message Tool Message', () {
      final first = _mapText(mapper, text: 'before', eventId: 'event-1');
      final tool = _mapTool(
        mapper,
        kind: 'tool_call',
        toolCallId: 'tool-1',
        eventId: 'event-tool',
      );
      final second = _mapText(mapper, text: 'after', eventId: 'event-2');

      expect(
        <AgentEvent>[first, tool, second],
        <Matcher>[
          isA<AgentMessageDeltaEvent>(),
          isA<AgentToolCallEvent>(),
          isA<AgentMessageDeltaEvent>(),
        ],
      );
      expect(first.messageId, isNot(second.messageId));
    });

    test('G3 reused source id across tool produces two entryIds', () {
      final first = _mapText(
        mapper,
        text: 'before',
        sourceMessageId: 'source-A',
        eventId: 'event-1',
      );
      _mapTool(
        mapper,
        kind: 'tool_call',
        toolCallId: 'tool-1',
        eventId: 'event-tool',
      );
      final second = _mapText(
        mapper,
        text: 'after',
        sourceMessageId: 'source-A',
        eventId: 'event-2',
      );

      expect(first.sourceMessageId, 'source-A');
      expect(second.sourceMessageId, 'source-A');
      expect(first.messageId, isNot(second.messageId));
      final snapshot = mapper.snapshot(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
      )!;
      expect(snapshot.sourceMessageEntryIds['source-A'], <String>[
        first.messageId,
        second.messageId,
      ]);
    });

    test('G4 changed source id starts a new message segment', () {
      final first = _mapText(
        mapper,
        text: 'a',
        sourceMessageId: 'source-A',
        eventId: 'event-1',
      );
      final second = _mapText(
        mapper,
        text: 'b',
        sourceMessageId: 'source-B',
        eventId: 'event-2',
      );

      expect(first.messageId, isNot(second.messageId));
    });

    test('G5 thought chunks with different eventIds share one phase', () {
      final first = _mapThought(mapper, text: 'a', eventId: 'thought-event-1');
      final second = _mapThought(mapper, text: 'b', eventId: 'thought-event-2');

      expect(first.itemId, second.itemId);
      expect('${first.delta}${second.delta}', 'ab');
    });

    test('G6 thought, tool, thought emits two reasoning phases', () {
      final first = _mapThought(mapper, text: 'a', eventId: 'thought-1');
      final tool = _mapTool(
        mapper,
        kind: 'tool_call',
        toolCallId: 'tool-1',
        eventId: 'tool-start',
      );
      final second = _mapThought(mapper, text: 'b', eventId: 'thought-2');

      expect(
        <AgentEvent>[first, tool, second],
        <Matcher>[
          isA<AgentReasoningDeltaEvent>(),
          isA<AgentToolCallEvent>(),
          isA<AgentReasoningDeltaEvent>(),
        ],
      );
      expect(first.itemId, isNot(second.itemId));
    });

    test('reasoning start and following text both close the prior phase', () {
      final first = _mapText(mapper, text: 'before', eventId: 'text-1');
      final reasoning = _mapThought(
        mapper,
        text: 'thought',
        eventId: 'thought-1',
      );
      final second = _mapText(mapper, text: 'after', eventId: 'text-2');

      expect(
        <AgentEvent>[first, reasoning, second],
        <Matcher>[
          isA<AgentMessageDeltaEvent>(),
          isA<AgentReasoningDeltaEvent>(),
          isA<AgentMessageDeltaEvent>(),
        ],
      );
      expect(first.messageId, isNot(second.messageId));
    });

    test('G7 permission boundary closes the current message', () {
      final first = _mapText(mapper, text: 'a', eventId: 'event-1');

      final noted = mapper.noteBoundary(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        runningTurnId: turnId,
        kind: GrokNarrativeBoundaryKind.permission,
      );
      final second = _mapText(mapper, text: 'b', eventId: 'event-2');

      expect(noted, isTrue);
      expect(first.messageId, isNot(second.messageId));
    });

    test('G8 tool update does not bump the message segment ordinal', () {
      _mapTool(
        mapper,
        kind: 'tool_call',
        toolCallId: 'tool-1',
        eventId: 'tool-start',
      );
      _mapTool(
        mapper,
        kind: 'tool_call_update',
        toolCallId: 'tool-1',
        eventId: 'tool-complete',
      );
      _mapText(mapper, text: 'after', eventId: 'event-1');

      final snapshot = mapper.snapshot(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
      )!;
      expect(snapshot.messageSegmentOrdinal, 1);
      expect(snapshot.seenToolCallIds, <String>{'tool-1'});
    });

    test('G9 terminal drops late text and records diagnostics', () {
      final terminal = mapper.mapXaiSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': promptId,
          'stop_reason': 'end_turn',
        }, eventId: 'terminal-1'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      final late = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'late'},
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'late-1'),
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );

      expect(
        terminal.events.whereType<AgentTurnCompletedEvent>(),
        hasLength(1),
      );
      expect(late.events, isEmpty);
      expect(mapper.diagnostics.lateContentDropped, 1);
    });

    test('G10 cancel and new turn never reuse the old entryId', () {
      final oldMessage = _mapText(mapper, text: 'old', eventId: 'event-1');
      mapper.mapPromptTerminal(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        stopReason: 'cancelled',
        source: GrokTerminalSource.cancel,
      );
      mapper.invalidateTurn(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        runningTurnId: turnId,
        promptId: null,
        reason: GrokIdentityInvalidationReason.cancel,
      );
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: 'turn-2',
      );

      final newMessage = _mapText(
        mapper,
        text: 'new',
        eventId: 'event-2',
        runningTurnId: 'turn-2',
        promptId: 'prompt-2',
      );

      expect(oldMessage.messageId, isNot(newMessage.messageId));
    });

    test('standard and xAI terminal notifications are first-terminal-wins', () {
      final standard = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'stopReason': 'end_turn',
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'standard-terminal'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      final xai = mapper.mapXaiSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': promptId,
          'stop_reason': 'end_turn',
        }, eventId: 'xai-terminal'),
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );

      expect(
        standard.events.whereType<AgentTurnCompletedEvent>(),
        hasLength(1),
      );
      expect(xai.events, isEmpty);
      expect(mapper.diagnostics.terminalAccepted, 1);
      expect(mapper.diagnostics.duplicateTerminalIgnored, 1);
    });

    test('prompt failure keeps a friendly summary and ignores duplicates', () {
      final first = mapper.mapPromptTerminal(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        stopReason: 'prompt_error',
        source: GrokTerminalSource.promptError,
        errorMessage: 'Grok rate limit reached. Please try again later.',
        raw: const <String, Object?>{
          'jsonRpcError': <String, Object?>{
            'code': -32003,
            'message': 'Rate limited',
          },
        },
      );
      final duplicate = mapper.mapPromptTerminal(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        stopReason: 'prompt_error',
        source: GrokTerminalSource.promptError,
        errorMessage: 'must not replace the first terminal',
      );

      final completed = first.events
          .whereType<AgentTurnCompletedEvent>()
          .single;
      expect(completed.status, AgentHistoryTurnStatus.failed);
      expect(
        completed.errorMessage,
        'Grok rate limit reached. Please try again later.',
      );
      expect(completed.raw['jsonRpcError'], const <String, Object?>{
        'code': -32003,
        'message': 'Rate limited',
      });
      expect(duplicate.events, isEmpty);
      expect(mapper.diagnostics.terminalAccepted, 1);
      expect(mapper.diagnostics.duplicateTerminalIgnored, 1);
    });

    test('maps rate-limit terminal updates to a friendly failed status', () {
      final mapped = mapper.mapXaiSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': promptId,
          'stop_reason': 'rate_limit',
        }, eventId: 'rate-limit-terminal'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      final completed = mapped.events
          .whereType<AgentTurnCompletedEvent>()
          .single;
      expect(completed.status, AgentHistoryTurnStatus.failed);
      expect(
        completed.errorMessage,
        'Grok rate limit reached. Please try again later.',
      );
    });

    test('terminal permits known tool terminal update but no new tool', () {
      _mapTool(
        mapper,
        kind: 'tool_call',
        toolCallId: 'known-tool',
        eventId: 'tool-start',
      );
      mapper.mapPromptTerminal(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        stopReason: 'end_turn',
        source: GrokTerminalSource.promptRpc,
      );

      final knownUpdate = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'known-tool',
          'status': 'completed',
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'tool-complete'),
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );
      final newTool = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'tool_call',
          'toolCallId': 'late-new-tool',
          'status': 'pending',
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'late-tool'),
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );

      expect(knownUpdate.events.single, isA<AgentToolCallEvent>());
      expect(newTool.events, isEmpty);
      expect(mapper.diagnostics.lateEventDropped, 1);
    });

    test('eventId is dedup-only and duplicate chunks are dropped', () {
      final first = _mapText(mapper, text: 'a', eventId: 'same-event');
      final duplicate = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'agent_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'a'},
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'same-event'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      expect(first.messageId, isNotEmpty);
      expect(duplicate.events, isEmpty);
      expect(mapper.diagnostics.duplicateRawEventDropped, 1);
    });

    test('plan and interaction/system boundaries all close message phases', () {
      final ids = <String>[
        _mapText(mapper, text: '0', eventId: 'text-0').messageId,
      ];

      final plan = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'plan',
          'entries': <Object?>[
            <String, Object?>{'content': 'step'},
          ],
          '_meta': <String, Object?>{'promptId': promptId},
        }, eventId: 'plan-1'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(plan.events.single, isA<AgentPlanUpdatedEvent>());
      ids.add(_mapText(mapper, text: '1', eventId: 'text-1').messageId);

      for (final kind in <GrokNarrativeBoundaryKind>[
        GrokNarrativeBoundaryKind.userQuestion,
        GrokNarrativeBoundaryKind.planApproval,
        GrokNarrativeBoundaryKind.warningOrSystem,
      ]) {
        expect(
          mapper.noteBoundary(
            runtimeScope: runtimeScope,
            sessionId: sessionId,
            runningTurnId: turnId,
            kind: kind,
          ),
          isTrue,
        );
        ids.add(
          _mapText(
            mapper,
            text: kind.name,
            eventId: 'text-${kind.name}',
          ).messageId,
        );
      }

      expect(ids.toSet(), hasLength(ids.length));
    });

    test('Phase 0 Grok fixtures produce normalized adapter identities', () {
      mapper.dispose();
      mapper = GrokAcpNotificationMapper();
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: 'grok-session-redacted',
        turnId: 'local-turn-fixture',
      );
      final fixture = readFixtureJsonMap(
        'agent_stream_identity/grok_live_text_tool_text.json',
      );
      final mappedEvents = <AgentEvent>[];
      for (final rawEvent in fixture['events']! as List<Object?>) {
        final event = (rawEvent! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final params = (event['params']! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final mapped = event['method'] == '_x.ai/session/update'
            ? mapper.mapXaiSessionUpdate(
                params: params,
                runningTurnId: 'local-turn-fixture',
                runtimeScope: runtimeScope,
              )
            : mapper.mapSessionUpdate(
                params: params,
                runningTurnId: 'local-turn-fixture',
                runtimeScope: runtimeScope,
              );
        mappedEvents.addAll(mapped.events);
      }

      final messages = mappedEvents
          .whereType<AgentMessageDeltaEvent>()
          .toList();
      final tools = mappedEvents.whereType<AgentToolCallEvent>().toList();
      expect(messages, hasLength(2));
      expect(messages.first.messageId, isNot(messages.last.messageId));
      expect(tools, hasLength(2));
      expect(tools.first.toolCall.id, tools.last.toolCall.id);
      expect(mappedEvents.whereType<AgentTurnCompletedEvent>(), hasLength(1));

      mapper.dispose();
      mapper = GrokAcpNotificationMapper();
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: 'grok-session-redacted',
        turnId: 'local-thought-fixture',
      );
      final thoughtFixture = readFixtureJsonMap(
        'agent_stream_identity/grok_live_consecutive_thought.json',
      );
      final reasoning = <AgentReasoningDeltaEvent>[];
      for (final rawEvent in thoughtFixture['events']! as List<Object?>) {
        final event = (rawEvent! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final params = (event['params']! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        reasoning.addAll(
          mapper
              .mapSessionUpdate(
                params: params,
                runningTurnId: 'local-thought-fixture',
                runtimeScope: runtimeScope,
              )
              .events
              .whereType<AgentReasoningDeltaEvent>(),
        );
      }
      expect(reasoning, hasLength(2));
      expect(reasoning.first.itemId, reasoning.last.itemId);
    });
  });
}

AgentMessageDeltaEvent _mapText(
  GrokAcpNotificationMapper mapper, {
  required String text,
  required String eventId,
  String? sourceMessageId,
  String runningTurnId = 'turn-1',
  String promptId = 'prompt-1',
}) {
  final mapped = mapper.mapSessionUpdate(
    params: _params(<String, Object?>{
      'sessionUpdate': 'agent_message_chunk',
      'messageId': ?sourceMessageId,
      'content': <String, Object?>{'type': 'text', 'text': text},
      '_meta': <String, Object?>{'promptId': promptId},
    }, eventId: eventId),
    runningTurnId: runningTurnId,
    runtimeScope: const AgentRuntimeScope(
      runtimeId: 'grok-runtime-test',
      connectionEpoch: 1,
    ),
  );
  return mapped.events.single as AgentMessageDeltaEvent;
}

AgentReasoningDeltaEvent _mapThought(
  GrokAcpNotificationMapper mapper, {
  required String text,
  required String eventId,
}) {
  final mapped = mapper.mapSessionUpdate(
    params: _params(<String, Object?>{
      'sessionUpdate': 'agent_thought_chunk',
      'content': <String, Object?>{'type': 'text', 'text': text},
      '_meta': <String, Object?>{'promptId': 'prompt-1'},
    }, eventId: eventId),
    runningTurnId: 'turn-1',
    runtimeScope: const AgentRuntimeScope(
      runtimeId: 'grok-runtime-test',
      connectionEpoch: 1,
    ),
  );
  return mapped.events.single as AgentReasoningDeltaEvent;
}

AgentToolCallEvent _mapTool(
  GrokAcpNotificationMapper mapper, {
  required String kind,
  required String toolCallId,
  required String eventId,
}) {
  final mapped = mapper.mapSessionUpdate(
    params: _params(<String, Object?>{
      'sessionUpdate': kind,
      'toolCallId': toolCallId,
      'kind': 'read',
      'status': kind == 'tool_call' ? 'pending' : 'completed',
      '_meta': <String, Object?>{'promptId': 'prompt-1'},
    }, eventId: eventId),
    runningTurnId: 'turn-1',
    runtimeScope: const AgentRuntimeScope(
      runtimeId: 'grok-runtime-test',
      connectionEpoch: 1,
    ),
  );
  return mapped.events.single as AgentToolCallEvent;
}

Map<String, Object?> _params(
  Map<String, Object?> update, {
  required String eventId,
}) => <String, Object?>{
  'sessionId': 'session-1',
  'update': update,
  '_meta': <String, Object?>{'eventId': eventId},
};
