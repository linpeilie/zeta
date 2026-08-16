import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/application/app_language_resolver.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';

void main() {
  test('maps first preferred locale by D1 and D7 rules', () {
    expect(
      resolveAppLanguageFromFirstSystemLocale(languageCode: 'en'),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'en',
        countryCode: 'US',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        scriptCode: 'Hans',
      ),
      AppLanguage.simplifiedChinese,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        countryCode: 'CN',
      ),
      AppLanguage.simplifiedChinese,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        countryCode: 'SG',
      ),
      AppLanguage.simplifiedChinese,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(languageCode: 'zh'),
      AppLanguage.simplifiedChinese,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'CN',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        countryCode: 'TW',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        countryCode: 'HK',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(
        languageCode: 'zh',
        countryCode: 'MO',
      ),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(languageCode: 'ja'),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(languageCode: null),
      AppLanguage.english,
    );
    expect(
      resolveAppLanguageFromFirstSystemLocale(languageCode: ''),
      AppLanguage.english,
    );
  });
}
