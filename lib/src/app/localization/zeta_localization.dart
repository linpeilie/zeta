import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';
import 'package:zeta/src/ui/localization/zeta_shadcn_localizations.dart';

/// App / Global / Zeta shadcn 本地化组合入口。
///
/// Flutter `Locale` 只允许出现在这一层。生产路径在启动时冻结已加载的设置语言。
abstract final class ZetaLocalization {
  static const Locale english = Locale('en');
  static const Locale simplifiedChinese = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hans',
  );

  static const List<Locale> supportedLocales = <Locale>[
    english,
    simplifiedChinese,
    Locale('zh'),
  ];

  static const List<LocalizationsDelegate<dynamic>> delegates =
      <LocalizationsDelegate<dynamic>>[
        ZetaAppLocalizationsDelegate(),
        ZetaShadcnLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];

  static Locale localeFor(AppLanguage language) {
    return switch (language) {
      AppLanguage.english => english,
      AppLanguage.simplifiedChinese => simplifiedChinese,
    };
  }

  /// 把当前进程 Locale 映射回领域语言；非英语一律视为简体中文。
  static AppLanguage languageForLocale(Locale locale) {
    return locale.languageCode == 'en'
        ? AppLanguage.english
        : AppLanguage.simplifiedChinese;
  }
}

/// 同步加载生成的 [AppLocalizations]，避免首帧因异步 delegate 空白。
final class ZetaAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const ZetaAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool shouldReload(covariant ZetaAppLocalizationsDelegate old) => false;
}
