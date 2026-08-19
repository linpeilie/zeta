import 'package:settings_client/settings_client.dart';
import 'package:test/test.dart';

void main() {
  test('general settings are immutable value objects with safe defaults', () {
    const defaults = GeneralSettingsResponse();
    const same = GeneralSettingsResponse();
    const different = GeneralSettingsResponse(
      sendMessageShortcut: MessageSendShortcutResponse.primaryModifierEnter,
      notifications: AgentNotificationSettingsResponse(
        enabled: false,
        turnTerminalEnabled: false,
        actionRequiredEnabled: false,
      ),
      appLanguage: AppLanguageResponse.english,
    );

    expect(defaults, same);
    expect(defaults.hashCode, same.hashCode);
    expect(defaults, isNot(different));
    expect(defaults, isNot('settings'));
    expect(defaults.sendMessageShortcut, MessageSendShortcutResponse.enter);
    expect(defaults.notifications.enabled, isTrue);
    expect(defaults.notifications.turnTerminalEnabled, isTrue);
    expect(defaults.notifications.actionRequiredEnabled, isTrue);
    expect(defaults.appLanguage, AppLanguageResponse.simplifiedChinese);
    expect(different.notifications, isNot(defaults.notifications));
    expect(different.notifications, isNot('notifications'));
  });

  test('appearance settings expose bounded defaults and value equality', () {
    const defaults = AppearanceSettingsResponse();
    const same = AppearanceSettingsResponse();
    final customized = AppearanceSettingsResponse(
      themeMode: AppearanceThemeModeResponse.dark,
      uiFontChoice: AppearanceFontChoiceResponse.system(' Inter '),
      codeFontChoice: const AppearanceFontChoiceResponse.systemDefault(),
      uiFontSize: maxUiFontSize,
      codeFontSize: maxCodeFontSize,
    );

    expect(defaults, same);
    expect(defaults.hashCode, same.hashCode);
    expect(defaults, isNot(customized));
    expect(defaults, isNot('appearance'));
    expect(defaults.uiFontSize, 12);
    expect(defaults.codeFontSize, 12);
    expect(minUiFontSize, 10);
    expect(maxUiFontSize, 20);
    expect(minCodeFontSize, 10);
    expect(maxCodeFontSize, 24);
    expect(customized.uiFontChoice.fontFamily, 'Inter');
    expect(
      customized.uiFontChoice.kind,
      AppearanceFontChoiceKindResponse.system,
    );
    expect(customized.uiFontChoice, isNot(defaults.uiFontChoice));
    expect(customized.uiFontChoice, isNot('font'));
    expect(
      const AppearanceFontChoiceResponse.bundledJetBrainsMono().kind,
      AppearanceFontChoiceKindResponse.bundledJetBrainsMono,
    );
  });

  test('system font choices reject blank family names', () {
    expect(
      () => AppearanceFontChoiceResponse.system('   '),
      throwsArgumentError,
    );
  });
}
