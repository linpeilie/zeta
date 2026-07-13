import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_activity_models.dart';

void main() {
  group('resolveAgentElapsed', () {
    test('prefers frozen duration over wall clock', () {
      final now = DateTime(2026, 1, 1, 12, 0, 30);
      final started = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        resolveAgentElapsed(
          now: now,
          startedAt: started,
          frozenDuration: const Duration(seconds: 9),
        ),
        const Duration(seconds: 9),
      );
    });

    test('uses startedAt to now when live', () {
      final now = DateTime(2026, 1, 1, 12, 0, 12);
      final started = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        resolveAgentElapsed(now: now, startedAt: started),
        const Duration(seconds: 12),
      );
    });
  });

  group('formatAgentDuration', () {
    test('formats seconds and minutes', () {
      expect(formatAgentDuration(const Duration(seconds: 12)), '12s');
      expect(formatAgentDuration(const Duration(seconds: 65)), '1m 5s');
      expect(formatAgentDuration(Duration.zero), isNull);
      expect(formatAgentDuration(Duration.zero, includeSubSecond: true), '<1s');
    });
  });

  group('agentActivitySegmentLabel', () {
    test('builds segment labels', () {
      expect(
        agentActivitySegmentLabel(
          const AgentTurnActivitySnapshot(
            phase: AgentTurnActivityPhase.thinking,
          ),
        ),
        '思考中',
      );
      expect(
        agentActivitySegmentLabel(
          const AgentTurnActivitySnapshot(
            phase: AgentTurnActivityPhase.toolRunning,
            label: 'git status',
          ),
        ),
        '执行中 · git status',
      );
    });
  });
}
