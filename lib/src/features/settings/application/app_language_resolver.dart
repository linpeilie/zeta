import 'package:zeta_foundation/platform.dart';

import 'package:zeta/src/features/settings/domain/app_language.dart';

/// 只根据系统首选语言的第一项决定首次语言（D1 / D7）。
///
/// 调用方负责拆出 language/script/region，本函数不接收 Flutter [Locale]。
AppLanguage resolveAppLanguageFromFirstSystemLocale({
  String? languageCode,
  String? scriptCode,
  String? countryCode,
}) {
  return ZetaSystemLanguage.resolveFromLocale(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
    english: AppLanguage.english,
    simplifiedChinese: AppLanguage.simplifiedChinese,
  );
}
