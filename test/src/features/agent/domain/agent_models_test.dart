import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentProviderConfig', () {
    test('normalizes the built-in Claude provider display name', () {
      expect(AgentProviderConfig.defaultClaudeCode.displayName, 'Claude');
      expect(
        AgentProviderConfig.normalizeDisplayName(
          defaultClaudeCodeProviderId,
          'Claude Code',
        ),
        'Claude',
      );
    });
  });

  group('Agent message identity contract', () {
    test('message events keep backward-compatible defaults', () {
      const delta = AgentMessageDeltaEvent(
        messageId: 'entry-1',
        delta: 'hello',
        role: AgentMessageRole.agent,
      );
      const updated = AgentMessageUpdatedEvent(messageId: 'entry-1');
      const reasoning = AgentReasoningDeltaEvent(
        itemId: 'reasoning-entry-1',
        kind: AgentReasoningDeltaKind.text,
      );

      expect(delta.kind, AgentMessageKind.regular);
      expect(delta.sourceMessageId, isNull);
      expect(updated.kind, AgentMessageKind.regular);
      expect(updated.sourceMessageId, isNull);
      expect(reasoning.sourceItemId, isNull);
    });

    test(
      'message events expose normalized and source identities separately',
      () {
        const delta = AgentMessageDeltaEvent(
          messageId: 'entry-1',
          sourceMessageId: 'provider-message-1',
          kind: AgentMessageKind.plan,
          delta: 'plan delta',
          role: AgentMessageRole.agent,
        );
        const updated = AgentMessageUpdatedEvent(
          messageId: 'entry-1',
          sourceMessageId: 'provider-message-1',
          kind: AgentMessageKind.plan,
          text: 'full plan',
        );
        const reasoning = AgentReasoningDeltaEvent(
          itemId: 'reasoning-entry-1',
          sourceItemId: 'provider-reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
        );

        expect(delta.messageId, 'entry-1');
        expect(delta.sourceMessageId, 'provider-message-1');
        expect(delta.kind, AgentMessageKind.plan);
        expect(updated.messageId, delta.messageId);
        expect(updated.sourceMessageId, delta.sourceMessageId);
        expect(updated.kind, delta.kind);
        expect(reasoning.itemId, 'reasoning-entry-1');
        expect(reasoning.sourceItemId, 'provider-reasoning-1');
      },
    );
  });

  group('AgentPlanEntry', () {
    test('normalizes provider plan status variants', () {
      expect(
        const AgentPlanEntry(
          content: 'Pending',
          status: 'pending',
        ).normalizedStatus,
        AgentPlanEntryStatus.pending,
      );
      expect(
        const AgentPlanEntry(
          content: 'Current',
          status: 'inProgress',
        ).normalizedStatus,
        AgentPlanEntryStatus.inProgress,
      );
      expect(
        const AgentPlanEntry(
          content: 'Current ACP',
          status: 'in_progress',
        ).normalizedStatus,
        AgentPlanEntryStatus.inProgress,
      );
      expect(
        const AgentPlanEntry(
          content: 'Done',
          status: 'completed',
        ).normalizedStatus,
        AgentPlanEntryStatus.completed,
      );
      expect(
        const AgentPlanEntry(
          content: 'Future',
          status: 'blocked',
        ).normalizedStatus,
        AgentPlanEntryStatus.unknown,
      );
    });
  });

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
