import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

void main() {
  group('AgentUsagePanelEntry.compactQuotaWindow', () {
    test('selects the shortest positive window for a paid plan', () {
      final weekly = _window('weekly', const Duration(days: 7));
      final hourly = _window('hourly', const Duration(hours: 1));
      final daily = _window('daily', const Duration(days: 1));
      final entry = _entry(windows: <AgentUsageWindow>[weekly, hourly, daily]);

      expect(entry.compactQuotaWindow, same(hourly));
    });

    test('keeps original order when positive durations are equal', () {
      final first = _window('first', const Duration(hours: 5));
      final second = _window('second', const Duration(hours: 5));
      final entry = _entry(windows: <AgentUsageWindow>[first, second]);

      expect(entry.compactQuotaWindow, same(first));
    });

    test('prefers a known positive duration over unknown windows', () {
      const unknown = AgentUsageWindow(label: 'unknown', usedPercent: 10);
      final known = _window('known', const Duration(days: 1));
      final entry = _entry(windows: <AgentUsageWindow>[unknown, known]);

      expect(entry.compactQuotaWindow, same(known));
    });

    test('falls back to the first window when every duration is unknown', () {
      const first = AgentUsageWindow(label: 'first', usedPercent: 10);
      const second = AgentUsageWindow(
        label: 'second',
        usedPercent: 20,
        windowDuration: Duration.zero,
      );
      const third = AgentUsageWindow(
        label: 'third',
        usedPercent: 30,
        windowDuration: Duration(hours: -1),
      );
      final entry = _entry(
        windows: const <AgentUsageWindow>[first, second, third],
      );

      expect(entry.compactQuotaWindow, same(first));
    });

    test('returns null for free, missing, or blank plans', () {
      final window = _window('daily', const Duration(days: 1));

      for (final planType in <String?>['free', ' FREE ', '', null]) {
        expect(
          _entry(
            planType: planType,
            windows: <AgentUsageWindow>[window],
          ).compactQuotaWindow,
          isNull,
          reason: '$planType',
        );
      }
    });

    test('returns null when a paid plan has no windows', () {
      expect(_entry().compactQuotaWindow, isNull);
      expect(
        const AgentUsagePanelEntry(
          providerId: 'provider-a',
          providerName: 'Provider A',
        ).compactQuotaWindow,
        isNull,
      );
    });
  });
}

AgentUsagePanelEntry _entry({
  String? planType = 'pro',
  List<AgentUsageWindow> windows = const <AgentUsageWindow>[],
}) {
  return AgentUsagePanelEntry(
    providerId: 'provider-a',
    providerName: 'Provider A',
    quota: AgentUsageQuotaSnapshot(
      providerId: 'provider-a',
      providerName: 'Provider A',
      planType: planType,
      windows: windows,
    ),
  );
}

AgentUsageWindow _window(String label, Duration duration) {
  return AgentUsageWindow(
    label: label,
    usedPercent: 10,
    windowDuration: duration,
  );
}
