import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/cursor_acp_extension_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CursorAcpExtensionMapper', () {
    test('maps multi-select questions with stable option ids', () {
      final mapper = CursorAcpExtensionMapper();
      final request = mapper.mapAskQuestion(
        requestId: 7,
        params: <String, Object?>{
          'title': 'Choose scope',
          'questions': <Object?>[
            <String, Object?>{
              'id': 'scope',
              'prompt': 'What should change?',
              'allowMultiple': true,
              'options': <Object?>[
                <String, Object?>{'id': 'src', 'label': 'Source'},
                <String, Object?>{'id': 'test', 'label': 'Tests'},
              ],
            },
          ],
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      expect(request.id, '7');
      expect(request.kind, AgentPermissionKind.userInput);
      expect(request.questions.single.allowMultiple, isTrue);
      expect(
        request.questions.single.resolvedOptions.map((item) => item.id),
        <String>['src', 'test'],
      );
    });

    test('maps plan markdown, todos, and phases independently', () {
      final mapper = CursorAcpExtensionMapper();
      final request = mapper.mapCreatePlan(
        requestId: 'plan-1',
        params: <String, Object?>{
          'name': 'Refactor tabs',
          'overview': 'Preserve existing behavior.',
          'plan': '1. Inspect\n2. Update',
          'todos': <Object?>[
            <String, Object?>{
              'id': 'todo-1',
              'content': 'Inspect',
              'status': 'completed',
            },
          ],
          'phases': <Object?>[
            <String, Object?>{
              'name': 'Implementation',
              'todos': <Object?>[
                <String, Object?>{
                  'id': 'todo-2',
                  'content': 'Update',
                  'status': 'pending',
                },
              ],
            },
          ],
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      expect(request.title, 'Refactor tabs');
      expect(request.markdown, contains('Inspect'));
      expect(request.todos.single.id, 'todo-1');
      expect(request.phases.single.todos.single.id, 'todo-2');
    });

    test('merges todos and maps task and image notifications', () {
      final mapper = CursorAcpExtensionMapper();
      mapper.mapNotification(
        method: 'cursor/update_todos',
        params: <String, Object?>{
          'todos': <Object?>[
            <String, Object?>{
              'id': 'one',
              'content': 'First',
              'status': 'pending',
            },
          ],
          'merge': false,
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final merged = mapper.mapNotification(
        method: 'cursor/update_todos',
        params: <String, Object?>{
          'todos': <Object?>[
            <String, Object?>{
              'id': 'one',
              'content': 'First',
              'status': 'completed',
            },
            <String, Object?>{
              'id': 'two',
              'content': 'Second',
              'status': 'pending',
            },
          ],
          'merge': true,
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final task = mapper.mapNotification(
        method: 'cursor/task',
        params: <String, Object?>{
          'toolCallId': 'task-1',
          'description': 'Explore codebase',
          'prompt': 'Find auth code',
          'durationMs': 25,
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );
      final image = mapper.mapNotification(
        method: 'cursor/generate_image',
        params: <String, Object?>{
          'toolCallId': 'image-1',
          'description': 'App icon',
          'filePath': '/tmp/icon.png',
        },
        sessionId: 'session-1',
        turnId: 'turn-1',
      );

      final todos = merged.events.whereType<AgentPlanUpdatedEvent>().single;
      expect(todos.entries, hasLength(2));
      expect(todos.entries.first.status, 'completed');
      final taskCall = task.events
          .whereType<AgentToolCallEvent>()
          .single
          .toolCall;
      expect(taskCall.id, 'task-1');
      expect(taskCall.duration, const Duration(milliseconds: 25));
      final imageCall = image.events
          .whereType<AgentToolCallEvent>()
          .single
          .toolCall;
      expect(imageCall.locations, <String>['/tmp/icon.png']);
    });
  });
}
