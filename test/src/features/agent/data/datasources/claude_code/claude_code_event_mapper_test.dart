import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import '../../../../../testing/agent_file_change_canonical.dart';

void main() {
  const scope = AgentRuntimeScope(
    runtimeId: 'cc-mapper-test',
    connectionEpoch: 1,
  );
  const fixturesRoot =
      'test/src/features/agent/data/datasources/claude_code/fixtures';

  group('ClaudeCodeEventMapper fixtures', () {
    test('hello_turn canonical signatures', () {
      final frames = _loadFixture('$fixturesRoot/hello_turn.jsonl');
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);

      final sessionId = frames.first['session_id']! as String;
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'turn-hello',
      );

      final events = <AgentEvent>[];
      final signatures = <String>[];
      for (final frame in frames) {
        final mapped = mapper.mapFrame(
          raw: frame,
          runtimeScope: scope,
          runningTurnId: 'turn-hello',
        );
        for (final event in mapped.events) {
          events.add(event);
          signatures.add(_canonicalSignature(event));
        }
      }

      expect(signatures, hasLength(7));
      expect(signatures[0], 'AgentSessionStartedEvent|session=$sessionId');
      expect(
        signatures[1],
        'AgentThreadStatusChangedEvent|thread=$sessionId|status=idle',
      );
      expect(
        signatures[2],
        matches(RegExp(r'^AgentReasoningDeltaEvent\|entry=.+\|kind=text$')),
      );
      expect(
        signatures[3],
        matches(
          RegExp(
            r'^AgentMessageDeltaEvent\|entry=.+\|status=completed\|role=agent$',
          ),
        ),
      );
      expect(
        signatures[4],
        matches(
          RegExp(
            r'^AgentMessageUpdatedEvent\|entry=.+\|status=completed\|role=agent$',
          ),
        ),
      );
      expect(signatures[2], isNot(contains('msg_fixture_hello_1')));
      expect(signatures[3], isNot(contains('msg_fixture_hello_1')));
      expect(signatures[4], isNot(contains('msg_fixture_hello_1')));
      expect(
        (events[3] as AgentMessageDeltaEvent).messageId,
        (events[4] as AgentMessageUpdatedEvent).messageId,
      );
      expect(
        signatures[5],
        'AgentTokenUsageEvent|turn=turn-hello|cumulative=false',
      );
      expect(
        signatures[6],
        'AgentTurnCompletedEvent|turn=turn-hello|status=completed',
      );
    });

    test(
      'final-only assistant snapshot creates a visible timeline message',
      () {
        // Arrange
        final frames = _loadFixture('$fixturesRoot/hello_turn.jsonl');
        final sessionId = frames.first['session_id']! as String;
        const turnId = 'turn-final-snapshot';
        final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
        addTearDown(mapper.dispose);
        mapper.beginTurn(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: turnId,
        );
        final assistantFrame = frames.lastWhere(
          (frame) => frame['type'] == 'assistant',
        );
        final mapped = mapper.mapFrame(
          raw: assistantFrame,
          runtimeScope: scope,
          runningTurnId: turnId,
        );
        final timeline = AgentConversationTimelineStore();
        addTearDown(timeline.dispose);
        timeline.startPendingLiveTurn();
        final processor = _processor(timeline: timeline, sessionId: sessionId);
        processor.process(
          AgentTurnStartedEvent(AgentTurn(id: turnId, sessionId: sessionId)),
        );

        // Act
        for (final event in mapped.events) {
          processor.process(event);
        }

        // Assert
        final message = timeline.messages.single;
        expect(message.text, '[redacted assistant text]');
        expect(message.role, AgentMessageRole.agent);
        expect(message.phase, AgentMessagePhase.response);
        expect(message.status, AgentMessageStatus.completed);
      },
    );

    test('session mismatch emits error without starting a session', () {
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);
      final raw = <String, Object?>{
        'type': 'system',
        'subtype': 'init',
        'session_id': 'unexpected-session',
      };

      final rejected = mapper.mapFrame(
        raw: raw,
        runtimeScope: scope,
        expectedSessionId: 'requested-session',
      );

      expect(rejected.events.whereType<AgentSessionStartedEvent>(), isEmpty);
      final error = rejected.events.whereType<AgentErrorEvent>().single;
      expect(error.code, 'claudeCodeSessionMismatch');
      expect(error.sessionId, 'requested-session');
      expect(error.message, isNot(contains('unexpected-session')));

      final lateMatchingInit = mapper.mapFrame(
        raw: <String, Object?>{...raw, 'session_id': 'requested-session'},
        runtimeScope: scope,
        expectedSessionId: 'requested-session',
      );
      expect(lateMatchingInit.events, isEmpty);
    });

    test('repeated init for one peer is idempotent', () {
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);
      final raw = <String, Object?>{
        'type': 'system',
        'subtype': 'init',
        'session_id': 'stable-session',
      };

      final first = mapper.mapFrame(
        raw: raw,
        runtimeScope: scope,
        expectedSessionId: 'stable-session',
      );
      final repeated = mapper.mapFrame(
        raw: raw,
        runtimeScope: scope,
        expectedSessionId: 'stable-session',
      );

      expect(first.events.whereType<AgentSessionStartedEvent>(), hasLength(1));
      expect(repeated.events, isEmpty);
      expect(repeated.ignoredReason, 'duplicate init');
    });

    test(
      'thinking_interleaved yields two reasoning entryIds and independent message',
      () {
        final frames = _loadFixture('$fixturesRoot/thinking_interleaved.jsonl');
        final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
        addTearDown(mapper.dispose);

        final sessionId = frames.first['session_id']! as String;
        mapper.beginTurn(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: 'turn-interleaved',
        );

        final reasoningIds = <String>[];
        final messageIds = <String>[];
        for (final frame in frames) {
          final mapped = mapper.mapFrame(
            raw: frame,
            runtimeScope: scope,
            runningTurnId: 'turn-interleaved',
          );
          for (final event in mapped.events) {
            if (event is AgentReasoningDeltaEvent) {
              reasoningIds.add(event.itemId);
            }
            if (event is AgentMessageUpdatedEvent) {
              messageIds.add(event.messageId);
            }
          }
        }

        // thinking → text → thinking → text
        expect(reasoningIds, hasLength(2));
        expect(reasoningIds[0], isNot(reasoningIds[1]));
        expect(messageIds, hasLength(2));
        // message entryIds 与两个 reasoning entryId 均独立
        for (final mid in messageIds) {
          expect(mid, isNot(reasoningIds[0]));
          expect(mid, isNot(reasoningIds[1]));
        }
        // 中间 text 与后续 text：fixture 换了 message.id，且 reasoning 会打断
        // segment，因此两个 message entryId 也不同
        expect(messageIds[0], isNot(messageIds[1]));
      },
    );

    test(
      'result_error maps three subtypes to completed/interrupted/failed',
      () {
        final frames = _loadFixture('$fixturesRoot/result_error.jsonl');
        final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
        addTearDown(mapper.dispose);

        final signatures = <String>[];
        String? activeTurn;
        String? activeSession;

        for (final frame in frames) {
          final type = frame['type'];
          if (type == 'system' && frame['subtype'] == 'init') {
            activeSession = frame['session_id']! as String;
            activeTurn = 'turn-${signatures.length}';
            mapper.beginTurn(
              runtimeScope: scope,
              sessionId: activeSession,
              turnId: activeTurn,
            );
          }
          final mapped = mapper.mapFrame(
            raw: frame,
            runtimeScope: scope,
            runningTurnId: activeTurn,
          );
          for (final event in mapped.events) {
            signatures.add(_canonicalSignature(event));
          }
        }

        final turnCompletions = signatures
            .where((s) => s.startsWith('AgentTurnCompletedEvent|'))
            .toList(growable: false);
        expect(turnCompletions, hasLength(3));
        expect(turnCompletions[0], contains('status=completed'));
        expect(turnCompletions[1], contains('status=interrupted'));
        expect(turnCompletions[2], contains('status=failed'));

        // failed path carries errorCode = subtype
        final failedEvents = <AgentTurnCompletedEvent>[];
        // re-run to inspect failed event fields
        final mapper2 = ClaudeCodeEventMapper(providerId: 'claude_code');
        addTearDown(mapper2.dispose);
        String? turn;
        for (final frame in frames) {
          if (frame['type'] == 'system' && frame['subtype'] == 'init') {
            turn = 't-${frame['session_id']}';
            mapper2.beginTurn(
              runtimeScope: scope,
              sessionId: frame['session_id']! as String,
              turnId: turn,
            );
          }
          final mapped = mapper2.mapFrame(
            raw: frame,
            runtimeScope: scope,
            runningTurnId: turn,
          );
          failedEvents.addAll(
            mapped.events.whereType<AgentTurnCompletedEvent>(),
          );
        }
        expect(failedEvents[1].errorCode, 'error_max_turns');
        expect(failedEvents[2].errorCode, 'error_during_execution');
        expect(failedEvents[2].errorMessage, isNotNull);
      },
    );

    test('tool_lifecycle maps success and is_error tool paths', () {
      final frames = _loadFixture('$fixturesRoot/tool_lifecycle.jsonl');
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);

      final sessionId = frames.first['session_id']! as String;
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'turn-tools',
      );

      final toolEvents = <AgentToolCallEvent>[];
      for (final frame in frames) {
        final mapped = mapper.mapFrame(
          raw: frame,
          runtimeScope: scope,
          runningTurnId: 'turn-tools',
        );
        toolEvents.addAll(mapped.events.whereType<AgentToolCallEvent>());
      }

      // tool_use ok → tool_result ok → tool_use fail → tool_result fail
      expect(toolEvents, hasLength(4));

      final startOk = toolEvents[0].toolCall;
      expect(startOk.id, 'toolu_fixture_read_ok');
      expect(startOk.title, 'Read');
      expect(startOk.kind, AgentToolKind.read);
      expect(startOk.status, AgentToolStatus.inProgress);
      expect(startOk.turnId, 'turn-tools');
      expect(startOk.rawInput['file_path'], isA<String>());

      final doneOk = toolEvents[1].toolCall;
      expect(doneOk.id, 'toolu_fixture_read_ok');
      expect(doneOk.title, startOk.title);
      expect(doneOk.kind, startOk.kind);
      expect(doneOk.locations, startOk.locations);
      expect(doneOk.rawInput, startOk.rawInput);
      expect(doneOk.status, AgentToolStatus.completed);
      expect(doneOk.content, isNotNull);

      final startFail = toolEvents[2].toolCall;
      expect(startFail.id, 'toolu_fixture_read_fail');
      expect(startFail.status, AgentToolStatus.inProgress);

      final doneFail = toolEvents[3].toolCall;
      expect(doneFail.id, 'toolu_fixture_read_fail');
      expect(doneFail.title, startFail.title);
      expect(doneFail.kind, startFail.kind);
      expect(doneFail.locations, startFail.locations);
      expect(doneFail.rawInput, startFail.rawInput);
      expect(doneFail.status, AgentToolStatus.failed);
      expect(doneFail.content, isNotNull);
    });

    test('real-shape Edit and Write keep typed evidence through result', () {
      // Arrange
      final fixture = _loadJsonObject(
        'test/fixtures/agent_file_change_evidence/'
        'claude_code_edit_write_2_1_227.json',
      );
      final scenarios = (fixture['scenarios']! as List<Object?>)
          .map(_stringMap)
          .toList(growable: false);

      for (final scenario in scenarios) {
        final name = scenario['name']! as String;
        final frames = (scenario['frames']! as List<Object?>)
            .map(_stringMap)
            .toList(growable: false);
        final sessionId = frames.first['session_id']! as String;
        final turnId = 'turn-$name';
        final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
        addTearDown(mapper.dispose);
        mapper.beginTurn(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: turnId,
        );

        // Act
        final events = <AgentEvent>[];
        for (final frame in frames) {
          events.addAll(
            mapper
                .mapFrame(
                  raw: frame,
                  runtimeScope: scope,
                  runningTurnId: turnId,
                )
                .events,
          );
        }

        // Assert
        final tools = events.whereType<AgentToolCallEvent>().toList();
        expect(tools, hasLength(2), reason: name);
        final started = tools.first.toolCall;
        final completed = tools.last.toolCall;
        expect(completed.status, AgentToolStatus.completed, reason: name);
        expect(completed.title, started.title, reason: name);
        expect(completed.kind, started.kind, reason: name);
        expect(completed.locations, started.locations, reason: name);
        expect(completed.rawInput, started.rawInput, reason: name);
        expect(completed.fileChanges, same(started.fileChanges), reason: name);
        final envelopes = canonicalFileChangeEnvelopes(events);
        expect(envelopes.map((event) => event.status), <String>[
          'inProgress',
          'completed',
        ], reason: name);
        expect(
          envelopes.map((event) => event.ownerId).toSet(),
          hasLength(1),
          reason: name,
        );
        expect(
          envelopes.map((event) => event.snapshotSignature).toSet(),
          hasLength(1),
          reason: name,
        );
        final change = completed.fileChanges!.changes.single;
        expect(change.path, contains('sample'), reason: name);
        if (name == 'edit') {
          expect(change.kind, AgentFileChangeKind.modified);
          expect(change.evidence, isA<AgentTextReplacementEvidence>());
        } else {
          expect(change.kind, AgentFileChangeKind.unknown);
          expect(change.evidence, isA<AgentWrittenContentEvidence>());
        }
        expect(events.whereType<AgentTurnCompletedEvent>(), hasLength(1));
        expect(
          mapper.fileChangeTracker.resolveToolResult(
            runtimeScope: scope,
            sessionId: sessionId,
            turnId: turnId,
            toolUseId: started.id,
          ),
          isNull,
          reason: '$name result must clear the completed turn tracker',
        );
      }
    });

    test('ExitPlanMode and its tool_result never become tool cards', () {
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);
      const sessionId = 'session-plan';
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'turn-plan',
      );

      final toolUse = mapper.mapFrame(
        raw: <String, Object?>{
          'type': 'assistant',
          'session_id': sessionId,
          'uuid': 'uuid-exit-plan',
          'message': <String, Object?>{
            'id': 'msg_plan',
            'role': 'assistant',
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool_use',
                'id': 'toolu_exit_plan',
                'name': 'ExitPlanMode',
                'input': <String, Object?>{'plan': 'Plan body'},
              },
            ],
          },
        },
        runtimeScope: scope,
        runningTurnId: 'turn-plan',
      );
      final toolResult = mapper.mapFrame(
        raw: <String, Object?>{
          'type': 'user',
          'session_id': sessionId,
          'uuid': 'uuid-exit-plan-result',
          'message': <String, Object?>{
            'role': 'user',
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool_result',
                'tool_use_id': 'toolu_exit_plan',
                'is_error': true,
                'content': 'Plan approval denied',
              },
            ],
          },
        },
        runtimeScope: scope,
        runningTurnId: 'turn-plan',
      );

      expect(toolUse.events, isEmpty);
      expect(toolResult.events, isEmpty);
      expect(
        mapper.planApprovalAdapter.shouldSuppressToolResult('toolu_exit_plan'),
        isTrue,
      );
    });

    test('user non-tool_result content is dropped silently', () {
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);
      const sessionId = 'session-echo';
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'turn-echo',
      );

      final mapped = mapper.mapFrame(
        raw: <String, Object?>{
          'type': 'user',
          'session_id': sessionId,
          'uuid': 'uuid-echo',
          'message': <String, Object?>{
            'role': 'user',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'echoed user text'},
            ],
          },
        },
        runtimeScope: scope,
        runningTurnId: 'turn-echo',
      );

      expect(mapped.events, isEmpty);
    });

    test('unknown_type does not throw and later frames still map', () {
      final frames = _loadFixture('$fixturesRoot/unknown_type.jsonl');
      final mapper = ClaudeCodeEventMapper(providerId: 'claude_code');
      addTearDown(mapper.dispose);

      final sessionId = frames.first['session_id']! as String;
      mapper.beginTurn(
        runtimeScope: scope,
        sessionId: sessionId,
        turnId: 'turn-unknown',
      );

      final signatures = <String>[];
      expect(() {
        for (final frame in frames) {
          final mapped = mapper.mapFrame(
            raw: frame,
            runtimeScope: scope,
            runningTurnId: 'turn-unknown',
          );
          for (final event in mapped.events) {
            signatures.add(_canonicalSignature(event));
          }
        }
      }, returnsNormally);

      expect(mapper.unknownTypeDropped, greaterThanOrEqualTo(2));
      expect(
        signatures.any((s) => s.startsWith('AgentSessionStartedEvent|')),
        isTrue,
      );
      expect(
        signatures.any((s) => s.startsWith('AgentMessageUpdatedEvent|')),
        isTrue,
      );
      expect(
        signatures.any(
          (s) =>
              s.startsWith('AgentTurnCompletedEvent|') &&
              s.contains('status=completed'),
        ),
        isTrue,
      );
      expect(
        signatures.any(
          (s) =>
              s.startsWith('AgentTokenUsageEvent|') &&
              s.contains('cumulative=false'),
        ),
        isTrue,
      );
    });
  });
}

