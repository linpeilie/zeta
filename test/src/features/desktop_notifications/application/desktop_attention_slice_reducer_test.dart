import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_intent.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_reducer.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('desktopAttentionSliceReduce', () {
    test('deduplicates one background identity and describes side effects', () {
      const attention = AgentWorkspaceAttention(
        signal: AgentAttentionSignal(
          kind: AgentAttentionKind.permissionRequired,
          phase: AgentAttentionPhase.raised,
          sourceId: 'request-1',
        ),
        providerId: 'codex',
        threadId: 'thread-1',
        projectPath: '/workspace',
      );
      final initialized = desktopAttentionSliceReduce(
        DesktopAttentionSliceState(),
        const DesktopAttentionInitialized(AgentNotificationSettings()),
      ).state;

      final first = desktopAttentionSliceReduce(
        initialized,
        const DesktopAttentionReceived(attention),
      );
      final duplicate = desktopAttentionSliceReduce(
        first.state,
        const DesktopAttentionReceived(attention),
      );

      expect(first.state.unreadCount, 1);
      expect(first.effects, hasLength(2));
      expect(first.effects.first, isA<DesktopAttentionSyncIndicatorEffect>());
      expect(first.effects.last, isA<DesktopAttentionShowNotificationEffect>());
      expect(duplicate.state, same(first.state));
      expect(duplicate.effects, isEmpty);
    });

    test(
      'visible thread removes unread and emits cancel plus indicator sync',
      () {
        const attention = AgentWorkspaceAttention(
          signal: AgentAttentionSignal(
            kind: AgentAttentionKind.turnCompleted,
            phase: AgentAttentionPhase.raised,
            sourceId: 'turn-1',
          ),
          providerId: 'codex',
          threadId: 'thread-1',
          projectPath: '/workspace',
        );
        final initialized = desktopAttentionSliceReduce(
          DesktopAttentionSliceState(),
          const DesktopAttentionInitialized(AgentNotificationSettings()),
        ).state;
        final unread = desktopAttentionSliceReduce(
          initialized,
          const DesktopAttentionReceived(attention),
        ).state;

        final transition = desktopAttentionSliceReduce(
          unread,
          const DesktopAttentionVisibilityChanged(
            DesktopAttentionVisibility(
              windowFocused: true,
              agentCanvasVisible: true,
              providerId: 'codex',
              threadId: 'thread-1',
            ),
          ),
        );

        expect(transition.state.unreadCount, 0);
        expect(
          transition.effects,
          containsAllInOrder(<Object>[
            isA<DesktopAttentionCancelNotificationsEffect>(),
            isA<DesktopAttentionSyncIndicatorEffect>(),
          ]),
        );
      },
    );
  });
}
