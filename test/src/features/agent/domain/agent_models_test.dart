import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentThreadSummary', () {
    test('normalizes display name from title, preview, and id', () {
      final baseTime = DateTime.fromMillisecondsSinceEpoch(1);

      expect(
        AgentThreadSummary(
          id: 'thread-123456',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          title: 'Named thread',
          preview: 'Preview text',
          createdAt: baseTime,
          updatedAt: baseTime,
          status: AgentThreadRuntimeStatus.idle,
        ).displayName,
        'Named thread',
      );
      expect(
        AgentThreadSummary(
          id: 'thread-123456',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: 'Preview text',
          createdAt: baseTime,
          updatedAt: baseTime,
          status: AgentThreadRuntimeStatus.idle,
        ).displayName,
        'Preview text',
      );
      expect(
        AgentThreadSummary(
          id: 'thread-123456',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: '',
          createdAt: baseTime,
          updatedAt: baseTime,
          status: AgentThreadRuntimeStatus.idle,
        ).displayName,
        'thread-1',
      );
    });

    test('uses recency time before updated time for last active time', () {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(2000);
      final recencyAt = DateTime.fromMillisecondsSinceEpoch(3000);

      expect(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: '',
          createdAt: createdAt,
          updatedAt: updatedAt,
          recencyAt: recencyAt,
          status: AgentThreadRuntimeStatus.idle,
        ).lastActiveAt,
        recencyAt,
      );
      expect(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: '',
          createdAt: createdAt,
          updatedAt: updatedAt,
          status: AgentThreadRuntimeStatus.idle,
        ).lastActiveAt,
        updatedAt,
      );
    });

    test('decodes session path from current and legacy cache payloads', () {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(1);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(2);

      final current = AgentThreadSummary.tryDecode(<String, Object?>{
        'id': 'thread-1',
        'providerId': defaultAgentProviderId,
        'projectPath': '/repo',
        'sessionPath': '/tmp/current.jsonl',
        'preview': 'Preview',
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'status': AgentThreadRuntimeStatus.idle.name,
        'raw': const <String, Object?>{},
      });
      expect(current?.sessionPath, '/tmp/current.jsonl');

      final legacy = AgentThreadSummary.tryDecode(<String, Object?>{
        'id': 'thread-2',
        'providerId': defaultAgentProviderId,
        'projectPath': '/repo',
        'preview': 'Preview',
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'status': AgentThreadRuntimeStatus.idle.name,
        'raw': const <String, Object?>{'path': '/tmp/legacy.jsonl'},
      });
      expect(legacy?.sessionPath, '/tmp/legacy.jsonl');
    });
  });
}
