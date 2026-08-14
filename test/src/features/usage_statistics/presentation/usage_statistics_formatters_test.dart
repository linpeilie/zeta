import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';

void main() {
  group('formatUsageResetAt', () {
    final now = DateTime(2026, 8, 14, 17, 30);

    test('距今不超过 24 小时展示 mm-dd HH:mm', () {
      expect(
        formatUsageResetAt(DateTime(2026, 8, 14, 20, 5), now: now),
        '08-14 20:05',
      );
      expect(
        formatUsageResetAt(DateTime(2026, 8, 15, 17, 30), now: now),
        '08-15 17:30',
      );
    });

    test('超过 24 小时且不超过 7 天展示 mm-dd HH', () {
      expect(
        formatUsageResetAt(DateTime(2026, 8, 15, 17, 31), now: now),
        '08-15 17',
      );
      expect(
        formatUsageResetAt(DateTime(2026, 8, 21, 17, 30), now: now),
        '08-21 17',
      );
    });

    test('超过 7 天只展示 mm-dd', () {
      expect(
        formatUsageResetAt(DateTime(2026, 8, 21, 17, 31), now: now),
        '08-21',
      );
      expect(formatUsageResetAt(DateTime(2026, 9, 1, 9), now: now), '09-01');
    });

    test('已过去的重置时刻按绝对值分档', () {
      expect(
        formatUsageResetAt(DateTime(2026, 8, 14, 10, 0), now: now),
        '08-14 10:00',
      );
      expect(formatUsageResetAt(DateTime(2026, 8, 1, 9, 0), now: now), '08-01');
    });
  });
}
