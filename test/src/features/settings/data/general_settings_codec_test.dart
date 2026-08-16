import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/data/general_settings_codec.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  const codec = GeneralSettingsCodec();

  test('v1 and v2 seed simplified Chinese and keep old fields', () {
    final v1 = codec.decode(<String, Object?>{
      'version': 1,
      'sendMessageShortcut': 'primaryModifierEnter',
    }, fallbackLanguage: AppLanguage.english);
    expect(
      v1,
      const GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        appLanguage: AppLanguage.simplifiedChinese,
      ),
    );

    final v2 = codec.decode(<String, Object?>{
      'version': 2,
      'sendMessageShortcut': 'enter',
      'notifications': <String, Object?>{
        'enabled': false,
        'turnTerminalEnabled': true,
        'actionRequiredEnabled': false,
      },
    }, fallbackLanguage: AppLanguage.english);
    expect(v2.appLanguage, AppLanguage.simplifiedChinese);
    expect(v2.notifications.enabled, isFalse);
    expect(v2.notifications.actionRequiredEnabled, isFalse);
  });

  test('v3 round-trips both languages', () {
    const english = GeneralSettings(appLanguage: AppLanguage.english);
    const chinese = GeneralSettings(
      appLanguage: AppLanguage.simplifiedChinese,
      sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
    );
    expect(
      codec.decode(
        codec.encode(english),
        fallbackLanguage: AppLanguage.english,
      ),
      english,
    );
    expect(
      codec.decode(
        codec.encode(chinese),
        fallbackLanguage: AppLanguage.english,
      ),
      chinese,
    );
  });

  test('unknown v3 language falls back to English', () {
    final settings = codec.decode(<String, Object?>{
      'version': 3,
      'sendMessageShortcut': 'enter',
      'notifications': const AgentNotificationSettings().toJson(),
      'appLanguage': 'fr',
    }, fallbackLanguage: AppLanguage.simplifiedChinese);
    expect(settings.appLanguage, AppLanguage.english);
  });

  test('unknown version can still read a known language', () {
    final settings = codec.decode(<String, Object?>{
      'version': 99,
      'sendMessageShortcut': 'primaryModifierEnter',
      'notifications': <String, Object?>{'enabled': false},
      'appLanguage': 'en',
    }, fallbackLanguage: AppLanguage.simplifiedChinese);
    expect(settings.appLanguage, AppLanguage.english);
    expect(
      settings.sendMessageShortcut,
      MessageSendShortcut.primaryModifierEnter,
    );
    expect(settings.notifications.enabled, isFalse);
  });

  test('damaged input uses the explicit fallback language', () {
    expect(
      codec
          .decode('not-json', fallbackLanguage: AppLanguage.english)
          .appLanguage,
      AppLanguage.english,
    );
    expect(
      codec
          .decode(null, fallbackLanguage: AppLanguage.simplifiedChinese)
          .appLanguage,
      AppLanguage.simplifiedChinese,
    );
  });
}
