/// 首期支持的界面语言。
///
/// 持久化码为 `en` / `zh-Hans`。Flutter [Locale] 只允许出现在 app/UI 组合层。
enum AppLanguage { english, simplifiedChinese }

extension AppLanguagePersistence on AppLanguage {
  String get persistenceCode {
    return switch (this) {
      AppLanguage.english => 'en',
      AppLanguage.simplifiedChinese => 'zh-Hans',
    };
  }

  static AppLanguage? tryParse(Object? raw) {
    return switch (raw) {
      'en' => AppLanguage.english,
      'zh-Hans' => AppLanguage.simplifiedChinese,
      _ => null,
    };
  }
}