List<Map<String, Object?>> _loadFixture(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'missing fixture $path');
  final frames = <Map<String, Object?>>[];
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final decoded = jsonDecode(trimmed);
    expect(decoded, isA<Map>());
    frames.add(<String, Object?>{
      for (final entry in (decoded as Map).entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }
  expect(frames, isNotEmpty);
  return frames;
}

Map<String, Object?> _loadJsonObject(String path) =>
    _stringMap(jsonDecode(File(path).readAsStringSync()));

Map<String, Object?> _stringMap(Object? value) => (value! as Map).map(
  (key, item) => MapEntry(key.toString(), item as Object?),
);

/// 事件类型 + entryId/turnId + status 的 canonical 签名（逐位置比对用）。
String _canonicalSignature(AgentEvent event) {
  return switch (event) {
    AgentSessionStartedEvent(:final session) =>
      'AgentSessionStartedEvent|session=${session.id}',
    AgentThreadStatusChangedEvent(:final threadId, :final status) =>
      'AgentThreadStatusChangedEvent|thread=$threadId|status=${status.name}',
    AgentMessageDeltaEvent(:final messageId, :final status, :final role) =>
      'AgentMessageDeltaEvent|entry=$messageId|status=${status?.name ?? '-'}|role=${role.name}',
    AgentMessageUpdatedEvent(:final messageId, :final status, :final role) =>
      'AgentMessageUpdatedEvent|entry=$messageId|status=${status?.name ?? '-'}|role=${role?.name ?? '-'}',
    AgentReasoningDeltaEvent(:final itemId, :final kind) =>
      'AgentReasoningDeltaEvent|entry=$itemId|kind=${kind.name}',
    AgentToolCallEvent(:final toolCall) =>
      'AgentToolCallEvent|id=${toolCall.id}|status=${toolCall.status.name}|kind=${toolCall.kind.name}',
    AgentTokenUsageEvent(:final turnId, :final isSessionCumulative) =>
      'AgentTokenUsageEvent|turn=${turnId ?? '-'}|cumulative=$isSessionCumulative',
    AgentTurnCompletedEvent(:final turnId, :final status) =>
      'AgentTurnCompletedEvent|turn=$turnId|status=${status.name}',
    _ => 'UnknownEvent|${event.runtimeType}',
  };
}

AgentConversationEventProcessor _processor({
  required AgentConversationTimelineStore timeline,
  required String sessionId,
}) {
  return AgentConversationEventProcessor(
    reducer: AgentConversationReducer.live(),
    context: () => AgentConversationReducerContext(
      scope: AgentConversationReductionScope.live,
      selectedThreadId: sessionId,
      requiresResumedSelectedThread: false,
      pendingTurnGroupId: timeline.pendingTurnGroupId,
      hasTurn: timeline.hasTurn,
      isHistoryTurnId: timeline.isHistoryTurnId,
      modelsRefreshing: false,
      activeProviderName: 'Claude Code',
      activeProviderConfig: AgentProviderConfig.defaultClaudeCode,
      effectScope: AgentConversationEffectScope(
        reductionScope: AgentConversationReductionScope.live,
        providerId: defaultClaudeCodeProviderId,
        listenerGeneration: 1,
        runtimeId: 'claude-code-mapper-test',
        connectionEpoch: 1,
        threadId: sessionId,
      ),
    ),
    timeline: timeline,
    stateTarget: const _NoOpStateMutationTarget(),
    uiUpdates: const _NoOpUiUpdatePort(),
    effectRunner: const _NoOpEffectRunner(),
  );
}

final class _NoOpStateMutationTarget
    implements AgentConversationStateMutationTarget {
  const _NoOpStateMutationTarget();

  @override
  AgentConversationStateMutationOutcome apply(
    AgentConversationStateChange change,
  ) => AgentConversationStateMutationOutcome.none;

  @override
  void requestThreadSnapshotRefresh() {}
}

final class _NoOpUiUpdatePort implements AgentUiUpdatePort {
  const _NoOpUiUpdatePort();

  @override
  void publish(AgentUiUpdateRequest request) {}
}

final class _NoOpEffectRunner implements AgentConversationEffectRunner {
  const _NoOpEffectRunner();

  @override
  void dispose() {}

  @override
  void run(AgentConversationEffect effect) {}
}
