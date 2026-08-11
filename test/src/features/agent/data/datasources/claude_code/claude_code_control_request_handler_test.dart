import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_control_request_handler.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('ClaudeCodeControlRequestHandler', () {
    late ClaudeCodeControlRequestHandler handler;

    setUp(() {
      handler = ClaudeCodeControlRequestHandler();
    });

    Map<String, Object?> canUseToolFrame({
      required String requestId,
      String toolName = 'Bash',
      Map<String, Object?>? input,
    }) {
      return <String, Object?>{
        'type': 'control_request',
        'request_id': requestId,
        'request': <String, Object?>{
          'type': 'can_use_tool',
          'tool_name': toolName,
          'input': input ?? <String, Object?>{'command': 'echo hi'},
        },
      };
    }

    test(
      'can_use_tool emits AgentPermissionRequestedEvent with turn identity',
      () {
        final result = handler.handle(
          canUseToolFrame(requestId: 'req_42'),
          sessionId: 'session-a',
          turnId: 'turn-7',
          cwd: r'C:\tmp\proj',
        );

        expect(result.responseFrame, isNull);
        expect(result.events, hasLength(1));
        final event = result.events.single as AgentPermissionRequestedEvent;
        expect(event.request.id, 'req_42');
        expect(event.request.sessionId, 'session-a');
        expect(event.request.turnId, 'turn-7');
        expect(event.request.kind, AgentPermissionKind.commandExecution);
        expect(event.request.command, 'echo hi');
        expect(event.request.cwd, r'C:\tmp\proj');
        expect(event.request.raw['tool_name'], 'Bash');
        // G8: raw 不含 input 正文。
        expect(event.request.raw.containsKey('input'), isFalse);
        expect(handler.pendingCount, 1);
        expect(handler.permissionRequestedCount, 1);
        expect(handler.deniedCount, 0);
      },
    );

    test('stub auto-deny path is gone for can_use_tool', () {
      final result = handler.handle(canUseToolFrame(requestId: 'req_live'));
      expect(result.responseFrame, isNull);
      expect(
        result.events.whereType<AgentPermissionRequestedEvent>(),
        hasLength(1),
      );
      expect(handler.deniedCount, 0);
    });

    group('four decision wire shapes', () {
      const toolInput = <String, Object?>{'command': 'ls'};

      Map<String, Object?> responseBody(Map<String, Object?> frame) {
        return frame['response']! as Map<String, Object?>;
      }

      test('allow_once → behavior allow + updatedInput', () {
        handler.handle(
          canUseToolFrame(requestId: 'req_allow_once', input: toolInput),
          sessionId: 's1',
          turnId: 't1',
        );
        final resolved = handler.resolveDecision(
          const AgentPermissionDecision(
            requestId: 'req_allow_once',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.accept,
          ),
        );
        expect(resolved, isNotNull);
        expect(resolved!.outcome, ClaudeCodeToolPermissionOutcome.allowOnce);
        expect(resolved.toolName, 'Bash');
        final frame = resolved.responseFrame;
        expect(frame['type'], 'control_response');
        expect(frame['request_id'], 'req_allow_once');
        final body = responseBody(frame);
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], toolInput);
        expect(body.containsKey('message'), isFalse);
        expect(handler.pendingCount, 0);
        expect(handler.resolvedCount, 1);
      });

      test('allow_always → behavior allow + updatedInput', () {
        handler.handle(
          canUseToolFrame(requestId: 'req_allow_always', input: toolInput),
        );
        final resolved = handler.resolveDecision(
          const AgentPermissionDecision(
            requestId: 'req_allow_always',
            approved: true,
            commandDecision: AgentCommandApprovalDecisionKind.acceptForSession,
          ),
        );
        expect(resolved, isNotNull);
        expect(resolved!.outcome, ClaudeCodeToolPermissionOutcome.allowAlways);
        final body = responseBody(resolved.responseFrame);
        expect(body['behavior'], 'allow');
        expect(body['updatedInput'], toolInput);
      });

      test('deny_once → behavior deny + message', () {
        handler.handle(canUseToolFrame(requestId: 'req_deny_once'));
        final resolved = handler.resolveDecision(
          const AgentPermissionDecision(
            requestId: 'req_deny_once',
            approved: false,
            commandDecision: AgentCommandApprovalDecisionKind.decline,
            message: 'Not this time',
          ),
        );
        expect(resolved, isNotNull);
        expect(resolved!.outcome, ClaudeCodeToolPermissionOutcome.denyOnce);
        final frame = resolved.responseFrame;
        expect(frame['type'], 'control_response');
        expect(frame['request_id'], 'req_deny_once');
        final body = responseBody(frame);
        expect(body['behavior'], 'deny');
        expect(body['message'], 'Not this time');
        expect(body.containsKey('updatedInput'), isFalse);
      });

      test('deny_always → behavior deny + default message', () {
        handler.handle(canUseToolFrame(requestId: 'req_deny_always'));
        final resolved = handler.resolveDecision(
          const AgentPermissionDecision(
            requestId: 'req_deny_always',
            approved: false,
            cancelTurn: true,
            commandDecision: AgentCommandApprovalDecisionKind.cancel,
          ),
        );
        expect(resolved, isNotNull);
        expect(resolved!.outcome, ClaudeCodeToolPermissionOutcome.denyAlways);
        final body = responseBody(resolved.responseFrame);
        expect(body['behavior'], 'deny');
        expect(body['message'], 'User denied tool use for this session');
        expect(body.containsKey('updatedInput'), isFalse);
      });
    });

    test('mapDecisionOutcome covers approved/cancelTurn fallbacks', () {
      expect(
        ClaudeCodeControlRequestHandler.mapDecisionOutcome(
          const AgentPermissionDecision(requestId: 'a', approved: true),
        ),
        ClaudeCodeToolPermissionOutcome.allowOnce,
      );
      expect(
        ClaudeCodeControlRequestHandler.mapDecisionOutcome(
          const AgentPermissionDecision(requestId: 'b', approved: false),
        ),
        ClaudeCodeToolPermissionOutcome.denyOnce,
      );
      expect(
        ClaudeCodeControlRequestHandler.mapDecisionOutcome(
          const AgentPermissionDecision(
            requestId: 'c',
            approved: false,
            cancelTurn: true,
          ),
        ),
        ClaudeCodeToolPermissionOutcome.denyAlways,
      );
    });

    test('buildControlResponse field shapes for all four outcomes', () {
      const input = <String, Object?>{'file_path': '/tmp/x'};
      for (final outcome in ClaudeCodeToolPermissionOutcome.values) {
        final frame = ClaudeCodeControlRequestHandler.buildControlResponse(
          requestId: 'req_${outcome.name}',
          outcome: outcome,
          toolInput: input,
        );
        expect(frame['type'], 'control_response');
        expect(frame['request_id'], 'req_${outcome.name}');
        final body = frame['response']! as Map<String, Object?>;
        switch (outcome) {
          case ClaudeCodeToolPermissionOutcome.allowOnce:
          case ClaudeCodeToolPermissionOutcome.allowAlways:
            expect(body['behavior'], 'allow');
            expect(body['updatedInput'], input);
          case ClaudeCodeToolPermissionOutcome.denyOnce:
          case ClaudeCodeToolPermissionOutcome.denyAlways:
            expect(body['behavior'], 'deny');
            expect(body['message'], isA<String>());
        }
      }
    });

    test('unknown request type is still fail-closed denied', () {
      final result = handler.handle(<String, Object?>{
        'type': 'control_request',
        'request_id': 'req_other',
        'request': <String, Object?>{'type': 'unknown_control'},
      });

      expect(result.events, isEmpty);
      expect(result.responseFrame, isNotNull);
      expect(result.responseFrame!['request_id'], 'req_other');
      final body = result.responseFrame!['response']! as Map<String, Object?>;
      expect(body['behavior'], 'deny');
      expect(handler.deniedCount, 1);
      expect(handler.pendingCount, 0);
    });

    test('missing request_id is counted malformed and still denies', () {
      final result = handler.handle(<String, Object?>{
        'type': 'control_request',
        'request': <String, Object?>{
          'type': 'can_use_tool',
          'tool_name': 'Bash',
        },
      });

      expect(result.responseFrame!['type'], 'control_response');
      final body = result.responseFrame!['response']! as Map<String, Object?>;
      expect(body['behavior'], 'deny');
      expect(handler.malformedCount, 1);
      expect(result.events, isEmpty);
    });

    test('resolveDecision on unknown id returns null', () {
      final resolved = handler.resolveDecision(
        const AgentPermissionDecision(requestId: 'ghost', approved: true),
      );
      expect(resolved, isNull);
      expect(handler.unknownDecisionCount, 1);
    });

    test('deny/allow response does not leak secret into deny message path', () {
      const secret = 'super-secret-token-value';
      handler.handle(
        canUseToolFrame(
          requestId: 'req_secret',
          input: <String, Object?>{'command': secret},
        ),
      );
      final denied = handler.resolveDecision(
        const AgentPermissionDecision(requestId: 'req_secret', approved: false),
      );
      final encoded = denied!.responseFrame.toString();
      // deny 路径不得回显 command/input。
      expect(encoded, isNot(contains(secret)));
      expect(encoded, isNot(contains('command')));
    });

    test('Edit tool maps to fileChange kind', () {
      final result = handler.handle(
        canUseToolFrame(
          requestId: 'req_edit',
          toolName: 'Edit',
          input: <String, Object?>{'file_path': '/tmp/a'},
        ),
        sessionId: 's',
        turnId: 't',
      );
      final event = result.events.single as AgentPermissionRequestedEvent;
      expect(event.request.kind, AgentPermissionKind.fileChange);
      expect(event.request.sessionId, 's');
      expect(event.request.turnId, 't');
    });

    test('clearPending drops waiting requests', () {
      handler.handle(canUseToolFrame(requestId: 'req_1'));
      handler.handle(canUseToolFrame(requestId: 'req_2'));
      expect(handler.pendingCount, 2);
      handler.clearPending();
      expect(handler.pendingCount, 0);
      expect(
        handler.resolveDecision(
          const AgentPermissionDecision(requestId: 'req_1', approved: true),
        ),
        isNull,
      );
    });
  });
}
