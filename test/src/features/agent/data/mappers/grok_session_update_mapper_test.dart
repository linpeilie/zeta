import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import '../../../../testing/agent_file_change_canonical.dart';
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

    test(
      'maps agent_result error detail as the user-visible failure message',
      () {
        final mapped = mapper.mapXaiSessionUpdate(
          params: _params(<String, Object?>{
            'sessionUpdate': 'turn_completed',
            'prompt_id': promptId,
            'stop_reason': 'error',
            'agent_result':
                'API error (status 402 Payment Required): '
                'Grok Build usage balance exhausted',
          }, eventId: 'agent-error-terminal'),
          runningTurnId: turnId,
          runtimeScope: runtimeScope,
        );

        final completed = mapped.events
            .whereType<AgentTurnCompletedEvent>()
            .single;
        expect(completed.status, AgentHistoryTurnStatus.failed);
        expect(
          completed.errorMessage,
          'API error (status 402 Payment Required): '
          'Grok Build usage balance exhausted',
        );
      },
    );

    test('reads camelCase agentResult from turn_completed raw payload', () {
      final mapped = mapper.mapXaiSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'turn_completed',
          'prompt_id': promptId,
          'stop_reason': 'error',
          'agentResult': 'API error (status 402): balance exhausted',
        }, eventId: 'agent-error-camel'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      final completed = mapped.events
          .whereType<AgentTurnCompletedEvent>()
          .single;
      expect(completed.status, AgentHistoryTurnStatus.failed);
      expect(
        completed.errorMessage,
        'API error (status 402): balance exhausted',
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

    test('maps session_info_update title to thread name event', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'session_info_update',
          'title': 'Realtime Session Grok retry_state Event Adaptation',
        }, eventId: 'title-1'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events.single, isA<AgentThreadNameUpdatedEvent>());
      final name = mapped.events.single as AgentThreadNameUpdatedEvent;
      expect(name.threadId, sessionId);
      expect(
        name.threadName,
        'Realtime Session Grok retry_state Event Adaptation',
      );
    });

    test('maps session_summary_generated to thread name event', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'session_summary_generated',
          'session_summary':
              'Realtime Session Grok retry_state Event Adaptation',
        }, eventId: 'summary-1'),
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events.single, isA<AgentThreadNameUpdatedEvent>());
      final name = mapped.events.single as AgentThreadNameUpdatedEvent;
      expect(name.threadId, sessionId);
      expect(
        name.threadName,
        'Realtime Session Grok retry_state Event Adaptation',
      );
    });

    test('ignores session_info_update without title', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'session_info_update',
          'modelId': 'grok-4.5',
        }, eventId: 'title-empty'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events, isEmpty);
      expect(mapped.ignoredReason, 'missing session title');
    });

    test('maps current_mode_update to a conversation mode event', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }, eventId: 'mode-1'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events.single, isA<AgentConversationModeUpdatedEvent>());
      final mode = mapped.events.single as AgentConversationModeUpdatedEvent;
      expect(mode.modeId, AgentConversationModeId.plan);
      expect(mode.sessionId, sessionId);
    });

    test('maps current_mode_update agent alias to default mode', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'agent',
        }, eventId: 'mode-agent'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events.single, isA<AgentConversationModeUpdatedEvent>());
      final mode = mapped.events.single as AgentConversationModeUpdatedEvent;
      expect(mode.modeId, AgentConversationModeId.defaultMode);
    });

    test('maps current_mode_update default wire value to default mode', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'default',
        }, eventId: 'mode-default'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      final mode = mapped.events.single as AgentConversationModeUpdatedEvent;
      expect(mode.modeId, AgentConversationModeId.defaultMode);
    });

    test('drops current_mode_update with unknown mode id', () {
      final mapped = mapper.mapSessionUpdate(
        params: _params(<String, Object?>{
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'planner-v2',
        }, eventId: 'mode-2'),
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      expect(mapped.events, isEmpty);
      expect(mapped.unmatchedKind, 'current_mode_update');
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

    test('real-shape Grok Edit emits one cumulative typed snapshot', () {
      // Arrange
      mapper.dispose();
      mapper = GrokAcpNotificationMapper();
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: 'grok-session-redacted',
        turnId: 'grok-edit-turn',
      );
      final fixture = readFixtureJsonMap(
        'agent_file_change_evidence/grok_edit_1_0_0.json',
      );
      final events = <AgentEvent>[];

      // Act
      for (final rawEvent in fixture['events']! as List<Object?>) {
        final event = (rawEvent! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final params = (event['params']! as Map).map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final mapped = (event['method']! as String).startsWith('_x.ai/')
            ? mapper.mapXaiSessionUpdate(
                params: params,
                runningTurnId: 'grok-edit-turn',
                runtimeScope: runtimeScope,
              )
            : mapper.mapSessionUpdate(
                params: params,
                runningTurnId: 'grok-edit-turn',
                runtimeScope: runtimeScope,
              );
        events.addAll(mapped.events);
      }

      // Assert
      final tools = events.whereType<AgentToolCallEvent>().toList();
      expect(tools, hasLength(3));
      expect(tools.first.toolCall.fileChanges, isNull);
      final inProgress = tools[1].toolCall;
      final completed = tools[2].toolCall;
      expect(inProgress.content, isNull);
      expect(completed.content, isNull);
      expect(inProgress.fileChanges, isNotNull);
      expect(completed.fileChanges, same(inProgress.fileChanges));
      expect(inProgress.fileChanges!.revision, 1);
      final change = inProgress.fileChanges!.changes.single;
      expect(change.path, '<WORKSPACE_REDACTED>/sample.txt');
      expect(change.kind, AgentFileChangeKind.modified);
      final evidence = change.evidence as AgentTextReplacementEvidence;
      expect(evidence.oldText, '[BEFORE_REDACTED]\n');
      expect(evidence.newText, '[AFTER_REDACTED]\n');
      expect(evidence.replaceAll, isFalse);
      final envelopes = canonicalFileChangeEnvelopes(events);
      expect(envelopes.map((event) => event.status), <String>[
        'pending',
        'completed',
      ]);
      expect(envelopes.map((event) => event.ownerId).toSet(), hasLength(1));
      expect(
        envelopes.map((event) => event.snapshotSignature).toSet(),
        hasLength(1),
      );
      expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
    });

    test('emits live context usage only when _meta.totalTokens changes', () {
      GrokAcpMappedUpdate mapChunk(String eventId, int totalTokens) {
        return mapper.mapSessionUpdate(
          params: <String, Object?>{
            'sessionId': sessionId,
            'update': <String, Object?>{
              'sessionUpdate': 'agent_message_chunk',
              'content': <String, Object?>{'type': 'text', 'text': eventId},
            },
            '_meta': <String, Object?>{
              'eventId': eventId,
              'promptId': promptId,
              'totalTokens': totalTokens,
            },
          },
          runningTurnId: turnId,
          runtimeScope: runtimeScope,
        );
      }

      final first = mapChunk('chunk-1', 1200);
      final unchanged = mapChunk('chunk-2', 1200);
      final changed = mapChunk('chunk-3', 1350);

      final firstUsage = first.events
          .whereType<AgentContextWindowUsageEvent>()
          .single;
      expect(firstUsage.sessionId, sessionId);
      expect(firstUsage.turnId, turnId);
      expect(firstUsage.usedTokens, 1200);
      expect(
        unchanged.events.whereType<AgentContextWindowUsageEvent>(),
        isEmpty,
      );
      expect(
        changed.events
            .whereType<AgentContextWindowUsageEvent>()
            .single
            .usedTokens,
        1350,
      );
      expect(first.events.whereType<AgentTokenUsageEvent>(), isEmpty);
    });

    test(
      'maps multi-call billing total separately from _meta context occupancy',
      () {
        // 流式 chunk 携带上下文占用。
        mapper.mapSessionUpdate(
          params: <String, Object?>{
            'sessionId': sessionId,
            'update': <String, Object?>{
              'sessionUpdate': 'agent_message_chunk',
              'content': <String, Object?>{'type': 'text', 'text': 'ok'},
            },
            '_meta': <String, Object?>{
              'eventId': 'chunk-1',
              'promptId': promptId,
              'totalTokens': 378650,
            },
          },
          runningTurnId: turnId,
          runtimeScope: runtimeScope,
        );

        // turn_completed.usage 是 multi-call 计费合计，远大于窗口占用。
        final mapped = mapper.mapXaiSessionUpdate(
          params: <String, Object?>{
            'sessionId': sessionId,
            'update': <String, Object?>{
              'sessionUpdate': 'turn_completed',
              'prompt_id': promptId,
              'stop_reason': 'end_turn',
              'usage': <String, Object?>{
                'inputTokens': 5791874,
                'outputTokens': 13088,
                'totalTokens': 5804962,
                'cachedReadTokens': 5755904,
                'reasoningTokens': 11625,
                'modelCalls': 16,
                'numTurns': 16,
              },
            },
            '_meta': <String, Object?>{'eventId': 'done'},
          },
          runningTurnId: turnId,
          runtimeScope: runtimeScope,
        );

        final usageEvent = mapped.events
            .whereType<AgentTokenUsageEvent>()
            .single;
        expect(usageEvent.isSessionCumulative, isFalse);
        // 计费合计保留在非 last* 字段。
        expect(usageEvent.tokenUsage.totalTokens, 5804962);
        expect(usageEvent.tokenUsage.inputTokens, 5791874);
        expect(usageEvent.tokenUsage.cachedInputTokens, 5755904);
        // 上下文占用来自 _meta.totalTokens。
        expect(usageEvent.tokenUsage.lastTotalTokens, 378650);
        expect(usageEvent.tokenUsage.lastInputTokens, 378650);
      },
    );

    test('late turn_completed supplements usage after prompt RPC terminal', () {
      // Arrange：流式 chunk 已提供当前上下文占用与 prompt identity。
      mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'ok'},
            '_meta': <String, Object?>{'promptId': promptId},
          },
          '_meta': <String, Object?>{
            'eventId': 'chunk-before-rpc',
            'totalTokens': 1200,
          },
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      // Act：RPC 终态先结束生命周期，权威通知随后携带完整 usage。
      final promptTerminal = mapper.mapPromptTerminal(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: turnId,
        stopReason: 'end_turn',
        source: GrokTerminalSource.promptRpc,
      );
      final lateTerminal = mapper.mapXaiSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'turn_completed',
            'prompt_id': promptId,
            'stop_reason': 'end_turn',
            'usage': <String, Object?>{
              'inputTokens': 1000,
              'outputTokens': 300,
              'totalTokens': 1300,
              'cachedReadTokens': 200,
              'reasoningTokens': 50,
            },
          },
          '_meta': <String, Object?>{'eventId': 'late-terminal'},
        },
        runningTurnId: null,
        runtimeScope: runtimeScope,
      );

      // Assert：完成事件仍只有一次，迟到通知只补 token 元数据。
      expect(
        promptTerminal.events.whereType<AgentTurnCompletedEvent>(),
        hasLength(1),
      );
      expect(lateTerminal.events.whereType<AgentTurnCompletedEvent>(), isEmpty);
      final usage = lateTerminal.events
          .whereType<AgentTokenUsageEvent>()
          .single;
      expect(usage.turnId, turnId);
      expect(usage.isSessionCumulative, isFalse);
      expect(usage.tokenUsage.totalTokens, 1300);
      expect(usage.tokenUsage.inputTokens, 1000);
      expect(usage.tokenUsage.cachedInputTokens, 200);
      expect(usage.tokenUsage.lastTotalTokens, 1200);
      expect(usage.tokenUsage.lastInputTokens, 1200);
    });

    test('clears tracked context occupancy across turns', () {
      mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'agent_message_chunk',
            'content': <String, Object?>{'type': 'text', 'text': 'a'},
          },
          '_meta': <String, Object?>{'eventId': 'c1', 'totalTokens': 100000},
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );
      mapper.mapXaiSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'turn_completed',
            'stop_reason': 'end_turn',
            'usage': <String, Object?>{
              'inputTokens': 500000,
              'outputTokens': 10,
              'totalTokens': 500010,
            },
          },
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      // 下一 turn 无 _meta 占用时，不得继承上一 turn 的 last*。
      mapper.beginTurn(
        runtimeScope: runtimeScope,
        sessionId: sessionId,
        turnId: 'turn-2',
      );
      final second = mapper.mapXaiSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'turn_completed',
            'stop_reason': 'end_turn',
            'usage': <String, Object?>{
              'inputTokens': 20,
              'outputTokens': 5,
              'totalTokens': 25,
            },
          },
        },
        runningTurnId: 'turn-2',
        runtimeScope: runtimeScope,
      );
      final usage = second.events.whereType<AgentTokenUsageEvent>().single;
      expect(usage.tokenUsage.totalTokens, 25);
      expect(usage.tokenUsage.lastTotalTokens, isNull);
      expect(usage.tokenUsage.lastInputTokens, isNull);
    });
  });

  group('GrokSessionUpdateMapper retry_state', () {
    test('maps retrying transport state to willRetry error', () {
      final mapped = mapper.mapXaiSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'retry_state',
            'type': 'retrying',
            'attempt': 1,
            'max_retries': 15,
            'reason':
                'reqwest error stream: Transport error: error decoding response body',
          },
          '_meta': <String, Object?>{'eventId': 'retry-1'},
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      expect(mapped.events, hasLength(1));
      final error = mapped.events.single as AgentErrorEvent;
      expect(error.sessionId, sessionId);
      expect(error.turnId, turnId);
      expect(error.willRetry, isTrue);
      expect(error.code, 'responseStreamDisconnected');
      expect(error.message, contains('retry 1/15'));
      // 原始 reason 不得直接拼进用户可见正文。
      expect(error.message, isNot(contains('reqwest')));
      expect(mapped.events.whereType<AgentTurnCompletedEvent>(), isEmpty);
    });

    test('maps exhausted retry_state to failed terminal', () {
      final mapped = mapper.mapXaiSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'retry_state',
            'type': 'exhausted',
            'attempts': 15,
            'reason': 'provider unavailable',
            'is_rate_limited': false,
          },
          '_meta': <String, Object?>{'eventId': 'retry-exhausted'},
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      final error = mapped.events.whereType<AgentErrorEvent>().single;
      final terminal = mapped.events
          .whereType<AgentTurnCompletedEvent>()
          .single;
      expect(error.willRetry, isFalse);
      expect(error.message, 'Grok request failed. Please try again.');
      expect(error.code, 'responseTooManyFailedAttempts');
      expect(terminal.status, AgentHistoryTurnStatus.failed);
      expect(terminal.errorMessage, error.message);
      expect(terminal.turnId, turnId);
    });

    test('maps rate-limited retry_state to usage limit failure', () {
      final mapped = mapper.mapSessionUpdate(
        params: <String, Object?>{
          'sessionId': sessionId,
          'update': <String, Object?>{
            'sessionUpdate': 'retry_state',
            'type': 'exhausted',
            'attempts': 2,
            'is_rate_limited': true,
            'reason':
                'API error (status 429 Too Many Requests): subscription:free-usage-exhausted',
          },
          '_meta': <String, Object?>{'eventId': 'retry-rate-limit'},
        },
        runningTurnId: turnId,
        runtimeScope: runtimeScope,
      );

      final error = mapped.events.whereType<AgentErrorEvent>().single;
      final terminal = mapped.events
          .whereType<AgentTurnCompletedEvent>()
          .single;
      expect(error.willRetry, isFalse);
      expect(error.code, 'usageLimitExceeded');
      expect(error.message, 'Grok rate limit reached. Please try again later.');
      expect(terminal.status, AgentHistoryTurnStatus.failed);
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
