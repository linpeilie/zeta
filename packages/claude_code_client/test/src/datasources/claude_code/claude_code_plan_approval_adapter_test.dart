import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_event_mapper.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_plan_approval_adapter.dart';
import 'package:test/test.dart';

void main() {
  const scope = AgentRuntimeScope(
    runtimeId: 'cc-plan-test',
    connectionEpoch: 1,
  );

  group('ClaudeCodePlanApprovalAdapter', () {
    test(
      'exit_plan_mode fixture emits one plan request and no tool lifecycle',
      () {
        final frames = _loadFixture(
          'test/src/datasources/claude_code/fixtures/exit_plan_mode.jsonl',
        );
        final adapter = ClaudeCodePlanApprovalAdapter();
        final mapper = ClaudeCodeEventMapper(
          providerId: 'claude_code',
          planApprovalAdapter: adapter,
        );
        addTearDown(mapper.dispose);
        const sessionId = '00000000-0000-4000-8000-000000000009';
        mapper.beginTurn(
          runtimeScope: scope,
          sessionId: sessionId,
          turnId: 'turn-plan',
        );

        final events = <AgentEvent>[];
        for (final frame in frames) {
          if (frame['type'] == 'control_request') {
            final control = adapter.handleControlRequest(frame);
            expect(control.handled, isTrue);
            expect(control.responseFrame, isNull);
            events.addAll(control.events);
            continue;
          }
          events.addAll(
            mapper
                .mapFrame(
                  raw: frame,
                  runtimeScope: scope,
                  runningTurnId: 'turn-plan',
                )
                .events,
          );
        }

        expect(events.whereType<AgentToolCallEvent>(), isEmpty);
        final approval = events
            .whereType<AgentPlanApprovalRequestedEvent>()
            .single
            .request;
        expect(approval.id, 'toolu_fixture_exit_plan');
        expect(approval.sessionId, sessionId);
        expect(approval.turnId, 'turn-plan');
        expect(approval.markdown, '[redacted plan prose]');
        expect(
          approval.continuation,
          AgentPlanApprovalContinuation.localExecutionHandoff,
        );
        expect(approval.raw, <String, Object?>{
          'source': 'claude_code.exit_plan_mode',
          'tool_name': 'ExitPlanMode',
        });
        expect(approval.raw, isNot(contains('input')));
        expect(adapter.pendingCount, 0, reason: 'result terminal clears turn');
      },
    );

    test(
      'tool_use_id pairs plan while request_id is reserved for response',
      () {
        final adapter = _adapterWithObservedPlan(
          input: <String, Object?>{
            'plan': 'Use the verified plan',
            'planFilePath': r'C:\redacted\plan.md',
          },
        );
        final control = adapter.handleControlRequest(
          _controlRequest(
            requestId: 'req-plan-1',
            toolUseId: 'toolu-plan-1',
            input: <String, Object?>{
              'plan': 'Use the verified plan',
              'planFilePath': r'C:\redacted\plan.md',
            },
          ),
        );

        expect(control.handled, isTrue);
        final approval =
            (control.events.single as AgentPlanApprovalRequestedEvent).request;
        expect(approval.id, 'toolu-plan-1');
        expect(approval.markdown, 'Use the verified plan');
        expect(adapter.pendingCount, 1);

        final resolved = adapter.resolveDecision(
          const AgentPlanApprovalDecision(
            requestId: 'toolu-plan-1',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        );
        expect(resolved, isNotNull);
        expect(resolved!.interruptTurn, isTrue);
        final envelope =
            resolved.responseFrame['response']! as Map<String, Object?>;
        expect(envelope['subtype'], 'success');
        expect(envelope['request_id'], 'req-plan-1');
        final body = envelope['response']! as Map<String, Object?>;
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], <String, Object?>{
          'plan': 'Use the verified plan',
          'planFilePath': r'C:\redacted\plan.md',
        });
        expect(adapter.pendingCount, 0);
      },
    );

    test('rejected plan returns nested deny with revision reason', () {
      final adapter = _adapterWithObservedPlan()
        ..handleControlRequest(
          _controlRequest(
            requestId: 'req-plan-reject',
            toolUseId: 'toolu-plan-1',
          ),
        );

      final resolved = adapter.resolveDecision(
        const AgentPlanApprovalDecision(
          requestId: 'toolu-plan-1',
          kind: AgentPlanApprovalDecisionKind.rejected,
          reason: 'Please revise the second step',
        ),
      );

      expect(resolved, isNotNull);
      expect(resolved!.interruptTurn, isFalse);
      final envelope =
          resolved.responseFrame['response']! as Map<String, Object?>;
      expect(envelope['request_id'], 'req-plan-reject');
      final body = envelope['response']! as Map<String, Object?>;
      expect(body, <String, Object?>{
        'behavior': 'deny',
        'message': 'Please revise the second step',
      });
    });

    test('cancelled plan denies and asks provider to interrupt turn', () {
      final adapter = _adapterWithObservedPlan()
        ..handleControlRequest(
          _controlRequest(
            requestId: 'req-plan-cancel',
            toolUseId: 'toolu-plan-1',
          ),
        );

      final resolved = adapter.resolveDecision(
        const AgentPlanApprovalDecision(
          requestId: 'toolu-plan-1',
          kind: AgentPlanApprovalDecisionKind.cancelled,
        ),
      );

      expect(resolved, isNotNull);
      expect(resolved!.interruptTurn, isTrue);
      final envelope =
          resolved.responseFrame['response']! as Map<String, Object?>;
      final body = envelope['response']! as Map<String, Object?>;
      expect(body['behavior'], 'deny');
      expect(body['message'], 'User cancelled plan approval');
    });

    test('ordinary tool control request stays on permission route', () {
      final adapter = ClaudeCodePlanApprovalAdapter();

      final result = adapter.handleControlRequest(<String, Object?>{
        'type': 'control_request',
        'request_id': 'req-bash',
        'request': <String, Object?>{
          'subtype': 'can_use_tool',
          'tool_use_id': 'toolu-bash',
          'tool_name': 'Bash',
          'input': <String, Object?>{'command': 'echo redacted'},
        },
      });

      expect(result.handled, isFalse);
      expect(result.events, isEmpty);
      expect(result.responseFrame, isNull);
    });

    test('unmatched ExitPlanMode is fail-closed without permission event', () {
      final adapter = ClaudeCodePlanApprovalAdapter();

      final result = adapter.handleControlRequest(
        _controlRequest(
          requestId: 'req-unmatched',
          toolUseId: 'toolu-unmatched',
        ),
      );

      expect(result.handled, isTrue);
      expect(result.events, isEmpty);
      final envelope =
          result.responseFrame!['response']! as Map<String, Object?>;
      expect(envelope['subtype'], 'error');
      expect(envelope['request_id'], 'req-unmatched');
      expect(adapter.pendingCount, 0);
    });
  });
}

