import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/localization/zeta_shadcn_localizations.dart';

void main() {
  Future<sf.ShadcnLocalizations> load(String languageCode) {
    return ZetaShadcnLocalizations.delegate.load(Locale(languageCode));
  }

  test('delegate supports en and zh only', () {
    expect(
      ZetaShadcnLocalizations.delegate.isSupported(const Locale('en')),
      isTrue,
    );
    expect(
      ZetaShadcnLocalizations.delegate.isSupported(const Locale('zh')),
      isTrue,
    );
    expect(
      ZetaShadcnLocalizations.delegate.isSupported(const Locale('fr')),
      isFalse,
    );
  });

  test(
    'command, menu and form strings resolve without mixed fallback',
    () async {
      final en = await load('en');
      final zh = await load('zh');

      expect(en.commandSearch, 'Type a command or search...');
      expect(zh.commandSearch, '输入命令或搜索…');
      expect(en.commandEmpty, 'No results found.');
      expect(zh.commandEmpty, '未找到结果。');
      expect(en.menuCopy, 'Copy');
      expect(zh.menuCopy, '复制');
      expect(en.formNotEmpty, 'This field cannot be empty');
      expect(zh.formNotEmpty, '此项不能为空');
      expect(en.placeholderDatePicker, 'Select a date');
      expect(zh.placeholderDatePicker, '选择日期');
      expect(en.datePickerSelectYear, 'Select a year');
      expect(zh.datePickerSelectYear, '选择年份');
    },
  );

  test('parameterized form copy translates only the static template', () async {
    final en = await load('en');
    final zh = await load('zh');
    expect(en.formLessThan(10), 'Must be less than 10');
    expect(zh.formLessThan(10), '必须小于 10');
    expect(en.formBetweenInclusively(1, 3.5), contains('1'));
    expect(en.formBetweenInclusively(1, 3.5), contains('3.5'));
    expect(zh.formBetweenInclusively(1, 3.5), contains('1'));
    expect(zh.formBetweenInclusively(1, 3.5), contains('3.5'));
    expect(zh.formBetweenInclusively(1, 3.5), isNot(contains('1.0')));
  });

  test('D6 date, number and duration snapshots stay language-stable', () async {
    final en = await load('en');
    final zh = await load('zh');
    final instant = DateTime(2026, 8, 16, 14, 5, 6);
    expect(en.formatDateTime(instant), zh.formatDateTime(instant));
    expect(en.formatDateTime(instant), 'August 16, 2026 14:5');
    expect(
      en.formatTimeOfDay(const sf.TimeOfDay(hour: 9, minute: 7, second: 0)),
      zh.formatTimeOfDay(const sf.TimeOfDay(hour: 9, minute: 7, second: 0)),
    );
    expect(en.formatNumber(12), zh.formatNumber(12));
    expect(en.formatNumber(12.5), zh.formatNumber(12.5));
    expect(
      en.formatDuration(const Duration(hours: 2, minutes: 3)),
      zh.formatDuration(const Duration(hours: 2, minutes: 3)),
    );
    expect(en.timeAM, zh.timeAM);
    expect(en.timePM, zh.timePM);
    expect(en.monthAugust, zh.monthAugust);
  });
}
