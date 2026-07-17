import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  const scope1 = AgentRuntimeScope(
    runtimeId: 'grok-runtime',
    connectionEpoch: 1,
  );

  group('GrokStreamIdentity isolation and diagnostics', () {
    test('keeps at most 512 (kind,eventId) keys per turn', () {
      final identity = GrokStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      for (var index = 0; index < 513; index++) {
        expect(
          identity.resolveMetadata(
            runtimeScope: scope1,
            sessionId: 'session-1',
            runningTurnId: 'turn-1',
            promptId: 'prompt-1',
            eventId: 'event-$index',
            eventKind: 'usage_update',
          ),
          isNotNull,
        );
      }

      final snapshot = identity.snapshot(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      )!;
      expect(snapshot.recentRawEventCount, 512);
    });

    test('connection epoch change rejects old epoch events', () {
      const scope2 = AgentRuntimeScope(
        runtimeId: 'grok-runtime',
        connectionEpoch: 2,
      );
      final identity = GrokStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      identity.beginTurn(
        runtimeScope: scope2,
        sessionId: 'session-1',
        turnId: 'turn-2',
      );

      final stale = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        promptId: 'prompt-1',
        sourceMessageId: 'source-A',
        eventId: 'event-old',
        eventKind: 'agent_message_chunk',
      );
      final current = identity.resolveMessage(
        runtimeScope: scope2,
        sessionId: 'session-1',
        runningTurnId: 'turn-2',
        promptId: 'prompt-2',
        sourceMessageId: 'source-A',
        eventId: 'event-new',
        eventKind: 'agent_message_chunk',
      );

      expect(stale, isNull);
      expect(current, isNotNull);
      expect(identity.diagnostics.missingTurnScopeDropped, 1);
    });

    test('peer close invalidation isolates the next runtime generation', () {
      const scope2 = AgentRuntimeScope(
        runtimeId: 'grok-runtime',
        connectionEpoch: 2,
      );
      final identity = GrokStreamIdentity();
      addTearDown(identity.dispose);
      identity.beginTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final oldMessage = identity.resolveMessage(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: 'turn-1',
        promptId: 'prompt-1',
        sourceMessageId: 'source-A',
        eventId: 'event-1',
        eventKind: 'agent_message_chunk',
      )!;
      identity.invalidateRuntime(
        runtimeScope: scope1,
        reason: GrokIdentityInvalidationReason.peerClosed,
      );
      identity.beginTurn(
        runtimeScope: scope2,
        sessionId: 'session-1',
        turnId: 'turn-2',
      );

      final newMessage = identity.resolveMessage(
        runtimeScope: scope2,
        sessionId: 'session-1',
        runningTurnId: 'turn-2',
        promptId: 'prompt-2',
        sourceMessageId: 'source-A',
        eventId: 'event-2',
        eventKind: 'agent_message_chunk',
      )!;

      expect(oldMessage.entryId, isNot(newMessage.entryId));
    });

    test('reused turn scope detects collision and disambiguates entryId', () {
      final identity = GrokStreamIdentity();
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
        promptId: 'prompt-1',
        sourceMessageId: 'source-A',
        eventId: 'event-1',
        eventKind: 'agent_message_chunk',
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
        promptId: 'prompt-2',
        sourceMessageId: 'source-A',
        eventId: 'event-2',
        eventKind: 'agent_message_chunk',
      )!;

      expect(first.entryId, isNot(second.entryId));
      expect(identity.diagnostics.identityCollisionDetected, greaterThan(0));
    });

    test('conflicting second terminal is diagnosed and ignored', () {
      final identity = GrokStreamIdentity();
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
        promptId: 'prompt-1',
        status: AgentHistoryTurnStatus.completed,
        source: GrokTerminalSource.standardNotification,
        eventId: 'terminal-1',
      );
      final second = identity.completeTurn(
        runtimeScope: scope1,
        sessionId: 'session-1',
        runningTurnId: null,
        promptId: 'prompt-1',
        status: AgentHistoryTurnStatus.failed,
        source: GrokTerminalSource.promptError,
        eventId: 'terminal-2',
      );

      expect(first.disposition, GrokTerminalDisposition.accepted);
      expect(second.disposition, GrokTerminalDisposition.conflicting);
      expect(second.status, AgentHistoryTurnStatus.completed);
      expect(identity.diagnostics.conflictingTerminalIgnored, 1);
    });
  });
}
