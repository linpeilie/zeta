import 'dart:ui';

/// 读取并解析当前系统首选语言的工具。
abstract final class ZetaSystemLanguage {
  /// 根据系统首选语言返回调用方提供的语言值。
  ///
  /// 只检查系统语言列表的第一项，规则与 Zeta 首次启动语言选择保持一致：
  /// 英语、简体中文返回对应值，繁体中文及其他语言回退到 [english]。
  static T getSystemLanguage<T>({
    required T english,
    required T simplifiedChinese,
    PlatformDispatcher? platformDispatcher,
  }) {
    final dispatcher = platformDispatcher ?? PlatformDispatcher.instance;
    final firstLocale = dispatcher.locales.isEmpty
        ? null
        : dispatcher.locales.first;
    return resolveFromLocale(
      languageCode: firstLocale?.languageCode,
      scriptCode: firstLocale?.scriptCode,
      countryCode: firstLocale?.countryCode,
      english: english,
      simplifiedChinese: simplifiedChinese,
    );
  }

  /// 按系统首选语言的字段解析调用方提供的语言值。
  ///
  /// 将字段参数化后，foundation 不需要依赖根应用的 `AppLanguage` 类型，
  /// 根应用和其他宿主仍可复用同一套语言判定规则。
  static T resolveFromLocale<T>({
    required String? languageCode,
    required String? scriptCode,
    required String? countryCode,
    required T english,
    required T simplifiedChinese,
  }) {
    final language = languageCode?.trim().toLowerCase();
    if (language == null || language.isEmpty) {
      return english;
    }
    if (language == 'en') {
      return english;
    }
    if (language != 'zh') {
      return english;
    }

    final script = scriptCode?.trim().toLowerCase();
    if (script == 'hant') {
      return english;
    }
    if (script == 'hans') {
      return simplifiedChinese;
    }

    final region = countryCode?.trim().toUpperCase();
    if (region == 'TW' || region == 'HK' || region == 'MO') {
      return english;
    }
    if (region == 'CN' || region == 'SG' || region == null || region.isEmpty) {
      return simplifiedChinese;
    }
    return english;
  }
}
