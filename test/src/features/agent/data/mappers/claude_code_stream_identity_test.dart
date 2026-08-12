import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  const scope1 = AgentRuntimeScope(runtimeId: 'cc-runtime', connectionEpoch: 1);

  group('ClaudeCodeStreamIdentity §3.B rows 1–6', () {
    test('1 same message.id continuous text blocks share entryId', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final first = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_fixture_1',
        eventId: 'evt-1',
        eventKind: 'assistant.text',
      )!;
      final second = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_fixture_1',
        eventId: 'evt-2',
        eventKind: 'assistant.text',
      )!;

      expect(first.entryId, second.entryId);
      expect(first.turnId, 'turn-1');
    });

    test('2 tool_use then text opens a new message entryId', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final beforeTool = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_fixture_1',
        eventId: 'evt-1',
        eventKind: 'assistant.text',
      )!;
      final tool = identity.resolveTool(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        toolCallId: 'toolu_1',
        eventId: 'evt-tool',
        eventKind: 'assistant.tool_use',
      )!;
      final afterTool = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_fixture_1',
        eventId: 'evt-2',
        eventKind: 'assistant.text',
      )!;

      expect(tool.isNewTool, isTrue);
      expect(afterTool.entryId, isNot(beforeTool.entryId));
    });

    test('3 duplicate raw event is dropped', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final first = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'same-frame',
        eventKind: 'assistant.text',
      );
      final second = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'same-frame',
        eventKind: 'assistant.text',
      );

      expect(first, isNotNull);
      expect(second, isNull);
      expect(identity.diagnostics.duplicateRawEventDropped, 1);
    });

    test('4 late assistant content after result is dropped', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final terminal = identity.completeTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        source: ClaudeCodeTerminalSource.resultFrame,
        eventId: 'result-1',
      );
      final late = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_late',
        eventId: 'evt-late',
        eventKind: 'assistant.text',
      );

      expect(terminal.accepted, isTrue);
      expect(late, isNull);
      expect(identity.diagnostics.lateContentDropped, 1);
    });

    test(
      '5 two results: same status is duplicate, different is conflicting',
      () {
        final identity = ClaudeCodeStreamIdentity();
        addTearDown(identity.dispose);
        identity.beginTurn(
          runtimeScope: scope1,
          sessionId: 'session-1',
          turnId: 'turn-1',
        );

        final first = identity.completeTurn(
          runtimeScope: scope1,
          sessionId: 'session-1',
          runningTurnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          source: ClaudeCodeTerminalSource.resultFrame,
          eventId: 'result-1',
        );
        final sameStatus = identity.completeTurn(
          runtimeScope: scope1,
          sessionId: 'session-1',
          runningTurnId: 'turn-1',
          status: AgentHistoryTurnStatus.completed,
          source: ClaudeCodeTerminalSource.resultFrame,
          eventId: 'result-2',
        );
        final conflict = identity.completeTurn(
          runtimeScope: scope1,
          sessionId: 'session-1',
          runningTurnId: 'turn-1',
          status: AgentHistoryTurnStatus.failed,
          source: ClaudeCodeTerminalSource.providerError,
          eventId: 'result-3',
        );

        expect(first.disposition, ClaudeCodeTerminalDisposition.accepted);
        expect(sameStatus.disposition, ClaudeCodeTerminalDisposition.duplicate);
        expect(sameStatus.status, AgentHistoryTurnStatus.completed);
        expect(conflict.disposition, ClaudeCodeTerminalDisposition.conflicting);
        expect(conflict.status, AgentHistoryTurnStatus.completed);
        expect(identity.diagnostics.terminalAccepted, 1);
        expect(identity.diagnostics.duplicateTerminalIgnored, 1);
        expect(identity.diagnostics.conflictingTerminalIgnored, 1);
      },
    );

    test('6 interrupt then result keeps first terminal only', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final interrupt = identity.completeTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        status: AgentHistoryTurnStatus.interrupted,
        source: ClaudeCodeTerminalSource.interrupt,
        eventId: 'interrupt-1',
        eventKind: 'control.interrupt',
      );
      final result = identity.completeTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        source: ClaudeCodeTerminalSource.resultFrame,
        eventId: 'result-1',
      );

      expect(interrupt.accepted, isTrue);
      expect(result.disposition, ClaudeCodeTerminalDisposition.conflicting);
      expect(result.status, AgentHistoryTurnStatus.interrupted);
      expect(identity.diagnostics.terminalAccepted, 1);
      expect(identity.diagnostics.conflictingTerminalIgnored, 1);
    });

    test('7 thinking → text → thinking yields two reasoning phases', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final think1 = identity.resolveReasoning(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceItemId: 'msg_inter',
        eventId: 'r1',
        eventKind: 'assistant.thinking',
      )!;
      final think1b = identity.resolveReasoning(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceItemId: 'msg_inter',
        eventId: 'r1b',
        eventKind: 'assistant.thinking',
      )!;
      final text = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_inter',
        eventId: 't1',
        eventKind: 'assistant.text',
      )!;
      final think2 = identity.resolveReasoning(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceItemId: 'msg_inter',
        eventId: 'r2',
        eventKind: 'assistant.thinking',
      )!;

      expect(think1.entryId, think1b.entryId);
      expect(think2.entryId, isNot(think1.entryId));
      expect(text.entryId, isNot(think1.entryId));
      expect(text.entryId, isNot(think2.entryId));

      final snap = identity.snapshot(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      )!;
      expect(snap.reasoningPhaseOrdinal, 2);
      expect(snap.messageSegmentOrdinal, 1);
    });

    test('8 late tool_result for known tool is accepted after terminal', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final start = identity.resolveTool(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        toolCallId: 'toolu_known',
        eventId: 'tool-start',
        eventKind: 'assistant.tool_use',
      )!;
      expect(start.isNewTool, isTrue);

      identity.completeTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        status: AgentHistoryTurnStatus.completed,
        source: ClaudeCodeTerminalSource.resultFrame,
        eventId: 'result-1',
      );

      final late = identity.resolveTool(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        toolCallId: 'toolu_known',
        eventId: 'tool-result-late',
        eventKind: 'user.tool_result',
      );
      final unknownLate = identity.resolveTool(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        toolCallId: 'toolu_unknown',
        eventId: 'tool-unknown',
        eventKind: 'user.tool_result',
      );

      expect(late, isNotNull);
      expect(late!.isNewTool, isFalse);
      expect(unknownLate, isNull);
      expect(identity.diagnostics.lateEventDropped, 1);
    });

    test('9 cross turn / session / runtime drops stale events', () {
      const scope2 = AgentRuntimeScope(
        runtimeId: 'cc-runtime',
        connectionEpoch: 2,
      );
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);

      // Cross turn：新 turn 使旧 turn tombstone 失效
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final t1 = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'e1',
        eventKind: 'assistant.text',
      )!;
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-2',
      );
      final staleTurn = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'e-stale-turn',
        eventKind: 'assistant.text',
      );
      final t2 = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-2',
        sourceMessageId: 'msg_a',
        eventId: 'e2',
        eventKind: 'assistant.text',
      )!;
      expect(staleTurn, isNull);
      expect(t2.entryId, isNot(t1.entryId));

      // Cross session：显式 invalidateSession 后旧 session 全部丢弃
      identity.invalidateSession(
        runtimeScope: scope1,
        sessionId: 'session-1',
        reason: ClaudeCodeIdentityInvalidationReason.sessionSwitched,
      );
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-2',
        turnId: 'turn-s2',
      );
      final staleSession = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-2',
        sourceMessageId: 'msg_a',
        eventId: 'e-cross-session',
        eventKind: 'assistant.text',
      );
      expect(staleSession, isNull);

      // Cross runtime epoch
      identity.beginTurn(
        runtimeScope: scope2,
        sessionId: 'session-2',
        turnId: 'turn-3',
      );
      final staleRuntime = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-2',
        runningTurnId: 'turn-s2',
        sourceMessageId: 'msg_a',
        eventId: 'e-stale-runtime',
        eventKind: 'assistant.text',
      );
      final currentRuntime = identity.resolveMessage(
        runtimeScope: scope2,
        sessionId: 'session-2',
        runningTurnId: 'turn-3',
        sourceMessageId: 'msg_a',
        eventId: 'e3',
        eventKind: 'assistant.text',
      );

      expect(staleRuntime, isNull);
      expect(currentRuntime, isNotNull);
      expect(identity.diagnostics.missingTurnScopeDropped, greaterThan(0));
    });

    test('10 entryId collision gets generation suffix', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);

      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'reused-turn',
      );
      final first = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'reused-turn',
        sourceMessageId: 'source-A',
        eventId: 'event-1',
        eventKind: 'assistant.text',
      )!;

      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'reused-turn',
      );
      final second = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'reused-turn',
        sourceMessageId: 'source-A',
        eventId: 'event-2',
        eventKind: 'assistant.text',
      )!;

      expect(first.entryId, isNot(second.entryId));
      expect(second.entryId, contains(':g'));
      expect(identity.diagnostics.identityCollisionDetected, greaterThan(0));
    });

    test('11 diagnostics and snapshot omit secrets (G7)', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-secret-id',
        turnId: 'turn-secret-id',
      );
      identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-secret-id',
        runningTurnId: 'turn-secret-id',
        sourceMessageId: 'msg_SOURCE_SECRET_xyz',
        eventId: 'evt-1',
        eventKind: 'assistant.text',
      );
      identity.resolveReasoning(
        runtimeScope: scope1,
        sessionId: 'session-secret-id',
        runningTurnId: 'turn-secret-id',
        sourceItemId: 'msg_SOURCE_SECRET_xyz',
        eventId: 'evt-r',
        eventKind: 'assistant.thinking',
      );

      final snap = identity.snapshot(
        runtimeScope: scope1,
        sessionId: 'session-secret-id',
        turnId: 'turn-secret-id',
      )!;
      final diag = identity.diagnostics;
      final banned = <String>[
        'msg_SOURCE_SECRET_xyz',
        'session-secret-id',
        'turn-secret-id',
        'token',
        'prompt',
        'payload',
      ];
      for (final secret in banned) {
        expect(diag.toString(), isNot(contains(secret)));
        expect(snap.toString(), isNot(contains(secret)));
      }
      expect(snap.sourceMessageEntryCount, 1);
      expect(snap.recentRawEventCount, greaterThan(0));
    });

    test('recentRawEventKeys window is bounded', () {
      final identity = ClaudeCodeStreamIdentity(maxRecentRawEvents: 8);
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      for (var i = 0; i < 12; i++) {
        identity.resolveMetadata(
          runtimeScope: scope1,
          sessionId: 'session-1',
          runningTurnId: 'turn-1',
          eventId: 'meta-$i',
          eventKind: 'usage',
        );
      }
      final snap = identity.snapshot(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      )!;
      expect(snap.recentRawEventCount, 8);
    });

    test('closeVisiblePhases forces new message segment', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final a = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'e1',
        eventKind: 'assistant.text',
      )!;
      expect(
        identity.closeVisiblePhases(
          runtimeScope: scope1,
          sessionId: 'session-1',
          runningTurnId: 'turn-1',
        ),
        isTrue,
      );
      final b = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_a',
        eventId: 'e2',
        eventKind: 'assistant.text',
      )!;
      expect(b.entryId, isNot(a.entryId));
    });

    test('partial and whole text paths share entryId (B2)', () {
      final identity = ClaudeCodeStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final delta = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_same',
        eventId: 'partial-1',
        eventKind: 'assistant.text_delta',
      )!;
      final whole = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        sourceMessageId: 'msg_same',
        eventId: 'whole-1',
        eventKind: 'assistant.text',
      )!;
      expect(delta.entryId, whole.entryId);
    });
  });
}
