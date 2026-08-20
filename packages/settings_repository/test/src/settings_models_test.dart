import 'package:settings_repository/settings_repository.dart';
import 'package:test/test.dart';

void main() {
  group('resolveAppLanguageFromFirstSystemLocale', () {
    test(
      'defaults missing, blank, English, and unsupported locales to English',
      () {
        expect(resolveAppLanguageFromFirstSystemLocale(), AppLanguage.english);
        expect(
          resolveAppLanguageFromFirstSystemLocale(languageCode: ' '),
          AppLanguage.english,
        );
        expect(
          resolveAppLanguageFromFirstSystemLocale(languageCode: ' EN '),
          AppLanguage.english,
        );
        expect(
          resolveAppLanguageFromFirstSystemLocale(languageCode: 'fr'),
          AppLanguage.english,
        );
      },
    );

    test('recognizes supported and unsupported Chinese locale variants', () {
      expect(
        resolveAppLanguageFromFirstSystemLocale(
          languageCode: 'zh',
          scriptCode: ' Hant ',
        ),
        AppLanguage.english,
      );
      expect(
        resolveAppLanguageFromFirstSystemLocale(
          languageCode: 'zh',
          scriptCode: ' Hans ',
        ),
        AppLanguage.simplifiedChinese,
      );
      expect(
        resolveAppLanguageFromFirstSystemLocale(
          languageCode: 'zh',
          countryCode: ' tw ',
        ),
        AppLanguage.english,
      );
      expect(
        resolveAppLanguageFromFirstSystemLocale(
          languageCode: 'zh',
          countryCode: ' cn ',
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
          countryCode: 'US',
        ),
        AppLanguage.english,
      );
    });
  });

  test('general value objects support complete immutable copies', () {
    const notifications = AgentNotificationSettings();
    final disabled = notifications.copyWith(
      enabled: false,
      turnTerminalEnabled: false,
      actionRequiredEnabled: false,
    );
    expect(
      disabled,
      const AgentNotificationSettings(
        enabled: false,
        turnTerminalEnabled: false,
        actionRequiredEnabled: false,
      ),
    );
    expect(notifications.copyWith(), notifications);

    const settings = GeneralSettings();
    final updated = settings.copyWith(
      sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      notifications: disabled,
      appLanguage: AppLanguage.english,
    );
    expect(
      updated,
      GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        notifications: disabled,
        appLanguage: AppLanguage.english,
      ),
    );
    expect(settings.copyWith(), settings);
  });

  test('font choices expose stable provider-neutral identities', () {
    const systemDefault = SettingsFontChoice.systemDefault();
    final system = SettingsFontChoice.system(' Inter ');
    const bundled = SettingsFontChoice.bundledJetBrainsMono();

    expect(systemDefault.isSystemDefault, isTrue);
    expect(systemDefault.isSystemFont, isFalse);
    expect(systemDefault.isBundledJetBrainsMono, isFalse);
    expect(systemDefault.stableId, 'system-default');
    expect(system.fontFamily, 'Inter');
    expect(system.isSystemDefault, isFalse);
    expect(system.isSystemFont, isTrue);
    expect(system.isBundledJetBrainsMono, isFalse);
    expect(system.stableId, 'system-Inter');
    expect(bundled.isSystemDefault, isFalse);
    expect(bundled.isSystemFont, isFalse);
    expect(bundled.isBundledJetBrainsMono, isTrue);
    expect(bundled.stableId, 'bundled-jetbrains-mono');
    expect(() => SettingsFontChoice.system(' '), throwsArgumentError);
  });

  test('appearance settings support complete immutable copies', () {
    const initial = AppearanceSettings();
    final updated = initial.copyWith(
      themeMode: SettingsThemeMode.dark,
      uiFontChoice: SettingsFontChoice.system('Inter'),
      codeFontChoice: SettingsFontChoice.system('Mono'),
      uiFontSize: 14,
      codeFontSize: 16,
    );
    expect(
      updated,
      AppearanceSettings(
        themeMode: SettingsThemeMode.dark,
        uiFontChoice: SettingsFontChoice.system('Inter'),
        codeFontChoice: SettingsFontChoice.system('Mono'),
        uiFontSize: 14,
        codeFontSize: 16,
      ),
    );
    expect(initial.copyWith(), initial);
  });

  test('snapshots and update commands have structural equality', () {
    final revision = int.parse('2');
    final general = <GeneralSettings>[const GeneralSettings()].single;
    final appearance = <AppearanceSettings>[const AppearanceSettings()].single;
    final snapshot = SettingsSnapshot(
      general: general,
      appearance: appearance,
      revision: revision,
    );
    expect(
      snapshot,
      SettingsSnapshot(
        general: general,
        appearance: appearance,
        revision: revision,
      ),
    );
    final generalUpdate = GeneralSettingsUpdate(general);
    expect(
      generalUpdate,
      GeneralSettingsUpdate(general),
    );
    final appearanceUpdate = AppearanceSettingsUpdate(appearance);
    expect(
      appearanceUpdate,
      AppearanceSettingsUpdate(appearance),
    );
  });

  test('repository failures have structural equality', () {
    final diagnosticCode = <String>['settings_general_load_failed'].single;
    final failure = SettingsRepositoryFailure(
      operation: SettingsRepositoryOperation.initializeGeneral,
      code: SettingsRepositoryFailureCode.externalFailure,
      diagnosticCode: diagnosticCode,
    );

    expect(
      failure,
      SettingsRepositoryFailure(
        operation: SettingsRepositoryOperation.initializeGeneral,
        code: SettingsRepositoryFailureCode.externalFailure,
        diagnosticCode: diagnosticCode,
      ),
    );
  });

  test('font families normalize, freeze, compare, and reject blank data', () {
    final aliases = <String>[' Legacy '];
    final family = SettingsFontFamily(
      id: ' platform:inter ',
      familyName: ' Inter ',
      displayName: ' Inter Display ',
      aliases: aliases,
      isMonospace: false,
    );
    aliases.add('Later');

    expect(family.id, 'platform:inter');
    expect(family.familyName, 'Inter');
    expect(family.displayName, 'Inter Display');
    expect(family.aliases, const <String>['Legacy']);
    expect(
      family,
      SettingsFontFamily(
        id: 'platform:inter',
        familyName: 'Inter',
        displayName: 'Inter Display',
        aliases: const <String>['Legacy'],
        isMonospace: false,
      ),
    );
    expect(() => family.aliases.add('Nope'), throwsUnsupportedError);

    for (final createInvalid in <SettingsFontFamily Function()>[
      () => SettingsFontFamily(
        id: ' ',
        familyName: 'Inter',
        displayName: 'Inter',
        aliases: const <String>[],
        isMonospace: false,
      ),
      () => SettingsFontFamily(
        id: 'id',
        familyName: ' ',
        displayName: 'Inter',
        aliases: const <String>[],
        isMonospace: false,
      ),
      () => SettingsFontFamily(
        id: 'id',
        familyName: 'Inter',
        displayName: ' ',
        aliases: const <String>[],
        isMonospace: false,
      ),
      () => SettingsFontFamily(
        id: 'id',
        familyName: 'Inter',
        displayName: 'Inter',
        aliases: const <String>[' '],
        isMonospace: false,
      ),
    ]) {
      expect(createInvalid, throwsArgumentError);
    }
  });
}
