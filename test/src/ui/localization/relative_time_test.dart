import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';
import 'package:zeta/src/ui/localization/relative_time.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 12);
  final en = lookupAppLocalizations(const Locale('en'));
  final zh = lookupAppLocalizations(const Locale('zh'));

  test('relative time tokens follow locale while buckets stay identical', () {
    final cases = <Duration, (String, String)>{
      Duration.zero: (en.relativeTimeJustNow, zh.relativeTimeJustNow),
      const Duration(seconds: 30): (
        en.relativeTimeJustNow,
        zh.relativeTimeJustNow,
      ),
      const Duration(minutes: 5): (
        en.relativeTimeMinutesAgo('5'),
        zh.relativeTimeMinutesAgo('5'),
      ),
      const Duration(hours: 3): (
        en.relativeTimeHoursAgo('3'),
        zh.relativeTimeHoursAgo('3'),
      ),
      const Duration(days: 2): (
        en.relativeTimeDaysAgo('2'),
        zh.relativeTimeDaysAgo('2'),
      ),
    };

    for (final entry in cases.entries) {
      final value = now.subtract(entry.key);
      expect(formatLocalizedRelativeTime(value, now, en), entry.value.$1);
      expect(formatLocalizedRelativeTime(value, now, zh), entry.value.$2);
    }
    expect(en.relativeTimeJustNow, 'Just now');
    expect(zh.relativeTimeJustNow, '刚刚');
    expect(en.relativeTimeMinutesAgo('5'), '5 minutes ago');
    expect(zh.relativeTimeMinutesAgo('5'), '5 分钟前');
  });
}
