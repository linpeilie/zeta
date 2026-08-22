import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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
      expect(formatAgentDuration(Duration.zero, includeSubSecond: true), '0s');
    });

    test('formats sub-second with one decimal ceil', () {
      // 1–100ms → 0.1s
      expect(formatAgentDuration(const Duration(milliseconds: 1)), '0.1s');
      expect(formatAgentDuration(const Duration(milliseconds: 100)), '0.1s');
      // 101–200ms → 0.2s（向上取整）
      expect(formatAgentDuration(const Duration(milliseconds: 101)), '0.2s');
      expect(formatAgentDuration(const Duration(milliseconds: 350)), '0.4s');
      expect(formatAgentDuration(const Duration(milliseconds: 900)), '0.9s');
      // 901–999ms → 1s
      expect(formatAgentDuration(const Duration(milliseconds: 999)), '1s');
      // live 活动条同样规则
      expect(
        formatAgentDuration(
          const Duration(milliseconds: 40),
          includeSubSecond: true,
        ),
        '0.1s',
      );
    });
  });

  group('activitySegmentLabel', () {
    test('builds segment labels', () {
      const catalog = FallbackAgentUiTextCatalog();
      expect(
        catalog.activitySegmentLabel(
          const AgentTurnActivitySnapshot(
            phase: AgentTurnActivityPhase.thinking,
          ),
        ),
        '思考中',
      );
      expect(
        catalog.activitySegmentLabel(
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