ClaudeCodePlanApprovalAdapter _adapterWithObservedPlan({
  Map<String, Object?> input = const <String, Object?>{},
}) {
  return ClaudeCodePlanApprovalAdapter()
    ..beginTurn(sessionId: 'session-plan-1', turnId: 'turn-plan-1')
    ..recordAssistantText(
      sessionId: 'session-plan-1',
      turnId: 'turn-plan-1',
      text: 'Fallback plan text',
    )
    ..recordExitPlanToolUse(
      toolUseId: 'toolu-plan-1',
      input: input,
      sessionId: 'session-plan-1',
      turnId: 'turn-plan-1',
    );
}

Map<String, Object?> _controlRequest({
  required String requestId,
  required String toolUseId,
  Map<String, Object?> input = const <String, Object?>{},
}) {
  return <String, Object?>{
    'type': 'control_request',
    'request_id': requestId,
    'request': <String, Object?>{
      'subtype': 'can_use_tool',
      'tool_use_id': toolUseId,
      'tool_name': 'ExitPlanMode',
      'input': input,
    },
  };
}

List<Map<String, Object?>> _loadFixture(String path) {
  final frames = <Map<String, Object?>>[];
  for (final line in File(path).readAsLinesSync()) {
    final normalized = line.trim();
    if (normalized.isEmpty || normalized.startsWith('#')) {
      continue;
    }
    final decoded = jsonDecode(normalized) as Map;
    frames.add(<String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }
  return frames;
}
