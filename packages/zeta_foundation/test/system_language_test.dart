import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_foundation/platform.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(binding.platformDispatcher.clearLocalesTestValue);

  test('按第一项系统首选语言返回简体中文', () {
    binding.platformDispatcher.localesTestValue = <Locale>[
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      const Locale('en'),
    ];

    expect(
      ZetaSystemLanguage.getSystemLanguage(
        english: 'en',
        simplifiedChinese: 'zh-Hans',
        platformDispatcher: binding.platformDispatcher,
      ),
      'zh-Hans',
    );
  });

  test('没有系统首选语言时回退到英语', () {
    binding.platformDispatcher.localesTestValue = <Locale>[];

    expect(
      ZetaSystemLanguage.getSystemLanguage(
        english: 'en',
        simplifiedChinese: 'zh-Hans',
        platformDispatcher: binding.platformDispatcher,
      ),
      'en',
    );
  });
}
