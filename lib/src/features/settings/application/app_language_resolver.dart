import 'package:zeta/src/features/settings/domain/app_language.dart';

/// 只根据系统首选语言的第一项决定首次语言（D1 / D7）。
///
/// 调用方负责拆出 language/script/region，本函数不接收 Flutter [Locale]。
AppLanguage resolveAppLanguageFromFirstSystemLocale({
  String? languageCode,
  String? scriptCode,
  String? countryCode,
}) {
  final language = languageCode?.trim().toLowerCase();
  if (language == null || language.isEmpty) {
    return AppLanguage.english;
  }
  if (language == 'en') {
    return AppLanguage.english;
  }
  if (language != 'zh') {
    return AppLanguage.english;
  }

  final script = scriptCode?.trim().toLowerCase();
  if (script == 'hant') {
    return AppLanguage.english;
  }
  if (script == 'hans') {
    return AppLanguage.simplifiedChinese;
  }

  final region = countryCode?.trim().toUpperCase();
  if (region == 'TW' || region == 'HK' || region == 'MO') {
    return AppLanguage.english;
  }
  if (region == 'CN' || region == 'SG' || region == null || region.isEmpty) {
    return AppLanguage.simplifiedChinese;
  }
  return AppLanguage.english;
}
